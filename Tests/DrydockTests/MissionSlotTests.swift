import XCTest
@testable import Drydock

final class MissionSlotTests: XCTestCase {
    // Absolute offset of slot 0's `isActive` byte (MissionObjectives base
    // 0x2822, local offset 0 for isActive). Mirrors the offset math in
    // MissionSlot.Layout, kept independent here as a regression check.
    private static let slotZeroIsActiveOffset = 0x2822
    private static let slotZeroRawMissionIDOffset = 0x2962 + 0x4d

    private func fixtureURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "Shane Merrol", withExtension: "plt", subdirectory: "Fixtures") else {
            XCTFail("Could not locate bundled fixture Shane Merrol.plt")
            throw XCTSkip("Fixture not found")
        }
        return url
    }

    // Copies the bundled fixture into a fresh temp directory so tests never
    // write into the bundle itself - same pattern as PilotFileRoundTripTests.
    private func makeTempCopyOfFixture() throws -> URL {
        let sourceURL = try fixtureURL()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let destinationURL = tempDirectory.appendingPathComponent("Shane Merrol.plt")
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        return destinationURL
    }

    func testDecodeAllProducesSixteenSlots() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let slots = MissionSlot.decodeAll(from: pilotFile.workingBytes)

        XCTAssertEqual(slots.count, 16)
        XCTAssertEqual(slots.map(\.index), Array(0..<16))
    }

    // Empirically verified against the real bytes: the Pascal length byte at
    // the mission-name field for slot 0 reads 27, and the 27 bytes it
    // declares decode to this clean, game-plausible mission title. (The
    // fixed 127-byte buffer actually holds more readable text past that
    // declared length - confirmed identical in both real sample files for
    // untouched template mission slots - but that trailing text is not part
    // of the length-prefixed name the game itself would display, so it is
    // deliberately excluded here.)
    func testDecodeMissionNameForSlotZero() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let slots = MissionSlot.decodeAll(from: pilotFile.workingBytes)
        let slotZero = slots[0]

        XCTAssertEqual(slotZero.missionName, "Meet With Merrol DockMaster")
        XCTAssertEqual(slotZero.missionID, 783)
        XCTAssertTrue(slotZero.isActive)

        let data = pilotFile.workingBytes
        let rawLow = UInt16(data[data.startIndex + Self.slotZeroRawMissionIDOffset])
        let rawHigh = UInt16(data[data.startIndex + Self.slotZeroRawMissionIDOffset + 1]) << 8
        XCTAssertEqual(rawLow | rawHigh, 655, "Pilot stores mïsn ID minus the resource base of 128")
    }

    func testSetFlagChangesOnlyThatByte() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        // Slot 0 is active in the fixture; flip it off and verify exactly
        // one byte changed.
        let before = MissionSlot.decodeAll(from: pilotFile.workingBytes)[0]
        XCTAssertTrue(before.isActive)

        XCTAssertNoThrow(try pilotFile.setMissionFlag(.isActive, to: false, missionIndex: 0))

        let original = pilotFile.originalBytes
        let working = pilotFile.workingBytes
        XCTAssertEqual(original.count, working.count)

        for index in 0..<original.count {
            if index == Self.slotZeroIsActiveOffset {
                continue
            }
            XCTAssertEqual(
                original[original.startIndex + index],
                working[working.startIndex + index],
                "Byte at offset \(index) outside the flipped flag byte was modified"
            )
        }

        XCTAssertEqual(working[working.startIndex + Self.slotZeroIsActiveOffset], 0)

        let after = MissionSlot.decodeAll(from: pilotFile.workingBytes)[0]
        XCTAssertFalse(after.isActive)
    }

    func testSetFlagOnInvalidIndexThrows() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertThrowsError(try pilotFile.setMissionFlag(.isActive, to: true, missionIndex: 16))
        XCTAssertThrowsError(try pilotFile.setMissionFlag(.isActive, to: true, missionIndex: -1))
    }

    func testSetPayChangesOnlyThoseFourBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        // Slot 3's pay field is well outside the removed-field regions and
        // verified cross-file to a plausible 20000-credit reward.
        let before = MissionSlot.decodeAll(from: pilotFile.workingBytes)[3]
        XCTAssertEqual(before.pay, 20000)

        XCTAssertNoThrow(try pilotFile.setMissionPay(42, missionIndex: 3))

        let original = pilotFile.originalBytes
        let working = pilotFile.workingBytes
        XCTAssertEqual(original.count, working.count)

        let payOffset = MissionSlot.Layout.missionDataBase
            + 3 * MissionSlot.Layout.missionDataStride
            + MissionSlot.Layout.payLocalOffset
        let payRange = payOffset..<(payOffset + 4)

        for index in 0..<original.count {
            if payRange.contains(index) {
                continue
            }
            XCTAssertEqual(
                original[original.startIndex + index],
                working[working.startIndex + index],
                "Byte at offset \(index) outside the pay field was modified"
            )
        }

        let after = MissionSlot.decodeAll(from: pilotFile.workingBytes)[3]
        XCTAssertEqual(after.pay, 42)
    }
}
