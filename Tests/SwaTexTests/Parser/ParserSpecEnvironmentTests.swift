import Testing

@testable import SwaTex

// Ported from ratex-parser/src/tests.rs: environment, verb, and recursion-limit
// test modules.

// ── Environment tests ────────────────────────────────────────────────────────

@Suite("ParserSpec: environments")
struct ParserSpecEnvironmentsTests {
    @Test func simpleMatrix() throws {
        let ast = try parseLaTeX(#"\begin{matrix} a & b \\ c & d \end{matrix}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "array")
        if case let .array(info) = ast[0].kind {
            #expect(info.body.count == 2)
            #expect(info.body[0].count == 2)
            #expect(info.body[1].count == 2)
        } else {
            Issue.record("Expected Array node")
        }
    }

    @Test func pmatrixWrapsInLeftright() throws {
        let ast = try parseLaTeX(#"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "leftright")
        if case let .leftRight(body, left, right, _) = ast[0].kind {
            #expect(left == "(")
            #expect(right == ")")
            #expect(body.count == 1)
            #expect(body[0].typeName == "array")
        } else {
            Issue.record("Expected LeftRight node")
        }
    }

    @Test func bmatrixWrapsInLeftright() throws {
        let ast = try parseLaTeX(#"\begin{bmatrix} 1 & 2 \\ 3 & 4 \end{bmatrix}"#)
        #expect(ast.count == 1)
        if case let .leftRight(_, left, right, _) = ast[0].kind {
            #expect(left == "[")
            #expect(right == "]")
        } else {
            Issue.record("Expected LeftRight node")
        }
    }

    @Test func vmatrixWrapsInLeftright() throws {
        let ast = try parseLaTeX(#"\begin{vmatrix} a & b \\ c & d \end{vmatrix}"#)
        if case let .leftRight(_, left, right, _) = ast[0].kind {
            #expect(left == "|")
            #expect(right == "|")
        } else {
            Issue.record("Expected LeftRight node")
        }
    }

    @Test func bigBmatrixWrapsInLeftright() throws {
        let ast = try parseLaTeX(#"\begin{Bmatrix} a \\ b \end{Bmatrix}"#)
        if case let .leftRight(_, left, right, _) = ast[0].kind {
            #expect(left == #"\{"#)
            #expect(right == #"\}"#)
        } else {
            Issue.record("Expected LeftRight node")
        }
    }

    @Test func casesEnvironment() throws {
        let ast = try parseLaTeX(
            #"\begin{cases} x & \text{if } x > 0 \\ -x & \text{otherwise} \end{cases}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "leftright")
        if case let .leftRight(body, left, right, _) = ast[0].kind {
            #expect(left == #"\{"#)
            #expect(right == ".")
            #expect(body.count == 1)
            if case let .array(info) = body[0].kind {
                let rows = info.body
                #expect(rows.count == 2)
                #expect(rows[0].count == 2)
                #expect(rows[1].count == 2)
            } else {
                Issue.record("Expected Array inside LeftRight")
            }
        } else {
            Issue.record("Expected LeftRight node for cases")
        }
    }

    @Test func alignEnvironment() throws {
        let ast = try parseLaTeX(#"\begin{aligned} x &= 1 \\ y &= 2 \end{aligned}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "array")
        if case let .array(info) = ast[0].kind {
            #expect(info.body.count == 2)
            #expect(info.addJot ?? false)
            #expect(info.colSeparationType == "align")
        } else {
            Issue.record("Expected Array node for aligned")
        }
    }

    @Test func tagPrimitiveParsesArgument() throws {
        let ast = try parseLaTeX(#"\tag{1}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "tag")
    }

    @Test func alignWithTagStripsTagAndSetsArrayTags() throws {
        let ast = try parseLaTeX(#"\begin{aligned} x &= 1 \tag{1} \\ y &= 2 \end{aligned}"#)
        if case let .array(info) = ast[0].kind {
            #expect(info.body.count == 2)
            let row0 = info.body[0]
            let row0Last = row0[row0.count - 1]
            let inner: ParseNode
            if case let .styling(_, sb) = row0Last.kind {
                inner = sb[0]
            } else {
                inner = row0Last
            }
            guard case let .ordGroup(ob, _) = inner.kind else {
                Issue.record("expected ordgroup")
                return
            }
            #expect(!ob.contains { $0.typeName == "tag" })
            let tags = try #require(info.tags, "tags")
            #expect(tags.count == 2)
            if case let .explicit(v) = tags[0] {
                #expect(!v.isEmpty)
            } else {
                Issue.record("Expected explicit tag for row 0")
            }
            if case .auto(false) = tags[1] {
            } else {
                Issue.record("Expected Auto(false) tag for row 1")
            }
        } else {
            Issue.record("Expected Array node")
        }
    }

    @Test func matrixSingleRow() throws {
        let ast = try parseLaTeX(#"\begin{matrix} a & b & c \end{matrix}"#)
        if case let .array(info) = ast[0].kind {
            #expect(info.body.count == 1)
            #expect(info.body[0].count == 3)
        } else {
            Issue.record("Expected Array node")
        }
    }

    @Test func matrix3x3() throws {
        let ast = try parseLaTeX(
            #"\begin{matrix} 1 & 2 & 3 \\ 4 & 5 & 6 \\ 7 & 8 & 9 \end{matrix}"#)
        if case let .array(info) = ast[0].kind {
            #expect(info.body.count == 3)
            for row in info.body {
                #expect(row.count == 3)
            }
            let cols = try #require(info.cols)
            #expect(cols.count == 3)
        } else {
            Issue.record("Expected Array node")
        }
    }

    @Test func envNameMismatchError() {
        do {
            _ = try parseLaTeX(#"\begin{matrix} a \end{pmatrix}"#)
            Issue.record("Expected parse error")
        } catch {
            #expect(error.message.contains("Mismatch"))
        }
    }

    @Test func unknownEnvironmentError() {
        do {
            _ = try parseLaTeX(#"\begin{foobar} a \end{foobar}"#)
            Issue.record("Expected parse error")
        } catch {
            #expect(error.message.contains("No such environment"))
        }
    }

    @Test func gatheredEnvironment() throws {
        let ast = try parseLaTeX(#"\begin{gathered} a \\ b \\ c \end{gathered}"#)
        #expect(ast[0].typeName == "array")
        if case let .array(info) = ast[0].kind {
            #expect(info.body.count == 3)
            for row in info.body {
                #expect(row.count == 1)
            }
        } else {
            Issue.record("Expected Array node")
        }
    }

    @Test func smallmatrixEnvironment() throws {
        let ast = try parseLaTeX(#"\begin{smallmatrix} a & b \\ c & d \end{smallmatrix}"#)
        #expect(ast[0].typeName == "array")
        if case let .array(info) = ast[0].kind {
            #expect(info.arraystretch == 0.5)
            #expect(info.colSeparationType == "small")
            #expect(info.body.count == 2)
        } else {
            Issue.record("Expected Array node")
        }
    }

    // Adapted from serde JSON assertions to structural assertions.
    @Test func matrixJsonStructure() throws {
        let ast = try parseLaTeX(#"\begin{matrix} a & b \\ c & d \end{matrix}"#)
        #expect(ast[0].typeName == "array")
        if case let .array(info) = ast[0].kind {
            #expect(info.body.count == 2)
            #expect(info.body[0].count == 2)
        } else {
            Issue.record("Expected Array node")
        }
    }

    // Adapted from serde JSON assertions to structural assertions.
    @Test func pmatrixJsonStructure() throws {
        let ast = try parseLaTeX(#"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#)
        #expect(ast[0].typeName == "leftright")
        if case let .leftRight(body, left, right, _) = ast[0].kind {
            #expect(left == "(")
            #expect(right == ")")
            #expect(body[0].typeName == "array")
        } else {
            Issue.record("Expected LeftRight node")
        }
    }

    // Adapted from serde JSON assertions to structural assertions.
    @Test func casesJsonStructure() throws {
        let ast = try parseLaTeX(#"\begin{cases} a \\ b \end{cases}"#)
        #expect(ast[0].typeName == "leftright")
        if case let .leftRight(_, left, right, _) = ast[0].kind {
            #expect(left == #"\{"#)
            #expect(right == ".")
        } else {
            Issue.record("Expected LeftRight node")
        }
    }

    @Test func nestedFracInMatrix() throws {
        let ast = try parseLaTeX(
            #"\begin{pmatrix} \frac{1}{2} & 0 \\ 0 & \frac{3}{4} \end{pmatrix}"#)
        #expect(ast[0].typeName == "leftright")
    }

    @Test func matrixWithExpressions() throws {
        let ast = try parseLaTeX(#"\begin{bmatrix} a+b & c^2 \\ \sqrt{d} & e_i \end{bmatrix}"#)
        #expect(ast[0].typeName == "leftright")
    }

    @Test func rcasesEnvironment() throws {
        let ast = try parseLaTeX(#"\begin{rcases} a \\ b \end{rcases}"#)
        if case let .leftRight(_, left, right, _) = ast[0].kind {
            #expect(left == ".")
            #expect(right == #"\}"#)
        } else {
            Issue.record("Expected LeftRight node for rcases")
        }
    }

    @Test func prooftreeUnaryWithLabelAndAbbreviations() throws {
        let ast = try parseLaTeX(#"\begin{prooftree}\AXC{P}\RL{r}\UIC{Q}\end{prooftree}"#)
        #expect(ast.count == 1)
        #expect(ast[0].typeName == "proofTree")
        if case let .proofTree(tree) = ast[0].kind {
            #expect(tree.premises.count == 1)
            #expect(tree.leftLabel == nil)
            #expect(tree.rightLabel != nil)
            #expect(tree.conclusion.count == 1)
        } else {
            Issue.record("Expected ProofTree node")
        }
    }

    @Test func prooftreeBinaryDashedLine() throws {
        let ast = try parseLaTeX(
            #"\begin{prooftree}\AxiomC{P}\AxiomC{Q}\dashedLine\BinaryInfC{R}\end{prooftree}"#)
        if case let .proofTree(tree) = ast[0].kind {
            #expect(tree.premises.count == 2)
            #expect(tree.lineStyle == .dashed)
        } else {
            Issue.record("Expected ProofTree node")
        }
    }

    @Test func prooftreeErrorsOnShortStack() {
        #expect(throws: ParseError.self) {
            try parseLaTeX(#"\begin{prooftree}\AxiomC{P}\BinaryInfC{Q}\end{prooftree}"#)
        }
    }

    @Test func prooftreeFcenterRendersVisibleSymbol() throws {
        let ast = try parseLaTeX(
            #"\begin{prooftree}\AxiomC{A \fCenter B}\UIC{C}\end{prooftree}"#)
        if case let .proofTree(tree) = ast[0].kind {
            // The axiom's conclusion contains A \fCenter B, stored in premises[0].conclusion
            let axiom = tree.premises[0]
            let hasArrowRel = axiom.conclusion.contains { n in
                if case let .atom(family, text) = n.kind {
                    return family == .rel && text == #"\Rightarrow"#
                }
                return false
            }
            #expect(
                hasArrowRel,
                #"\fCenter should produce a relation arrow (\Rightarrow) in the axiom"#)
        } else {
            Issue.record("Expected ProofTree node")
        }
    }

    @Test func prooftreeRootAtTopFlag() throws {
        let ast = try parseLaTeX(#"\begin{prooftree}\AxiomC{P}\rootAtTop\UIC{Q}\end{prooftree}"#)
        if case let .proofTree(tree) = ast[0].kind {
            #expect(tree.rootAtTop, #"\rootAtTop should set rootAtTop flag"#)
        } else {
            Issue.record("Expected ProofTree node")
        }
    }

    @Test func prooftreeRootAtBottomIsDefault() throws {
        let ast = try parseLaTeX(#"\begin{prooftree}\AxiomC{P}\UIC{Q}\end{prooftree}"#)
        if case let .proofTree(tree) = ast[0].kind {
            #expect(!tree.rootAtTop, "rootAtTop should default to false")
        } else {
            Issue.record("Expected ProofTree node")
        }
    }

    @Test func prooftreeOrphanLabelErrors() {
        #expect(throws: ParseError.self, #"orphan \LeftLabel should produce an error"#) {
            try parseLaTeX(#"\begin{prooftree}\AxiomC{P}\LeftLabel{L}\end{prooftree}"#)
        }
    }

    @Test func vmatrixDoubleWraps() throws {
        let ast = try parseLaTeX(#"\begin{Vmatrix} a & b \\ c & d \end{Vmatrix}"#)
        if case let .leftRight(_, left, right, _) = ast[0].kind {
            #expect(left == #"\Vert"#)
            #expect(right == #"\Vert"#)
        } else {
            Issue.record("Expected LeftRight node")
        }
    }
}

// ── Verb ─────────────────────────────────────────────────────────────────────

@Suite("ParserSpec: verb")
struct ParserSpecVerbTests {
    @Test func asciiDelimiter() throws {
        let ast = try parseLaTeX(#"\verb|hello|"#)
        #expect(ast.count == 1)
        if case let .verb(body, star) = ast[0].kind {
            #expect(body == "hello")
            #expect(!star)
        } else {
            Issue.record("Expected Verb node")
        }
    }

    @Test func starredAsciiDelimiter() throws {
        let ast = try parseLaTeX(#"\verb*|hello world|"#)
        if case let .verb(body, star) = ast[0].kind {
            #expect(body == "hello world")
            #expect(star)
        } else {
            Issue.record("Expected Verb node")
        }
    }

    @Test func multibyteDelimiterDoesNotPanic() throws {
        let ast = try parseLaTeX(#"\verbéxé"#)
        if case let .verb(body, star) = ast[0].kind {
            #expect(body == "x")
            #expect(!star)
        } else {
            Issue.record("Expected Verb node")
        }
    }

    @Test func starredMultibyteDelimiterDoesNotPanic() throws {
        let ast = try parseLaTeX(#"\verb*éxé"#)
        if case let .verb(body, star) = ast[0].kind {
            #expect(body == "x")
            #expect(star)
        } else {
            Issue.record("Expected Verb node")
        }
    }

    @Test func tooShortReturnsError() {
        #expect(throws: ParseError.self) {
            try parseLaTeX(#"\verbé"#)
        }
    }
}

// ── Recursion limit ──────────────────────────────────────────────────────────

@Suite("ParserSpec: recursion limit")
struct ParserSpecRecursionLimitTests {
    private func nestedBraces(_ n: Int) -> String {
        String(repeating: "{", count: n) + "x" + String(repeating: "}", count: n)
    }

    private func assertRecursionLimitErr(_ input: String) {
        do {
            _ = try parseLaTeX(input)
            Issue.record("Expected recursion limit error")
        } catch {
            #expect(
                error.message.contains("Recursion limit exceeded"),
                "unexpected error: \(error)")
        }
    }

    @Test func recursionLimitErrorMessage() {
        let err = ParseError.recursionLimitExceeded
        #expect(err.message.contains("Recursion limit exceeded"))
    }

    // The Rust suite gates the following tests behind cfg(not(debug_assertions)):
    // "Needs release-sized stacks; debug overflows before MAX (512) is reached."
    // `swift test` builds are debug and Swift Testing runs on limited-size
    // stacks, so they are disabled here to mirror that gating.

    @Test(
        .disabled("Needs release-sized stacks; Rust gates this behind cfg(not(debug_assertions))"))
    func nestedBracesAtLimitSucceeds() throws {
        _ = try parseLaTeX(nestedBraces(511))
    }

    @Test(
        .disabled("Needs release-sized stacks; Rust gates this behind cfg(not(debug_assertions))"))
    func nestedBracesOverLimitFails() {
        assertRecursionLimitErr(nestedBraces(512))
    }

    @Test(
        .disabled("Needs release-sized stacks; Rust gates this behind cfg(not(debug_assertions))"))
    func pocDeepNestingDoesNotAbort() {
        assertRecursionLimitErr(nestedBraces(200_000))
    }
}
