import Foundation

// A complete connected story graph. Unlike `successChain(from:)`, a
// component includes branches reached through every mission trigger
// (accept/refuse/success/failure/abort/ship-done), so no alternate route is
// hidden just because it is not the first success successor.
public struct MissionChainComponent: Identifiable, Equatable, Sendable {
    public let missions: [MissionDefinition]
    public let rootMissionIDs: [Int]
    public let edgeCount: Int

    public var id: Int { missions.first?.id ?? -1 }
    public var isCyclic: Bool { rootMissionIDs.isEmpty }

    public init(missions: [MissionDefinition], rootMissionIDs: [Int], edgeCount: Int) {
        self.missions = missions
        self.rootMissionIDs = rootMissionIDs
        self.edgeCount = edgeCount
    }
}

// Builds a walkable graph over a decoded set of MissionDefinition values,
// using the "Sxxx" (start mission xxx) chain links embedded in each
// mission's NCB set-expression fields (see MissionDefinition's file doc
// comment for how that mechanism was discovered and verified), plus flag
// links: one mission's success turning on a flag another mission waits for.
// This is what lets the UI show a mission's full story chain rather than
// just an unconnected flat list.
public struct MissionChainResolver: Sendable {
    private let byID: [Int: MissionDefinition]

    // Every mission that lists a given ID as one of its chained
    // (successor) mission IDs, keyed by that target ID - i.e. the reverse
    // edges, used to answer "what leads to this mission?".
    private let predecessorsByID: [Int: [MissionDefinition]]

    // All successors per mission: explicit "Sxxx" starts plus flag links.
    private let successorIDsByID: [Int: [Int]]

    // Flag links: most storylines (Polaris, for one) never use "Sxxx".
    // Mission A's success turns a flag on and mission B waits for that flag
    // to be on. Keyed by A then B, the value is the flag that links them.
    private let unlockFlagByLink: [Int: [Int: Int]]

    // A flag that more missions than this turn on is a shared marker (e.g.
    // 518 "a main storyline has begun"), not a specific story step. The
    // waiter limit is looser: Polaris 4b's flag 278 legitimately unlocks
    // Polaris 5 and six Vell-os missions at once.
    static let maxFlagSetters = 3
    static let maxFlagWaiters = 12

    public init(missions: [MissionDefinition]) {
        var byID: [Int: MissionDefinition] = [:]
        byID.reserveCapacity(missions.count)
        for mission in missions {
            byID[mission.id] = mission
        }
        self.byID = byID

        let unlockFlagByLink: [Int: [Int: Int]] = Self.findFlagLinks(missions: missions)
        self.unlockFlagByLink = unlockFlagByLink

        var successorIDsByID: [Int: [Int]] = [:]
        var predecessors: [Int: [MissionDefinition]] = [:]

        for mission in missions {
            let flagTargets: [Int] = (unlockFlagByLink[mission.id] ?? [:]).keys.sorted()
            let targets: [Int] = Array(Set(mission.allChainedMissionIDs + flagTargets)).sorted()
            successorIDsByID[mission.id] = targets

            for targetID in targets {
                predecessors[targetID, default: []].append(mission)
            }
        }

        self.successorIDsByID = successorIDsByID
        self.predecessorsByID = predecessors
    }

    private static func findFlagLinks(missions: [MissionDefinition]) -> [Int: [Int: Int]] {
        var setterIDsByFlag: [Int: Set<Int>] = [:]
        var successSetterIDsByFlag: [Int: Set<Int>] = [:]
        var waiterIDsByFlag: [Int: Set<Int>] = [:]

        let outcomes: (MissionDefinition) -> [String] = { mission in
            [mission.onAccept, mission.onRefuse, mission.onSuccess, mission.onFailure, mission.onAbort, mission.onShipDone]
        }

        for mission in missions {
            for expression in outcomes(mission) {
                for operation in StoryFlagCatalog.bitOperations(in: expression, isTest: false) where operation.effect == .sets || operation.effect == .toggles {
                    setterIDsByFlag[operation.id, default: []].insert(mission.id)
                }
            }

            for operation in StoryFlagCatalog.bitOperations(in: mission.onSuccess, isTest: false) where operation.effect == .sets {
                successSetterIDsByFlag[operation.id, default: []].insert(mission.id)
            }

            for operation in StoryFlagCatalog.bitOperations(in: mission.availBits, isTest: true) where operation.effect == .requiresSet {
                waiterIDsByFlag[operation.id, default: []].insert(mission.id)
            }
        }

        var links: [Int: [Int: Int]] = [:]

        for (flagID, successSetters) in successSetterIDsByFlag {
            let setterCount: Int = setterIDsByFlag[flagID]?.count ?? 0
            let waiters: Set<Int> = waiterIDsByFlag[flagID] ?? []

            guard setterCount <= maxFlagSetters, !waiters.isEmpty, waiters.count <= maxFlagWaiters else { continue }

            for setterID in successSetters {
                for waiterID in waiters where waiterID != setterID {
                    // Lowest flag wins if two flags link the same pair, so
                    // labels stay stable between launches.
                    let existing: Int? = links[setterID]?[waiterID]
                    links[setterID, default: [:]][waiterID] = min(existing ?? flagID, flagID)
                }
            }
        }

        return links
    }

    // The storyline a mission belongs to, from the tag scenario authors put
    // after ";" in mission names: "Polaris4 CONTINUE" and "Polaris
    // ActionMan 001" are both "polaris", "Rebel I11" and "Rebel II14" both
    // "rebel", "Vell-os" matches "Vellos". nil when there's no tag.
    static func storylineFamily(of mission: MissionDefinition?) -> String? {
        guard let name = mission?.name,
              let separator = name.firstIndex(of: ";") else { return nil }

        let note: Substring = name[name.index(after: separator)...]
        let beforeDigits: Substring = note.prefix { !$0.isNumber }
        let firstWord: Substring? = beforeDigits.split(whereSeparator: { $0 == " " }).first
        let family: String = String(firstWord ?? "")
            .lowercased()
            .filter { $0.isLetter }

        return family.isEmpty ? nil : family
    }

    // The flag through which `mission`'s success unlocks `targetID`, if
    // they're linked that way.
    public func unlockFlag(from mission: MissionDefinition, to targetID: Int) -> Int? {
        unlockFlagByLink[mission.id]?[targetID]
    }

    public func mission(id: Int) -> MissionDefinition? {
        byID[id]
    }

    // Missions this mission can automatically start (via any trigger -
    // accept/refuse/success/failure/abort/ship-done), resolved to actual
    // MissionDefinition values where the referenced ID exists in this
    // decoded set (a chain link can point to an ID from a plugin/expansion
    // not present in the currently loaded game data, which is dropped
    // silently here rather than surfaced as an error).
    public func successors(of mission: MissionDefinition) -> [MissionDefinition] {
        (successorIDsByID[mission.id] ?? []).compactMap { byID[$0] }
    }

    // Missions that chain TO this one (the reverse of successors(of:)) -
    // "what leads here".
    public func predecessors(of mission: MissionDefinition) -> [MissionDefinition] {
        (predecessorsByID[mission.id] ?? []).sorted { $0.id < $1.id }
    }

    // Whether this mission is part of any chain at all (has at least one
    // successor or predecessor link).
    public func isPartOfChain(_ mission: MissionDefinition) -> Bool {
        !(successorIDsByID[mission.id] ?? []).isEmpty || !(predecessorsByID[mission.id] ?? []).isEmpty
    }

    // Returns every chain as a connected component of the complete trigger
    // graph. Edges are treated as undirected only while finding components;
    // their direction and trigger remain available on MissionDefinition for
    // presentation. Standalone missions are intentionally omitted.
    public func allChains() -> [MissionChainComponent] {
        var neighbours: [Int: Set<Int>] = [:]
        for mission in byID.values {
            let loadedTargets = Set((successorIDsByID[mission.id] ?? []).filter { byID[$0] != nil })
            for targetID in loadedTargets {
                neighbours[mission.id, default: []].insert(targetID)
                neighbours[targetID, default: []].insert(mission.id)
            }
        }

        var visited = Set<Int>()
        var components: [MissionChainComponent] = []

        for startID in byID.keys.sorted() where !visited.contains(startID) {
            guard isPartOfChain(byID[startID]!) else { continue }

            var pending = [startID]
            var componentIDs = Set<Int>()
            var componentFamily: String?

            while let currentID = pending.popLast() {
                guard !visited.contains(currentID) else { continue }

                // Storylines hand off to each other (Wild Geese leads into
                // Pirate or Auroran), so following every link merges most of
                // the game into one unreadable chain. Links still show as
                // "leads to" and "comes from"; they just don't join groups.
                if let family = Self.storylineFamily(of: byID[currentID]) {
                    if let componentFamily, componentFamily != family { continue }
                    componentFamily = family
                }

                visited.insert(currentID)
                componentIDs.insert(currentID)
                pending.append(contentsOf: (neighbours[currentID] ?? []).filter { !visited.contains($0) })
            }

            let idSortedMissions = componentIDs.compactMap { byID[$0] }.sorted { $0.id < $1.id }
            let roots = idSortedMissions
                .filter { mission in
                    (predecessorsByID[mission.id] ?? []).allSatisfy { !componentIDs.contains($0.id) }
                }
                .map(\.id)
            let edgeCount = idSortedMissions.reduce(into: 0) { count, mission in
                count += Set(successorIDsByID[mission.id] ?? []).filter { componentIDs.contains($0) }.count
            }
            let componentMissions = traversalOrder(
                componentIDs: componentIDs,
                rootIDs: roots,
                byID: byID
            )
            components.append(MissionChainComponent(
                missions: componentMissions,
                rootMissionIDs: roots,
                edgeCount: edgeCount
            ))
        }

        return components.sorted {
            if $0.missions.count != $1.missions.count { return $0.missions.count > $1.missions.count }
            return $0.id < $1.id
        }
    }

    // Root-first breadth-first order makes branched chains readable while
    // still handling cycles and malformed components deterministically.
    private func traversalOrder(
        componentIDs: Set<Int>,
        rootIDs: [Int],
        byID: [Int: MissionDefinition]
    ) -> [MissionDefinition] {
        var pending = rootIDs.sorted()
        if pending.isEmpty, let firstID = componentIDs.min() { pending = [firstID] }
        var seen = Set<Int>()
        var ordered: [MissionDefinition] = []

        while !pending.isEmpty {
            let currentID = pending.removeFirst()
            guard seen.insert(currentID).inserted, let mission = byID[currentID] else { continue }
            ordered.append(mission)
            let successors = Set(successorIDsByID[mission.id] ?? [])
                .filter { componentIDs.contains($0) && !seen.contains($0) }
                .sorted()
            pending.append(contentsOf: successors)
        }

        for id in componentIDs.sorted() where !seen.contains(id) {
            if let mission = byID[id] { ordered.append(mission) }
        }
        return ordered
    }

    // Walks the "on success" chain forward from `mission`, following each
    // mission's successMissionIDs (the primary "next mission in the
    // story" link) as far as it goes, stopping on a dead end, a missing/
    // not-loaded mission ID, or a cycle (a mission chaining back to one
    // already in the path - real story data shouldn't cycle, but this
    // guards against malformed/adversarial plugin data producing an
    // infinite loop). The returned array starts with `mission` itself.
    public func successChain(from mission: MissionDefinition) -> [MissionDefinition] {
        var chain: [MissionDefinition] = [mission]
        var visited: Set<Int> = [mission.id]
        var current = mission

        while let nextID = current.successMissionIDs.first, let next = byID[nextID], !visited.contains(next.id) {
            chain.append(next)
            visited.insert(next.id)
            current = next
        }

        return chain
    }

    // Walks the "on success" chain BACKWARD from `mission` - i.e. finds
    // the mission (if any) whose OWN successMissionIDs points at
    // `mission`, and repeats from there - to find where a chain started.
    // Same cycle/dead-end guards as successChain(from:).
    public func predecessorChain(from mission: MissionDefinition) -> [MissionDefinition] {
        var chain: [MissionDefinition] = [mission]
        var visited: Set<Int> = [mission.id]
        var current = mission

        while
            let previous = (predecessorsByID[current.id] ?? []).first(where: { $0.successMissionIDs.contains(current.id) }),
            !visited.contains(previous.id)
        {
            chain.insert(previous, at: 0)
            visited.insert(previous.id)
            current = previous
        }

        return chain
    }

    // The full story chain `mission` belongs to: everything reachable by
    // walking successChain backward to the start, then forward to the end.
    // `mission` itself is included exactly once, at its correct position.
    public func fullChain(containing mission: MissionDefinition) -> [MissionDefinition] {
        let backward = predecessorChain(from: mission)
        let forward = successChain(from: mission)
        // backward already ends with `mission`; forward already starts
        // with it - concatenate without duplicating the shared element.
        return backward + forward.dropFirst()
    }
}
