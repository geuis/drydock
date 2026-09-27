import XCTest
@testable import EVNPilotEditor

final class MissionLocationCodeTests: XCTestCase {
    func testDecodesEveryRangeWithTheResourceIDOffset() {
        XCTAssertEqual(MissionLocationCode(-1), .anyInhabited)
        XCTAssertEqual(MissionLocationCode(300), .stellar(300))
        XCTAssertEqual(MissionLocationCode(5000), .adjacentToSystem(128))
        XCTAssertEqual(MissionLocationCode(9999), .government(nil))
        XCTAssertEqual(MissionLocationCode(10003), .government(131))
        XCTAssertEqual(MissionLocationCode(15002), .allyOf(130))
        XCTAssertEqual(MissionLocationCode(20000), .notGovernment(128))
        XCTAssertEqual(MissionLocationCode(25001), .enemyOf(129))
        XCTAssertEqual(MissionLocationCode(30004), .governmentOrClass(132))
        XCTAssertEqual(MissionLocationCode(31005), .neitherGovernmentNorClass(133))
        XCTAssertEqual(MissionLocationCode(4000), .unrecognized(4000))
    }

    func testDiagnosticsWordingUsesTheSameIDsAsTheDetailsView() {
        // These used to read "system 72" and "government 1".
        XCTAssertEqual(MissionDiagnostics.locationDescription(availStel: 5072), "a stellar in a system adjacent to system 200")
        XCTAssertEqual(MissionDiagnostics.locationDescription(availStel: 10000), "a stellar belonging to government 128")
        XCTAssertEqual(MissionDiagnostics.locationDescription(availStel: 9999), "a stellar belonging to independents")
    }
}
