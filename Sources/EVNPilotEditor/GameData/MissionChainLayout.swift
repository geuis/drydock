import Foundation

// Places a story chain's missions on a top-to-bottom grid for drawing as a
// flowchart, in the style of the classic EV Nova walkthroughs: each mission
// sits one row below the missions that lead to it, and alternate tracks
// (A/B branches, accept/refuse paths) sit side by side in the same row.
//
// A standard layered ("Sugiyama") layout, kept simple:
//   1. Links that loop back (to a mission already on the current path) are
//      set aside so the rest forms a tree-like graph.
//   2. Each mission's row is the longest path to it from a starting mission,
//      so a mission always appears below everything that leads to it.
//   3. Missions within a row are ordered by the average position of their
//      neighbours, a few passes down and up, which keeps lines from crossing.
public struct MissionChainLayout: Sendable, Equatable {
    public struct Placement: Sendable, Equatable {
        public let row: Int
        // Left-to-right slot within the row, 0-based.
        public let slot: Int
        // Horizontal position in column widths. Missions sit under the
        // missions that lead to them, so a straight run of a storyline is a
        // straight line even when a neighbouring row is wide. Can be
        // negative; only differences matter.
        public let column: Double
    }

    public struct Link: Sendable, Equatable, Hashable {
        public let fromID: Int
        public let toID: Int
        // Points back up the chart (a repeatable mission or a loop).
        public let loopsBack: Bool
    }

    public let placements: [Int: Placement]
    public let links: [Link]
    public let rowCount: Int
    // The widest row, for sizing the chart.
    public let maxRowWidth: Int
    // Missions per row, left to right.
    public let rows: [[Int]]

    // Enough to settle typical storylines; more passes rarely change much.
    static let orderingPasses = 4

    public init(chain: MissionChainComponent, resolver: MissionChainResolver) {
        let memberIDs: [Int] = chain.missions.map(\.id)
        let members: Set<Int> = Set(memberIDs)
        var successors: [Int: [Int]] = [:]

        for mission in chain.missions {
            successors[mission.id] = resolver.successors(of: mission)
                .map(\.id)
                .filter { members.contains($0) && $0 != mission.id }
        }

        self.init(memberIDs: memberIDs, rootIDs: chain.rootMissionIDs, successors: successors)
    }

    // Separate from the resolver so the layout rules can be tested with
    // small hand-built graphs.
    init(memberIDs: [Int], rootIDs: [Int], successors: [Int: [Int]]) {
        let orderedIDs: [Int] = Self.searchOrder(memberIDs: memberIDs, rootIDs: rootIDs, successors: successors)
        let backLinks: Set<Link> = Self.findBackLinks(order: orderedIDs, successors: successors)

        var links: [Link] = []

        for fromID in orderedIDs {
            for toID in successors[fromID] ?? [] {
                let loopsBack: Bool = backLinks.contains(Link(fromID: fromID, toID: toID, loopsBack: true))
                links.append(Link(fromID: fromID, toID: toID, loopsBack: loopsBack))
            }
        }

        let forwardLinks: [Link] = links.filter { !$0.loopsBack }
        let rowByID: [Int: Int] = Self.assignRows(order: orderedIDs, forwardLinks: forwardLinks)
        let rowCount: Int = (rowByID.values.max() ?? -1) + 1

        var rows: [[Int]] = Array(repeating: [], count: rowCount)

        for missionID in orderedIDs {
            if let row = rowByID[missionID] {
                rows[row].append(missionID)
            }
        }

        rows = Self.reduceCrossings(rows: rows, forwardLinks: forwardLinks)

        let columns: [Int: Double] = Self.assignColumns(rows: rows, forwardLinks: forwardLinks)
        var placements: [Int: Placement] = [:]

        for (rowIndex, row) in rows.enumerated() {
            for (slot, missionID) in row.enumerated() {
                placements[missionID] = Placement(row: rowIndex, slot: slot, column: columns[missionID] ?? Double(slot))
            }
        }

        self.placements = placements
        self.links = links
        self.rowCount = rowCount
        self.maxRowWidth = rows.map(\.count).max() ?? 0
        self.rows = rows
        self.minColumn = columns.values.min() ?? 0
        self.maxColumn = columns.values.max() ?? 0
    }

    // Leftmost and rightmost column positions, for sizing the chart.
    public let minColumn: Double
    public let maxColumn: Double

    // The middle of the first row, where the story starts.
    public var startColumn: Double {
        let first: [Double] = rows.first?.compactMap { placements[$0]?.column } ?? []
        guard let low = first.min(), let high = first.max() else { return 0 }

        return (low + high) / 2
    }

    // MARK: - Steps

    // Depth-first from each starting mission, then from anything a loop
    // left unreached, so every member gets visited exactly once.
    private static func searchOrder(memberIDs: [Int], rootIDs: [Int], successors: [Int: [Int]]) -> [Int] {
        var visited: Set<Int> = []
        var order: [Int] = []
        let starts: [Int] = rootIDs + memberIDs.sorted()

        for startID in starts where !visited.contains(startID) {
            var stack: [Int] = [startID]

            while let missionID = stack.popLast() {
                guard visited.insert(missionID).inserted else { continue }

                order.append(missionID)

                // Reversed so the first successor is visited first.
                for nextID in (successors[missionID] ?? []).reversed() where !visited.contains(nextID) {
                    stack.append(nextID)
                }
            }
        }

        return order
    }

    // A link is a back link when it reaches a mission that's still on the
    // current depth-first path, i.e. it closes a loop.
    private static func findBackLinks(order: [Int], successors: [Int: [Int]]) -> Set<Link> {
        enum Mark { case onPath, done }

        var marks: [Int: Mark] = [:]
        var backLinks: Set<Link> = []

        for startID in order where marks[startID] == nil {
            // Explicit stack of (mission, next successor index) so deep
            // storylines can't overflow the call stack.
            var stack: [(id: Int, nextIndex: Int)] = [(startID, 0)]
            marks[startID] = .onPath

            while let top = stack.last {
                let next: [Int] = successors[top.id] ?? []

                guard top.nextIndex < next.count else {
                    marks[top.id] = .done
                    stack.removeLast()
                    continue
                }

                stack[stack.count - 1].nextIndex += 1
                let targetID: Int = next[top.nextIndex]

                switch marks[targetID] {
                case .onPath:
                    backLinks.insert(Link(fromID: top.id, toID: targetID, loopsBack: true))

                case .done:
                    break

                case nil:
                    marks[targetID] = .onPath
                    stack.append((targetID, 0))
                }
            }
        }

        return backLinks
    }

    // Longest path from a start, in topological order (Kahn's algorithm).
    private static func assignRows(order: [Int], forwardLinks: [Link]) -> [Int: Int] {
        var incoming: [Int: Int] = Dictionary(uniqueKeysWithValues: order.map { ($0, 0) })
        var outgoing: [Int: [Int]] = [:]

        for link in forwardLinks {
            incoming[link.toID, default: 0] += 1
            outgoing[link.fromID, default: []].append(link.toID)
        }

        var rowByID: [Int: Int] = [:]
        var ready: [Int] = order.filter { incoming[$0] == 0 }
        var readIndex: Int = 0

        for missionID in ready {
            rowByID[missionID] = 0
        }

        while readIndex < ready.count {
            let missionID: Int = ready[readIndex]
            readIndex += 1

            for nextID in outgoing[missionID] ?? [] {
                rowByID[nextID] = max(rowByID[nextID] ?? 0, (rowByID[missionID] ?? 0) + 1)
                incoming[nextID, default: 0] -= 1

                if incoming[nextID] == 0 {
                    ready.append(nextID)
                }
            }
        }

        return rowByID
    }

    // Barycenter ordering: sort each row by where its neighbours sit in the
    // row above (going down) or below (going up).
    private static func reduceCrossings(rows: [[Int]], forwardLinks: [Link]) -> [[Int]] {
        var rows: [[Int]] = rows
        var parents: [Int: [Int]] = [:]
        var children: [Int: [Int]] = [:]

        for link in forwardLinks {
            parents[link.toID, default: []].append(link.fromID)
            children[link.fromID, default: []].append(link.toID)
        }

        for _ in 0..<orderingPasses {
            for rowIndex in rows.indices.dropFirst() {
                rows[rowIndex] = sortedByNeighbours(rows[rowIndex], neighbours: parents, positions: slotPositions(rows))
            }

            for rowIndex in rows.indices.reversed().dropFirst() {
                rows[rowIndex] = sortedByNeighbours(rows[rowIndex], neighbours: children, positions: slotPositions(rows))
            }
        }

        return rows
    }

    // Top to bottom, each mission aims for the average position of the
    // missions that lead to it. A row's missions then get pushed apart to
    // at least one column each (keeping their order), and the whole row
    // slides so it's off its targets by as little as possible on average.
    // An only child lands straight under its parent; siblings fan out.
    private static func assignColumns(rows: [[Int]], forwardLinks: [Link]) -> [Int: Double] {
        var parents: [Int: [Int]] = [:]

        for link in forwardLinks {
            parents[link.toID, default: []].append(link.fromID)
        }

        var columns: [Int: Double] = [:]

        for row in rows {
            let targets: [Double] = columnTargets(for: row, parents: parents, placed: columns)
            var positions: [Double] = []

            for target in targets {
                let leftLimit: Double = (positions.last ?? -Double.infinity) + 1
                positions.append(max(target, leftLimit))
            }

            let drift: Double = zip(targets, positions).reduce(0) { $0 + ($1.0 - $1.1) } / Double(max(positions.count, 1))

            for (missionID, position) in zip(row, positions) {
                columns[missionID] = position + drift
            }
        }

        return columns
    }

    // Where each mission in a row would like to sit. Missions with no
    // placed parent (a first row, or one reached only by a loop) line up
    // next to their neighbours instead.
    private static func columnTargets(for row: [Int], parents: [Int: [Int]], placed: [Int: Double]) -> [Double] {
        var targets: [Double?] = row.map { missionID in
            let parentColumns: [Double] = (parents[missionID] ?? []).compactMap { placed[$0] }
            guard !parentColumns.isEmpty else { return nil }

            return parentColumns.reduce(0, +) / Double(parentColumns.count)
        }

        // Nothing to go on: centre the row on zero.
        if targets.allSatisfy({ $0 == nil }) {
            return row.indices.map { Double($0) - Double(row.count - 1) / 2 }
        }

        for index in targets.indices where targets[index] == nil {
            if index > 0, let left = targets[index - 1] {
                targets[index] = left + 1
            }
        }

        for index in targets.indices.reversed() where targets[index] == nil {
            if index + 1 < targets.count, let right = targets[index + 1] {
                targets[index] = right - 1
            }
        }

        return targets.map { $0 ?? 0 }
    }

    // Each mission's position as a fraction of its row's width, so rows of
    // different widths line up around a shared centre.
    private static func slotPositions(_ rows: [[Int]]) -> [Int: Double] {
        var positions: [Int: Double] = [:]

        for row in rows {
            for (slot, missionID) in row.enumerated() {
                positions[missionID] = Double(slot) - Double(row.count - 1) / 2
            }
        }

        return positions
    }

    private static func sortedByNeighbours(_ row: [Int], neighbours: [Int: [Int]], positions: [Int: Double]) -> [Int] {
        let current: [Int: Double] = positions

        let keyed: [(id: Int, key: Double, original: Int)] = row.enumerated().map { index, missionID in
            let neighbourPositions: [Double] = (neighbours[missionID] ?? []).compactMap { current[$0] }

            // No neighbours on that side: keep its current place.
            let key: Double = neighbourPositions.isEmpty
                ? (current[missionID] ?? Double(index))
                : neighbourPositions.reduce(0, +) / Double(neighbourPositions.count)

            return (missionID, key, index)
        }

        return keyed
            .sorted { $0.key != $1.key ? $0.key < $1.key : $0.original < $1.original }
            .map(\.id)
    }
}
