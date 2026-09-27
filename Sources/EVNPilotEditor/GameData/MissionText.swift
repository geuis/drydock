import Foundation

// The text a mission shows the player, read from the scenario's `dësc`
// resources. Each dësc starts with its text as a null-terminated Mac Roman
// string (line breaks are "\r"); the Graphic, MovieFile, and Flags fields
// that follow it aren't needed here.
public enum DescriptionText {
    public static func decodeAll(from library: GameDataLibrary) -> [Int: String] {
        var texts: [Int: String] = [:]

        for resource in library.resources(ofType: "dësc") where texts[resource.id] == nil {
            if let text = decode(resource.data) {
                texts[resource.id] = text
            }
        }

        return texts
    }

    static func decode(_ data: Data) -> String? {
        let end: Data.Index = data.firstIndex(of: 0) ?? data.endIndex

        guard let text = String(data: data[data.startIndex..<end], encoding: .macOSRoman) else { return nil }

        let normalized: String = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }
}

public struct MissionTextPart: Identifiable, Equatable, Sendable {
    public let title: String
    public let descriptionID: Int
    public let text: String

    public var id: Int { descriptionID }
}

public enum MissionText {
    // The Bible reserves dësc 4000-4999 for the text shown when a mission
    // is offered, numbered from the first mission ID (128).
    static let offerDescriptionBase = 4000 - 128

    // Every piece of text the mission has, in the order the player sees it.
    public static func parts(for mission: MissionDefinition, descriptions: [Int: String]) -> [MissionTextPart] {
        let sources: [(title: String, descriptionID: Int)] = [
            ("When offered", mission.id + offerDescriptionBase),
            ("On accepting", Int(mission.briefText)),
            ("Mission briefing", Int(mission.quickBrief)),
            ("Cargo loaded", Int(mission.loadCargText)),
            ("Cargo delivered", Int(mission.dumpCargoText)),
            ("On completing", Int(mission.compText))
        ]

        return sources.compactMap { source in
            // IDs below 128 mean "no text" (usually -1).
            guard source.descriptionID >= 128, let text = descriptions[source.descriptionID] else { return nil }
            return MissionTextPart(title: source.title, descriptionID: source.descriptionID, text: text)
        }
    }

    // Applies the dësc text switches, e.g. {b818 "if on" "if off"},
    // {!b12 "..."}, {G "male" "female"}, {P "paid" "unpaid"}, the way the
    // game would for this pilot. Registration can't be known, so P reads as
    // registered. A switch that can't be read is left as written.
    public static func resolveSwitches(in text: String, storyFlags: [Bool], isMale: Bool) -> String {
        let characters: [Character] = Array(text)
        var result: String = ""
        var index: Int = 0

        while index < characters.count {
            if characters[index] == "{", let parsed = parseSwitch(characters, from: index) {
                let isTrue: Bool = evaluate(parsed.test, storyFlags: storyFlags, isMale: isMale)
                result += isTrue ? parsed.whenTrue : parsed.whenFalse
                index = parsed.end
                continue
            }

            result.append(characters[index])
            index += 1
        }

        return result
    }

    // MARK: - Switch parsing

    private enum SwitchTest {
        case storyFlag(Int, negated: Bool)
        case male(negated: Bool)
        case registered(negated: Bool)
    }

    private struct ParsedSwitch {
        let test: SwitchTest
        let whenTrue: String
        let whenFalse: String
        // Index just past the closing "}".
        let end: Int
    }

    private static func evaluate(_ test: SwitchTest, storyFlags: [Bool], isMale: Bool) -> Bool {
        switch test {
        case .storyFlag(let flagID, let negated):
            let isOn: Bool = storyFlags.indices.contains(flagID) && storyFlags[flagID]
            return isOn != negated

        case .male(let negated):
            return isMale != negated

        case .registered(let negated):
            return !negated
        }
    }

    private static func parseSwitch(_ characters: [Character], from start: Int) -> ParsedSwitch? {
        var index: Int = skipSpaces(characters, from: start + 1)
        var negated: Bool = false

        if index < characters.count, characters[index] == "!" {
            negated = true
            index = skipSpaces(characters, from: index + 1)
        }

        guard index < characters.count else { return nil }

        let test: SwitchTest

        switch characters[index] {
        case "b", "B":
            let digitsEnd: Int = digitRunEnd(characters, from: index + 1)
            guard digitsEnd > index + 1, let flagID = Int(String(characters[(index + 1)..<digitsEnd])) else { return nil }
            test = .storyFlag(flagID, negated: negated)
            index = digitsEnd

        case "g", "G":
            test = .male(negated: negated)
            index += 1

        case "p", "P":
            // The optional day count doesn't matter, since registration is
            // always assumed.
            test = .registered(negated: negated)
            index = digitRunEnd(characters, from: index + 1)

        default:
            return nil
        }

        var strings: [String] = []
        index = skipSpaces(characters, from: index)

        while index < characters.count, characters[index] == "\"", strings.count < 2 {
            guard let quoted = readQuoted(characters, from: index) else { return nil }
            strings.append(quoted.text)
            index = skipSpaces(characters, from: quoted.end)
        }

        guard !strings.isEmpty, index < characters.count, characters[index] == "}" else { return nil }

        return ParsedSwitch(test: test, whenTrue: strings[0], whenFalse: strings.count > 1 ? strings[1] : "", end: index + 1)
    }

    // A "..." string with C-style \" escapes; `end` is just past the
    // closing quote.
    private static func readQuoted(_ characters: [Character], from start: Int) -> (text: String, end: Int)? {
        var text: String = ""
        var index: Int = start + 1

        while index < characters.count {
            let character: Character = characters[index]

            if character == "\\", index + 1 < characters.count {
                text.append(characters[index + 1])
                index += 2
                continue
            }

            if character == "\"" {
                return (text, index + 1)
            }

            text.append(character)
            index += 1
        }

        return nil
    }

    private static func skipSpaces(_ characters: [Character], from start: Int) -> Int {
        var index: Int = start

        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }

        return index
    }

    private static func digitRunEnd(_ characters: [Character], from start: Int) -> Int {
        var index: Int = start

        while index < characters.count, characters[index].isASCII, characters[index].isNumber {
            index += 1
        }

        return index
    }
}
