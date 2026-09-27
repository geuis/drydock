import XCTest
@testable import Drydock

// Covers the resource129 fields added on top of PilotUniverseStateTests.swift:
// strictPlayFlag, gender, cronDuration, cronHoldOff, reinforcements,
// stelDestroyed, escortOrders, playerNickname, datePrefix, dateSuffix.
final class PilotUniverseStateNewFieldsTests: XCTestCase {
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

    // MARK: - Decoding

    // strictPlayFlag reads 0 (off) in the fixture - within the documented
    // 0/1 domain.
    func testDecodeStrictPlayMatchesFixtureDomain() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertFalse(PilotUniverseState.decodeStrictPlay(from: pilotFile.workingBytes))
    }

    // gender reads 1 (male) in the fixture - matches the documented "1 = male".
    func testDecodeIsMaleMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertTrue(PilotUniverseState.decodeIsMale(from: pilotFile.workingBytes))
    }

    func testDecodeCronFieldsProduceCorrectCountsAndDomain() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)
        let data = pilotFile.workingBytes

        let cronDuration = PilotUniverseState.decodeCronDuration(from: data)
        let cronHoldOff = PilotUniverseState.decodeCronHoldOff(from: data)

        XCTAssertEqual(cronDuration.count, 512)
        XCTAssertEqual(cronHoldOff.count, 512)

        // Both real fixtures decode to mostly -1 (498/512 entries), matching
        // this format's established "-1 = inactive" sentinel convention,
        // with the remaining nonzero entries holding small live values.
        XCTAssertEqual(cronDuration.filter { $0 == -1 }.count, 498)
        XCTAssertEqual(cronDuration.filter { $0 != 0 }.count, 511)
        XCTAssertEqual(cronHoldOff.filter { $0 == -1 }.count, 498)
        XCTAssertEqual(cronHoldOff.filter { $0 != 0 }.count, 507)
    }

    func testDecodeReinforcementsAllZeroInFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let reinforcements = PilotUniverseState.decodeReinforcements(from: pilotFile.workingBytes)

        XCTAssertEqual(reinforcements.count, 2048)
        XCTAssertTrue(reinforcements.allSatisfy { $0 == 0 })
    }

    // Matches the doc's own stated sentinel exactly: "-1 = alive".
    func testDecodeStelDestroyedAllAliveInFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let stelDestroyed = PilotUniverseState.decodeStelDestroyed(from: pilotFile.workingBytes)

        XCTAssertEqual(stelDestroyed.count, 2048)
        XCTAssertTrue(stelDestroyed.allSatisfy { $0 == -1 })
    }

    func testDecodeEscortOrdersMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let escortOrders = PilotUniverseState.decodeEscortOrders(from: pilotFile.workingBytes)

        XCTAssertEqual(escortOrders, [0, 0, 0, 0])
    }

    // Same bytes the schema's "shipName" FieldDefinition reads (offset
    // 83698) - both should decode to the pilot's known nickname "Hawkeye".
    func testDecodePlayerNicknameMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertEqual(PilotUniverseState.decodePlayerNickname(from: pilotFile.workingBytes), "Hawkeye")
    }

    func testDecodeDateFieldsMatchFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)
        let data = pilotFile.workingBytes

        XCTAssertEqual(PilotUniverseState.decodeDatePrefix(from: data), "")
        XCTAssertEqual(PilotUniverseState.decodeDateSuffix(from: data), " NC")
    }

    // MARK: - Writing

    func testSetStrictPlayChangesOnlyThatFieldAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let resource129Start = PilotUniverseState.resource129Start(in: pilotFile.workingBytes)
        XCTAssertNoThrow(try pilotFile.setStrictPlay(true))

        let targetOffset = resource129Start + 0x0002
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)
        XCTAssertTrue(PilotUniverseState.decodeStrictPlay(from: pilotFile.workingBytes))
    }

    func testSetIsMaleChangesOnlyThatFieldAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let resource129Start = PilotUniverseState.resource129Start(in: pilotFile.workingBytes)
        XCTAssertNoThrow(try pilotFile.setIsMale(false))

        let targetOffset = resource129Start + 0x0004
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)
        XCTAssertFalse(PilotUniverseState.decodeIsMale(from: pilotFile.workingBytes))
    }

    func testSetCronDurationChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let resource129Start = PilotUniverseState.resource129Start(in: pilotFile.workingBytes)
        XCTAssertNoThrow(try pilotFile.setCronDuration(42, at: 10))

        let targetOffset = resource129Start + 0x3590 + 10 * 2
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)
        XCTAssertEqual(PilotUniverseState.decodeCronDuration(from: pilotFile.workingBytes)[10], 42)
    }

    func testSetCronHoldOffChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let resource129Start = PilotUniverseState.resource129Start(in: pilotFile.workingBytes)
        XCTAssertNoThrow(try pilotFile.setCronHoldOff(17, at: 5))

        let targetOffset = resource129Start + 0x3990 + 5 * 2
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)
        XCTAssertEqual(PilotUniverseState.decodeCronHoldOff(from: pilotFile.workingBytes)[5], 17)
    }

    func testSetReinforcementsChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let resource129Start = PilotUniverseState.resource129Start(in: pilotFile.workingBytes)
        XCTAssertNoThrow(try pilotFile.setReinforcements(3, at: 100))

        let targetOffset = resource129Start + 0x3d90 + 100 * 2
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)
        XCTAssertEqual(PilotUniverseState.decodeReinforcements(from: pilotFile.workingBytes)[100], 3)
    }

    func testSetStelDestroyedChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let resource129Start = PilotUniverseState.resource129Start(in: pilotFile.workingBytes)
        XCTAssertNoThrow(try pilotFile.setStelDestroyed(5, at: 200))

        let targetOffset = resource129Start + 0x4d90 + 200 * 2
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)
        XCTAssertEqual(PilotUniverseState.decodeStelDestroyed(from: pilotFile.workingBytes)[200], 5)
    }

    func testSetEscortOrderChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let resource129Start = PilotUniverseState.resource129Start(in: pilotFile.workingBytes)
        XCTAssertNoThrow(try pilotFile.setEscortOrder(2, at: 1))

        let targetOffset = resource129Start + 0x5d90 + 1 * 2
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)
        XCTAssertEqual(PilotUniverseState.decodeEscortOrders(from: pilotFile.workingBytes)[1], 2)
    }

    func testSetNicknameChangesOnlyDeclaredSpanAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let resource129Start = PilotUniverseState.resource129Start(in: pilotFile.workingBytes)
        XCTAssertNoThrow(try pilotFile.setNickname("Newname"))

        let targetOffset = resource129Start + 0x5d98
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 64), original: pilotFile.originalBytes, working: pilotFile.workingBytes)
        XCTAssertEqual(PilotUniverseState.decodePlayerNickname(from: pilotFile.workingBytes), "Newname")
    }

    func testSetDatePrefixAndSuffixChangeOnlyDeclaredSpanAndDecodeBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let resource129Start = PilotUniverseState.resource129Start(in: pilotFile.workingBytes)
        XCTAssertNoThrow(try pilotFile.setDatePrefix("Early"))

        let prefixOffset = resource129Start + 0x5ede
        assertOnlyBytesChanged(prefixOffset..<(prefixOffset + 16), original: pilotFile.originalBytes, working: pilotFile.workingBytes)
        XCTAssertEqual(PilotUniverseState.decodeDatePrefix(from: pilotFile.workingBytes), "Early")

        let afterPrefix = pilotFile.workingBytes
        XCTAssertNoThrow(try pilotFile.setDateSuffix("Late"))

        let suffixOffset = resource129Start + 0x5eee
        assertOnlyBytesChanged(suffixOffset..<(suffixOffset + 16), original: afterPrefix, working: pilotFile.workingBytes)
        XCTAssertEqual(PilotUniverseState.decodeDateSuffix(from: pilotFile.workingBytes), "Late")
    }

    // A 16-char string leaves no room for the NUL terminator in the 16-byte
    // buffer, so it should be truncated to 15 chars + NUL rather than
    // overflowing into the next field.
    func testSetDatePrefixTruncatesToFitBuffer() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertNoThrow(try pilotFile.setDatePrefix("123456789012345678"))
        XCTAssertEqual(PilotUniverseState.decodeDatePrefix(from: pilotFile.workingBytes), "123456789012345")
    }

    func testSetOnInvalidIndexThrows() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertThrowsError(try pilotFile.setCronDuration(1, at: 512))
        XCTAssertThrowsError(try pilotFile.setCronHoldOff(1, at: -1))
        XCTAssertThrowsError(try pilotFile.setReinforcements(1, at: 2048))
        XCTAssertThrowsError(try pilotFile.setStelDestroyed(1, at: 2048))
        XCTAssertThrowsError(try pilotFile.setEscortOrder(1, at: 4))
    }
}
