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
}
