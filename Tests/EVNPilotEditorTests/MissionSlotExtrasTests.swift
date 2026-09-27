import XCTest
@testable import EVNPilotEditor

// Covers the mission-slot extras added on top of MissionSlotTests.swift:
// travelStel/returnStel decode, setTimeLeft, and PilotFile.clearMissionSlot.
final class MissionSlotExtrasTests: XCTestCase {
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

    // Slot 0 (the active "Meet With Merrol DockMaster" mission) decodes to
    // travelStel -1 (no travel objective pending - plausible, since this
    // mission is already docked) and returnStel 43 (a plausible stellar
    // object index). Single-sample confirmation only (Geuis's fixture has no
    // active missions to cross-check against) - Probable.
    func testDecodeTravelAndReturnStelForActiveSlot() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let slots = MissionSlot.decodeAll(from: pilotFile.workingBytes)
        let slotZero = slots[0]

        XCTAssertTrue(slotZero.isActive)
        XCTAssertEqual(slotZero.travelStel, -1)
        XCTAssertEqual(slotZero.returnStel, 43)
    }

    func testSetTimeLeftChangesOnlyThoseTwoBytesAndDecodesBack() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertNoThrow(try pilotFile.setMissionTimeLeft(30, missionIndex: 3))

        let offset = MissionSlot.Layout.missionDataBase
            + 3 * MissionSlot.Layout.missionDataStride
            + MissionSlot.Layout.timeLeftLocalOffset

        assertOnlyBytesChanged(offset..<(offset + 2), original: pilotFile.originalBytes, working: pilotFile.workingBytes)

        let after = MissionSlot.decodeAll(from: pilotFile.workingBytes)[3]
        XCTAssertEqual(after.timeLeft, 30)
    }

    func testSetTimeLeftOnInvalidIndexThrows() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertThrowsError(try pilotFile.setMissionTimeLeft(1, missionIndex: 16))
        XCTAssertThrowsError(try pilotFile.setMissionTimeLeft(1, missionIndex: -1))
    }

    // clearMissionSlot flips all four MissionObjectives flags for slot 0
    // (active in the fixture) to false, and touches only those four bytes.
    func testClearMissionSlotClearsAllFourFlagsAndChangesOnlyThoseBytes() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let before = MissionSlot.decodeAll(from: pilotFile.workingBytes)[0]
        XCTAssertTrue(before.isActive)

        XCTAssertNoThrow(try pilotFile.clearMissionSlot(0))

        let objStart = MissionSlot.Layout.missionObjectivesBase + 0 * MissionSlot.Layout.missionObjectivesStride
        let original = pilotFile.originalBytes
        let working = pilotFile.workingBytes
        XCTAssertEqual(original.count, working.count)

        let flagRange = objStart..<(objStart + 4)
        for index in 0..<original.count {
            if flagRange.contains(index) {
                continue
            }
            XCTAssertEqual(
                original[original.startIndex + index],
                working[working.startIndex + index],
                "Byte at offset \(index) outside the four MissionObjectives flags was modified"
            )
        }

        let after = MissionSlot.decodeAll(from: pilotFile.workingBytes)[0]
        XCTAssertFalse(after.isActive)
        XCTAssertFalse(after.travelObjComplete)
        XCTAssertFalse(after.shipObjComplete)
        XCTAssertFalse(after.missionFailed)
    }

    // An invalid index must leave workingBytes completely untouched (all
    // four scratch writes are atomic - either all commit or none do).
    func testClearMissionSlotOnInvalidIndexThrowsAndMutatesNothing() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertThrowsError(try pilotFile.clearMissionSlot(16))
        XCTAssertEqual(pilotFile.workingBytes, pilotFile.originalBytes)

        XCTAssertThrowsError(try pilotFile.clearMissionSlot(-1))
        XCTAssertEqual(pilotFile.workingBytes, pilotFile.originalBytes)
    }
}
