import XCTest
@testable import Drydock

final class PilotEscortsTests: XCTestCase {
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

    func testDecodeAllProduceSixtyFourEntries() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertEqual(PilotEscorts.decodeEscortClass(from: pilotFile.workingBytes).count, 64)
        XCTAssertEqual(PilotEscorts.decodeFighterClass(from: pilotFile.workingBytes).count, 64)
        XCTAssertEqual(PilotEscorts.decodeEscortUpgrade(from: pilotFile.workingBytes).count, 64)
        XCTAssertEqual(PilotEscorts.decodeEscortSale(from: pilotFile.workingBytes).count, 64)
        XCTAssertEqual(PilotEscorts.decodeEscortVoiceMode(from: pilotFile.workingBytes).count, 64)
    }

    // Expected values computed directly from the fixture's raw bytes at
    // absolute offset 59090 (escortClass). Shane Merrol actually has hired
    // escorts, so this fixture exercises the non-trivial (non-all -1) case -
    // see PilotEscorts.swift for how this confirms the -96 adjustment.
    func testDecodeEscortClassMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let escortClass = PilotEscorts.decodeEscortClass(from: pilotFile.workingBytes)

        XCTAssertEqual(escortClass[0], -1)
        XCTAssertEqual(escortClass[1], 13)
        XCTAssertEqual(escortClass[3], 18)
        XCTAssertEqual(escortClass[11], 1059)
        XCTAssertEqual(escortClass[12], 1059)
        XCTAssertEqual(escortClass[14], 1244)
    }

    func testDecodeFighterClassMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let fighterClass = PilotEscorts.decodeFighterClass(from: pilotFile.workingBytes)

        XCTAssertEqual(fighterClass[7], 29)
        XCTAssertEqual(fighterClass[8], 29)
        XCTAssertEqual(fighterClass[15], 29)
        XCTAssertEqual(fighterClass[0], -1)
    }

    // Only -1/0/1 should ever appear per the documented domain.
    func testDecodeEscortVoiceModeMatchesFixtureAndStaysInDocumentedDomain() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let escortVoiceMode = PilotEscorts.decodeEscortVoiceMode(from: pilotFile.workingBytes)

        XCTAssertEqual(escortVoiceMode[1], 0)
        XCTAssertEqual(escortVoiceMode[3], 1)
        XCTAssertTrue(escortVoiceMode.allSatisfy { $0 == -1 || $0 == 0 || $0 == 1 })
    }

    func testDecodeEscortUpgradeAndSaleAllZeroForFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertTrue(PilotEscorts.decodeEscortUpgrade(from: pilotFile.workingBytes).allSatisfy { $0 == 0 })
        XCTAssertTrue(PilotEscorts.decodeEscortSale(from: pilotFile.workingBytes).allSatisfy { $0 == 0 })
    }

    func testSetEscortClassChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertNoThrow(try pilotFile.setEscortClass(500, at: 20))

        let targetOffset = PilotEscorts.escortClassBaseOffset + 20 * 2
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)

        XCTAssertEqual(PilotEscorts.decodeEscortClass(from: pilotFile.workingBytes)[20], 500)
    }

    func testSetEscortVoiceModeChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertNoThrow(try pilotFile.setEscortVoiceMode(1, at: 5))

        let targetOffset = PilotEscorts.escortVoiceModeBaseOffset + 5 * 2
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)

        XCTAssertEqual(PilotEscorts.decodeEscortVoiceMode(from: pilotFile.workingBytes)[5], 1)
    }

    func testSetOnInvalidIndexThrows() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertThrowsError(try pilotFile.setEscortClass(1, at: -1))
        XCTAssertThrowsError(try pilotFile.setFighterClass(1, at: 64))
        XCTAssertThrowsError(try pilotFile.setEscortUpgrade(1, at: 64))
        XCTAssertThrowsError(try pilotFile.setEscortSale(1, at: 64))
        XCTAssertThrowsError(try pilotFile.setEscortVoiceMode(1, at: 64))
    }
}
