import XCTest
@testable import Drydock

final class PilotProfileTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "Chuck Yeager", withExtension: "plt", subdirectory: "Fixtures") else {
            XCTFail("Could not locate bundled fixture Chuck Yeager.plt")
            throw XCTSkip("Fixture not found")
        }
        return url
    }

    private func makeTempCopyOfFixture() throws -> URL {
        let sourceURL = try fixtureURL()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let destinationURL = tempDirectory.appendingPathComponent("Chuck Yeager.plt")
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        return destinationURL
    }

    private func assertOnlyBytesChanged(_ range: Range<Int>, original: Data, working: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(original.count, working.count, file: file, line: line)

        for index in 0..<original.count {
            if range.contains(index) {
                continue
            }
            XCTAssertEqual(
                original[original.startIndex + index],
                working[working.startIndex + index],
                "Byte at offset \(index) outside \(range) was modified",
                file: file, line: line
            )
        }
    }

    // shipClassIndex decodes to 19 for the Chuck Yeager fixture -> ship ID 147
    // ("Pirate Carrier"), matching his known ship name "Pirate Carrier 476".
    func testDecodeShipClassIndexMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertEqual(PilotProfile.decodeShipClassIndex(from: pilotFile.workingBytes), 19)
        XCTAssertEqual(Int(PilotProfile.decodeShipClassIndex(from: pilotFile.workingBytes)) + 128, 147)
    }

    func testDecodeCombatRatingMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertEqual(PilotProfile.decodeCombatRating(from: pilotFile.workingBytes), 6369)
    }

    func testDecodeCreditsMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertEqual(PilotProfile.decodeCredits(from: pilotFile.workingBytes), 48_950_698)
    }

    func testSetShipClassIndexChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertNoThrow(try pilotFile.setShipClassIndex(37))

        assertOnlyBytesChanged(
            PilotProfile.shipClassIndexOffset..<(PilotProfile.shipClassIndexOffset + 2),
            original: pilotFile.originalBytes,
            working: pilotFile.workingBytes
        )

        XCTAssertEqual(pilotFile.shipClassIndex, 37)
    }
}
