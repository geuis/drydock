import Foundation

// Parses and evaluates the NCB (Nova Control Bit) "test expression" syntax
// documented in the Nova Bible (lines ~106-137 of the converted text),
// used by mïsn's AvailBits field (and by outfit/ship availability fields,
// though this type is scenario-data-agnostic and works on any such string).
//
// Grammar (case-insensitive):
//   Bxxx    control bit xxx's current value
//   Pxxx    "is the game registered, or unregistered but less than xxx
//            days elapsed" - this app has no way to know either fact about
//            a real player's copy of the game, so it is always treated as
//            TRUE and reported as "assumed" rather than measured.
//   G       player's gender (1 if male, 0 if female)
//   Oxxx    player owns at least one of outfit item ID xxx
//   Exxx    player has explored system ID xxx
//   |  &  !  ( )
// A blank expression evaluates to true (the Bible states this explicitly -
// most missions leave AvailBits blank and are available purely based on
// their other Avail* fields).
//
// PRECEDENCE CHOICE: the Bible itself warns "the Nova evaluator is fairly
// primitive" and may do "unpredictable things" with an expression that
// mixes `&` and `|` without disambiguating parentheses, explicitly
// recommending authors write `b1 & (b2 | b3)` rather than `b1 & b2 | b3`.
// Rather than guess at Nova's real internal operator-precedence table (which
// is not documented), this parser follows the Bible's own warning literally:
// `&` and `|` are treated as equal-precedence, left-to-right binary
// operators - so `a & b | c` parses as `(a & b) | c`, NOT as the C-family
// convention of `a & (b | c)` (which `&` binding tighter than `|` would
// give). This choice is deliberately visible to the caller: any expression
// where a single unparenthesized run of terms mixes both `&` and `|` is
// flagged via `NCBParseResult.isAmbiguous`, since that is exactly the shape
// the Bible warns is unreliable - the UI should call this out rather than
// silently trust either reading. Parenthesizing a sub-expression starts a
// fresh run, so `b1 & (b2 | b3)` is NOT ambiguous (each run uses only one
// operator), matching the Bible's own suggested fix.
public enum NCBTestExpression {
    public static func parse(_ text: String) -> NCBParseResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NCBParseResult(node: nil, error: nil, isAmbiguous: false)
        }

        do {
            let tokens = try Lexer.tokenize(trimmed)
            var parser = Parser(tokens: tokens)
            let node = try parser.parseExpression()
            try parser.expectEnd()
            return NCBParseResult(node: node, error: nil, isAmbiguous: parser.sawAmbiguity)
        } catch let error as ParseError {
            return NCBParseResult(node: nil, error: error.message, isAmbiguous: false)
        } catch {
            return NCBParseResult(node: nil, error: "Could not parse expression \"\(trimmed)\".", isAmbiguous: false)
        }
    }
}

// MARK: - Result / AST types

public indirect enum NCBNode: Sendable, Equatable {
    case bit(Int)
    case registered(days: Int)
    case male
    case outfit(Int)
    case explored(Int)
    case not(NCBNode)
    case and([NCBNode])
    case or([NCBNode])
}

public struct NCBParseResult: Sendable {
    public let node: NCBNode?
    public let error: String?
    public let isAmbiguous: Bool

    public init(node: NCBNode?, error: String?, isAmbiguous: Bool) {
        self.node = node
        self.error = error
        self.isAmbiguous = isAmbiguous
    }
}

// MARK: - Evaluation types

public enum NCBTermKind: Sendable, Equatable {
    case bit(Int)
    case registered(days: Int)
    case male
    case outfit(Int)
    case explored(Int)
}

public struct NCBTermEvaluation: Sendable, Equatable {
    public let kind: NCBTermKind
    // The term's current truth value.
    public let value: Bool
    // True for P terms (we cannot know registration/elapsed-day state) and
    // for G terms when the pilot's gender is unknown - in both cases the
    // value above is a best-effort assumption, not a measurement.
    public let isAssumed: Bool

    public init(kind: NCBTermKind, value: Bool, isAssumed: Bool) {
        self.kind = kind
        self.value = value
        self.isAssumed = isAssumed
    }
}

public indirect enum NCBExplanation: Sendable, Equatable {
    case term(NCBTermEvaluation)
    case not(NCBExplanation, value: Bool)
    case all([NCBExplanation], value: Bool)
    case any([NCBExplanation], value: Bool)

    public var value: Bool {
        switch self {
        case .term(let evaluation): return evaluation.value
        case .not(_, let value): return value
        case .all(_, let value): return value
        case .any(_, let value): return value
        }
    }
}

// MARK: - Evaluation

extension NCBNode {
    // Walks this parsed expression against a pilot's current story state,
    // producing both the overall truth value and a full explanation tree
    // the UI can render term-by-term (see MissionDiagnostics, which is the
    // primary consumer).
    public func explain(against state: PilotStoryState) -> NCBExplanation {
        switch self {
        case .bit(let id):
            let value = (0..<state.bits.count).contains(id) ? state.bits[id] : false
            return .term(NCBTermEvaluation(kind: .bit(id), value: value, isAssumed: false))

        case .registered(let days):
            // We have no way to know whether this player's copy of the game
            // is registered, or how many days have elapsed - per the task
            // spec, always assume TRUE (the more permissive reading) and
            // mark the term as assumed rather than measured.
            return .term(NCBTermEvaluation(kind: .registered(days: days), value: true, isAssumed: true))

        case .male:
            if let isMale = state.isMale {
                return .term(NCBTermEvaluation(kind: .male, value: isMale, isAssumed: false))
            }
            // Gender unknown: assume true (male), consistent with the
            // "assume permissive/true when we can't know" convention used
            // for P terms above. Marked assumed either way.
            return .term(NCBTermEvaluation(kind: .male, value: true, isAssumed: true))

        case .outfit(let id):
            let index = id - PilotStoryState.outfitIDBase
            let value = (0..<state.outfitCounts.count).contains(index) ? state.outfitCounts[index] > 0 : false
            return .term(NCBTermEvaluation(kind: .outfit(id), value: value, isAssumed: false))

        case .explored(let id):
            let index = id - PilotStoryState.systemIDBase
            let value = (0..<state.exploration.count).contains(index) ? state.exploration[index] > 0 : false
            return .term(NCBTermEvaluation(kind: .explored(id), value: value, isAssumed: false))

        case .not(let inner):
            let explanation = inner.explain(against: state)
            return .not(explanation, value: !explanation.value)

        case .and(let nodes):
            let explanations = nodes.map { $0.explain(against: state) }
            return .all(explanations, value: explanations.allSatisfy(\.value))

        case .or(let nodes):
            let explanations = nodes.map { $0.explain(against: state) }
            return .any(explanations, value: explanations.contains(where: \.value))
        }
    }
}

// MARK: - Lexer

private enum Token: Equatable {
    case leftParen
    case rightParen
    case and
    case or
    case not
    case bit(Int)
    case registered(days: Int)
    case male
    case outfit(Int)
    case explored(Int)
}

private struct ParseError: Error {
    let message: String
}

private enum Lexer {
    static func tokenize(_ text: String) throws -> [Token] {
        var tokens: [Token] = []
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character.isWhitespace {
                index += 1
                continue
            }

            switch character {
            case "(":
                tokens.append(.leftParen)
                index += 1
            case ")":
                tokens.append(.rightParen)
                index += 1
            case "&":
                tokens.append(.and)
                index += 1
            case "|":
                tokens.append(.or)
                index += 1
            case "!":
                tokens.append(.not)
                index += 1
            case "b", "B":
                let (digits, next) = readDigits(characters, from: index + 1)
                guard let value = digits else {
                    throw ParseError(message: "\"B\" at position \(index) must be followed by a control bit number.")
                }
                tokens.append(.bit(value))
                index = next
            case "p", "P":
                let (digits, next) = readDigits(characters, from: index + 1)
                guard let value = digits else {
                    throw ParseError(message: "\"P\" at position \(index) must be followed by a day count.")
                }
                tokens.append(.registered(days: value))
                index = next
            case "o", "O":
                let (digits, next) = readDigits(characters, from: index + 1)
                guard let value = digits else {
                    throw ParseError(message: "\"O\" at position \(index) must be followed by an outfit ID.")
                }
                tokens.append(.outfit(value))
                index = next
            case "e", "E":
                let (digits, next) = readDigits(characters, from: index + 1)
                guard let value = digits else {
                    throw ParseError(message: "\"E\" at position \(index) must be followed by a system ID.")
                }
                tokens.append(.explored(value))
                index = next
            case "g", "G":
                tokens.append(.male)
                index += 1
            default:
                throw ParseError(message: "Unexpected character \"\(character)\" at position \(index).")
            }
        }

        return tokens
    }

    // Reads a run of ASCII digits starting at `start`, returning nil (no
    // consumption) if `start` isn't a digit at all - callers use that to
    // report "letter with no number after it" as a parse error.
    private static func readDigits(_ characters: [Character], from start: Int) -> (Int?, Int) {
        var end = start
        while end < characters.count, characters[end].isASCII, characters[end].isNumber {
            end += 1
        }
        guard end > start, let value = Int(String(characters[start..<end])) else {
            return (nil, start)
        }
        return (value, end)
    }
}

// MARK: - Parser
//
// Recursive-descent parser implementing the equal-precedence, left-to-right
// `&`/`|` rule described in the file's top-of-file doc comment. Each call to
// `parseExpression()` handles one "run" of terms at a single nesting level
// (bounded by parentheses or the ends of the input); if that single run uses
// both `&` and `|`, `sawAmbiguity` is set for the whole parse.

private struct Parser {
    let tokens: [Token]
    var position = 0
    var sawAmbiguity = false

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    mutating func expectEnd() throws {
        guard position == tokens.count else {
            throw ParseError(message: "Unexpected extra input after a complete expression.")
        }
    }

    // One level: term ((& | \|) term)*, folded left-to-right. Runs of the
    // same operator are flattened into a single .and/.or for a cleaner tree;
    // switching operator mid-run still folds left-to-right (see doc comment
    // above) and marks the whole parse ambiguous.
    mutating func parseExpression() throws -> NCBNode {
        var accumulated = try parseUnary()
        var lastOperatorWasAnd: Bool?
        var sawAnd = false
        var sawOr = false

        while let operatorToken = peekOperator() {
            position += 1
            let term = try parseUnary()
            let isAnd = operatorToken == .and

            if isAnd { sawAnd = true } else { sawOr = true }

            if lastOperatorWasAnd == isAnd, case .and(let existing) = accumulated, isAnd {
                accumulated = .and(existing + [term])
            } else if lastOperatorWasAnd == isAnd, case .or(let existing) = accumulated, !isAnd {
                accumulated = .or(existing + [term])
            } else {
                accumulated = isAnd ? .and([accumulated, term]) : .or([accumulated, term])
            }

            lastOperatorWasAnd = isAnd
        }

        if sawAnd, sawOr {
            sawAmbiguity = true
        }

        return accumulated
    }

    private func peekOperator() -> Token? {
        guard position < tokens.count else { return nil }
        let token = tokens[position]
        return (token == .and || token == .or) ? token : nil
    }

    mutating func parseUnary() throws -> NCBNode {
        guard position < tokens.count else {
            throw ParseError(message: "Expression ended unexpectedly.")
        }

        if tokens[position] == .not {
            position += 1
            return .not(try parseUnary())
        }

        return try parsePrimary()
    }

    mutating func parsePrimary() throws -> NCBNode {
        guard position < tokens.count else {
            throw ParseError(message: "Expected a term but the expression ended.")
        }

        switch tokens[position] {
        case .leftParen:
            position += 1
            let inner = try parseExpression()
            guard position < tokens.count, tokens[position] == .rightParen else {
                throw ParseError(message: "Missing closing parenthesis.")
            }
            position += 1
            return inner

        case .rightParen:
            throw ParseError(message: "Unexpected closing parenthesis.")

        case .and, .or:
            throw ParseError(message: "Unexpected operator - expected a term first.")

        case .not:
            // Handled by parseUnary, but guard defensively so this switch
            // stays exhaustive without ever falling through silently.
            position += 1
            return .not(try parseUnary())

        case .bit(let id):
            position += 1
            return .bit(id)

        case .registered(let days):
            position += 1
            return .registered(days: days)

        case .male:
            position += 1
            return .male

        case .outfit(let id):
            position += 1
            return .outfit(id)

        case .explored(let id):
            position += 1
            return .explored(id)
        }
    }
}
