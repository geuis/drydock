import XCTest
@testable import Drydock

final class PilotExplorationTests: XCTestCase {
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

    func testDecodeAllProduceCorrectCounts() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertEqual(PilotExploration.decodeExploration(from: pilotFile.workingBytes).count, 2048)
        XCTAssertEqual(PilotExploration.decodeLegalStatus(from: pilotFile.workingBytes).count, 2048)
        XCTAssertEqual(PilotExploration.decodeStelDominated(from: pilotFile.workingBytes).count, 2048)
    }

    // Expected values computed directly from the fixture's raw bytes at
    // absolute offset 30 (exploration) - see PilotExploration.swift for the
    // offset derivation. All values land in the documented {0-ish, 1, 2}
    // domain, with a plausible scattering of visited (1) and
    // visited+landed (2) systems for a well-played pilot.
    func testDecodeExplorationMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let exploration = PilotExploration.decodeExploration(from: pilotFile.workingBytes)

        XCTAssertEqual(exploration[0], 2)
        XCTAssertEqual(exploration.filter { $0 == 1 }.count, 52)
        XCTAssertEqual(exploration.filter { $0 == 2 }.count, 180)
        XCTAssertTrue(exploration.allSatisfy { $0 <= 0 || $0 == 1 || $0 == 2 })
    }

    // Expected values computed directly from the fixture's raw bytes at
    // absolute offset 5150 (legalStatus).
    func testDecodeLegalStatusMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let legalStatus = PilotExploration.decodeLegalStatus(from: pilotFile.workingBytes)

        XCTAssertEqual(legalStatus.filter { $0 != 0 }.count, 347)
        XCTAssertEqual(Array(legalStatus.prefix(5)), [49, 36, 33, 29, 37])
    }

    // The entire stelDominated region decodes to all-false for both real
    // bundled pilot files - see PilotExploration.swift for why the offset
    // is still considered verified despite this weaker positive evidence.
    func testDecodeStelDominatedAllFalseForFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let stelDominated = PilotExploration.decodeStelDominated(from: pilotFile.workingBytes)

        XCTAssertTrue(stelDominated.allSatisfy { $0 == false })
    }

    func testSetExplorationChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertNoThrow(try pilotFile.setExploration(2, at: 1000))

        let targetOffset = PilotExploration.explorationBaseOffset + 1000 * 2
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)

        XCTAssertEqual(PilotExploration.decodeExploration(from: pilotFile.workingBytes)[1000], 2)
    }

    func testSetLegalStatusChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertNoThrow(try pilotFile.setLegalStatus(-10, at: 900))

        let targetOffset = PilotExploration.legalStatusBaseOffset + 900 * 2
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)

        XCTAssertEqual(PilotExploration.decodeLegalStatus(from: pilotFile.workingBytes)[900], -10)
    }

    func testSetStelDominatedChangesOnlyThatByteAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertNoThrow(try pilotFile.setStelDominated(true, at: 42))

        let targetOffset = PilotExploration.stelDominatedBaseOffset + 42
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 1), original: pilotFile.originalBytes, working: pilotFile.workingBytes)

        XCTAssertTrue(PilotExploration.decodeStelDominated(from: pilotFile.workingBytes)[42])
    }

    func testSetOnInvalidIndexThrows() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertThrowsError(try pilotFile.setExploration(1, at: -1))
        XCTAssertThrowsError(try pilotFile.setExploration(1, at: 2048))
        XCTAssertThrowsError(try pilotFile.setLegalStatus(1, at: 2048))
        XCTAssertThrowsError(try pilotFile.setStelDominated(true, at: 2048))
    }
}
