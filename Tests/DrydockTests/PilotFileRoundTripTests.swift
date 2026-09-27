import XCTest
@testable import Drydock

final class PilotFileRoundTripTests: XCTestCase {
    private static let shipNameField = FieldDefinition(
        id: "shipName",
        name: "Ship Name",
        offset: 83698,
        length: 70,
        type: FieldType(kind: .pascalString, maxLength: 69),
        group: "Identity",
        confidence: .verified,
        editable: true
    )

    private static let shipClassNameField = FieldDefinition(
        id: "shipClassName",
        name: "Ship Class",
        offset: 86104,
        length: -1,
        type: FieldType(kind: .cString, maxLength: 256),
        group: "Identity",
        confidence: .verified,
        editable: false
    )

    private func fixtureURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "Chuck Yeager", withExtension: "plt", subdirectory: "Fixtures") else {
            XCTFail("Could not locate bundled fixture Chuck Yeager.plt")
            throw XCTSkip("Fixture not found")
        }
        return url
    }

    // Copies the bundled fixture into a fresh temp directory so tests never
    // write into the bundle itself.
    private func makeTempCopyOfFixture() throws -> URL {
        let sourceURL = try fixtureURL()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let destinationURL = tempDirectory.appendingPathComponent("Chuck Yeager.plt")
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        return destinationURL
    }

    func testRoundTripByteIdentical() throws {
        let tempURL = try makeTempCopyOfFixture()
        let originalBytesBeforeSave = try Data(contentsOf: tempURL)

        let pilotFile = try PilotFile(url: tempURL)
        XCTAssertTrue(pilotFile.isRoundTripIdentical)

        try pilotFile.save()

        let bytesAfterSave = try Data(contentsOf: tempURL)
        XCTAssertEqual(bytesAfterSave, originalBytesBeforeSave)
    }

    func testDecodeShipName() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        let value = pilotFile.value(for: Self.shipNameField)
        XCTAssertEqual(value, .string("Hawkeye"))
    }

    func testDecodeShipClassName() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        guard case .string(let value) = pilotFile.value(for: Self.shipClassNameField) else {
            XCTFail("Expected shipClassName to decode as a string")
            return
        }

        XCTAssertTrue(value.hasSuffix("Pirate Carrier 476") || value == "Pirate Carrier 476")
    }

    func testSetShipNameThenRoundTripOnlyChangesDeclaredBytes() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)
        let field = Self.shipNameField

        XCTAssertNoThrow(try pilotFile.setValue(.string("Testpilot"), for: field))

        let original = pilotFile.originalBytes
        let working = pilotFile.workingBytes
        XCTAssertEqual(original.count, working.count)

        let fieldRange = field.offset..<(field.offset + field.length)

        for index in 0..<original.count {
            if fieldRange.contains(index) {
                continue
            }
            XCTAssertEqual(
                original[original.startIndex + index],
                working[working.startIndex + index],
                "Byte at offset \(index) outside the declared field range was modified"
            )
        }

        let decoded = pilotFile.value(for: field)
        XCTAssertEqual(decoded, .string("Testpilot"))
    }

    func testSaveRefusesWhenFileChangedOnDisk() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)
        try pilotFile.setNickname("Edited")

        // Simulates the game saving the pilot while the editor has it open.
        var gameSave = try Data(contentsOf: tempURL)
        gameSave[gameSave.startIndex + PilotProfile.creditsOffset] ^= 0xFF
        try gameSave.write(to: tempURL)

        XCTAssertTrue(pilotFile.hasChangedOnDisk)
        XCTAssertThrowsError(try pilotFile.save()) { error in
            XCTAssertEqual(error as? PilotFileError, .changedOnDisk)
        }
        XCTAssertEqual(try Data(contentsOf: tempURL), gameSave)
    }

    func testOverwritingExternalChangesBacksUpTheDiskVersion() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)
        try pilotFile.setNickname("Edited")

        var gameSave = try Data(contentsOf: tempURL)
        gameSave[gameSave.startIndex + PilotProfile.creditsOffset] ^= 0xFF
        try gameSave.write(to: tempURL)

        try pilotFile.save(overwritingExternalChanges: true)

        let directory = tempURL.deletingLastPathComponent()
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains(".bak-") }
        XCTAssertEqual(backups.count, 1)

        let backupBytes = try Data(contentsOf: directory.appendingPathComponent(backups[0]))
        XCTAssertEqual(backupBytes, gameSave)
        XCTAssertEqual(try Data(contentsOf: tempURL), pilotFile.workingBytes)
        XCTAssertFalse(pilotFile.hasChangedOnDisk)
    }

    func testEditingNonEditableFieldThrows() throws {
        let tempURL = try makeTempCopyOfFixture()
        let pilotFile = try PilotFile(url: tempURL)

        XCTAssertThrowsError(try pilotFile.setValue(.string("x"), for: Self.shipClassNameField))
    }
}
