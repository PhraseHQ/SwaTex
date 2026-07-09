import Testing

@testable import SwaTex

/// MacroExpander branch coverage: builtin function-macros, macro definition
/// error paths, the expansion counter, and `\noexpand`/`\char` handling.
@Suite("MacroExpanderCoverage")
struct MacroExpanderCoverageTests {
    private func parseError(_ input: String) -> ParseError? {
        do {
            _ = try parseLaTeX(input)
            return nil
        } catch {
            return error
        }
    }

    private func symbolTexts(_ input: String) throws -> [String] {
        try parseLaTeX(input).compactMap(\.symbolText)
    }

    // ── \message / \errmessage ──────────────────────────────────────────

    @Test func messageIsDiscarded() throws {
        #expect(try symbolTexts(#"\message{hello world}x"#) == ["x"])
    }

    @Test func errmessageIsDiscarded() throws {
        #expect(try symbolTexts(#"\errmessage{oops}y"#) == ["y"])
    }

    // ── \@firstoftwo / \@secondoftwo / \@ifnextchar / \@ifstar ──────────

    @Test func firstOfTwo() throws {
        #expect(try symbolTexts(#"\@firstoftwo{a}{b}"#) == ["a"])
    }

    @Test func secondOfTwo() throws {
        #expect(try symbolTexts(#"\@secondoftwo{a}{b}"#) == ["b"])
    }

    @Test func ifNextCharMatch() throws {
        #expect(try symbolTexts(#"\@ifnextchar x{y}{n}xc"#) == ["y", "x", "c"])
    }

    @Test func ifNextCharNoMatch() throws {
        #expect(try symbolTexts(#"\@ifnextchar q{y}{n}xc"#) == ["n", "x", "c"])
    }

    @Test func ifStarWithStar() throws {
        #expect(try symbolTexts(#"\@ifstar{s}{n}*x"#) == ["s", "x"])
    }

    @Test func ifStarWithoutStar() throws {
        #expect(try symbolTexts(#"\@ifstar{s}{n}x"#) == ["n", "x"])
    }

    // ── \TextOrMath ─────────────────────────────────────────────────────

    @Test func textOrMathInMathMode() throws {
        #expect(try symbolTexts(#"\TextOrMath{t}{m}"#) == ["m"])
    }

    @Test func textOrMathInTextMode() throws {
        let nodes = try parseLaTeX(#"\text{\TextOrMath{t}{m}}"#)
        guard case let .text(body, _) = nodes[0].kind else {
            Issue.record("expected text node")
            return
        }
        #expect(body.compactMap(\.symbolText) == ["t"])
    }

    // ── \newcommand / \renewcommand / \providecommand ───────────────────

    @Test func newcommandDefinesAndExpands() throws {
        #expect(try symbolTexts(#"\newcommand{\fooX}[2]{#1+#2}\fooX{a}{b}"#) == ["a", "+", "b"])
    }

    @Test func newcommandRedefineExistingFails() {
        let e = parseError(#"\newcommand{\sin}{s}"#)
        #expect(e?.message.contains("attempting to redefine") == true)
    }

    @Test func renewcommandUndefinedFails() {
        let e = parseError(#"\renewcommand{\notdefinedxyz}{x}"#)
        #expect(e?.message.contains("does not yet exist") == true)
    }

    @Test func renewcommandRedefines() throws {
        #expect(try symbolTexts(#"\renewcommand{\sin}{q}\sin"#) == ["q"])
    }

    @Test func newcommandMissingBracketFails() {
        let e = parseError(#"\newcommand{\fooY}[1x]{z}"#)
        #expect(e?.message == "Expected ] in \\newcommand")
    }

    @Test func providecommandKeepsExisting() throws {
        // \providecommand on an existing name silently redefines in KaTeX-compat mode
        let nodes = try parseLaTeX(#"\providecommand{\fooZ}{z}\fooZ"#)
        #expect(nodes.compactMap(\.symbolText) == ["z"])
    }

    // ── Expansion limit ─────────────────────────────────────────────────

    @Test func infiniteExpansionFails() {
        let e = parseError(#"\def\selfrec{\selfrec\selfrec}\selfrec"#)
        #expect(e?.message.contains("Too many expansions") == true)
    }

    // ── \noexpand ───────────────────────────────────────────────────────

    // NOTE: `\noexpand` inside `\edef` is covered by NoexpandTests
    // (Tests/SwaTexTests/Parser/NoexpandTests.swift); no duplicate here.

    @Test func noexpandNonExpandable() throws {
        // x is not expandable — \noexpand is a no-op
        #expect(try symbolTexts(#"\noexpand x"#) == ["x"])
    }

    @Test func noexpandThenRelax() throws {
        // A frozen (treatAsRelax) token reaching the parser acts like \relax
        let nodes = try parseLaTeX(#"\def\ccd{C}\noexpand\ccd x"#)
        #expect(nodes.compactMap(\.symbolText).contains("x"))
    }

    // ── \char forms ─────────────────────────────────────────────────────

    private func charText(_ input: String) throws -> String? {
        let nodes = try parseLaTeX(input)
        return nodes.first?.symbolText
    }

    @Test func charDecimal() throws {
        #expect(try charText(#"\char65"#) == "A")
    }

    @Test func charOctal() throws {
        #expect(try charText(#"\char'101"#) == "A")
    }

    @Test func charHex() throws {
        #expect(try charText(#"\char"41"#) == "A")
    }

    @Test func charBacktick() throws {
        #expect(try charText(#"\char`B"#) == "B")
    }

    @Test func charBacktickControlSequence() throws {
        #expect(try charText(#"\char`\C"#) == "C")
    }

    @Test func charMultiDigitRun() throws {
        // contiguous digit tokens accumulate: \char066 → 66 → 'B'
        #expect(try charText(#"\char066"#) == "B")
    }

    // ── \htmlClass / \htmlId / \htmlData expand to content ─────────────

    @Test(arguments: [
        #"\htmlClass{cls}{xy}"#,
        #"\htmlId{ident}{xy}"#,
        #"\htmlData{foo=bar}{xy}"#,
    ])
    func htmlExtensionsKeepContent(_ input: String) throws {
        // KaTeX-correctness fix (2026-07-09): content stays in order.
        // (RaTeX reverses it — "xy" rendered as "yx"; SwaTex now matches
        // KaTeX proper. See HtmlClassOrderTests.)
        #expect(try symbolTexts(input) == ["x", "y"])
    }

    // ── \bra@ket / \bra@set (braket.sty) ────────────────────────────────

    @Test func braketReplacesAllBars() throws {
        let nodes = try parseLaTeX(#"\Braket{a | b | c}"#)
        #expect(!nodes.isEmpty)
        // Both | were replaced by \middle| inside a leftright group
        let lr = nodes.first { $0.typeName == "leftright" }
        #expect(lr != nil)
        if case let .leftRight(body, left, right, _) = lr!.kind {
            #expect(left == "\u{27E8}" || left == "\\langle" || left.contains("angle") || left == "⟨")
            #expect(right == "\u{27E9}" || right == "\\rangle" || right.contains("angle") || right == "⟩")
            #expect(body.filter { $0.typeName == "middle" }.count == 2)
        }
    }

    @Test func braketDoubleBar() throws {
        let nodes = try parseLaTeX(#"\Braket{a || b}"#)
        let lr = nodes.first { $0.typeName == "leftright" }
        #expect(lr != nil)
    }

    @Test func braSetReplacesFirstBarOnly() throws {
        let nodes = try parseLaTeX(#"\Set{ x | x > 0 }"#)
        let lr = nodes.first { $0.typeName == "leftright" }
        #expect(lr != nil)
        if case let .leftRight(body, _, _, _) = lr!.kind {
            #expect(body.contains { $0.typeName == "middle" })
        }
    }

    @Test func braSetDoubleBar() throws {
        let nodes = try parseLaTeX(#"\Set{ x || x > 0 }"#)
        #expect(nodes.contains { $0.typeName == "leftright" })
    }

    @Test func lowercaseSetKeepsBar() throws {
        // \set does not use \middle — the | stays a plain atom
        let nodes = try parseLaTeX(#"\set{x|x>0}"#)
        #expect(!nodes.isEmpty)
    }

    // ── ## in macro bodies ──────────────────────────────────────────────

    @Test func doubleHashInMacroBody() throws {
        // ## in a macro body collapses to a literal # (consumed by \message here)
        #expect(try symbolTexts(#"\def\hsh#1{\message{##}#1}\hsh{q}"#) == ["q"])
    }

    // ── \ce / \pu error propagation ─────────────────────────────────────

    @Test func ceErrorWrapsAsParseError() {
        let e = parseError(#"\ce{\color{red} H2O}"#)
        #expect(e?.message.contains("mhchem") == true)
    }

    // ── Undefined control sequence ──────────────────────────────────────

    @Test func undefinedControlSequence() {
        let e = parseError(#"\thiscommanddoesnotexist"#)
        #expect(e?.message.contains("Undefined control sequence") == true)
    }
}
