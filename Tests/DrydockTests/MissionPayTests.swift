import XCTest
@testable import Drydock

final class MissionPayTests: XCTestCase {
    func testDecodesEveryDocumentedRange() {
        XCTAssertEqual(MissionPay(0), .none)
        XCTAssertEqual(MissionPay(-1), .none)
        XCTAssertEqual(MissionPay(25000), .credits(25000))
        XCTAssertEqual(MissionPay(-10130), .clearRecord(governmentID: 130, scope: .government))
        XCTAssertEqual(MissionPay(-20128), .clearRecord(governmentID: 128, scope: .withAllies))
        XCTAssertEqual(MissionPay(-30383), .clearRecord(governmentID: 383, scope: .withClassmates))
        XCTAssertEqual(MissionPay(-40010), .takePercentOfCash(10))
        XCTAssertEqual(MissionPay(-55000), .takeCreditsAtStart(5000))
        XCTAssertEqual(MissionPay(-5), .unrecognized(-5))
    }

    func testDescriptionUsesTheGivenGovernmentNames() {
        let text: String = MissionPay(-10130).description { $0 == 130 ? "Federation" : "?" }

        XCTAssertEqual(text, "Clears legal record with Federation")
        XCTAssertEqual(MissionPay(-10130).description(), "Clears legal record with government 130")
    }
}
