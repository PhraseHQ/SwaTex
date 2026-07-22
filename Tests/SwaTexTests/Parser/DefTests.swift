import Testing

@testable import SwaTex

/// Focused tests for \def / \edef / \let / \futurelet / \global
/// (crates/ratex-parser/src/functions/def.rs behavior).
@Suite("DefCommands")
struct DefTests {
    @Test func defWithParameters() throws {
        let result = try parseLaTeX(#"\def\pair#1#2{(#1,#2)} \pair{a}{b}"#)
        let texts = result.compactMap(\.symbolText)
        #expect(texts == ["(", "a", ",", "b", ")"])
    }

    @Test func defParameterOrderError() {
        // Parameters must be numbered sequentially: #2 before #1 is an error.
        #expect(throws: ParseError.self) {
            try parseLaTeX(#"\def\bad#2#1{#1#2} \bad{a}{b}"#)
        }
    }

    @Test func gdefSurvivesGroup() throws {
        let result = try parseLaTeX(#"{\gdef\x{y}} \x"#)
        #expect(result.count >= 1)
        #expect(result.last?.symbolText == "y")
    }

    @Test func defIsGroupLocal() {
        // \def inside a group is undone at group end.
        #expect(throws: ParseError.self) {
            try parseLaTeX(#"{\def\x{y}} \x"#)
        }
    }

    @Test func globalDef() throws {
        let result = try parseLaTeX(#"{\global\def\x{y}} \x"#)
        #expect(result.last?.symbolText == "y")
    }

    @Test func edefExpandsAtDefinition() throws {
        // \edef expands \b at definition time; redefining \b later must not
        // change \a's expansion.
        let result = try parseLaTeX(#"\def\b{1} \edef\a{\b} \def\b{2} \a"#)
        #expect(result.last?.symbolText == "1")
    }

    @Test func defDoesNotExpandAtDefinition() throws {
        let result = try parseLaTeX(#"\def\b{1} \def\a{\b} \def\b{2} \a"#)
        #expect(result.last?.symbolText == "2")
    }

    @Test func letCopiesCurrentMeaning() throws {
        let result = try parseLaTeX(#"\def\b{1} \let\a\b \def\b{2} \a\b"#)
        let texts = result.compactMap(\.symbolText)
        #expect(texts == ["1", "2"])
    }

    @Test func letWithEquals() throws {
        let result = try parseLaTeX(#"\def\b{x} \let\a=\b \a"#)
        #expect(result.last?.symbolText == "x")
    }

    @Test func futurelet() throws {
        // \futurelet\a\b c: \a becomes c's meaning, then \b c continue.
        let result = try parseLaTeX(#"\def\b{q} \futurelet\a\b z \a"#)
        let texts = result.compactMap(\.symbolText)
        #expect(texts == ["q", "z", "z"])
    }

    @Test func defExpectedControlSequenceError() {
        #expect(throws: ParseError.self) {
            try parseLaTeX(#"\def{x}{y}"#)
        }
    }

    // ── Global definitions inside groups (KaTeX Namespace.set global) ────

    @Test func gdefAfterLocalDefInSameGroup() throws {
        // An earlier local \def of the same name must not be restored over
        // the global definition when the group closes.
        let result = try parseLaTeX(#"{\def\x{a}\gdef\x{b}}\x"#)
        #expect(result.last?.symbolText == "b")
    }

    @Test func xdefAfterLocalDefInSameGroup() throws {
        let result = try parseLaTeX(#"{\def\x{a}\xdef\x{b}}\x"#)
        #expect(result.last?.symbolText == "b")
    }

    @Test func globalLetAfterLocalDefInSameGroup() throws {
        let result = try parseLaTeX(#"\def\b{c}{\def\x{a}\global\let\x\b}\x"#)
        #expect(result.last?.symbolText == "c")
    }

    @Test func gdefAfterLocalDefInNestedGroups() throws {
        // The purge must clear undo records in every open group, not just
        // the innermost one.
        let result = try parseLaTeX(#"{\def\x{a}{\def\x{o}\gdef\x{b}}}\x"#)
        #expect(result.last?.symbolText == "b")
    }

    // ── Delimited parameters (KaTeX def.js `delimiters`) ─────────────────

    @Test func delimitedParameterBinding() throws {
        // `\a x#1x` — #1 is delimited by `x`; `\a x1x` binds #1 = 1.
        let result = try parseLaTeX(#"\def\a x#1x{[#1]}\a x1x"#)
        #expect(result.compactMap(\.symbolText) == ["[", "1", "]"])
    }

    @Test func delimitedMultiParameter() throws {
        let result = try parseLaTeX(#"\def\pt(#1;#2){[#1|#2]}\pt(a;b)"#)
        #expect(result.compactMap(\.symbolText) == ["[", "a", "|", "b", "]"])
    }

    @Test func delimitedMultiTokenDelimiter() throws {
        // The delimiter for #1 is the two-token sequence `xy`; a partial
        // match (`x` not followed by `y`) must reset.
        let result = try parseLaTeX(#"\def\a#1xy{[#1]}\a bxbxyc"#)
        #expect(result.compactMap(\.symbolText) == ["[", "b", "x", "b", "]", "c"])
    }

    @Test func delimitedParameterMismatchThrows() {
        // Use-site tokens must match the leading delimiter text.
        #expect(throws: ParseError.self) {
            try parseLaTeX(#"\def\a x#1x{[#1]}\a y1x"#)
        }
    }

    @Test func hashBraceDelimiter() throws {
        // `\def\a#1#{…}`: #1 is delimited by `{`, and the `{` reappears at
        // the end of the replacement text (TeXbook §203).
        let result = try parseLaTeX(#"\def\a#1#{[#1]}\a 12{x}"#)
        #expect(result.compactMap(\.symbolText) == ["[", "1", "2", "]"])
        #expect(result.count == 5)  // "[", "1", "2", "]", and the group {x}
    }

    @Test func zeroArgDelimitedMacroConsumesDelimiters() throws {
        // KaTeX calls consumeArgs even for zero numbered args, so the
        // parameter text after the macro name is validated and consumed.
        // Regression: the `xy` used to be left in the stream → "barxyz".
        let result = try parseLaTeX(#"\def\foo xy{bar}\foo xyz"#)
        #expect(result.compactMap(\.symbolText) == ["b", "a", "r", "z"])
    }

    @Test func zeroArgDelimitedMacroMismatchThrows() {
        // Regression: mismatched delimiter text was silently accepted.
        #expect(throws: ParseError.self) {
            try parseLaTeX(#"\def\foo xy{bar}\foo qz"#)
        }
    }

    @Test func hashBraceZeroArgBalancesBraces() throws {
        // `\def\a#{u}` with no numbered args: the `{` delimiter is consumed
        // from the input and re-emitted after the replacement, so `\a{v}`
        // yields the balanced `u{v}`. Regression: the input `{` was not
        // consumed, producing `u{{v}` → "Expected '}', got 'EOF'".
        let result = try parseLaTeX(#"\def\a#{u}\a{v}"#)
        #expect(result.compactMap(\.symbolText) == ["u"])
        #expect(
            result.contains { node in
                if case .ordGroup = node.kind { return true }
                return false
            }, "the re-emitted brace must open the group that captures v")
    }

    /// Internal invariant guard: `consumeArgs` requires
    /// `delimiters.count == numArgs + 1` (KaTeX throws the same error).
    /// Unreachable through `\def` (which always builds a matching pair),
    /// so exercised directly.
    @Test func consumeArgsRejectsMismatchedDelimiters() {
        let gullet = MacroExpander("x", mode: .math)
        #expect(throws: ParseError.self) {
            try gullet.consumeArgs(1, delimiters: [[]])
        }
    }
}
