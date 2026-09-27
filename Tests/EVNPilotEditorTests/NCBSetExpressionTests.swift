import XCTest
@testable import EVNPilotEditor

final class NCBSetExpressionTests: XCTestCase {
    func testOperationsFlattenRandomChoices() {
        XCTAssertEqual(
            NCBSetExpression.operations(in: "b1 R(b2 !b3) ^b4 S700"),
            [.set(1), .set(2), .clear(3), .toggle(4), .other("S700")]
        )
        XCTAssertEqual(NCBSetExpression.flagIDsInsideRandomChoices(in: "b1 R(b2 !b3) ^b4"), [2, 3])
        XCTAssertEqual(NCBSetExpression.startedMissionIDs(in: "R(S100 S200) b5 S300"), [100, 200, 300])
    }

    // A test expression the real parser rejects still reports its flags.
    func testUnparseableTestExpressionStillListsItsFlags() {
        let operations = StoryFlagCatalog.bitOperations(in: "(b1 & !b2", isTest: true)

        XCTAssertEqual(operations.map(\.id), [1, 2])
        XCTAssertEqual(operations.map(\.effect), [.requiresSet, .requiresClear])
    }
}
