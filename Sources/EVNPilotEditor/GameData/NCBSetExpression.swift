import Foundation

// The one parser for NCB "set" expressions (mïsn OnAccept/OnSuccess/...,
// and the matching fields on outfits, ships, events, and so on; Nova Bible
// lines ~146-227). Whitespace-separated operations such as "b353" (turn
// flag 353 on), "!b12" (off), "^b3" (toggle), "S783" (start mission 783),
// with "R(op1 op2)" picking one of its operations at random.
//
// Mission chaining, story-flag references, and marking a mission done all
// read expressions through here, so they can't disagree about what one does.
enum NCBSetExpression {
    // One operation.
    enum Operation: Equatable, Sendable {
        case set(Int)
        case clear(Int)
        case toggle(Int)
        // Anything that isn't a flag change, kept as written ("S733").
        case other(String)

        var flagID: Int? {
            switch self {
            case .set(let id), .clear(let id), .toggle(let id): return id
            case .other: return nil
            }
        }

        // The mission an "Sxxx" operation starts.
        var startedMissionID: Int? {
            guard case .other(let token) = self, let letter = token.first, letter == "S" || letter == "s" else { return nil }

            return NCBSetExpression.leadingNumber(token.dropFirst())
        }
    }

    // A top-level step: a plain operation, or an R(...) random choice
    // between several.
    enum Step: Equatable, Sendable {
        case single(Operation)
        case randomChoice([Operation])

        var operations: [Operation] {
            switch self {
            case .single(let operation): return [operation]
            case .randomChoice(let options): return options
            }
        }
    }

    // Splits a set expression into steps: whitespace-separated operations,
    // with each R(...) group kept together as one random choice.
    static func parse(_ expression: String) -> [Step] {
        let characters: [Character] = Array(expression)
        var steps: [Step] = []
        var index: Int = 0

        while index < characters.count {
            if characters[index].isWhitespace {
                index += 1
                continue
            }

            let isRandomGroup: Bool = (characters[index] == "R" || characters[index] == "r")
                && index + 1 < characters.count
                && characters[index + 1] == "("

            if isRandomGroup {
                var cursor: Int = index + 2
                var depth: Int = 1

                while cursor < characters.count, depth > 0 {
                    if characters[cursor] == "(" { depth += 1 }
                    if characters[cursor] == ")" { depth -= 1 }
                    cursor += 1
                }

                let contentEnd: Int = depth == 0 ? cursor - 1 : cursor
                let content: String = String(characters[(index + 2)..<max(index + 2, contentEnd)])
                let options: [Operation] = content.split(whereSeparator: \.isWhitespace).map { operation(String($0)) }

                steps.append(.randomChoice(options))
                index = cursor
                continue
            }

            var end: Int = index

            while end < characters.count, !characters[end].isWhitespace {
                end += 1
            }

            steps.append(.single(operation(String(characters[index..<end]))))
            index = end
        }

        return steps
    }

    // Every operation, with random choices flattened (either option could
    // happen), in the order written.
    static func operations(in expression: String) -> [Operation] {
        parse(expression).flatMap(\.operations)
    }

    // Mission IDs this expression starts ("Sxxx"), in order.
    static func startedMissionIDs(in expression: String) -> [Int] {
        operations(in: expression).compactMap(\.startedMissionID)
    }

    // Flags that only one side of an R(...) random choice changes, so an
    // outcome doesn't always change them.
    static func flagIDsInsideRandomChoices(in expression: String) -> Set<Int> {
        var ids: Set<Int> = []

        for step in parse(expression) {
            if case .randomChoice(let options) = step {
                ids.formUnion(options.compactMap(\.flagID))
            }
        }

        return ids
    }

    private static func operation(_ token: String) -> Operation {
        var text: Substring = Substring(token)
        var prefix: Character?

        if let first = text.first, first == "!" || first == "^" {
            prefix = first
            text = text.dropFirst()
        }

        guard let letter = text.first, letter == "b" || letter == "B", let id = leadingNumber(text.dropFirst()) else {
            return .other(token)
        }

        switch prefix {
        case "!": return .clear(id)
        case "^": return .toggle(id)
        default: return .set(id)
        }
    }

    // The run of digits at the start of `text`, ignoring anything after it
    // (a stray ")" or "," in hand-edited data).
    private static func leadingNumber(_ text: Substring) -> Int? {
        let digits: Substring = text.prefix { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}
