import Testing

@testable import SwaTex

/// KaTeX-correctness tests for `\edef` expansion order and `\noexpand`.
///
/// Two RaTeX bugs are fixed in SwaTex (verified against KaTeX semantics):
/// 1. RaTeX's `\edef` expands its body back-to-front (invisible to
///    dimension-only golden tests, since widths add commutatively).
/// 2. `\noexpand` protection leaked out of `\edef` as a permanent
///    treat-as-relax flag, so the defined macro rendered as nothing.
@Suite("EdefNoexpand")
struct NoexpandTests {
    @Test func edefPreservesTokenOrder() throws {
        let result = try parseLaTeX(#"\edef\q{abc}\q"#)
        let texts = result.compactMap(\.symbolText)
        #expect(texts == ["a", "b", "c"])
    }

    @Test func edefExpandsMacrosInOrder() throws {
        let result = try parseLaTeX(#"\def\u{uv}\edef\q{x\u y}\q"#)
        let texts = result.compactMap(\.symbolText)
        #expect(texts == ["x", "u", "v", "y"])
    }

    @Test func noexpandInsideEdefProtectsOnce() throws {
        // \alpha is not expandable (it's a symbol), so \noexpand is a no-op
        // and the stored macro contains a normal \alpha (KaTeX renders α;
        // RaTeX renders nothing).
        let result = try parseLaTeX(#"\edef\z{\noexpand\alpha}\z"#)
        #expect(result.count == 1)
        #expect(result[0].symbolText == "\\alpha")
    }

    @Test func noexpandProtectsMacroFromEdefExpansion() throws {
        // Without \noexpand, \b expands at \edef time (to "1"); with it,
        // \a captures \b itself and sees \b's later redefinition (KaTeX).
        let result = try parseLaTeX(#"\def\b{1} \edef\a{\noexpand\b} \def\b{2} \a"#)
        #expect(result.last?.symbolText == "2")
    }

    @Test func bareNoexpandOnSymbolIsNoOp() throws {
        // \alpha is not expandable → \noexpand leaves it untouched (KaTeX).
        let result = try parseLaTeX(#"x\noexpand\alpha y"#)
        let texts = result.compactMap(\.symbolText)
        #expect(texts == ["x", "\\alpha", "y"])
    }

    @Test func bareNoexpandOnMacroActsAsRelax() throws {
        // \b IS expandable → \noexpand marks it treat-as-relax for this
        // fetch, so it renders as nothing (KaTeX).
        let result = try parseLaTeX(#"\def\b{1} x\noexpand\b y"#)
        let texts = result.compactMap(\.symbolText)
        #expect(texts == ["x", "y"])
    }
}

/// KaTeX-correctness: \htmlClass/\htmlId/\htmlData keep their content in
/// order (RaTeX reversed it: {xy} rendered as "yx").
@Suite("HtmlClassOrder")
struct HtmlClassOrderTests {
    @Test func contentKeepsOrder() throws {
        let result = try parseLaTeX(#"\htmlClass{c}{xyz}"#)
        let texts = result.compactMap(\.symbolText)
        #expect(texts == ["x", "y", "z"])
    }

    @Test func htmlIdAndData() throws {
        #expect(try parseLaTeX(#"\htmlId{i}{ab}"#).compactMap(\.symbolText) == ["a", "b"])
        #expect(try parseLaTeX(#"\htmlData{k=v}{ab}"#).compactMap(\.symbolText) == ["a", "b"])
    }
}
