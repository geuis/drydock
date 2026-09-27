import XCTest
@testable import Drydock

final class PilotShipIdentityTests: XCTestCase {
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

    // MARK: - Decoding

    // Confirmed against the fixture's raw bytes: tailStart (86104) to EOF
    // reads "Pirate Carrier 476\0" - matching the already-verified
    // "shipClassName" FieldDefinition's decoded value in
    // PilotFileRoundTripTests, and the pilot's known ship class ("Pirate
    // Carrier", ship ID 147).
    func testDecodeShipNameMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertEqual(pilotFile.shipName, "Pirate Carrier 476")
    }

    func testTailStartMatchesKnownGoodOffset() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        // resource129Start (59738) + resource129's documented struct size
        // (26366) = 86104, exactly matching the schema's independently
        // recorded "shipClassName" field offset.
        XCTAssertEqual(PilotShipIdentity.tailStart(in: pilotFile.workingBytes), 86104)
    }

    // MARK: - Writing

    func testSetShipNameOnlyChangesTailAndKeepsRestByteIdentical() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let originalCount = pilotFile.originalBytes.count
        let tailStart = PilotShipIdentity.tailStart(in: pilotFile.workingBytes)

        XCTAssertNoThrow(try pilotFile.setShipName("Testpilot"))

        let original = pilotFile.originalBytes
        let working = pilotFile.workingBytes

        // Bytes before the tail must be byte-identical.
        for index in 0..<tailStart {
            XCTAssertEqual(
                original[original.startIndex + index],
                working[working.startIndex + index],
                "Byte at offset \(index) before the ship-name tail was modified"
            )
        }

        // The new tail is exactly "Testpilot" + NUL.
        let expectedTail = "Testpilot".data(using: .macOSRoman)! + Data([0x00])
        let actualTail = working.subdata(in: (working.startIndex + tailStart)..<working.endIndex)
        XCTAssertEqual(actualTail, expectedTail)

        // File length changed by (new tail length - old tail length).
        let oldTailLength = originalCount - tailStart
        let newTailLength = expectedTail.count
        XCTAssertEqual(working.count, originalCount - oldTailLength + newTailLength)

        XCTAssertEqual(pilotFile.shipName, "Testpilot")
    }

    // Round-trips a resize through an actual save() to a temp copy.
    func testSetShipNameRoundTripsThroughSave() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertNoThrow(try pilotFile.setShipName("Roundtrip"))
        XCTAssertNoThrow(try pilotFile.save())

        let bytesAfterSave = try Data(contentsOf: tempURL)
        XCTAssertEqual(bytesAfterSave, pilotFile.workingBytes)
        XCTAssertTrue(pilotFile.isRoundTripIdentical)

        // Re-load from disk and confirm the resized file decodes correctly.
        let reloaded = try PilotFile(url: tempURL)
        XCTAssertEqual(reloaded.shipName, "Roundtrip")
    }

    func testSetShipNameRejectsEmptyName() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertThrowsError(try pilotFile.setShipName(""))
        XCTAssertEqual(pilotFile.shipName, "Pirate Carrier 476", "A rejected write must not mutate workingBytes")
    }

    func testSetShipNameRejectsNameLongerThan63Characters() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let tooLong = String(repeating: "A", count: 64)
        XCTAssertThrowsError(try pilotFile.setShipName(tooLong))
        XCTAssertEqual(pilotFile.shipName, "Pirate Carrier 476")
    }

    func testSetShipNameAccepts63CharacterName() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let maxLength = String(repeating: "B", count: 63)
        XCTAssertNoThrow(try pilotFile.setShipName(maxLength))
        XCTAssertEqual(pilotFile.shipName, maxLength)
    }

    // A CJK character has no representation in Mac OS Roman, so it must be
    // rejected rather than silently mangled.
    func testSetShipNameRejectsCharactersMacRomanCannotRepresent() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertThrowsError(try pilotFile.setShipName("船名"))
        XCTAssertEqual(pilotFile.shipName, "Pirate Carrier 476")
    }
}
