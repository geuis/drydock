import XCTest
@testable import Drydock

final class MissionBitsTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "Chuck Yeager", withExtension: "plt", subdirectory: "Fixtures") else {
            XCTFail("Could not locate bundled fixture Chuck Yeager.plt")
            throw XCTSkip("Fixture not found")
        }
        return url
    }

    // Copies the bundled fixture into a fresh temp directory so tests never
    // write into the bundle itself - same pattern as MissionSlotTests.
    private func makeTempCopyOfFixture() throws -> URL {
        let sourceURL = try fixtureURL()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let destinationURL = tempDirectory.appendingPathComponent("Chuck Yeager.plt")
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        return destinationURL
    }

    // Reads the raw byte for a missionBit index directly, independent of
    // MissionBits.decodeAll, so the test doesn't just check the code against
    // itself - mirrors MissionSlotTests keeping its own offset constant.
    private func rawBitIsSet(_ index: Int, in data: Data) -> Bool {
        let absoluteIndex = data.startIndex + MissionBits.baseOffset + index
        return data[absoluteIndex] != 0
    }

    func testDecodeAllProducesTenThousandEntries() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let bits = MissionBits.decodeAll(from: pilotFile.workingBytes)

        XCTAssertEqual(bits.count, 10000)
    }

    // The known-set indices below were computed directly from the raw bytes
    // of the bundled fixture (scanning the 10,000-byte region at absolute
    // offset 47042 for non-zero bytes), not guessed - 46 set bits total,
    // matching the independently-verified count for this sample file.
    func testDecodeAllMatchesRawBytesForFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)
        let data = pilotFile.workingBytes

        let expectedSetIndices = [
            0, 9, 10, 14, 17, 33, 34, 35, 42, 43, 47, 48, 49, 50, 51, 52, 53, 54,
            55, 56, 57, 58, 59, 60, 61, 62, 124, 179, 341, 510, 511, 512, 513,
            515, 518, 4000, 6004, 6006, 6029, 7777, 7781, 7786, 8888, 8889,
            9215, 9998
        ]

        // Sanity check: confirm each expected index really is set by reading
        // the raw byte directly, independent of MissionBits.decodeAll.
        for index in expectedSetIndices {
            XCTAssertTrue(rawBitIsSet(index, in: data), "Expected raw byte at index \(index) to be set")
        }

        XCTAssertEqual(MissionBits.setIndices(from: data), expectedSetIndices)

        let decoded = MissionBits.decodeAll(from: data)
        for index in 0..<MissionBits.count {
            XCTAssertEqual(decoded[index], expectedSetIndices.contains(index), "Mismatch at index \(index)")
        }
    }

    func testSetBitChangesOnlyThatByte() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        // Index 5000 is not among the fixture's set indices, so flipping it
        // on is a clean, isolated change.
        let targetIndex = 5000
        XCTAssertFalse(MissionBits.decodeAll(from: pilotFile.workingBytes)[targetIndex])

        XCTAssertNoThrow(try pilotFile.setMissionBit(targetIndex, to: true))

        let original = pilotFile.originalBytes
        let working = pilotFile.workingBytes
        XCTAssertEqual(original.count, working.count)

        let targetOffset = MissionBits.baseOffset + targetIndex

        for index in 0..<original.count {
            if index == targetOffset {
                continue
            }
            XCTAssertEqual(
                original[original.startIndex + index],
                working[working.startIndex + index],
                "Byte at offset \(index) outside the flipped flag byte was modified"
            )
        }

        XCTAssertEqual(working[working.startIndex + targetOffset], 1)

        let after = MissionBits.decodeAll(from: pilotFile.workingBytes)
        XCTAssertTrue(after[targetIndex])
    }

    func testSetBitOnInvalidIndexThrows() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertThrowsError(try pilotFile.setMissionBit(-1, to: true))
        XCTAssertThrowsError(try pilotFile.setMissionBit(10000, to: true))
    }

    func testIsSetReadsOneBitWithoutDecodingWholeArray() throws {
        let pilotFile = try PilotFile(url: makeTempCopyOfFixture())

        XCTAssertTrue(MissionBits.isSet(0, in: pilotFile.workingBytes))
        XCTAssertFalse(MissionBits.isSet(1, in: pilotFile.workingBytes))
        XCTAssertFalse(MissionBits.isSet(-1, in: pilotFile.workingBytes))
        XCTAssertFalse(MissionBits.isSet(MissionBits.count, in: pilotFile.workingBytes))
    }

    func testStoryFlagParserDistinguishesTestAndMutationOperators() {
        let tests = StoryFlagCatalog.bitOperations(in: "b10 & !B11 | P30", isTest: true)
        XCTAssertEqual(tests.map(\.id), [10, 11])
        XCTAssertEqual(tests.map(\.effect), [.requiresSet, .requiresClear])

        let mutations = StoryFlagCatalog.bitOperations(in: "b20 !B21 ^b22 S700", isTest: false)
        XCTAssertEqual(mutations.map(\.id), [20, 21, 22])
        XCTAssertEqual(mutations.map(\.effect), [.sets, .clears, .toggles])
    }

    func testStoryFlagCatalogUsesInstalledScenarioWhenAvailable() throws {
        let directory = try novaFilesDirectory()

        let catalog = StoryFlagCatalog(library: try GameDataLibrary(contentsOfDirectory: directory))
        XCTAssertGreaterThan(catalog.flagsByID.count, 100)

        let vellosProgress = try XCTUnwrap(catalog[353])
        XCTAssertTrue(vellosProgress.name.localizedCaseInsensitiveContains("Infiltrate the Rebels"))
        XCTAssertTrue(vellosProgress.description.localizedCaseInsensitiveContains("completed"))
    }
}
