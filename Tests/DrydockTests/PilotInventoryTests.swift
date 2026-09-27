import XCTest
@testable import Drydock

final class PilotInventoryTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "Chuck Yeager", withExtension: "plt", subdirectory: "Fixtures") else {
            XCTFail("Could not locate bundled fixture Chuck Yeager.plt")
            throw XCTSkip("Fixture not found")
        }
        return url
    }

    // Copies the bundled fixture into a fresh temp directory so tests never
    // write into the bundle itself - same pattern as MissionBitsTests.
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

    func testDecodeAllProduceCorrectCounts() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertEqual(PilotInventory.decodeItemCount(from: pilotFile.workingBytes).count, 512)
        XCTAssertEqual(PilotInventory.decodeWeapCount(from: pilotFile.workingBytes).count, 256)
        XCTAssertEqual(PilotInventory.decodeAmmo(from: pilotFile.workingBytes).count, 256)
    }

    // Expected values computed directly from the fixture's raw bytes at
    // absolute offset 4126 (itemCount), not guessed - see PilotInventory.swift
    // for the offset derivation.
    func testDecodeItemCountMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let itemCount = PilotInventory.decodeItemCount(from: pilotFile.workingBytes)

        XCTAssertEqual(itemCount[5], 2)
        XCTAssertEqual(itemCount[8], 3)
        XCTAssertEqual(itemCount[9], 150)
        XCTAssertEqual(itemCount[15], 300)
        XCTAssertEqual(itemCount[16], 1)
        XCTAssertEqual(itemCount.filter { $0 != 0 }.count, 40)
    }

    // Expected values computed directly from the fixture's raw bytes at
    // absolute offset 9246 (weapCount).
    func testDecodeWeapCountMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let weapCount = PilotInventory.decodeWeapCount(from: pilotFile.workingBytes)

        XCTAssertEqual(weapCount[5], 2)
        XCTAssertEqual(weapCount[7], 3)
        XCTAssertEqual(weapCount[11], 1)
        XCTAssertEqual(weapCount[15], 5)
        XCTAssertEqual(weapCount[25], 1)
        XCTAssertEqual(weapCount[29], 5)
    }

    // Expected values computed directly from the fixture's raw bytes at
    // absolute offset 9758 (ammo).
    func testDecodeAmmoMatchesFixture() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let ammo = PilotInventory.decodeAmmo(from: pilotFile.workingBytes)

        XCTAssertEqual(ammo[7], 150)
        XCTAssertEqual(ammo[10], 300)
        XCTAssertEqual(ammo.filter { $0 != 0 }.count, 2)
    }

    func testSetItemCountChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertNoThrow(try pilotFile.setItemCount(77, at: 100))

        let targetOffset = PilotInventory.itemCountBaseOffset + 100 * 2
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)

        XCTAssertEqual(PilotInventory.decodeItemCount(from: pilotFile.workingBytes)[100], 77)
    }

    func testSetWeapCountChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertNoThrow(try pilotFile.setWeapCount(9, at: 50))

        let targetOffset = PilotInventory.weapCountBaseOffset + 50 * 2
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)

        XCTAssertEqual(PilotInventory.decodeWeapCount(from: pilotFile.workingBytes)[50], 9)
    }

    func testSetAmmoChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertNoThrow(try pilotFile.setAmmo(200, at: 30))

        let targetOffset = PilotInventory.ammoBaseOffset + 30 * 2
        assertOnlyBytesChanged(targetOffset..<(targetOffset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)

        XCTAssertEqual(PilotInventory.decodeAmmo(from: pilotFile.workingBytes)[30], 200)
    }

    func testSetOnInvalidIndexThrows() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertThrowsError(try pilotFile.setItemCount(1, at: -1))
        XCTAssertThrowsError(try pilotFile.setItemCount(1, at: 512))
        XCTAssertThrowsError(try pilotFile.setWeapCount(1, at: 256))
        XCTAssertThrowsError(try pilotFile.setAmmo(1, at: 256))
    }
}
