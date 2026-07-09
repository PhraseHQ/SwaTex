import Testing

@testable import SwaTex

/// `\expandafter` — TeX expansion primitive, beyond-RaTeX (KaTeX-parity)
/// addition. `\expandafter⟨tok1⟩⟨tok2⟩` expands tok2 once, then reinserts
/// tok1 before the expansion.
@Suite("Expandafter")
struct ExpandafterTests {
    @Test func expandsSecondTokenFirst() throws {
        // \greet expands once, then 'x' is put back in front → "xhi".
        let result = try parseLaTeX(#"\def\greet{hi}\expandafter x\greet"#)
        let texts = result.compactMap(\.symbolText)
        #expect(texts == ["x", "h", "i"])
    }

    @Test func expandsOnlyOnce() throws {
        // \outer → \inner (one step); \expandafter expands \outer once,
        // leaving \inner to expand later on its own.
        let result = try parseLaTeX(#"\def\inner{Z}\def\outer{\inner}\expandafter q\outer"#)
        let texts = result.compactMap(\.symbolText)
        #expect(texts == ["q", "Z"])
    }

    @Test func classicLetAfterExpansion() throws {
        // Canonical use: \let via \expandafter grabs the first token OF THE
        // EXPANSION rather than the macro name. After the double
        // \expandafter, the stream is `\let\first AB`: \let binds \first:=A
        // and the remaining B stays in the stream (true TeX behavior), then
        // `\first\pair` yields A AB.
        let result = try parseLaTeX(
            #"\def\pair{AB}\expandafter\let\expandafter\first\pair \first\pair"#)
        let texts = result.compactMap(\.symbolText)
        #expect(texts == ["B", "A", "A", "B"])
    }

    @Test func nonExpandableSecondTokenIsKept() throws {
        // tok2 is a plain letter — nothing to expand; tok1 goes back in front.
        let result = try parseLaTeX(#"\expandafter ab"#)
        let texts = result.compactMap(\.symbolText)
        #expect(texts == ["a", "b"])
    }

    @Test func undefinedSecondTokenThrows() {
        #expect(throws: ParseError.self) {
            try parseLaTeX(#"\expandafter a\thisIsNotDefined"#)
        }
    }
}
