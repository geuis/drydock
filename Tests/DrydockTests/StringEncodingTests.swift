import XCTest
@testable import Drydock

// Pilot strings are Mac OS Roman, like every other string the game stores.
final class StringEncodingTests: XCTestCase {
    func testPascalStringRoundTripsAccentedCharactersAsMacRoman() throws {
        var data = Data(repeating: 0, count: 16)
        try ByteWriter.writePascalString("José", at: 0, maxLength: 15, into: &data)

        // "é" is the single byte 0x8E in Mac OS Roman.
        XCTAssertEqual(Array(data.prefix(5)), [4, 0x4A, 0x6F, 0x73, 0x8E])
        XCTAssertEqual(try ByteReader(data).pascalString(at: 0, maxLength: 15), "José")
    }

    func testPascalStringRejectsCharactersMacRomanCannotHold() {
        var data = Data(repeating: 0, count: 16)

        XCTAssertThrowsError(try ByteWriter.writePascalString("Pilot 🚀", at: 0, maxLength: 15, into: &data)) { error in
            XCTAssertEqual(error as? ByteWriterError, .unencodableCharacters)
            // Alerts show this text, so it must be the readable message.
            XCTAssertTrue(error.localizedDescription.contains("can't store"))
        }
        XCTAssertEqual(data, Data(repeating: 0, count: 16))
    }

    func testHighBytesInAMissionNameNoLongerBlankTheSlot() throws {
        // A classic-Mac curly apostrophe (0xD5) used to fail UTF8 decoding.
        let data = Data([6, 0x4B, 0x69, 0x6D, 0xD5, 0x73, 0x21])

        XCTAssertEqual(try ByteReader(data).pascalString(at: 0, maxLength: 63), "Kim\u{2019}s!")
    }

    func testCStringWithUnboundedMaxLengthDoesNotOverflow() throws {
        let data = Data([0x41, 0x42, 0x43])

        XCTAssertEqual(try ByteReader(data).cString(at: 1, maxLength: Int.max), "BC")
    }

    func testDateSuffixWritesMacRoman() throws {
        guard let url = Bundle.module.url(forResource: "Chuck Yeager", withExtension: "plt", subdirectory: "Fixtures") else {
            throw XCTSkip("Fixture not found")
        }

        var data = try Data(contentsOf: url)
        try PilotUniverseState.setDateSuffix(" Año", in: &data)

        XCTAssertEqual(PilotUniverseState.decodeDateSuffix(from: data), " Año")
    }
}
