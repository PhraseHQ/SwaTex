import Testing

@testable import SwaTex

// Comprehensive test suite ported from ratex-parser/src/tests.rs, organized by
// feature area. Tests are designed to validate against KaTeX's parsing behavior.

// ── Basic characters, operators, grouping, scripts ──────────────────────────

@Suite("ParserSpec: core parsing")
struct ParserSpecCoreParsingTests {
    // ── Basic characters ─────────────────────────────────

    @Test func singleLetter() throws {
        let ast = try parseLaTeX("x")
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "mathord")
        #expect(ast[0].symbolText == "x")
    }

    @Test func multipleLetters() throws {
        let ast = try parseLaTeX("abc")
        #expect(ast.count == 3)
        #expect(ast.allSatisfy { $0.typeName == "mathord" })
    }

    @Test func digit() throws {
        let ast = try parseLaTeX("5")
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "textord")
        #expect(ast[0].symbolText == "5")
    }

    @Test func emptyInput() throws {
        let ast = try parseLaTeX("")
        #expect(ast.isEmpty)
    }

    // ── Operators and symbols ────────────────────────────

    @Test func binaryOperatorPlus() throws {
        let ast = try parseLaTeX("a+b")
        #expect(ast.count == 3)
        #expect(ast[1].typeName == "atom")
        if case let .atom(family, text) = ast[1].kind {
            #expect(family == .bin)
            #expect(text == "+")
        }
    }

    @Test func relationEquals() throws {
        let ast = try parseLaTeX("a=b")
        #expect(ast.count == 3)
        #expect(ast[1].typeName == "atom")
        if case let .atom(family, _) = ast[1].kind {
            #expect(family == .rel)
        }
    }

    @Test func dotscBeforeCommaOmitsThinspace() throws {
        let ast = try parseLaTeX(#"x,\dotsc,y"#)
        #expect(
            !ast.contains { node in
                if case .kern = node.kind { return true }
                return false
            })
        #expect(ast.count == 5)
        #expect(ast[2].symbolText == #"\ldots"#)
        #expect(ast[3].symbolText == ",")
    }

    @Test func dotscBeforeSelectedPunctuationKeepsThinspace() throws {
        let ast = try parseLaTeX(#"x,\dotsc;y"#)
        #expect(ast.count == 6)
        #expect(ast[2].symbolText == #"\ldots"#)
        if case .kern = ast[3].kind {
        } else {
            Issue.record("Expected kern node at index 3")
        }
        #expect(ast[4].symbolText == ";")
    }

    @Test func openParen() throws {
        let ast = try parseLaTeX("(")
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "atom")
        if case let .atom(family, _) = ast[0].kind {
            #expect(family == .open)
        }
    }

    @Test func closeParen() throws {
        let ast = try parseLaTeX(")")
        #expect(ast.count == 1)
        if case let .atom(family, _) = ast[0].kind {
            #expect(family == .close)
        }
    }

    // ── Grouping ─────────────────────────────────────────

    @Test func bracedGroup() throws {
        let ast = try parseLaTeX("{a+b}")
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "ordgroup")
        if case let .ordGroup(body, _) = ast[0].kind {
            #expect(body.count == 3)
        }
    }

    @Test func nestedGroups() throws {
        let ast = try parseLaTeX("{{x}}")
        #expect(ast.count == 1)
        if case let .ordGroup(body, _) = ast[0].kind {
            #expect(body.count == 1)
            #expect(body[0].typeName == "ordgroup")
        }
    }

    @Test func emptyGroup() throws {
        let ast = try parseLaTeX("{}")
        #expect(ast.count == 1)
        if case let .ordGroup(body, _) = ast[0].kind {
            #expect(body.isEmpty)
        }
    }

    // ── Super/subscripts ─────────────────────────────────

    @Test func superscript() throws {
        let ast = try parseLaTeX("x^2")
        #expect(ast.count == 1)
        if case let .supSub(base, sup, sub) = ast[0].kind {
            #expect(base != nil)
            #expect(sup != nil)
            #expect(sub == nil)
            #expect(sup?.symbolText == "2")
        }
    }

    @Test func subscriptTest() throws {
        let ast = try parseLaTeX("a_i")
        #expect(ast.count == 1)
        if case let .supSub(base, sup, sub) = ast[0].kind {
            #expect(base != nil)
            #expect(sup == nil)
            #expect(sub != nil)
        }
    }

    @Test func bothSupSub() throws {
        let ast = try parseLaTeX("x^2_i")
        #expect(ast.count == 1)
        if case let .supSub(_, sup, sub) = ast[0].kind {
            #expect(sup != nil)
            #expect(sub != nil)
        }
    }

    @Test func subThenSup() throws {
        let ast = try parseLaTeX("x_i^2")
        #expect(ast.count == 1)
        if case let .supSub(_, sup, sub) = ast[0].kind {
            #expect(sup != nil)
            #expect(sub != nil)
        }
    }

    @Test func groupedSuperscript() throws {
        let ast = try parseLaTeX("x^{2+3}")
        #expect(ast.count == 1)
        if case let .supSub(_, sup, _) = ast[0].kind {
            let s = try #require(sup)
            #expect(s.typeName == "ordgroup")
        }
    }

    @Test func doubleSuperscriptError() {
        #expect(throws: ParseError.self) {
            try parseLaTeX("x^2^3")
        }
    }

    @Test func doubleSubscriptError() {
        #expect(throws: ParseError.self) {
            try parseLaTeX("x_2_3")
        }
    }
}

// ── Fractions and radicals ───────────────────────────────────────────────────

@Suite("ParserSpec: fractions and radicals")
struct ParserSpecFractionsAndRadicalsTests {
    @Test func simpleFrac() throws {
        let ast = try parseLaTeX(#"\frac{a}{b}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "genfrac")
        if case let .genfrac(_, numer, denom, hasBarLine, _, _, _) = ast[0].kind {
            #expect(hasBarLine)
            // numer and denom are wrapped in OrdGroup
            if case let .ordGroup(body, _) = numer.kind {
                #expect(body.count == 1)
                #expect(body[0].symbolText == "a")
            }
            if case let .ordGroup(body, _) = denom.kind {
                #expect(body.count == 1)
                #expect(body[0].symbolText == "b")
            }
        }
    }

    @Test func fracWithExpressions() throws {
        let ast = try parseLaTeX(#"\frac{a^2 + b}{c}"#)
        #expect(ast.count == 1)
        if case let .genfrac(_, numer, _, _, _, _, _) = ast[0].kind {
            if case let .ordGroup(body, _) = numer.kind {
                #expect(body.count >= 3)  // a^2, +, b (with supsub)
            }
        }
    }

    @Test func dfrac() throws {
        let ast = try parseLaTeX(#"\dfrac{a}{b}"#)
        // dfrac wraps in styling node
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "styling")
    }

    @Test func tfrac() throws {
        let ast = try parseLaTeX(#"\tfrac{a}{b}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "styling")
    }

    @Test func binom() throws {
        let ast = try parseLaTeX(#"\binom{n}{k}"#)
        #expect(ast.count == 1)
        // binom has delimiters and no bar line
        func check(_ node: ParseNode) {
            if case let .genfrac(_, _, _, hasBarLine, leftDelim, rightDelim, _) = node.kind {
                #expect(!hasBarLine)
                #expect(leftDelim == "(")
                #expect(rightDelim == ")")
            }
        }
        // Might be wrapped in styling
        if ast[0].typeName == "genfrac" {
            check(ast[0])
        } else if case let .styling(_, body) = ast[0].kind {
            check(body[0])
        }
    }

    @Test func sqrtSimple() throws {
        let ast = try parseLaTeX(#"\sqrt{x}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "sqrt")
        if case let .sqrt(_, index) = ast[0].kind {
            #expect(index == nil)
        }
    }

    @Test func sqrtWithIndex() throws {
        let ast = try parseLaTeX(#"\sqrt[3]{x}"#)
        #expect(ast.count == 1)
        if case let .sqrt(body, index) = ast[0].kind {
            #expect(index != nil)
            // body is an OrdGroup wrapping x
            #expect(body.typeName == "ordgroup")
        }
    }

    @Test func nestedFracSqrt() throws {
        let ast = try parseLaTeX(#"\frac{\sqrt{a^2+b^2}}{c}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "genfrac")
        if case let .genfrac(_, numer, _, _, _, _, _) = ast[0].kind {
            if case let .ordGroup(body, _) = numer.kind {
                #expect(body[0].typeName == "sqrt")
            }
        }
    }
}

// ── Operators ────────────────────────────────────────────────────────────────

@Suite("ParserSpec: operators")
struct ParserSpecOperatorsTests {
    @Test func sumSymbol() throws {
        let ast = try parseLaTeX(#"\sum"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "op")
        if case let .op(limits, _, _, _, symbol, name, _) = ast[0].kind {
            #expect(symbol)
            #expect(limits)
            #expect(name == #"\sum"#)
        }
    }

    @Test func intSymbol() throws {
        let ast = try parseLaTeX(#"\int"#)
        #expect(ast.count == 1)
        if case let .op(limits, _, _, _, symbol, _, _) = ast[0].kind {
            #expect(symbol)
            #expect(!limits)  // integrals don't use limits by default
        }
    }

    /// KaTeX: "Limit controls must follow a math operator" — a limit control
    /// after a non-operator (or at the start) is an error, not a no-op.
    @Test(arguments: [#"x\limits^2"#, #"x\nolimits_1"#, #"\limits^2"#])
    func limitControlAfterNonOperatorThrows(_ latex: String) {
        #expect(throws: ParseError.self) {
            try parseLaTeX(latex)
        }
    }

    @Test func limitControlAfterOperatorParses() throws {
        let ast = try parseLaTeX(#"\int\limits_0^1"#)
        #expect(ast.count == 1)
    }

    @Test func limTextOp() throws {
        let ast = try parseLaTeX(#"\lim"#)
        #expect(ast.count == 1)
        if case let .op(limits, _, _, _, symbol, name, _) = ast[0].kind {
            #expect(!symbol)
            #expect(limits)
            #expect(name == #"\lim"#)
        }
    }

    @Test func sinTextOp() throws {
        let ast = try parseLaTeX(#"\sin"#)
        #expect(ast.count == 1)
        if case let .op(limits, _, _, _, symbol, _, _) = ast[0].kind {
            #expect(!symbol)
            #expect(!limits)
        }
    }

    @Test func sumWithLimits() throws {
        let ast = try parseLaTeX(#"\sum_{i=0}^{n}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "supsub")
        if case let .supSub(base, sup, sub) = ast[0].kind {
            #expect(base?.typeName == "op")
            #expect(sup != nil)
            #expect(sub != nil)
        }
    }

    @Test func sumWithExplicitLimitsForcesSupsubHandling() throws {
        let ast = try parseLaTeX(#"\sum\limits_{i=0}^{n}"#)
        #expect(ast.count == 1)
        if case let .supSub(base, _, _) = ast[0].kind {
            if case let .op(limits, alwaysHandleSupSub, _, _, _, _, _) = base?.kind {
                #expect(limits)
                #expect(alwaysHandleSupSub == true)
            } else {
                Issue.record("expected op base")
            }
        } else {
            Issue.record("expected supsub")
        }
    }

    @Test func sumWithExplicitNolimitsClearsLimitsOnly() throws {
        // KaTeX (Parser.ts): a limit control on an op base always sets
        // alwaysHandleSupSub = true; \nolimits only clears `limits`. With
        // limits == false the flag is inert (every layout read conjoins the
        // two), so scripts still render beside the operator.
        let ast = try parseLaTeX(#"\sum\nolimits_{i=0}^{n}"#)
        #expect(ast.count == 1)
        if case let .supSub(base, _, _) = ast[0].kind {
            if case let .op(limits, alwaysHandleSupSub, _, _, _, _, _) = base?.kind {
                #expect(!limits)
                #expect(alwaysHandleSupSub == true)
            } else {
                Issue.record("expected op base")
            }
        } else {
            Issue.record("expected supsub")
        }
    }

    @Test func plainOperatornameIgnoresLimitControls() throws {
        // KaTeX: `\operatorname` (alwaysHandleSupSub == false) silently
        // ignores \limits — no error, no limits, and the flag must NOT be
        // overwritten. Regression: \limits used to force both to true,
        // rendering the superscript above instead of beside.
        let ast = try parseLaTeX(#"\operatorname{f}\limits^2"#)
        #expect(ast.count == 1)
        if case let .supSub(base, _, _) = ast[0].kind {
            if case let .operatorName(_, alwaysHandleSupSub, limits, _) = base?.kind {
                #expect(alwaysHandleSupSub == false)
                #expect(limits == false)
            } else {
                Issue.record("expected operatorname base")
            }
        } else {
            Issue.record("expected supsub")
        }
    }

    @Test func operatornameStarNolimitsKeepsSupsubHandling() throws {
        // KaTeX: `\operatorname*` honors limit controls — \nolimits clears
        // `limits` but never clears alwaysHandleSupSub. Regression:
        // \nolimits used to clear both, changing the display-style layout.
        let ast = try parseLaTeX(#"\operatorname*{sup}\nolimits_x"#)
        #expect(ast.count == 1)
        if case let .supSub(base, _, _) = ast[0].kind {
            if case let .operatorName(_, alwaysHandleSupSub, limits, _) = base?.kind {
                #expect(alwaysHandleSupSub == true)
                #expect(limits == false)
            } else {
                Issue.record("expected operatorname base")
            }
        } else {
            Issue.record("expected supsub")
        }
    }
}

// ── Accents and fonts ────────────────────────────────────────────────────────

@Suite("ParserSpec: accents and fonts")
struct ParserSpecAccentsAndFontsTests {
    @Test func hatAccent() throws {
        let ast = try parseLaTeX(#"\hat{x}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "accent")
        if case let .accent(label, isStretchy, _, _) = ast[0].kind {
            #expect(label == #"\hat"#)
            #expect(isStretchy == false)
        }
    }

    @Test func widehatAccent() throws {
        let ast = try parseLaTeX(#"\widehat{ABC}"#)
        #expect(ast.count == 1)
        if case let .accent(label, isStretchy, _, _) = ast[0].kind {
            #expect(label == #"\widehat"#)
            #expect(isStretchy == true)
        }
    }

    @Test func mathbf() throws {
        let ast = try parseLaTeX(#"\mathbf{A}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "font")
        if case let .font(font, _) = ast[0].kind {
            #expect(font == "mathbf")
        }
    }

    @Test func mathit() throws {
        let ast = try parseLaTeX(#"\mathit{x}"#)
        #expect(ast.count == 1)
        if case let .font(font, _) = ast[0].kind {
            #expect(font == "mathit")
        }
    }

    @Test func textFunction() throws {
        let ast = try parseLaTeX(#"\text{hello}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "text")
        if case let .text(body, _) = ast[0].kind {
            #expect(!body.isEmpty)
        }
    }
}

// ── Delimiters ───────────────────────────────────────────────────────────────

@Suite("ParserSpec: delimiters")
struct ParserSpecDelimitersTests {
    @Test func leftRightParens() throws {
        let ast = try parseLaTeX(#"\left( x \right)"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "leftright")
        if case let .leftRight(body, left, right, _) = ast[0].kind {
            #expect(left == "(")
            #expect(right == ")")
            #expect(!body.isEmpty)
        }
    }

    @Test func leftRightWithFrac() throws {
        let ast = try parseLaTeX(#"\left( \frac{a}{b} \right)"#)
        #expect(ast.count == 1)
        if case let .leftRight(body, _, _, _) = ast[0].kind {
            #expect(body[0].typeName == "genfrac")
        }
    }

    @Test func rightWithoutLeftError() {
        #expect(throws: ParseError.self) {
            try parseLaTeX(#"\right)"#)
        }
    }
}

// ── Colors and sizing ────────────────────────────────────────────────────────

@Suite("ParserSpec: colors and sizing")
struct ParserSpecColorsAndSizingTests {
    @Test func textcolor() throws {
        let ast = try parseLaTeX(#"\textcolor{red}{x}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "color")
        if case let .color(color, body) = ast[0].kind {
            #expect(color == "red")
            #expect(!body.isEmpty)
        }
    }

    @Test func overline() throws {
        let ast = try parseLaTeX(#"\overline{x}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "overline")
    }

    @Test func underline() throws {
        let ast = try parseLaTeX(#"\underline{x}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "underline")
    }

    @Test func htmlstyle() throws {
        let ast = try parseLaTeX(#"\htmlStyle{color: blue; font-size: 20px;}{x^2}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "html")
        if case let .html(attributes, body) = ast[0].kind {
            #expect(attributes["style"] == "color: blue; font-size: 20px;")
            #expect(!body.isEmpty)
        } else {
            Issue.record("Expected html node")
        }
    }
}

// ── Complex expressions ──────────────────────────────────────────────────────

@Suite("ParserSpec: complex expressions")
struct ParserSpecComplexExpressionsTests {
    @Test func quadraticFormula() throws {
        let ast = try parseLaTeX(#"\frac{-b \pm \sqrt{b^2-4ac}}{2a}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "genfrac")
    }

    @Test func eulerIdentity() throws {
        let ast = try parseLaTeX(#"e^{i\pi} + 1 = 0"#)
        #expect(ast.count >= 4)  // supsub, +, 1, =, 0
    }

    @Test func sinSquared() throws {
        let ast = try parseLaTeX(#"\sin^2(x) + \cos^2(x) = 1"#)
        #expect(ast.count >= 5)
    }

    @Test func nestedFractions() throws {
        let ast = try parseLaTeX(#"\frac{1}{1+\frac{1}{x}}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "genfrac")
    }

    @Test func multipleSuperscriptsInExpr() throws {
        let ast = try parseLaTeX(#"a^2 + b^2 = c^2"#)
        let supsubCount = ast.filter { $0.typeName == "supsub" }.count
        #expect(supsubCount == 3)
    }
}

// ── Error handling ───────────────────────────────────────────────────────────

@Suite("ParserSpec: error handling")
struct ParserSpecErrorHandlingTests {
    @Test func unclosedBrace() {
        #expect(throws: ParseError.self) {
            try parseLaTeX("{x")
        }
    }

    @Test func extraCloseBrace() {
        #expect(throws: ParseError.self) {
            try parseLaTeX("x}")
        }
    }

    @Test func missingFracArg() {
        #expect(throws: ParseError.self) {
            try parseLaTeX(#"\frac{a}"#)
        }
    }

    @Test func doubleSuperscript() {
        #expect(throws: ParseError.self) {
            try parseLaTeX("x^1^2")
        }
    }

    @Test func doubleSubscript() {
        #expect(throws: ParseError.self) {
            try parseLaTeX("x_1_2")
        }
    }

    @Test func undefinedCommand() {
        #expect(throws: ParseError.self) {
            try parseLaTeX(#"\nonexistentcommand"#)
        }
    }
}

// ── JSON serialization (adapted) ─────────────────────────────────────────────
//
// The Rust suite asserted on serde JSON output. The Swift ParseNode has no
// Codable conformance, so these tests assert the same facts structurally
// (typeName, mode, pattern matching on .kind).

@Suite("ParserSpec: node structure (was JSON serialization)")
struct ParserSpecJsonSerializationTests {
    @Test func basicJsonOutput() throws {
        let ast = try parseLaTeX("x")
        #expect(ast[0].typeName == "mathord")
        #expect(ast[0].mode == .math)
        #expect(ast[0].symbolText == "x")
    }

    @Test func supsubJsonStructure() throws {
        let ast = try parseLaTeX("x^2")
        #expect(ast[0].typeName == "supsub")
        if case let .supSub(base, sup, _) = ast[0].kind {
            #expect(base?.typeName == "mathord")
            #expect(sup?.typeName == "textord")
            #expect(sup?.symbolText == "2")
        } else {
            Issue.record("Expected supsub node")
        }
    }

    @Test func fracJsonStructure() throws {
        let ast = try parseLaTeX(#"\frac{a}{b}"#)
        #expect(ast[0].typeName == "genfrac")
        if case let .genfrac(_, numer, denom, hasBarLine, _, _, _) = ast[0].kind {
            #expect(hasBarLine == true)
            #expect(numer.typeName == "ordgroup")
            #expect(denom.typeName == "ordgroup")
        } else {
            Issue.record("Expected genfrac node")
        }
    }

    @Test func atomJsonStructure() throws {
        let ast = try parseLaTeX("+")
        #expect(ast[0].typeName == "atom")
        if case let .atom(family, text) = ast[0].kind {
            #expect(family == .bin)
            #expect(text == "+")
        } else {
            Issue.record("Expected atom node")
        }
    }
}
