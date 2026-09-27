import XCTest
@testable import EVNPilotEditor

// Covers the convenience read accessors added directly to PilotFile:
// shipName, nickname, shipClassIndex, isMale, strictPlay, combatRating,
// credits, missionSlots.
final class PilotFileConvenienceTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "Shane Merrol", withExtension: "plt", subdirectory: "Fixtures") else {
            XCTFail("Could not locate bundled fixture Shane Merrol.plt")
            throw XCTSkip("Fixture not found")
        }
        return url
    }

    private func makeTempCopyOfFixture() throws -> URL {
        let sourceURL = try fixtureURL()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let destinationURL = tempDirectory.appendingPathComponent("Shane Merrol.plt")
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        return destinationURL
    }

    func testConvenienceAccessorsMatchFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertEqual(pilotFile.shipName, "Pirate Carrier 476")
        XCTAssertEqual(pilotFile.nickname, "Hawkeye")
        XCTAssertEqual(pilotFile.shipClassIndex, 19)
        XCTAssertTrue(pilotFile.isMale)
        XCTAssertFalse(pilotFile.strictPlay)
        XCTAssertEqual(pilotFile.combatRating, 6369)
        XCTAssertEqual(pilotFile.credits, 48_950_698)
    }

    func testMissionSlotsConvenienceMatchesDirectDecode() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let viaConvenience = pilotFile.missionSlots
        let viaDirectDecode = MissionSlot.decodeAll(from: pilotFile.workingBytes)

        XCTAssertEqual(viaConvenience.count, 16)
        XCTAssertEqual(viaConvenience, viaDirectDecode)
        XCTAssertEqual(viaConvenience[0].missionName, "Meet With Merrol DockMaster")
    }
}
