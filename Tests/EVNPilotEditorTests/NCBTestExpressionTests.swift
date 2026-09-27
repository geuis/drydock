import XCTest
@testable import EVNPilotEditor

// Covers NCBTestExpression's parser (grammar, precedence/ambiguity choice,
// error handling) and NCBNode.explain(against:)'s evaluation against a
// PilotStoryState. See NCBTestExpression.swift's file doc comment for the
// left-to-right equal-precedence design this parser deliberately follows.
final class NCBTestExpressionTests: XCTestCase {
    // MARK: - Blank

    func testBlankExpressionParsesAsTrueWithNoNode() {
        let result = NCBTestExpression.parse("")
        XCTAssertNil(result.node)
        XCTAssertNil(result.error)
        XCTAssertFalse(result.isAmbiguous)
    }

    func testWhitespaceOnlyExpressionIsTreatedAsBlank() {
        let result = NCBTestExpression.parse("   \t  ")
        XCTAssertNil(result.node)
        XCTAssertNil(result.error)
    }

    // MARK: - Single terms

    func testSingleBitTermParses() {
        let result = NCBTestExpression.parse("B512")
        XCTAssertEqual(result.node, .bit(512))
        XCTAssertNil(result.error)
    }

    func testRegisteredTermParses() {
        let result = NCBTestExpression.parse("P30")
        XCTAssertEqual(result.node, .registered(days: 30))
    }

    func testGenderTermParses() {
        let result = NCBTestExpression.parse("G")
        XCTAssertEqual(result.node, .male)
    }

    func testOutfitAndExploredTermsParse() {
        let result = NCBTestExpression.parse("O200 & E300")
        XCTAssertEqual(result.node, .and([.outfit(200), .explored(300)]))
    }

    // MARK: - Case insensitivity

    func testParsingIsCaseInsensitive() {
        let lower = NCBTestExpression.parse("b13 & (b15 | !b72) & g & o5 & e6 & p10")
        let upper = NCBTestExpression.parse("B13 & (B15 | !B72) & G & O5 & E6 & P10")
        let mixed = NCBTestExpression.parse("B13 & (b15 | !B72) & G & o5 & E6 & p10")

        XCTAssertNotNil(lower.node)
        XCTAssertEqual(lower.node, upper.node)
        XCTAssertEqual(lower.node, mixed.node)
    }

    // MARK: - Negation

    func testNegationWrapsTerm() {
        let result = NCBTestExpression.parse("!B5")
        XCTAssertEqual(result.node, .not(.bit(5)))
    }

    func testDoubleNegationNests() {
        let result = NCBTestExpression.parse("!!B1")
        XCTAssertEqual(result.node, .not(.not(.bit(1))))
    }

    // MARK: - Parentheses / precedence / ambiguity

    // The Bible's own suggested fix - parenthesizing a mixed sub-expression
    // - should NOT be flagged ambiguous, since each run then uses only one
    // operator type.
    func testParenthesizedMixedExpressionIsNotAmbiguous() {
        let result = NCBTestExpression.parse("b1 & (b2 | b3)")
        XCTAssertEqual(result.node, .and([.bit(1), .or([.bit(2), .bit(3)])]))
        XCTAssertFalse(result.isAmbiguous)
    }

    // Mixing `&` and `|` in the same unparenthesized run is exactly what
    // the Bible warns is unreliable in the real game - must be flagged.
    func testMixedOperatorsWithoutParensIsAmbiguous() {
        let result = NCBTestExpression.parse("b1 & b2 | b3")
        XCTAssertTrue(result.isAmbiguous)
        // Left-to-right, equal precedence: (b1 & b2) | b3.
        XCTAssertEqual(result.node, .or([.and([.bit(1), .bit(2)]), .bit(3)]))
    }

    func testMixedOperatorsOtherOrderIsAlsoAmbiguous() {
        let result = NCBTestExpression.parse("b1 | b2 & b3")
        XCTAssertTrue(result.isAmbiguous)
        // Left-to-right, equal precedence: (b1 | b2) & b3 - notably NOT the
        // C-family precedence reading of b1 | (b2 & b3).
        XCTAssertEqual(result.node, .and([.or([.bit(1), .bit(2)]), .bit(3)]))
    }

    func testUniformAndChainIsNotAmbiguous() {
        let result = NCBTestExpression.parse("b1 & b2 & b3")
        XCTAssertFalse(result.isAmbiguous)
        XCTAssertEqual(result.node, .and([.bit(1), .bit(2), .bit(3)]))
    }

    func testUniformOrChainIsNotAmbiguous() {
        let result = NCBTestExpression.parse("b1 | b2 | b3")
        XCTAssertFalse(result.isAmbiguous)
        XCTAssertEqual(result.node, .or([.bit(1), .bit(2), .bit(3)]))
    }

    // Real examples straight from the Nova Bible's own documentation of
    // this grammar (lines ~128-130 of the converted text).
    func testBibleExampleOneParsesAndIsNotAmbiguous() {
        let result = NCBTestExpression.parse("b13 & (b15 | !b72)")
        XCTAssertEqual(result.node, .and([.bit(13), .or([.bit(15), .not(.bit(72))])]))
        XCTAssertFalse(result.isAmbiguous)
    }

    func testBibleExampleTwoParsesAndIsNotAmbiguous() {
        let result = NCBTestExpression.parse("!(B42 | B53) & b103")
        XCTAssertEqual(result.node, .and([.not(.or([.bit(42), .bit(53)])), .bit(103)]))
        XCTAssertFalse(result.isAmbiguous)
    }

    // MARK: - Errors (must never crash)

    func testLetterWithoutDigitsReturnsParseError() {
        for text in ["B", "O", "E", "P"] {
            let result = NCBTestExpression.parse(text)
            XCTAssertNil(result.node, "\"\(text)\" should not produce a node")
            XCTAssertNotNil(result.error, "\"\(text)\" should produce a parse error")
        }
    }

    func testUnbalancedOpeningParenReturnsParseError() {
        let result = NCBTestExpression.parse("(b1 & b2")
        XCTAssertNil(result.node)
        XCTAssertNotNil(result.error)
    }

    func testUnbalancedClosingParenReturnsParseError() {
        let result = NCBTestExpression.parse("b1 & b2)")
        XCTAssertNil(result.node)
        XCTAssertNotNil(result.error)
    }

    func testTrailingOperatorReturnsParseError() {
        let result = NCBTestExpression.parse("b1 &")
        XCTAssertNil(result.node)
        XCTAssertNotNil(result.error)
    }

    func testDoubleOperatorReturnsParseError() {
        let result = NCBTestExpression.parse("b1 & & b2")
        XCTAssertNil(result.node)
        XCTAssertNotNil(result.error)
    }

    func testEmptyParenthesesReturnsParseError() {
        let result = NCBTestExpression.parse("()")
        XCTAssertNil(result.node)
        XCTAssertNotNil(result.error)
    }

    func testTotalGarbageReturnsParseErrorWithoutCrashing() {
        for garbage in ["###", "b1 $ b2", "@@@@", "b1 b2", "\u{0}\u{1}\u{2}"] {
            let result = NCBTestExpression.parse(garbage)
            XCTAssertNil(result.node, "\"\(garbage)\" should not produce a node")
            XCTAssertNotNil(result.error, "\"\(garbage)\" should produce a parse error")
        }
    }

    // MARK: - Evaluation

    private func makeState(
        bits: [Bool] = [],
        outfitCounts: [Int16] = [],
        exploration: [Int16] = [],
        isMale: Bool? = nil
    ) -> PilotStoryState {
        PilotStoryState(
            bits: bits,
            outfitCounts: outfitCounts,
            exploration: exploration,
            combatRating: 0,
            isMale: isMale,
            activeMissionIDs: []
        )
    }

    func testBitTermEvaluatesAgainstState() {
        var bits = [Bool](repeating: false, count: 10)
        bits[5] = true
        let state = makeState(bits: bits)

        let onExplanation = NCBNode.bit(5).explain(against: state)
        XCTAssertTrue(onExplanation.value)
        guard case .term(let evaluation) = onExplanation else { return XCTFail("expected a term") }
        XCTAssertFalse(evaluation.isAssumed)

        let offExplanation = NCBNode.bit(3).explain(against: state)
        XCTAssertFalse(offExplanation.value)
    }

    func testOutOfRangeBitIsTreatedAsFalseNotACrash() {
        let state = makeState(bits: [])
        let explanation = NCBNode.bit(9999).explain(against: state)
        XCTAssertFalse(explanation.value)
    }

    func testRegisteredTermIsAlwaysAssumedTrue() {
        let state = makeState()
        let explanation = NCBNode.registered(days: 30).explain(against: state)
        XCTAssertTrue(explanation.value)
        guard case .term(let evaluation) = explanation else { return XCTFail("expected a term") }
        XCTAssertTrue(evaluation.isAssumed)
    }

    func testGenderTermUsesKnownValueWithoutAssumption() {
        let state = makeState(isMale: false)
        let explanation = NCBNode.male.explain(against: state)
        XCTAssertFalse(explanation.value)
        guard case .term(let evaluation) = explanation else { return XCTFail("expected a term") }
        XCTAssertFalse(evaluation.isAssumed)
    }

    func testGenderTermIsAssumedWhenUnknown() {
        let state = makeState(isMale: nil)
        let explanation = NCBNode.male.explain(against: state)
        guard case .term(let evaluation) = explanation else { return XCTFail("expected a term") }
        XCTAssertTrue(evaluation.isAssumed)
    }

    func testOutfitTermUsesOutfitIDBaseOffset() {
        // Outfit ID 130 -> index 130 - 128 = 2.
        var counts = [Int16](repeating: 0, count: 10)
        counts[2] = 3
        let state = makeState(outfitCounts: counts)

        XCTAssertTrue(NCBNode.outfit(130).explain(against: state).value)
        XCTAssertFalse(NCBNode.outfit(131).explain(against: state).value)
    }

    func testExploredTermUsesSystemIDBaseOffset() {
        // System ID 200 -> index 200 - 128 = 72.
        var exploration = [Int16](repeating: 0, count: 100)
        exploration[72] = 1
        let state = makeState(exploration: exploration)

        XCTAssertTrue(NCBNode.explored(200).explain(against: state).value)
        XCTAssertFalse(NCBNode.explored(201).explain(against: state).value)
    }

    func testAndOrNotComposeCorrectly() {
        var bits = [Bool](repeating: false, count: 10)
        bits[1] = true
        bits[2] = false
        let state = makeState(bits: bits)

        // b1 & !b2  ->  true & !false  ->  true & true  ->  true
        let node = NCBNode.and([.bit(1), .not(.bit(2))])
        let explanation = node.explain(against: state)
        XCTAssertTrue(explanation.value)

        // b1 | b2 with b2 false is still true because b1 is true.
        let orNode = NCBNode.or([.bit(1), .bit(2)])
        XCTAssertTrue(orNode.explain(against: state).value)
    }
}
