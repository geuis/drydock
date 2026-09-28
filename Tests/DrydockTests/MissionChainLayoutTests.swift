import XCTest
@testable import Drydock

final class MissionChainLayoutTests: XCTestCase {
    private func layout(_ successors: [Int: [Int]], roots: [Int]) -> MissionChainLayout {
        let memberIDs: [Int] = Array(Set(successors.keys).union(successors.values.flatMap { $0 })).sorted()
        return MissionChainLayout(memberIDs: memberIDs, rootIDs: roots, successors: successors)
    }

    func testStraightChainIsOneColumn() {
        let result = layout([1: [2], 2: [3]], roots: [1])

        XCTAssertEqual(result.rows, [[1], [2], [3]])
        XCTAssertEqual(result.maxRowWidth, 1)
    }

    func testBranchesSitSideBySideAndRejoin() {
        // 5 randomly picks track A (6) or B (7); both lead to 8.
        let result = layout([5: [6, 7], 6: [8], 7: [8]], roots: [5])

        XCTAssertEqual(result.rows.count, 3)
        XCTAssertEqual(Set(result.rows[1]), [6, 7])
        XCTAssertEqual(result.rows[2], [8])
    }

    func testMissionSitsBelowEverythingThatLeadsToIt() {
        // 3 follows both 1 and 2, and 2 follows 1: 3 must be below 2.
        let result = layout([1: [2, 3], 2: [3]], roots: [1])

        XCTAssertEqual(result.placements[3]?.row, 2)
    }

    func testLoopIsMarkedAndDoesNotBreakTheRows() {
        let result = layout([1: [2], 2: [1]], roots: [1])

        XCTAssertEqual(result.rows, [[1], [2]])
        XCTAssertEqual(result.links.filter(\.loopsBack).map { [$0.fromID, $0.toID] }, [[2, 1]])
    }

    func testChainWithNoStartStillPlacesEveryMission() {
        // A pure loop has no starting mission.
        let result = layout([1: [2], 2: [3], 3: [1]], roots: [])

        XCTAssertEqual(result.placements.count, 3)
        XCTAssertEqual(result.links.filter(\.loopsBack).count, 1)
    }

    func testCrossingsAreUndone() {
        // Rows start as [1, 2] and [3, 4] with 1 -> 4 and 2 -> 3; ordering
        // by neighbours should put 4 on the left under 1.
        let result = layout([0: [1, 2], 1: [4], 2: [3]], roots: [0])
        let row: [Int] = result.rows[2]

        XCTAssertEqual(row.firstIndex(of: 4)! < row.firstIndex(of: 3)!, result.rows[1].firstIndex(of: 1)! < result.rows[1].firstIndex(of: 2)!)
    }

    func testStraightRunStaysInOneColumnPastAWideRow() {
        // 1 leads to the main mission 2 and four side missions; the main
        // line (2 -> 3 -> 4) must stay under 2, not drift with the row.
        let result = layout([1: [10, 11, 2, 12, 13], 2: [3], 3: [4]], roots: [1])
        let column: (Int) -> Double = { result.placements[$0]!.column }

        XCTAssertEqual(column(3), column(2), accuracy: 0.001)
        XCTAssertEqual(column(4), column(2), accuracy: 0.001)
    }

    func testSiblingsAreAtLeastOneColumnApart() {
        let result = layout([1: [2, 3, 4, 5, 6, 7, 8, 9]], roots: [1])
        let columns: [Double] = result.rows[1].map { result.placements[$0]!.column }

        for (left, right) in zip(columns, columns.dropFirst()) {
            XCTAssertGreaterThanOrEqual(right - left, 1 - 0.001)
        }

        // The parent sits over the middle of its children.
        XCTAssertEqual(result.placements[1]!.column, (columns.first! + columns.last!) / 2, accuracy: 0.001)
    }

    func testRealPolarisChainFlowsDownward() throws {
        let directory = try novaFilesDirectory()

        let missions = MissionDefinition.decodeAll(from: try GameDataLibrary(contentsOfDirectory: directory))
        let resolver = MissionChainResolver(missions: missions)
        let polaris = try XCTUnwrap(resolver.allChains().first { chain in chain.missions.contains { $0.id == 150 } })
        let result = MissionChainLayout(chain: polaris, resolver: resolver)

        XCTAssertEqual(result.placements.count, polaris.missions.count)
        XCTAssertEqual(result.placements[150]?.row, 0)

        for link in result.links where !link.loopsBack {
            XCTAssertLessThan(result.placements[link.fromID]!.row, result.placements[link.toID]!.row, "\(link)")
        }

        // Polaris 1 comes well before the last Polaris mission.
        XCTAssertGreaterThan(result.placements[192]!.row, 10)
    }
}
