import XCTest
@testable import EVNPilotEditor

final class PilotUniverseStateTests: XCTestCase {
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

    // resource128Size reads 59730 in the fixture (matching the
    // already-verified `rating` field's own offset), so resource129Start
    // should compute to 4 + 59730 + 4 = 59738 - see PilotUniverseState.swift
    // for the full three-way confirmation of this arithmetic.
    func testResource129StartComputesKnownGoodOffsetForFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertEqual(PilotUniverseState.resource129Start(in: pilotFile.workingBytes), 59738)
    }

    func testDecodeAllProduceCorrectCounts() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)
        let data = pilotFile.workingBytes

        XCTAssertEqual(PilotUniverseState.decodeStelShipCount(from: data).count, 2048)
        XCTAssertEqual(PilotUniverseState.decodePersonAlive(from: data).count, 1024)
        XCTAssertEqual(PilotUniverseState.decodePersonGrudge(from: data).count, 1024)
        XCTAssertEqual(PilotUniverseState.decodeStelAnnoyance(from: data).count, 2048)
        XCTAssertEqual(PilotUniverseState.decodeDisasterTime(from: data).count, 256)
        XCTAssertEqual(PilotUniverseState.decodeDisasterStellar(from: data).count, 256)
        XCTAssertEqual(PilotUniverseState.decodeJunkQty(from: data).count, 128)
        XCTAssertEqual(PilotUniverseState.decodePriceFlux(from: data).count, 4)
        XCTAssertEqual(PilotUniverseState.decodeRankActive(from: data).count, 128)
    }

    // Expected values computed directly from the fixture's raw bytes at
    // absolute offset 59744 (resource129Start + 6).
    func testDecodeStelShipCountMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let stelShipCount = PilotUniverseState.decodeStelShipCount(from: pilotFile.workingBytes)

        XCTAssertEqual(Array(stelShipCount.prefix(10)), [600, 0, 0, 0, 0, 120, 120, 0, 120, 120])
        XCTAssertEqual(stelShipCount.filter { $0 != 0 }.count, 294)
    }

    // Matches the documented "flag to set each 'pers' active or not" -
    // decodes exclusively to 0/1.
    func testDecodePersonAliveMatchesFixtureDomain() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let personAlive = PilotUniverseState.decodePersonAlive(from: pilotFile.workingBytes)

        XCTAssertTrue(personAlive.allSatisfy { $0 == 0 || $0 == 1 })
        XCTAssertEqual(personAlive.filter { $0 != 0 }.count, 505)
    }

    func testDecodeSeenIntroScreenMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertTrue(PilotUniverseState.decodeSeenIntroScreen(from: pilotFile.workingBytes))
    }

    // Sample values computed directly from the fixture's raw bytes - see
    // PilotUniverseState.swift for the reasoning behind this being marked
    // Probable rather than Verified (0 rather than the doc's stated "<0"
    // sentinel appears for inactive-looking entries).
    func testDecodeDisasterFieldsMatchFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let disasterTime = PilotUniverseState.decodeDisasterTime(from: pilotFile.workingBytes)
        let disasterStellar = PilotUniverseState.decodeDisasterStellar(from: pilotFile.workingBytes)

        XCTAssertEqual(Array(disasterTime.prefix(5)), [2, 11, 10, 34, 15])
        XCTAssertEqual(Array(disasterStellar.prefix(5)), [9, 47, 35, 85, 11])
    }

    func testDecodePriceFluxMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertEqual(PilotUniverseState.decodePriceFlux(from: pilotFile.workingBytes), [95, 92, 103, 96])
    }

    // 0-0-0 is within the documented 0-32 range, though both real files
    // showing an unset (0,0,0) color is weaker confirmation - see
    // PilotUniverseState.swift.
    func testDecodeShipColorMatchesFixtureAndStaysInDocumentedRange() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)
        let data = pilotFile.workingBytes

        let red = PilotUniverseState.decodeShipColorRed(from: data)
        let green = PilotUniverseState.decodeShipColorGreen(from: data)
        let blue = PilotUniverseState.decodeShipColorBlue(from: data)

        XCTAssertEqual(red, 0)
        XCTAssertEqual(green, 0)
        XCTAssertEqual(blue, 0)
        XCTAssertTrue((0...32).contains(red))
        XCTAssertTrue((0...32).contains(green))
        XCTAssertTrue((0...32).contains(blue))
    }

    func testDecodeRankActiveMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let rankActive = PilotUniverseState.decodeRankActive(from: pilotFile.workingBytes)

        XCTAssertEqual(rankActive[0], 1)
        XCTAssertEqual(rankActive[17], 1)
        XCTAssertEqual(rankActive[18], 1)
        XCTAssertEqual(rankActive.filter { $0 != 0 }.count, 5)
    }

    func testSetStelShipCountChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let resource129Start = PilotUniverseState.resource129Start(in: pilotFile.workingBytes)
        XCTAssertNoThrow(try pilotFile.setStelShipCount(250, at: 300))

        let targetOffset = resource129Start + 0x0006 + 300 * 2
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)

        XCTAssertEqual(PilotUniverseState.decodeStelShipCount(from: pilotFile.workingBytes)[300], 250)
    }

    func testSetSeenIntroScreenChangesOnlyThatByte() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let resource129Start = PilotUniverseState.resource129Start(in: pilotFile.workingBytes)
        XCTAssertNoThrow(try pilotFile.setSeenIntroScreen(false))

        let targetOffset = resource129Start + 0x3086
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 1), original: pilotFile.originalBytes, working: pilotFile.workingBytes)

        XCTAssertFalse(PilotUniverseState.decodeSeenIntroScreen(from: pilotFile.workingBytes))
    }

    func testSetShipColorRedChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let resource129Start = PilotUniverseState.resource129Start(in: pilotFile.workingBytes)
        XCTAssertNoThrow(try pilotFile.setShipColorRed(16))

        let targetOffset = resource129Start + 0x5dd8
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)

        XCTAssertEqual(PilotUniverseState.decodeShipColorRed(from: pilotFile.workingBytes), 16)
    }

    func testSetOnInvalidIndexThrows() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertThrowsError(try pilotFile.setStelShipCount(1, at: -1))
        XCTAssertThrowsError(try pilotFile.setPersonAlive(1, at: 1024))
        XCTAssertThrowsError(try pilotFile.setPersonGrudge(1, at: 1024))
        XCTAssertThrowsError(try pilotFile.setStelAnnoyance(1, at: 2048))
        XCTAssertThrowsError(try pilotFile.setDisasterTime(1, at: 256))
        XCTAssertThrowsError(try pilotFile.setDisasterStellar(1, at: 256))
        XCTAssertThrowsError(try pilotFile.setJunkQty(1, at: 128))
        XCTAssertThrowsError(try pilotFile.setPriceFlux(1, at: 4))
        XCTAssertThrowsError(try pilotFile.setRankActive(1, at: 128))
    }
}
