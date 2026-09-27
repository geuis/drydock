import XCTest
@testable import Drydock

final class MissionTextTests: XCTestCase {
    private func flags(on flagIDs: [Int]) -> [Bool] {
        var bits: [Bool] = Array(repeating: false, count: 10000)

        for flagID in flagIDs {
            bits[flagID] = true
        }

        return bits
    }

    // MARK: - dësc decoding

    func testDecodeStopsAtNullAndNormalizesLineBreaks() {
        var data = Data("First line.\rSecond line.".utf8)
        data.append(contentsOf: [0, 0x41, 0x42])

        XCTAssertEqual(DescriptionText.decode(data), "First line.\nSecond line.")
    }

    func testDecodeTreatsBlankTextAsMissing() {
        XCTAssertNil(DescriptionText.decode(Data([0, 0, 0])))
    }

    // MARK: - Text switches

    func testStoryFlagSwitchPicksFirstStringWhenOn() {
        let text = "This is a {b1 \"great\" \"lousy\"} example."

        XCTAssertEqual(MissionText.resolveSwitches(in: text, storyFlags: flags(on: [1]), isMale: true), "This is a great example.")
        XCTAssertEqual(MissionText.resolveSwitches(in: text, storyFlags: flags(on: []), isMale: true), "This is a lousy example.")
    }

    func testNegatedSwitchAndMissingSecondString() {
        let text = "A{!b2 \" and B\"}."

        XCTAssertEqual(MissionText.resolveSwitches(in: text, storyFlags: flags(on: []), isMale: true), "A and B.")
        XCTAssertEqual(MissionText.resolveSwitches(in: text, storyFlags: flags(on: [2]), isMale: true), "A.")
    }

    func testEscapedQuotesInsideSwitch() {
        let text = "My name is {b3 \"Dave \\\"pipeline\\\" Williams\"}"

        XCTAssertEqual(MissionText.resolveSwitches(in: text, storyFlags: flags(on: [3]), isMale: true), "My name is Dave \"pipeline\" Williams")
    }

    func testGenderAndRegistrationSwitches() {
        let text = "{G \"sir\" \"ma'am\"}, you {P30 \"have paid\" \"haven't paid\"}"

        XCTAssertEqual(MissionText.resolveSwitches(in: text, storyFlags: [], isMale: false), "ma'am, you have paid")
    }

    func testUnreadableSwitchIsLeftAsWritten() {
        let text = "Odd {braces} and {b5 \"unclosed\""

        XCTAssertEqual(MissionText.resolveSwitches(in: text, storyFlags: flags(on: [5]), isMale: true), text)
    }

    // MARK: - Parts

    func testPartsUseOfferIDAndSkipMissingText() throws {
        let missions = try realMissions()
        let mission = try XCTUnwrap(missions.missions.first { $0.id == 161 })
        let parts = MissionText.parts(for: mission, descriptions: missions.descriptions)

        // Meet With Rebels: offer 4033, accept 5286, briefing 6286,
        // delivered 8286, completion 9286; no load-cargo text (-1).
        XCTAssertEqual(parts.map(\.descriptionID), [4033, 5286, 6286, 8286, 9286])
        XCTAssertEqual(parts.first?.title, "When offered")
        XCTAssertTrue(parts[2].text.hasPrefix("Take Mu'Randa to <RST>"))
    }

    func testRealBriefingSwitchResolves() throws {
        let missions = try realMissions()
        let briefing = try XCTUnwrap(missions.descriptions[5275])
        let withFlag = MissionText.resolveSwitches(in: briefing, storyFlags: flags(on: [818]), isMale: true)
        let withoutFlag = MissionText.resolveSwitches(in: briefing, storyFlags: flags(on: []), isMale: true)

        XCTAssertTrue(withFlag.hasPrefix("You agree rapidly"), withFlag)
        XCTAssertTrue(withoutFlag.hasPrefix("After agreeing to help her"), withoutFlag)
        XCTAssertFalse(withoutFlag.contains("{b818"))
    }

    private func realMissions() throws -> (missions: [MissionDefinition], descriptions: [Int: String]) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/EV Nova/Nova Files", isDirectory: true)

        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("EV Nova game files not found - skipping real-data check.")
        }

        let library = try GameDataLibrary(contentsOfDirectory: directory)
        return (MissionDefinition.decodeAll(from: library), DescriptionText.decodeAll(from: library))
    }
}
