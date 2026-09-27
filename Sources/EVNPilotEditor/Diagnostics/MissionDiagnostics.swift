import Foundation

// The engine behind "why isn't this mission/story chain triggering" - the
// task's whole point. Combines a decoded mission set, the derived story
// flag catalog (who sets/clears/toggles each control bit, see
// StoryFlagCatalog.swift), and a snapshot of one pilot's current state to
// answer, per mission: is it active, available, already done, blocked (and
// by what, in plain English), or flatly impossible given the loaded data.
//
// This file intentionally avoids the term "NCB" in any user-facing string -
// the game's internal name for its control-bit system is meaningless to a
// player; the UI-facing language always talks about "story flags".

// MARK: - Pilot state snapshot

// Equatable so views can skip rebuilding diagnostics after edits that don't
// touch anything a mission's availability depends on (e.g. credits).
public struct PilotStoryState: Sendable, Equatable {
    // missionBit[10000] - see MissionBits.swift.
    public let bits: [Bool]
    // itemCount, indexed by outfit ID - outfitIDBase (128) - see
    // PilotInventory.swift.
    public let outfitCounts: [Int16]
    // exploration, indexed by system ID - systemIDBase (128); > 0 means
    // explored - see PilotExploration.swift.
    public let exploration: [Int16]
    public let combatRating: Int32
    // nil = unknown (this app never guesses at a value it wasn't given).
    public let isMale: Bool?
    // mïsn IDs currently occupying one of the pilot's 16 active mission
    // slots - see MissionSlot.swift.
    public let activeMissionIDs: Set<Int>
    // nil when the pilot's ship isn't in the loaded game data; the ship
    // checks are then skipped rather than guessed.
    public let ship: PilotShipState?

    // Both outfit item IDs and system IDs are documented (Nova Bible) as
    // starting at 128, matching the game's general resource-ID numbering -
    // see MissionSlot's own `missionID = rawMissionID + 128` convention for
    // the same pattern elsewhere in this codebase.
    public static let outfitIDBase = 128
    public static let systemIDBase = 128

    public init(
        bits: [Bool],
        outfitCounts: [Int16],
        exploration: [Int16],
        combatRating: Int32,
        isMale: Bool?,
        activeMissionIDs: Set<Int>,
        ship: PilotShipState? = nil
    ) {
        self.bits = bits
        self.outfitCounts = outfitCounts
        self.exploration = exploration
        self.combatRating = combatRating
        self.isMale = isMale
        self.activeMissionIDs = activeMissionIDs
        self.ship = ship
    }
}

// The facts about the pilot's current ship that decide some mission offers
// (mission Flags/Flags2 in the Nova Bible).
public struct PilotShipState: Sendable, Equatable {
    public let name: String
    // shïp InherentAI: 1-2 are cargo ships, 3-4 warships.
    public let inherentAI: Int16
    public let capacity: ShipCapacity
    public let fuel: Int

    public init(name: String, inherentAI: Int16, capacity: ShipCapacity, fuel: Int) {
        self.name = name
        self.inherentAI = inherentAI
        self.capacity = capacity
        self.fuel = fuel
    }

    // nil when the pilot's ship type isn't in the loaded game data.
    public init?(pilotBytes: Data, shipsByID: [Int: ShipDefinition], outfitsByID: [Int: OutfitDefinition]) {
        let shipID: Int = Int(PilotProfile.decodeShipClassIndex(from: pilotBytes)) + 128
        guard let ship = shipsByID[shipID] else { return nil }

        self.init(
            name: ship.name,
            inherentAI: ship.inherentAI,
            capacity: ShipCapacity(ship: ship, outfitsByID: outfitsByID, pilotBytes: pilotBytes),
            fuel: Int(PilotProfile.decodeFuel(from: pilotBytes))
        )
    }
}

// MARK: - Result types

public enum MissionStatus: String, Sendable, CaseIterable {
    case active
    case available
    case completed
    case blocked
    case impossible
}

public enum IssueSeverity: String, Sendable {
    case blocker
    case warning
    case info
}

// An editor fix for a story lock. Copying a real mission outcome is
// preferred over clearing flags by hand, so the pilot ends up in a state
// the game itself could have produced.
public enum LockFix: Sendable, Equatable {
    // Apply what this mission's outcome does. `event` uses the story-flag
    // reference names ("completed", "failed", "aborted", ...).
    case missionOutcome(missionID: Int, event: String)
    case clearFlags([Int])
}

public struct MissionIssue: Identifiable, Sendable, Equatable {
    public let id: String
    public let severity: IssueSeverity
    public let title: String
    public let detail: String
    public let relatedFlagIDs: [Int]
    public let relatedMissionIDs: [Int]
    public let fix: LockFix?

    public init(
        id: String,
        severity: IssueSeverity,
        title: String,
        detail: String,
        relatedFlagIDs: [Int],
        relatedMissionIDs: [Int],
        fix: LockFix? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.relatedFlagIDs = relatedFlagIDs
        self.relatedMissionIDs = relatedMissionIDs
        self.fix = fix
    }
}

public struct MissionDiagnosis: Identifiable, Sendable {
    public let missionID: Int
    public var id: Int { missionID }
    public let status: MissionStatus
    // nil when availBits is blank (trivially true, nothing to explain) or
    // failed to parse (see parseError instead).
    public let explanation: NCBExplanation?
    public let parseError: String?
    // Blockers first, then warnings, then info - see the sort in
    // MissionDiagnostics.computeDiagnosis(for:).
    public let issues: [MissionIssue]

    public init(missionID: Int, status: MissionStatus, explanation: NCBExplanation?, parseError: String?, issues: [MissionIssue]) {
        self.missionID = missionID
        self.status = status
        self.explanation = explanation
        self.parseError = parseError
        self.issues = issues
    }
}

public struct ChainSummary: Sendable {
    public let counts: [MissionStatus: Int]
    // Blocked/impossible missions whose predecessors in the chain are all
    // completed or active - i.e. this is as far as the story can currently
    // progress ("the stuck point"). A blocked/impossible mission with no
    // predecessors at all (a chain root) also counts, since nothing needs
    // to happen first for it to be the stuck point.
    public let firstBlockedMissionIDs: [Int]
    public let conflictCount: Int

    public init(counts: [MissionStatus: Int], firstBlockedMissionIDs: [Int], conflictCount: Int) {
        self.counts = counts
        self.firstBlockedMissionIDs = firstBlockedMissionIDs
        self.conflictCount = conflictCount
    }
}

// MARK: - Engine

public struct MissionDiagnostics: Sendable {
    // Two missions that share a common "parent" (one mission's outcome
    // starts both of them, via any trigger) where one's outcome sets/
    // toggles a story flag the other's own AvailBits structurally requires
    // to be off - a design-level mutual exclusion, independent of the
    // pilot's current state. See the doc comment on the conflict-detection
    // code below for why this is a useful, distinct signal from the
    // state-based "conflicts with" issue attached to a blocked mission.
    fileprivate struct SiblingConflict: Sendable {
        let missionAID: Int
        let missionBID: Int
        let flagID: Int
    }

    // Everything about the missions that doesn't depend on the pilot:
    // parsed availability expressions, sibling conflicts, and which
    // expressions can never be true. Built once per loaded game data, so an
    // edit to the pilot only redoes the pilot-dependent part.
    public struct Prepared: Sendable {
        fileprivate let missions: [MissionDefinition]
        fileprivate let missionsByID: [Int: MissionDefinition]
        fileprivate let parsedByID: [Int: NCBParseResult]
        fileprivate let siblingConflicts: [SiblingConflict]
        fileprivate let conflictsByMissionID: [Int: [SiblingConflict]]
        fileprivate let requiresOffBitIDsByID: [Int: [Int]]
        fileprivate let unsatisfiableByID: [Int: Bool]

        public init(missions: [MissionDefinition]) {
            var missionsByID: [Int: MissionDefinition] = [:]
            missionsByID.reserveCapacity(missions.count)
            for mission in missions { missionsByID[mission.id] = mission }

            var parsedByID: [Int: NCBParseResult] = [:]
            parsedByID.reserveCapacity(missions.count)
            for mission in missions { parsedByID[mission.id] = NCBTestExpression.parse(mission.availBits) }

            let siblingConflicts: [SiblingConflict] = MissionDiagnostics.findSiblingConflicts(missions: missions, parsedByID: parsedByID)

            var conflictsByMissionID: [Int: [SiblingConflict]] = [:]
            for conflict in siblingConflicts {
                conflictsByMissionID[conflict.missionAID, default: []].append(conflict)
                conflictsByMissionID[conflict.missionBID, default: []].append(conflict)
            }

            var requiresOffBitIDsByID: [Int: [Int]] = [:]
            var unsatisfiableByID: [Int: Bool] = [:]

            for (missionID, parseResult) in parsedByID {
                guard let node = parseResult.node else { continue }

                requiresOffBitIDsByID[missionID] = MissionDiagnostics.requiresOffLeaves(of: node).compactMap { term -> Int? in
                    if case .bit(let id) = term { return id }
                    return nil
                }
                unsatisfiableByID[missionID] = MissionDiagnostics.isStructurallyUnsatisfiable(node) == true
            }

            self.missions = missions
            self.missionsByID = missionsByID
            self.parsedByID = parsedByID
            self.siblingConflicts = siblingConflicts
            self.conflictsByMissionID = conflictsByMissionID
            self.requiresOffBitIDsByID = requiresOffBitIDsByID
            self.unsatisfiableByID = unsatisfiableByID
        }
    }

    private let storyFlags: [Int: StoryFlagMetadata]
    private let precomputedDiagnoses: [Int: MissionDiagnosis]
    private let siblingConflicts: [SiblingConflict]

    public init(missions: [MissionDefinition], storyFlags: [Int: StoryFlagMetadata], state: PilotStoryState) {
        self.init(prepared: Prepared(missions: missions), storyFlags: storyFlags, state: state)
    }

    public init(prepared: Prepared, storyFlags: [Int: StoryFlagMetadata], state: PilotStoryState) {
        self.storyFlags = storyFlags
        self.siblingConflicts = prepared.siblingConflicts

        var diagnoses: [Int: MissionDiagnosis] = [:]
        diagnoses.reserveCapacity(prepared.missions.count)
        for mission in prepared.missions {
            diagnoses[mission.id] = Self.computeDiagnosis(
                for: mission,
                parseResult: prepared.parsedByID[mission.id] ?? NCBParseResult(node: nil, error: nil, isAmbiguous: false),
                requiresOffBitIDs: prepared.requiresOffBitIDsByID[mission.id] ?? [],
                isUnsatisfiable: prepared.unsatisfiableByID[mission.id] ?? false,
                missionsByID: prepared.missionsByID,
                storyFlags: storyFlags,
                state: state,
                siblingConflicts: prepared.conflictsByMissionID[mission.id] ?? []
            )
        }
        self.precomputedDiagnoses = Self.explainLocks(
            in: diagnoses,
            missionsByID: prepared.missionsByID,
            storyFlags: storyFlags
        )
    }

    // MARK: - Lock causes

    // Second pass, because it needs every mission's status. A blocked
    // mission's "Conflicts with" list names every mission that could turn
    // the blocking flag on; for shared flags like 511 that's dozens. When
    // some of them actually happened (completed or in progress), replace
    // the list with one issue naming them, plus the missions that would
    // turn the flag back off.
    private static func explainLocks(
        in diagnoses: [Int: MissionDiagnosis],
        missionsByID: [Int: MissionDefinition],
        storyFlags: [Int: StoryFlagMetadata]
    ) -> [Int: MissionDiagnosis] {
        var result: [Int: MissionDiagnosis] = diagnoses

        for (missionID, diagnosis) in diagnoses where diagnosis.status == .blocked || diagnosis.status == .impossible {
            let conflictIssues: [MissionIssue] = diagnosis.issues.filter { $0.id.hasPrefix("conflict-") }
            guard !conflictIssues.isEmpty else { continue }

            var flagOrder: [Int] = []
            var issuesByFlag: [Int: [MissionIssue]] = [:]

            for issue in conflictIssues {
                guard let flagID = issue.relatedFlagIDs.first else { continue }

                if issuesByFlag[flagID] == nil {
                    flagOrder.append(flagID)
                }

                issuesByFlag[flagID, default: []].append(issue)
            }

            var replaced: Set<String> = []

            // Flags locked by the same missions share one issue: Wild
            // Geese 1 holds both 511 and 515, and two identical "Locked by"
            // entries read like two different problems.
            var causeOrder: [[Int]] = []
            var flagsByCauses: [[Int]: [Int]] = [:]

            for flagID in flagOrder {
                let candidates: [Int] = (issuesByFlag[flagID] ?? []).compactMap(\.relatedMissionIDs.first)
                let causes: [Int] = candidates.filter { candidateID in
                    let status: MissionStatus? = diagnoses[candidateID]?.status
                    return status == .completed || status == .active
                }

                guard !causes.isEmpty else { continue }

                for issue in issuesByFlag[flagID] ?? [] {
                    replaced.insert(issue.id)
                }

                // The generic "needs flag N off" issue lists every mission
                // that could be involved; the lock issue already says which
                // one actually was.
                replaced.insert("bit-\(flagID)-requiresClear")

                if flagsByCauses[causes] == nil {
                    causeOrder.append(causes)
                }

                flagsByCauses[causes, default: []].append(flagID)
            }

            let lockIssues: [MissionIssue] = causeOrder.map { causes in
                lockIssue(
                    flagIDs: flagsByCauses[causes] ?? [],
                    causeIDs: causes,
                    lockedMissionID: missionID,
                    diagnoses: diagnoses,
                    missionsByID: missionsByID,
                    storyFlags: storyFlags
                )
            }

            guard !lockIssues.isEmpty else { continue }

            var issues: [MissionIssue] = lockIssues + diagnosis.issues.filter { !replaced.contains($0.id) }
            issues.sort { severityOrder($0.severity) < severityOrder($1.severity) }

            result[missionID] = MissionDiagnosis(
                missionID: missionID,
                status: diagnosis.status,
                explanation: diagnosis.explanation,
                parseError: diagnosis.parseError,
                issues: issues
            )
        }

        return result
    }

    private static func lockIssue(
        flagIDs: [Int],
        causeIDs: [Int],
        lockedMissionID: Int,
        diagnoses: [Int: MissionDiagnosis],
        missionsByID: [Int: MissionDefinition],
        storyFlags: [Int: StoryFlagMetadata]
    ) -> MissionIssue {
        let references: [StoryFlagReference] = flagIDs.flatMap { storyFlags[$0]?.references ?? [] }

        let causeDescriptions: [String] = causeIDs.map { causeID in
            var seenEvents: Set<String> = []
            let events: [String] = references
                .filter { $0.sourceID == causeID && $0.sourceKind == "Mission" && ($0.effect == .sets || $0.effect == .toggles) }
                .map(\.event)
                .filter { seenEvents.insert($0).inserted }
            let happened: String = diagnoses[causeID]?.status == .active ? "have in progress" : "did"
            let pronoun: String = flagIDs.count == 1 ? "the story flag" : "them"
            let eventText: String = events.isEmpty ? "" : " (it turns \(pronoun) on when \(events.joined(separator: " or ")))"
            return "you \(happened) '\(displayName(missionsByID[causeID]?.name, fallbackID: causeID))'\(eventText)"
        }

        let holderIDs: [Int] = holdingCauseIDs(causeIDs, flagIDs: flagIDs, references: references, diagnoses: diagnoses, missionsByID: missionsByID)
        let holderFamilies: Set<String> = Set(holderIDs.compactMap { MissionChainResolver.storylineFamily(of: missionsByID[$0]) })

        let releaseIDs: [Int] = releasingMissionIDs(for: flagIDs, excluding: lockedMissionID, storyFlags: storyFlags, diagnoses: diagnoses, missionsByID: missionsByID, statuses: [.available, .active])
        // Only the holding storyline's own later missions count as a future
        // way out. Other storylines also clear shared locks partway
        // through, but they can't start while the lock is on.
        let laterIDs: [Int] = releaseIDs.isEmpty
            ? releasingMissionIDs(for: flagIDs, excluding: lockedMissionID, storyFlags: storyFlags, diagnoses: diagnoses, missionsByID: missionsByID, statuses: [.blocked], onlyFamilies: holderFamilies)
            : []
        let releaseText: String = releaseDescription(flagIDs: flagIDs, releaseIDs: releaseIDs, laterIDs: laterIDs, references: references, missionsByID: missionsByID)
        let fix: LockFix = chooseFix(flagIDs: flagIDs, lockedMissionID: lockedMissionID, holderFamilies: holderFamilies, references: references, diagnoses: diagnoses, missionsByID: missionsByID, storyFlags: storyFlags)

        let flagList: String = listText(flagIDs.map(String.init))
        let storylines: [String] = uniquedStrings(holderIDs.compactMap { MissionStoryline.tag(of: missionsByID[$0]) })
        let isStorylineLock: Bool = !storylines.isEmpty && flagIDs.allSatisfy { isSharedFlag($0, storyFlags: storyFlags) }
        let title: String
        let detail: String

        if isStorylineLock {
            // Shared flags like 511 are how the game allows only one main
            // storyline at a time; naming the storyline says far more than
            // listing a dozen missions that could have set them.
            let flagsText: String = flagIDs.count == 1 ? "Story flag \(flagList) marks one as in progress, and it's on" : "Story flags \(flagList) mark one as in progress, and they're on"
            let isCertain: Bool = holderIDs.allSatisfy { diagnoses[$0]?.status == .active }
            title = "A main storyline is still in progress (\(isCertain ? "" : "most likely ")\(listText(Array(storylines.prefix(2)), joiner: "or")))"
            detail = "Only one main storyline can run at a time. \(flagsText) because \(causeDescriptions.joined(separator: "; ")). \(releaseText)"
        } else {
            let causeNames: [String] = causeIDs.prefix(2).map { displayName(missionsByID[$0]?.name, fallbackID: $0) }
            let extra: String = causeIDs.count > 2 ? " and \(causeIDs.count - 2) more" : ""
            let flagsText: String = flagIDs.count == 1
                ? "Story flag \(flagList) must be off for this mission, and it's on"
                : "Story flags \(flagList) must be off for this mission, and they're on"
            title = "Locked by '\(causeNames.joined(separator: "', '"))'\(extra)"
            detail = "\(flagsText) because \(causeDescriptions.joined(separator: "; ")). \(releaseText)"
        }

        return MissionIssue(
            id: "lock-" + flagIDs.map(String.init).joined(separator: "-"),
            severity: .blocker,
            title: title,
            detail: detail,
            relatedFlagIDs: flagIDs,
            // An in-progress mission can be both the cause and the way out.
            relatedMissionIDs: uniqued(holderIDs + causeIDs + releaseIDs + laterIDs),
            fix: fix
        )
    }

    // The causes most likely still holding the lock: missions in progress
    // if any, and otherwise not storylines that already ended (one of their
    // finished missions turned the flags back off). The save doesn't record
    // what order things happened in, so this is a best guess; if every
    // cause looks ended, all of them are kept.
    private static func holdingCauseIDs(
        _ causeIDs: [Int],
        flagIDs: [Int],
        references: [StoryFlagReference],
        diagnoses: [Int: MissionDiagnosis],
        missionsByID: [Int: MissionDefinition]
    ) -> [Int] {
        let endedFamilies: Set<String> = Set(references.compactMap { reference -> String? in
            guard reference.sourceKind == "Mission", reference.effect == .clears, reference.event == "completed" else { return nil }
            guard diagnoses[reference.sourceID]?.status == .completed else { return nil }

            return MissionChainResolver.storylineFamily(of: missionsByID[reference.sourceID])
        })

        let stillHolding: [Int] = causeIDs.filter { causeID in
            guard let family = MissionChainResolver.storylineFamily(of: missionsByID[causeID]) else { return true }
            return !endedFamilies.contains(family)
        }

        // A storyline with a mission in progress is certainly holding it.
        let candidates: [Int] = stillHolding.isEmpty ? causeIDs : stillHolding
        let active: [Int] = candidates.filter { diagnoses[$0]?.status == .active }
        return active.isEmpty ? candidates : active
    }

    // The mission outcome to copy when the editor fixes the lock: one that
    // clears every lock flag, preferring (in order) missions the player can
    // take right now, the storyline holding the lock, outcomes the player
    // can cause, outcomes that don't start another storyline lock, and
    // plain success. Falls back to clearing the flags.
    private static func chooseFix(
        flagIDs: [Int],
        lockedMissionID: Int,
        holderFamilies: Set<String>,
        references: [StoryFlagReference],
        diagnoses: [Int: MissionDiagnosis],
        missionsByID: [Int: MissionDefinition],
        storyFlags: [Int: StoryFlagMetadata]
    ) -> LockFix {
        struct Outcome: Hashable {
            let missionID: Int
            let event: String
        }

        var clearedByOutcome: [Outcome: Set<Int>] = [:]

        for reference in references where reference.sourceKind == "Mission" && reference.effect == .clears && reference.sourceID != lockedMissionID {
            clearedByOutcome[Outcome(missionID: reference.sourceID, event: reference.event), default: []].formUnion(
                flagIDs.filter { storyFlags[$0]?.references.contains(reference) == true }
            )
        }

        let complete: [Outcome] = clearedByOutcome.filter { $0.value.count == flagIDs.count }.map(\.key)

        let rank: (Outcome) -> [Int] = { outcome in
            let mission: MissionDefinition? = missionsByID[outcome.missionID]
            let status: MissionStatus? = diagnoses[outcome.missionID]?.status
            let family: String? = MissionChainResolver.storylineFamily(of: mission)
            let expression: String = mission.map { MissionCompletion.expression(for: outcome.event, of: $0) } ?? ""
            let setsSharedLock: Bool = flagsAlwaysTurnedOn(by: expression).contains { isSharedFlag($0, storyFlags: storyFlags) }

            return [
                status == .available || status == .active ? 0 : 1,
                family.map(holderFamilies.contains) == true ? 0 : 1,
                releaseRoute(event: outcome.event, mission: mission) != nil ? 0 : 1,
                setsSharedLock ? 1 : 0,
                outcome.event == "completed" ? 0 : 1,
                outcome.missionID
            ]
        }

        let best: Outcome? = complete.min { first, second in
            let firstRank: [Int] = rank(first)
            let secondRank: [Int] = rank(second)
            return firstRank != secondRank ? firstRank.lexicographicallyPrecedes(secondRank) : first.event < second.event
        }

        guard let best else { return .clearFlags(flagIDs) }
        return .missionOutcome(missionID: best.missionID, event: best.event)
    }

    private static func uniquedStrings(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0).inserted }
    }

    // First issue per ID wins.
    private static func uniquedIssues(_ issues: [MissionIssue]) -> [MissionIssue] {
        var seen: Set<String> = []
        return issues.filter { seen.insert($0.id).inserted }
    }

    private static func uniqued(_ ids: [Int]) -> [Int] {
        var seen: Set<Int> = []
        return ids.filter { seen.insert($0).inserted }
    }

    // "511, 515 and 518".
    private static func listText(_ items: [String], joiner: String = "and") -> String {
        guard items.count > 1, let last = items.last else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " \(joiner) " + last
    }

    // "story flag 285" or "story flags 285 and 6666". Flag numbers share
    // their range with mission numbers, so a bare "flag 285" reads like
    // mission 285; every flag mention names its kind.
    static func storyFlagsText(_ flagIDs: [Int]) -> String {
        let noun: String = flagIDs.count == 1 ? "story flag" : "story flags"
        return "\(noun) \(listText(flagIDs.map(String.init)))"
    }

    // How the player can make one of a mission's outcomes happen. Failing
    // is never a free choice, so it only counts when the mission has a way
    // to fail; aborting only counts when the mission allows it.
    enum ReleaseRoute: Equatable {
        case playerChoice
        case onlyIfItFails(String)
    }

    static func releaseRoute(event: String, mission: MissionDefinition?) -> ReleaseRoute? {
        guard let mission else { return nil }

        switch event {
        case "accepted", "completed", "ship objective completed":
            return .playerChoice

        case "refused":
            return mission.flags & flagCantRefuse == 0 ? .playerChoice : nil

        case "aborted":
            return mission.canAbort ? .playerChoice : nil

        case "failed":
            let reasons: [String] = failureReasons(of: mission)
            return reasons.isEmpty ? nil : .onlyIfItFails(listText(reasons, joiner: "or"))

        default:
            return nil
        }
    }

    private static let flagCantRefuse: UInt16 = 0x0004
    private static let flagFailsIfScanned: UInt16 = 0x0020
    private static let flagFailsIfBoardedByPirates: UInt16 = 0x8000
    private static let flag2FailsIfDisabled: UInt16 = 0x0004

    // The ways the Nova Bible says a mission can fail, in plain words.
    static func failureReasons(of mission: MissionDefinition) -> [String] {
        var reasons: [String] = []

        if mission.timeLimit > 0 {
            reasons.append("running out of time")
        }

        switch mission.shipGoal {
        case 1, 2: reasons.append("destroying the ships you're meant to \(mission.shipGoal == 1 ? "disable" : "board")")
        case 3, 5: reasons.append("letting the ships you're protecting be destroyed")
        default: break
        }

        if mission.flags & flagFailsIfScanned != 0 {
            reasons.append("being scanned")
        }

        if mission.flags & flagFailsIfBoardedByPirates != 0 {
            reasons.append("being boarded by pirates")
        }

        if mission.flags2 & flag2FailsIfDisabled != 0 {
            reasons.append("being disabled or destroyed")
        }

        return reasons
    }

    // Missions with one of `statuses` whose outcome turns the flags back
    // off in a way the player can bring about. Missions that clear every
    // one of the flags come first, since clearing only some leaves it
    // locked; within those, ones that don't depend on failing come first.
    private static func releasingMissionIDs(
        for flagIDs: [Int],
        excluding lockedMissionID: Int,
        storyFlags: [Int: StoryFlagMetadata],
        diagnoses: [Int: MissionDiagnosis],
        missionsByID: [Int: MissionDefinition],
        statuses: Set<MissionStatus>,
        onlyFamilies: Set<String>? = nil
    ) -> [Int] {
        var freeChoiceIDs: Set<Int> = []

        let releasersByFlag: [Set<Int>] = flagIDs.map { flagID in
            let references: [StoryFlagReference] = (storyFlags[flagID]?.references ?? []).filter { reference in
                guard reference.sourceKind == "Mission", reference.effect == .clears || reference.effect == .toggles, reference.sourceID != lockedMissionID else { return false }

                let route: ReleaseRoute? = releaseRoute(event: reference.event, mission: missionsByID[reference.sourceID])

                if route == .playerChoice {
                    freeChoiceIDs.insert(reference.sourceID)
                }

                return route != nil
            }

            return Set(references.map(\.sourceID))
        }

        let hasStatus: (Int) -> Bool = { releaserID in
            guard let status = diagnoses[releaserID]?.status, statuses.contains(status) else { return false }
            guard let onlyFamilies else { return true }

            var visiting: Set<Int> = []
            let inFamily: Bool = MissionChainResolver.storylineFamily(of: missionsByID[releaserID]).map(onlyFamilies.contains) ?? false
            return inFamily && couldStillBeOffered(releaserID, diagnoses: diagnoses, storyFlags: storyFlags, visiting: &visiting)
        }

        let ordered: (Set<Int>) -> [Int] = { ids in
            ids.filter(hasStatus).sorted { first, second in
                let firstIsFree: Bool = freeChoiceIDs.contains(first)
                let secondIsFree: Bool = freeChoiceIDs.contains(second)
                return firstIsFree != secondIsFree ? firstIsFree : first < second
            }
        }

        let clearsAll: Set<Int> = releasersByFlag.dropFirst().reduce(releasersByFlag.first ?? []) { $0.intersection($1) }
        let clearsSome: Set<Int> = releasersByFlag.reduce(Set<Int>()) { $0.union($1) }

        let preferred: [Int] = ordered(clearsAll)
        let fallback: [Int] = ordered(clearsSome)

        return Array((preferred.isEmpty ? fallback : preferred).prefix(4))
    }

    // Whether a mission that isn't offered now could still be, later. A
    // flag it needs on can only come on if a mission that hasn't happened
    // yet (and could itself still be offered) turns it on. When every such
    // mission is already done, the story took another branch: Wild Geese
    // 4a can never come up once the player went 3b, because only 3a sets
    // what 4a needs. Anything else is assumed possible, since this is a
    // hint, not a proof.
    private static func couldStillBeOffered(
        _ missionID: Int,
        diagnoses: [Int: MissionDiagnosis],
        storyFlags: [Int: StoryFlagMetadata],
        visiting: inout Set<Int>
    ) -> Bool {
        guard let diagnosis = diagnoses[missionID] else { return false }

        switch diagnosis.status {
        case .available, .active: return true
        case .completed, .impossible: return false
        case .blocked: break
        }

        // A loop back to a mission already being checked proves nothing.
        guard visiting.insert(missionID).inserted else { return false }
        defer { visiting.remove(missionID) }

        guard let explanation = diagnosis.explanation else { return true }
        return canStillBecome(explanation, true, diagnoses: diagnoses, storyFlags: storyFlags, visiting: &visiting)
    }

    private static func canStillBecome(
        _ explanation: NCBExplanation,
        _ wanted: Bool,
        diagnoses: [Int: MissionDiagnosis],
        storyFlags: [Int: StoryFlagMetadata],
        visiting: inout Set<Int>
    ) -> Bool {
        switch explanation {
        case .term(let term):
            guard term.value != wanted, wanted, case .bit(let flagID) = term.kind else { return true }

            for reference in storyFlags[flagID]?.references ?? [] where reference.effect == .sets || reference.effect == .toggles {
                guard reference.sourceKind == "Mission" else { return true }

                if couldStillBeOffered(reference.sourceID, diagnoses: diagnoses, storyFlags: storyFlags, visiting: &visiting) {
                    return true
                }
            }

            return false

        case .not(let inner, _):
            return canStillBecome(inner, !wanted, diagnoses: diagnoses, storyFlags: storyFlags, visiting: &visiting)

        case .all(let children, _):
            if wanted {
                for child in children where !canStillBecome(child, true, diagnoses: diagnoses, storyFlags: storyFlags, visiting: &visiting) {
                    return false
                }

                return true
            }

            for child in children where canStillBecome(child, false, diagnoses: diagnoses, storyFlags: storyFlags, visiting: &visiting) {
                return true
            }

            return false

        case .any(let children, _):
            if wanted {
                for child in children where canStillBecome(child, true, diagnoses: diagnoses, storyFlags: storyFlags, visiting: &visiting) {
                    return true
                }

                return false
            }

            for child in children where !canStillBecome(child, false, diagnoses: diagnoses, storyFlags: storyFlags, visiting: &visiting) {
                return false
            }

            return true
        }
    }

    private static func releaseDescription(
        flagIDs: [Int],
        releaseIDs: [Int],
        laterIDs: [Int],
        references: [StoryFlagReference],
        missionsByID: [Int: MissionDefinition]
    ) -> String {
        let flagsText: String = flagIDs.count == 1 ? storyFlagsText(flagIDs) : "these story flags"
        let itText: String = flagIDs.count == 1 ? "it" : "them"
        let anyReleaser: Bool = references.contains { $0.effect == .clears || $0.effect == .toggles }

        guard anyReleaser else {
            return "Nothing in the loaded game data turns \(flagsText) back off, so only this editor can clear \(itText)."
        }

        guard releaseIDs.isEmpty else {
            let options: [String] = releaseIDs.map { releaseOption($0, references: references, missionsByID: missionsByID) }
            return "To free it up in the game: \(options.joined(separator: "; or ")). This editor can also clear \(flagIDs.count == 1 ? "the story flag" : "the story flags") directly."
        }

        guard laterIDs.isEmpty else {
            let names: [String] = laterIDs.prefix(2).map { "'\(displayName(missionsByID[$0]?.name, fallbackID: $0))'" }
            return "Nothing you can do right now turns \(itText) off, but \(listText(names, joiner: "or")) could later, once it's offered. This editor can also clear \(itText) now."
        }

        return "Nothing you can do in the game turns \(flagsText) off any more: the story that turned \(itText) on has moved on without clearing \(itText). Only this editor can fix it."
    }

    // "abort 'X'", or "fail 'X' (only if it fails, by running out of
    // time)", plus a warning when aborting is allowed but does nothing for
    // these flags (so the player doesn't try it expecting a way out).
    private static func releaseOption(_ releaserID: Int, references: [StoryFlagReference], missionsByID: [Int: MissionDefinition]) -> String {
        let mission: MissionDefinition? = missionsByID[releaserID]
        var seenEvents: Set<String> = []
        var verbs: [String] = []
        var failNote: String = ""

        let events: [String] = references
            .filter { $0.sourceID == releaserID && $0.sourceKind == "Mission" && ($0.effect == .clears || $0.effect == .toggles) }
            .map(\.event)
            .filter { seenEvents.insert($0).inserted }

        for event in events {
            switch releaseRoute(event: event, mission: mission) {
            case .playerChoice:
                verbs.append(eventVerb(event))

            case .onlyIfItFails(let reasons):
                verbs.append(eventVerb(event))
                failNote = " (only if it fails, by \(reasons))"

            case nil:
                break
            }
        }

        let abortNote: String = mission?.canAbort == true && !events.contains("aborted") ? " (aborting it won't help)" : ""
        return "\(verbs.joined(separator: " or ")) '\(displayName(mission?.name, fallbackID: releaserID))'\(failNote)\(abortNote)"
    }

    // "aborted" -> "abort", for "To free it up: abort 'X'".
    private static func eventVerb(_ event: String) -> String {
        switch event {
        case "aborted": return "abort"
        case "failed": return "fail"
        case "refused": return "refuse"
        case "accepted": return "accept"
        case "completed": return "complete"
        case "ship objective completed": return "finish the ship objective of"
        default: return "trigger (\(event))"
        }
    }

    // "Title;Note" -> "Title (Note)".
    static func displayName(_ rawName: String?, fallbackID: Int) -> String {
        guard let rawName else { return "mission \(fallbackID)" }

        let parts: [Substring] = rawName.split(separator: ";", maxSplits: 1)
        guard parts.count == 2 else { return rawName }

        let title: String = parts[0].trimmingCharacters(in: .whitespaces)
        let note: String = parts[1].trimmingCharacters(in: .whitespaces)
        return note.isEmpty ? title : "\(title) (\(note))"
    }

    public func diagnosis(for missionID: Int) -> MissionDiagnosis? {
        precomputedDiagnoses[missionID]
    }

    public var diagnoses: [Int: MissionDiagnosis] {
        precomputedDiagnoses
    }

    public func summary(for component: MissionChainComponent, resolver: MissionChainResolver) -> ChainSummary {
        var counts: [MissionStatus: Int] = [:]
        for status in MissionStatus.allCases { counts[status] = 0 }

        for mission in component.missions {
            guard let diagnosis = precomputedDiagnoses[mission.id] else { continue }
            counts[diagnosis.status, default: 0] += 1
        }

        let stuckPoints = component.missions.filter { mission in
            guard let diagnosis = precomputedDiagnoses[mission.id],
                  diagnosis.status == .blocked || diagnosis.status == .impossible
            else { return false }

            let predecessors = resolver.predecessors(of: mission)
            if predecessors.isEmpty { return true }

            return predecessors.allSatisfy { predecessor in
                guard let predecessorDiagnosis = precomputedDiagnoses[predecessor.id] else { return false }
                return predecessorDiagnosis.status == .completed || predecessorDiagnosis.status == .active
            }
        }.map(\.id)

        let componentIDs = Set(component.missions.map(\.id))
        let conflictCount = siblingConflicts.filter {
            componentIDs.contains($0.missionAID) && componentIDs.contains($0.missionBID)
        }.count

        return ChainSummary(counts: counts, firstBlockedMissionIDs: stuckPoints, conflictCount: conflictCount)
    }

    // MARK: - Per-mission diagnosis

    private static func computeDiagnosis(
        for mission: MissionDefinition,
        parseResult: NCBParseResult,
        requiresOffBitIDs: [Int],
        isUnsatisfiable: Bool,
        missionsByID: [Int: MissionDefinition],
        storyFlags: [Int: StoryFlagMetadata],
        state: PilotStoryState,
        siblingConflicts: [SiblingConflict]
    ) -> MissionDiagnosis {
        var issues: [MissionIssue] = []

        // Evaluated before the active rule so an active mission's details
        // can still list its requirements; without it the view had nothing
        // to show and reported the expression as unreadable.
        let explanation = parseResult.node?.explain(against: state)

        // Rule: Active - the pilot has this mission in one of their 16
        // active slots right now, full stop.
        if state.activeMissionIDs.contains(mission.id) {
            return MissionDiagnosis(missionID: mission.id, status: .active, explanation: explanation, parseError: parseResult.error, issues: [])
        }

        // Rule: Completed heuristic. The standard EV Nova "one-time
        // mission" pattern is: AvailBits requires some flag OFF, and that
        // same mission's own OnSuccess (or OnAccept) turns that flag ON.
        // Once the flag is on, AvailBits can never be true again, which
        // would otherwise look identical to "permanently blocked". We can't
        // tell this apart from a *different* mission locking this one out
        // via the same flag (see the "Conflicts with" issue below) - both
        // produce the same observable state - so this is a heuristic, not a
        // certainty, and is documented as such wherever it's surfaced.
        // "Refused" missions use the same pattern via OnRefuse and are
        // reported as completed too, with a distinguishing info issue.
        //
        // The guard flag alone isn't enough proof. Flags like 511/515 are
        // shared "you're in a main storyline" locks that many missions turn
        // on, so Polaris 1 looked "done" for a pilot who had only started
        // Wild Geese. Each outcome therefore also has to show evidence:
        // every flag it turns on that few other missions touch must be on.
        if parseResult.node != nil {
            for flagID in requiresOffBitIDs where (0..<state.bits.count).contains(flagID) && state.bits[flagID] {
                let setsOnSuccessOrAccept = flagIsSetOrToggled(flagID, in: mission.onSuccess) || flagIsSetOrToggled(flagID, in: mission.onAccept)
                let successHappened = outcomeHasEvidence(
                    mission.onSuccess,
                    guardFlagID: flagID,
                    storyFlags: storyFlags,
                    state: state
                )

                if setsOnSuccessOrAccept, successHappened {
                    return MissionDiagnosis(
                        missionID: mission.id,
                        status: .completed,
                        explanation: explanation,
                        parseError: parseResult.error,
                        issues: [MissionIssue(
                            id: "completed-\(flagID)",
                            severity: .info,
                            title: "Looks already completed",
                            detail: "This mission's availability requires story flag \(flagID) to be off, and completing (or accepting) this very mission is what turns it on - the standard pattern for a one-time mission. This is a best guess: another mission could set the same flag instead (see any \"Conflicts with\" issue below).",
                            relatedFlagIDs: [flagID],
                            relatedMissionIDs: [mission.id]
                        )]
                    )
                }

                let refusalHappened = outcomeHasEvidence(
                    mission.onRefuse,
                    guardFlagID: flagID,
                    storyFlags: storyFlags,
                    state: state
                )

                if flagIsSetOrToggled(flagID, in: mission.onRefuse), refusalHappened {
                    return MissionDiagnosis(
                        missionID: mission.id,
                        status: .completed,
                        explanation: explanation,
                        parseError: parseResult.error,
                        issues: [MissionIssue(
                            id: "refused-\(flagID)",
                            severity: .info,
                            title: "You refused this mission earlier",
                            detail: "This mission's availability requires story flag \(flagID) to be off, and refusing this mission is what turns it on. It looks like it was offered and turned down.",
                            relatedFlagIDs: [flagID],
                            relatedMissionIDs: [mission.id]
                        )]
                    )
                }
            }
        }

        // From here on, this mission is not active and not (heuristically)
        // already completed - work out whether it's available, blocked, or
        // impossible, and build up every issue that explains why.

        // AvailBits: parse failure.
        if let parseError = parseResult.error {
            issues.append(MissionIssue(
                id: "parse-error",
                severity: .warning,
                title: "Could not understand this mission's availability requirement",
                detail: "The availability text couldn't be parsed (\(parseError)). This editor can't verify whether the mission is currently available - treat this mission's status as uncertain rather than trusting it outright.",
                relatedFlagIDs: [],
                relatedMissionIDs: []
            ))
        }

        if parseResult.isAmbiguous {
            issues.append(MissionIssue(
                id: "ambiguous-expression",
                severity: .warning,
                title: "Availability text mixes AND/OR without parentheses",
                detail: "\"\(mission.availBits)\" combines & and | in the same group without parentheses to make the grouping explicit. The game's own evaluator is documented as unreliable in this situation, so the requirement shown here may not exactly match what the game actually checks.",
                relatedFlagIDs: [],
                relatedMissionIDs: []
            ))
        }

        var bitsSatisfied = true
        if let explanation {
            bitsSatisfied = explanation.value

            if !bitsSatisfied {
                let blockingTerms = contributingTerms(of: explanation)
                for (term, negated) in blockingTerms {
                    issues.append(contentsOf: issuesForBlockingTerm(term, negated: negated, storyFlags: storyFlags))
                }
            }

            // Informational notes for terms that exist in the expression
            // regardless of whether they're currently blocking anything -
            // the pilot deserves to know a check depends on an assumption.
            for term in allLeaves(of: explanation) {
                switch term.kind {
                case .registered(let days):
                    issues.append(MissionIssue(
                        id: "registered-\(days)",
                        severity: .info,
                        title: "Depends on registration/trial status",
                        detail: "This mission's availability checks whether the game is registered, or fewer than \(days) day(s) have passed since install. This editor can't know that, so it was assumed true.",
                        relatedFlagIDs: [],
                        relatedMissionIDs: []
                    ))
                case .male where term.isAssumed:
                    issues.append(MissionIssue(
                        id: "gender-assumed",
                        severity: .info,
                        title: "Depends on the pilot's gender (unknown)",
                        detail: "This mission's availability checks the pilot's gender, which this pilot file doesn't specify. It was assumed to be male.",
                        relatedFlagIDs: [],
                        relatedMissionIDs: []
                    ))
                default:
                    break
                }
            }
        }

        // AvailRating.
        var ratingSatisfied = true
        if mission.availRating >= 0, state.combatRating < Int32(mission.availRating) {
            ratingSatisfied = false
            issues.append(MissionIssue(
                id: "avail-rating",
                severity: .blocker,
                title: "Needs combat rating \(mission.availRating) (currently \(state.combatRating))",
                detail: "The pilot's combat rating must be at least \(mission.availRating) for this mission to be offered. It currently stands at \(state.combatRating).",
                relatedFlagIDs: [],
                relatedMissionIDs: []
            ))
        }

        // Ship requirements from Flags/Flags2.
        let shipIssues: [MissionIssue] = state.ship.map { shipRequirementIssues(for: mission, ship: $0) } ?? []
        let shipSatisfied: Bool = !shipIssues.contains { $0.severity == .blocker }
        issues.append(contentsOf: shipIssues)

        // AvailRandom.
        if mission.availRandom == 0 {
            issues.append(MissionIssue(
                id: "avail-random-zero",
                severity: .blocker,
                title: "Never offered (0% random chance)",
                detail: "This mission's random-availability roll is 0%, so it will never be offered no matter what else is true.",
                relatedFlagIDs: [],
                relatedMissionIDs: []
            ))
        } else if mission.availRandom < 100 {
            issues.append(MissionIssue(
                id: "avail-random",
                severity: mission.availRandom <= 25 ? .warning : .info,
                title: "Only offered \(mission.availRandom)% of the time when you land",
                detail: "Re-rolled every time the system is entered, so this mission may simply not have come up yet - it isn't necessarily blocked.",
                relatedFlagIDs: [],
                relatedMissionIDs: []
            ))
        }

        // AvailRecord.
        if mission.availRecord != 0 {
            let detail: String
            switch mission.availRecord {
            case -32000:
                detail = "Requires the pilot to have dominated the stellar where this mission is offered."
            case -32001:
                detail = "Requires the pilot to have dominated at least one stellar."
            default:
                detail = "Requires a legal record in the system where this mission is offered that meets a threshold (raw value \(mission.availRecord)). This editor doesn't resolve which system that is, so it can't check this automatically."
            }
            issues.append(MissionIssue(
                id: "avail-record",
                severity: .info,
                title: "Depends on the pilot's legal record",
                detail: detail,
                relatedFlagIDs: [],
                relatedMissionIDs: []
            ))
        }

        // AvailStel / AvailLoc.
        issues.append(MissionIssue(
            id: "avail-location",
            severity: .info,
            title: "Offering location",
            detail: "Offered at: \(locationDescription(availStel: mission.availStel)) (\(offerPlaceDescription(availLoc: mission.availLoc))).",
            relatedFlagIDs: [],
            relatedMissionIDs: []
        ))

        // Conflicts: a currently-blocked flag requirement that's on because
        // another mission's outcome turned it on.
        if let explanation, !bitsSatisfied {
            // A mission can turn the same flag on at several events
            // (accepted and completed); one issue per mission is enough,
            // and issue IDs must be unique for the list views.
            var seenConflictIDs: Set<String> = []

            for (term, negated) in contributingTerms(of: explanation) {
                guard negated, case .bit(let flagID) = term.kind, term.value else { continue }
                guard let metadata = storyFlags[flagID] else { continue }
                for reference in metadata.references where reference.sourceKind == "Mission" && (reference.effect == .sets || reference.effect == .toggles) {
                    guard seenConflictIDs.insert("conflict-\(flagID)-\(reference.sourceID)").inserted else { continue }

                    issues.append(MissionIssue(
                        id: "conflict-\(flagID)-\(reference.sourceID)",
                        severity: .warning,
                        title: "Conflicts with '\(reference.sourceName)'",
                        detail: "'\(reference.sourceName)' being \(reference.event) turns on story flag \(flagID), which locks this mission out. To reach this mission, that outcome needs to not have happened (or something else needs to turn the story flag back off).",
                        relatedFlagIDs: [flagID],
                        relatedMissionIDs: [reference.sourceID]
                    ))
                }
            }
        }

        // Sibling (chain-design) conflicts - see findSiblingConflicts.
        for conflict in siblingConflicts {
            let otherID = conflict.missionAID == mission.id ? conflict.missionBID : conflict.missionAID
            let otherName = missionsByID[otherID]?.name ?? "mission \(otherID)"
            issues.append(MissionIssue(
                id: "sibling-conflict-\(conflict.flagID)-\(conflict.missionAID)-\(conflict.missionBID)",
                severity: .warning,
                title: "Mutually exclusive with '\(otherName)'",
                detail: "This mission and '\(otherName)' both branch from the same earlier mission, but completing '\(otherName)' turns on story flag \(conflict.flagID), which this mission's own availability requires to be off. Only one branch is reachable.",
                relatedFlagIDs: [conflict.flagID],
                relatedMissionIDs: [otherID]
            ))
        }

        // A flag, outfit, or system named twice in one expression would
        // otherwise produce two issues with the same ID, which list views
        // need to be unique.
        issues = uniquedIssues(issues)
        issues.sort { severityOrder($0.severity) < severityOrder($1.severity) }

        let overallSatisfied = bitsSatisfied && ratingSatisfied && shipSatisfied && mission.availRandom != 0

        if overallSatisfied, parseResult.error == nil {
            return MissionDiagnosis(missionID: mission.id, status: .available, explanation: explanation, parseError: nil, issues: issues)
        }

        // Impossible: either the AvailBits expression can never be true on
        // its own (checked via brute-force truth table when there are few
        // enough distinct atoms to make that cheap), or a bit requirement
        // that's currently blocking this mission is never touched by
        // anything in the loaded game data in the direction that would fix
        // it. Both are worded carefully in the issue text below, since the
        // loaded scenario data may not cover every source (e.g. plugin
        // content not present here).
        if parseResult.node != nil, !bitsSatisfied {
            if isUnsatisfiable {
                issues.insert(MissionIssue(
                    id: "impossible-unsatisfiable",
                    severity: .blocker,
                    title: "This availability requirement can never be true",
                    detail: "\"\(mission.availBits)\" is unsatisfiable by itself - no combination of story flags, outfits, or exploration could ever make it true. This looks like a mistake in the mission data rather than something the pilot can fix.",
                    relatedFlagIDs: [],
                    relatedMissionIDs: []
                ), at: 0)
                return MissionDiagnosis(missionID: mission.id, status: .impossible, explanation: explanation, parseError: nil, issues: issues)
            }

            for (term, negated) in contributingTerms(of: explanation!) {
                guard case .bit(let flagID) = term.kind else { continue }
                let metadata = storyFlags[flagID]
                let everTurnsItOn = metadata?.references.contains { $0.effect == .sets || $0.effect == .toggles } ?? false
                let everTurnsItOff = metadata?.references.contains { $0.effect == .clears || $0.effect == .toggles } ?? false

                if !negated, !everTurnsItOn {
                    issues.insert(MissionIssue(
                        id: "impossible-bit-\(flagID)-never-set",
                        severity: .blocker,
                        title: "Story flag \(flagID) is never turned on by anything loaded",
                        detail: "This mission requires story flag \(flagID) to be on, but nothing in the loaded game data ever sets or toggles it. The catalog may not cover every source (e.g. plugin content not loaded here), so treat this as a strong warning rather than absolute proof.",
                        relatedFlagIDs: [flagID],
                        relatedMissionIDs: []
                    ), at: 0)
                    return MissionDiagnosis(missionID: mission.id, status: .impossible, explanation: explanation, parseError: nil, issues: issues)
                }

                if negated, !everTurnsItOff {
                    issues.insert(MissionIssue(
                        id: "impossible-bit-\(flagID)-never-cleared",
                        severity: .blocker,
                        title: "Story flag \(flagID) is never turned off by anything loaded",
                        detail: "This mission requires story flag \(flagID) to be off, and it's currently on, but nothing in the loaded game data ever clears or toggles it back off. The catalog may not cover every source, so treat this as a strong warning rather than absolute proof.",
                        relatedFlagIDs: [flagID],
                        relatedMissionIDs: []
                    ), at: 0)
                    return MissionDiagnosis(missionID: mission.id, status: .impossible, explanation: explanation, parseError: nil, issues: issues)
                }
            }
        }

        return MissionDiagnosis(missionID: mission.id, status: .blocked, explanation: explanation, parseError: parseResult.error, issues: issues)
    }

    // The ship-dependent offer rules from mïsn Flags/Flags2. The game
    // silently skips the mission when one fails, so these are the reasons
    // hardest to spot in play.
    static func shipRequirementIssues(for mission: MissionDefinition, ship: PilotShipState) -> [MissionIssue] {
        var issues: [MissionIssue] = []
        let capacity: ShipCapacity = ship.capacity

        if mission.flags2 & MissionDefinition.flag2NeedsCargoSpace != 0, mission.cargoQty != -1, mission.cargoQty != 0 {
            let free: Int = capacity.freeCargo

            // CargoQty of -2 and below means abs(value) tons, give or take
            // 50%, rolled when the mission is offered.
            let fewest: Int = mission.cargoQty > 0 ? Int(mission.cargoQty) : abs(Int(mission.cargoQty)) / 2
            let most: Int = mission.cargoQty > 0 ? Int(mission.cargoQty) : abs(Int(mission.cargoQty)) * 3 / 2
            let needed: String = fewest == most ? "\(most) tons" : "\(fewest) to \(most) tons"

            if free < most {
                issues.append(MissionIssue(
                    id: "ship-cargo-space",
                    severity: free < fewest ? .blocker : .warning,
                    title: "Needs \(needed) of free cargo space (you have \(free))",
                    detail: "The game won't offer this mission unless the mission cargo fits in your hold, even if it's picked up later. \(cargoBreakdown(capacity)) Free up space by selling cargo or removing outfits that take hold space, or fly a ship with bigger holds.",
                    relatedFlagIDs: [],
                    relatedMissionIDs: []
                ))
            }
        }

        let isCargoShip: Bool = ship.inherentAI == 1 || ship.inherentAI == 2
        let isWarship: Bool = ship.inherentAI == 3 || ship.inherentAI == 4

        if mission.flags & MissionDefinition.flagNotForCargoShips != 0, isCargoShip {
            issues.append(MissionIssue(
                id: "ship-not-cargo",
                severity: .blocker,
                title: "Not offered to cargo ships",
                detail: "The game won't offer this mission while you fly a cargo-type ship, and the \(GameName(ship.name).full) is one.",
                relatedFlagIDs: [],
                relatedMissionIDs: []
            ))
        }

        if mission.flags & MissionDefinition.flagNotForWarships != 0, isWarship {
            issues.append(MissionIssue(
                id: "ship-not-warship",
                severity: .blocker,
                title: "Not offered to warships",
                detail: "The game won't offer this mission while you fly a warship, and the \(GameName(ship.name).full) is one.",
                relatedFlagIDs: [],
                relatedMissionIDs: []
            ))
        }

        if mission.flags & MissionDefinition.flagDrainsFuel != 0, ship.fuel < 100 {
            issues.append(MissionIssue(
                id: "ship-fuel",
                severity: .blocker,
                title: "Needs at least 100 fuel (you have \(ship.fuel))",
                detail: "This mission takes 100 fuel (one jump) and isn't offered with less in the tank.",
                relatedFlagIDs: [],
                relatedMissionIDs: []
            ))
        }

        return issues
    }

    // "Holds 20 tons, Mass Retool -12, 0 aboard." style summary.
    private static func cargoBreakdown(_ capacity: ShipCapacity) -> String {
        var parts: [String] = ["Your ship holds \(capacity.baseCargo) tons"]

        for adjustment in capacity.cargoAdjustments {
            let sign: String = adjustment.amount > 0 ? "+" : ""
            let copies: String = adjustment.count > 1 ? " x\(adjustment.count)" : ""
            parts.append("\(GameName(adjustment.outfitName).full)\(copies) \(sign)\(adjustment.amount)")
        }

        var text: String = parts.joined(separator: ", ") + ", for \(capacity.cargoCapacity) tons in all."

        if capacity.cargoAboard > 0 {
            text += " \(capacity.cargoAboard) tons are already aboard."
        }

        return text
    }

    private static func severityOrder(_ severity: IssueSeverity) -> Int {
        switch severity {
        case .blocker: return 0
        case .warning: return 1
        case .info: return 2
        }
    }

    // MARK: - Blocking-term issue text

    private static func issuesForBlockingTerm(
        _ term: NCBTermEvaluation,
        negated: Bool,
        storyFlags: [Int: StoryFlagMetadata]
    ) -> [MissionIssue] {
        switch term.kind {
        case .bit(let flagID):
            if !negated {
                let (sourceText, sourceMissionIDs) = describeSources(
                    flagID: flagID,
                    storyFlags: storyFlags,
                    effects: [.sets, .toggles],
                    verbPhrase: "turned on",
                    emptyMessage: "Nothing in the loaded game data ever turns story flag \(flagID) on - it may never be reachable, or may be set by something this catalog doesn't cover."
                )
                return [MissionIssue(
                    id: "bit-\(flagID)-requiresSet",
                    severity: .blocker,
                    title: "Needs story flag \(flagID) on (currently off)",
                    detail: "Needs story flag \(flagID) on. \(sourceText)",
                    relatedFlagIDs: [flagID],
                    relatedMissionIDs: sourceMissionIDs
                )]
            } else {
                let (onText, onMissionIDs) = describeSources(
                    flagID: flagID,
                    storyFlags: storyFlags,
                    effects: [.sets, .toggles],
                    verbPhrase: "turned on",
                    emptyMessage: "Nothing in the loaded game data records what turned story flag \(flagID) on."
                )
                let (offText, offMissionIDs) = describeSources(
                    flagID: flagID,
                    storyFlags: storyFlags,
                    effects: [.clears, .toggles],
                    verbPhrase: "turned back off",
                    emptyMessage: "Nothing in the loaded game data ever turns story flag \(flagID) back off, so this mission may be permanently locked out once that happens."
                )
                return [MissionIssue(
                    id: "bit-\(flagID)-requiresClear",
                    severity: .blocker,
                    title: "Needs story flag \(flagID) off (currently on)",
                    detail: "Needs story flag \(flagID) off, but it's currently on. \(onText) To fix it: \(offText)",
                    relatedFlagIDs: [flagID],
                    relatedMissionIDs: Array(Set(onMissionIDs + offMissionIDs))
                )]
            }

        case .outfit(let outfitID):
            let title = negated ? "Requires NOT owning outfit \(outfitID)" : "Requires owning outfit \(outfitID)"
            let detail = negated
                ? "The pilot must not own any of outfit item \(outfitID)."
                : "The pilot needs to own at least one of outfit item \(outfitID)."
            return [MissionIssue(id: "outfit-\(outfitID)-\(negated)", severity: .blocker, title: title, detail: detail, relatedFlagIDs: [], relatedMissionIDs: [])]

        case .explored(let systemID):
            let title = negated ? "Requires NOT having explored system \(systemID)" : "Requires having explored system \(systemID)"
            let detail = negated
                ? "The pilot must not have explored system \(systemID) yet."
                : "The pilot needs to have explored system \(systemID)."
            return [MissionIssue(id: "explored-\(systemID)-\(negated)", severity: .blocker, title: title, detail: detail, relatedFlagIDs: [], relatedMissionIDs: [])]

        case .male:
            let requiresMale = !negated
            return [MissionIssue(
                id: "gender-requirement",
                severity: term.isAssumed ? .warning : .blocker,
                title: requiresMale ? "Requires the pilot to be male" : "Requires the pilot to be female",
                detail: term.isAssumed
                    ? "This pilot file doesn't specify a gender, so it was assumed male - this may not reflect the real pilot."
                    : "The pilot's recorded gender doesn't match this requirement.",
                relatedFlagIDs: [],
                relatedMissionIDs: []
            )]

        case .registered:
            // Always assumed true (see NCBTestExpression's evaluator), so
            // this can only appear here if negated - i.e. the expression
            // requires the registration/trial check to fail, which this
            // editor can never confirm either way.
            return [MissionIssue(
                id: "registered-blocking",
                severity: .info,
                title: "Depends on registration/trial status",
                detail: "This mission's availability requires the registration/trial-period check to evaluate false, which this editor can't verify - it's assumed true, which may be blocking this mission incorrectly.",
                relatedFlagIDs: [],
                relatedMissionIDs: []
            )]
        }
    }

    private static func describeSources(
        flagID: Int,
        storyFlags: [Int: StoryFlagMetadata],
        effects: Set<StoryFlagEffect>,
        verbPhrase: String,
        emptyMessage: String
    ) -> (text: String, missionIDs: [Int]) {
        guard let metadata = storyFlags[flagID] else {
            return (emptyMessage, [])
        }

        let matches = metadata.references.filter { effects.contains($0.effect) }
        guard !matches.isEmpty else {
            return (emptyMessage, [])
        }

        let phrases = matches.prefix(4).map { reference in
            "\(reference.sourceKind.lowercased()) '\(reference.sourceName)' is \(reference.event)"
        }
        let missionIDs = matches.filter { $0.sourceKind == "Mission" }.map(\.sourceID)
        let text = "It is \(verbPhrase) when " + phrases.joined(separator: ", or when ") + "."
        return (text, missionIDs)
    }

    // MARK: - Location text

    // Name-free wording of the location code; MissionLocationCode does the
    // decoding so this can't drift from the details view or the map.
    public static func locationDescription(availStel: Int16) -> String {
        switch MissionLocationCode(availStel) {
        case .anyInhabited:
            return "any inhabited stellar"
        case .stellar(let stellarID):
            return "stellar \(stellarID)"
        case .adjacentToSystem(let systemID):
            return "a stellar in a system adjacent to system \(systemID)"
        case .government(let governmentID):
            return "a stellar belonging to \(governmentText(governmentID))"
        case .allyOf(let governmentID):
            return "a stellar belonging to an ally of \(governmentText(governmentID))"
        case .notGovernment(let governmentID):
            return "a stellar belonging to anyone but \(governmentText(governmentID))"
        case .enemyOf(let governmentID):
            return "a stellar belonging to an enemy of \(governmentText(governmentID))"
        case .governmentOrClass(let governmentID):
            return "a stellar belonging to \(governmentText(governmentID)) or one of its classmates"
        case .neitherGovernmentNorClass(let governmentID):
            return "a stellar belonging to neither \(governmentText(governmentID)) nor any of its classmates"
        case .unrecognized(let value):
            return "an unrecognized location code (\(value))"
        }
    }

    private static func governmentText(_ governmentID: Int?) -> String {
        governmentID.map { "government \($0)" } ?? "independents"
    }

    public static func offerPlaceDescription(availLoc: Int16) -> String {
        switch availLoc {
        case 0: return "mission computer"
        case 1: return "bar"
        case 2: return "from ship"
        case 3: return "spaceport"
        case 4: return "trading dialog"
        case 5: return "shipyard"
        case 6: return "outfitter"
        default: return "unrecognized location kind (\(availLoc))"
        }
    }

    // MARK: - Structural helpers (operate on the parsed expression itself,
    // independent of any particular pilot's current state)

    // Every leaf term in the tree that sits under an odd number of `!`
    // wrappers - i.e. every term the expression structurally requires to be
    // FALSE, independent of any pilot's actual current state. Always start
    // the walk at the root with no enclosing NOT yet seen (`negated: false`
    // in the private recursive helper); the helper flips that flag each
    // time it steps into a `.not`, and only records a leaf once that
    // running flag is true.
    private static func requiresOffLeaves(of node: NCBNode) -> [NCBTermKind] {
        var result: [NCBTermKind] = []
        collectLeaves(node, negated: false, into: &result)
        return result
    }

    private static func collectLeaves(_ node: NCBNode, negated: Bool, into result: inout [NCBTermKind]) {
        switch node {
        case .bit(let id): if negated { result.append(.bit(id)) }
        case .registered(let days): if negated { result.append(.registered(days: days)) }
        case .male: if negated { result.append(.male) }
        case .outfit(let id): if negated { result.append(.outfit(id)) }
        case .explored(let id): if negated { result.append(.explored(id)) }
        case .not(let inner): collectLeaves(inner, negated: !negated, into: &result)
        case .and(let xs), .or(let xs):
            for x in xs { collectLeaves(x, negated: negated, into: &result) }
        }
    }

    // Every leaf term evaluation in an explanation tree, regardless of
    // value or whether it's currently contributing to the result - used for
    // "this expression depends on an assumption" informational notes.
    private static func allLeaves(of explanation: NCBExplanation) -> [NCBTermEvaluation] {
        switch explanation {
        case .term(let term): return [term]
        case .not(let inner, _): return allLeaves(of: inner)
        case .all(let subs, _), .any(let subs, _): return subs.flatMap(allLeaves)
        }
    }

    // The leaf term evaluations that are genuinely responsible for
    // `explanation`'s current value, honoring AND/OR short-circuit
    // semantics: for a false AND, only its false children are at fault (the
    // true ones didn't stop anything); for a false OR, every child is false
    // and all are at fault; a NOT simply flips which value each descendant
    // is being sought for. `negated` in the result tracks how many NOTs
    // were crossed to reach that leaf, needed to know whether a bit is
    // required on or off. Since this function is only ever invoked at the
    // top with `explanation`'s own true value, and every recursive call
    // passes down the exact value of the node it's about to visit, the two
    // must be equal at each step, which is why it can walk by value alone
    // rather than needing to compare against a target.
    private static func contributingTerms(of explanation: NCBExplanation) -> [(kind: NCBTermEvaluation, negated: Bool)] {
        var result: [(kind: NCBTermEvaluation, negated: Bool)] = []
        collectContributingTerms(explanation, negated: false, into: &result)
        return result
    }

    private static func collectContributingTerms(
        _ explanation: NCBExplanation,
        negated: Bool,
        into result: inout [(kind: NCBTermEvaluation, negated: Bool)]
    ) {
        switch explanation {
        case .term(let term):
            result.append((term, negated))
        case .not(let inner, _):
            collectContributingTerms(inner, negated: !negated, into: &result)
        case .all(let subs, let value):
            if value {
                for sub in subs { collectContributingTerms(sub, negated: negated, into: &result) }
            } else {
                for sub in subs where !sub.value { collectContributingTerms(sub, negated: negated, into: &result) }
            }
        case .any(let subs, let value):
            if value {
                for sub in subs where sub.value { collectContributingTerms(sub, negated: negated, into: &result) }
            } else {
                for sub in subs { collectContributingTerms(sub, negated: negated, into: &result) }
            }
        }
    }

    // MARK: - Satisfiability

    private enum AtomKey: Hashable {
        case bit(Int)
        case registered(Int)
        case male
        case outfit(Int)
        case explored(Int)
    }

    private static func atomKey(_ kind: NCBTermKind) -> AtomKey {
        switch kind {
        case .bit(let id): return .bit(id)
        case .registered(let days): return .registered(days)
        case .male: return .male
        case .outfit(let id): return .outfit(id)
        case .explored(let id): return .explored(id)
        }
    }

    private static func distinctAtoms(_ node: NCBNode) -> Set<AtomKey> {
        switch node {
        case .bit(let id): return [.bit(id)]
        case .registered(let days): return [.registered(days)]
        case .male: return [.male]
        case .outfit(let id): return [.outfit(id)]
        case .explored(let id): return [.explored(id)]
        case .not(let inner): return distinctAtoms(inner)
        case .and(let xs), .or(let xs):
            return xs.reduce(into: Set<AtomKey>()) { $0.formUnion(distinctAtoms($1)) }
        }
    }

    private static func evaluate(_ node: NCBNode, assignment: [AtomKey: Bool]) -> Bool {
        switch node {
        case .bit(let id): return assignment[.bit(id)] ?? false
        case .registered(let days): return assignment[.registered(days)] ?? false
        case .male: return assignment[.male] ?? false
        case .outfit(let id): return assignment[.outfit(id)] ?? false
        case .explored(let id): return assignment[.explored(id)] ?? false
        case .not(let inner): return !evaluate(inner, assignment: assignment)
        case .and(let xs): return xs.allSatisfy { evaluate($0, assignment: assignment) }
        case .or(let xs): return xs.contains { evaluate($0, assignment: assignment) }
        }
    }

    // Brute-force truth table over the expression's own distinct atoms
    // (ignoring the pilot's actual state entirely) - returns true if NO
    // assignment of those atoms can make it true, nil if there are too many
    // distinct atoms (>16) to check cheaply, matching the task's specified
    // cutoff.
    private static func isStructurallyUnsatisfiable(_ node: NCBNode) -> Bool? {
        let atoms = Array(distinctAtoms(node))
        guard atoms.count <= 16 else { return nil }

        let combinations = 1 << atoms.count
        for mask in 0..<combinations {
            var assignment: [AtomKey: Bool] = [:]
            for (index, atom) in atoms.enumerated() {
                assignment[atom] = (mask >> index) & 1 == 1
            }
            if evaluate(node, assignment: assignment) {
                return false
            }
        }
        return true
    }

    // MARK: - Flag mutation lookup

    private static func flagIsSetOrToggled(_ flagID: Int, in setExpression: String) -> Bool {
        StoryFlagCatalog.bitOperations(in: setExpression, isTest: false)
            .contains { $0.id == flagID && ($0.effect == .sets || $0.effect == .toggles) }
    }

    // More missions than this turning a flag on makes it a shared marker
    // (e.g. 511 "a main storyline is in progress"), not proof that one
    // particular mission happened.
    static let sharedFlagSetterLimit = 3

    static func isSharedFlag(_ flagID: Int, storyFlags: [Int: StoryFlagMetadata]) -> Bool {
        let setters: Set<Int> = Set(
            (storyFlags[flagID]?.references ?? [])
                .filter { $0.sourceKind == "Mission" && ($0.effect == .sets || $0.effect == .toggles) }
                .map(\.sourceID)
        )
        return setters.count > sharedFlagSetterLimit
    }

    // Flags an outcome always turns on: plain sets, not toggles and not
    // one side of an R(...) random choice.
    static func flagsAlwaysTurnedOn(by setExpression: String) -> [Int] {
        let randomIDs: Set<Int> = NCBSetExpression.flagIDsInsideRandomChoices(in: setExpression)

        return StoryFlagCatalog.bitOperations(in: setExpression, isTest: false)
            .filter { $0.effect == .sets && !randomIDs.contains($0.id) }
            .map(\.id)
    }

    // Whether the pilot's flags show this outcome (success or refusal)
    // really happened. Every flag the outcome always turns on that isn't a
    // shared marker must be on. With no such flags to check, only a guard
    // flag that isn't shared counts as proof.
    private static func outcomeHasEvidence(
        _ setExpression: String,
        guardFlagID: Int,
        storyFlags: [Int: StoryFlagMetadata],
        state: PilotStoryState
    ) -> Bool {
        let evidence: [Int] = flagsAlwaysTurnedOn(by: setExpression)
            .filter { !isSharedFlag($0, storyFlags: storyFlags) }

        guard !evidence.isEmpty else {
            return !isSharedFlag(guardFlagID, storyFlags: storyFlags)
        }

        return evidence.allSatisfy { flagID in
            (0..<state.bits.count).contains(flagID) && state.bits[flagID]
        }
    }

    // MARK: - Sibling (chain-design) conflicts

    // Two missions "started from the same predecessor outcome set" - i.e.
    // both appear among some third mission's chained (Sxxx) targets, via
    // any trigger - are candidate story branches. If one's own outcome sets
    // or toggles a flag the other's AvailBits structurally requires off,
    // that is a design-level mutual exclusion worth surfacing even before
    // looking at the pilot's current state (which is what the separate
    // state-based "Conflicts with" issue covers). This intentionally does
    // not try to distinguish an R(...) exclusive-random branch from two
    // triggers that both fire unconditionally - either way, one outcome
    // locking the other's requirement out is worth a warning.
    private static func findSiblingConflicts(
        missions: [MissionDefinition],
        parsedByID: [Int: NCBParseResult]
    ) -> [SiblingConflict] {
        var missionsByID: [Int: MissionDefinition] = [:]
        for mission in missions { missionsByID[mission.id] = mission }

        var childrenByParent: [Int: Set<Int>] = [:]
        for mission in missions {
            let targets = Set(mission.allChainedMissionIDs).filter { missionsByID[$0] != nil }
            if targets.count > 1 {
                childrenByParent[mission.id] = targets
            }
        }

        // Structurally-required-off bit IDs per mission, computed once.
        var requiresOffByID: [Int: Set<Int>] = [:]
        for mission in missions {
            guard let node = parsedByID[mission.id]?.node else { continue }
            let bitIDs = requiresOffLeaves(of: node).compactMap { kind -> Int? in
                if case .bit(let id) = kind { return id }
                return nil
            }
            requiresOffByID[mission.id] = Set(bitIDs)
        }

        var conflicts: [SiblingConflict] = []
        var seenPairs: Set<String> = []

        for (_, childIDs) in childrenByParent {
            let sortedChildren = childIDs.sorted()
            for i in 0..<sortedChildren.count {
                for j in (i + 1)..<sortedChildren.count {
                    let aID = sortedChildren[i]
                    let bID = sortedChildren[j]
                    guard let missionA = missionsByID[aID], let missionB = missionsByID[bID] else { continue }

                    let aSets = allSetOrToggledFlags(of: missionA)
                    if let requiredOffByB = requiresOffByID[bID] {
                        for flagID in aSets.intersection(requiredOffByB) {
                            let key = "\(aID)-\(bID)-\(flagID)"
                            if seenPairs.insert(key).inserted {
                                conflicts.append(SiblingConflict(missionAID: aID, missionBID: bID, flagID: flagID))
                            }
                        }
                    }

                    let bSets = allSetOrToggledFlags(of: missionB)
                    if let requiredOffByA = requiresOffByID[aID] {
                        for flagID in bSets.intersection(requiredOffByA) {
                            let key = "\(bID)-\(aID)-\(flagID)"
                            if seenPairs.insert(key).inserted {
                                conflicts.append(SiblingConflict(missionAID: bID, missionBID: aID, flagID: flagID))
                            }
                        }
                    }
                }
            }
        }

        return conflicts
    }

    private static func allSetOrToggledFlags(of mission: MissionDefinition) -> Set<Int> {
        let expressions = [mission.onAccept, mission.onRefuse, mission.onSuccess, mission.onFailure, mission.onAbort, mission.onShipDone]
        var result: Set<Int> = []
        for expression in expressions {
            for operation in StoryFlagCatalog.bitOperations(in: expression, isTest: false) where operation.effect == .sets || operation.effect == .toggles {
                result.insert(operation.id)
            }
        }
        return result
    }
}
