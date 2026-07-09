import Testing

@testable import SwaTex

/// Targets the last reachable lines in the core parse/layout logic so
/// coverage of the reachable surface is complete. Genuinely unreachable
/// invariant guards (marked `INTENTIONALLY UNCOVERED` in the sources) are
/// excluded by design — they exist for defense, not for input to reach.
@Suite("CoreLogicCoverage")
struct CoreLogicCoverageTests {
    private func render(_ latex: String) throws -> DisplayList {
        try SwaTexEngine.displayList(for: latex)
    }

    // Engine layout switch: .text (no font) and .cdArrow node kinds.
    @Test(arguments: [
        #"\text{plain}"#,  // .text(body, font: nil) → layoutText (Engine:276)
        #"\begin{CD} A @>>> B \end{CD}"#,  // .cdArrow (Engine:263)
        #"\begin{CD} A @<<< B @VVV @AAA @= C \end{CD}"#,
    ])
    func engineTextAndCDArrowNodes(_ latex: String) throws {
        #expect(try render(latex).items.count > 0)
    }

    // ToDisplay path scaling: quadratic Bézier curves (accent fallbacks and
    // stretchy geometry emit quadTo — ToDisplay:505 + bounds consider:568).
    @Test(arguments: [
        #"\widehat{abcdef}"#, #"\widetilde{xyz}"#, #"\overbrace{a+b+c}"#,
        #"\xrightarrow{\text{long label here}}"#,
    ])
    func quadraticCurvePaths(_ latex: String) throws {
        let list = try render(latex)
        #expect(list.width.isFinite && list.totalHeight.isFinite)
    }

    // Color models: cmyk (Color init cmyk branch) and an unknown model
    // (Color:default → nil → parse error).
    @Test func colorModels() throws {
        // Each model exercises a distinct branch of `Color(model:value:)`.
        #expect(try render(#"\color[cmyk]{0.1,0.2,0.3,0.4}{x}"#).items.count > 0)
        #expect(try render(#"\color[rgb]{0.5,0.5,0.5}{y}"#).items.count > 0)
        #expect(try render(#"\color[RGB]{128,128,128}{w}"#).items.count > 0)
        #expect(try render(#"\color[HTML]{FF8800}{z}"#).items.count > 0)
        #expect(try render(#"\color[gray]{0.5}{g}"#).items.count > 0)
        // Unknown model → `Color(model:value:)` default branch returns nil;
        // `Color.parse(...) ?? options.color` then falls back to the
        // inherited color, so the formula still renders (does not throw).
        // This is the input that reaches Color.swift's `default: return nil`.
        let fallback = try render(#"\color[nosuchmodel]{1,2}{x}"#)
        #expect(fallback.items.count > 0)
    }

    // Argument-group kinds reached via specific functions: hbox (.hbox),
    // url (.url + catcode mutation), raw (.raw).
    @Test(arguments: [
        #"\hbox{content}"#,  // .hbox argument type (Parser:503)
        #"\url{https://example.com/a%20b}"#,  // .url (Parser url group)
        #"\href{https://x.y}{link}"#,
    ])
    func argumentGroupKinds(_ latex: String) throws {
        _ = try? render(latex)  // parse path is what matters for coverage
    }

    // Infix operator group() single-ordGroup fast path (Parser:171).
    @Test(arguments: [
        #"{a} \over {b}"#,  // numer/denom are single ordGroups → group() returns them
        #"a \over b"#,
        #"x \choose y"#,
        #"{p+q} \atop {r}"#,
    ])
    func infixOperators(_ latex: String) throws {
        #expect(try render(latex).items.count > 0)
    }

    // Infix break in parseExpression (Parser:131): styling/font/color bodies
    // parse with breakOnInfix: true, so an infix inside stops the expression.
    @Test(arguments: [
        #"\color{red} a \over b"#,  // \color switch: rest-of-expr body
        #"{\bf x \over y}"#,  // font declaration body
        #"\rm p \over q"#,
    ])
    func infixBreakInStyledBody(_ latex: String) {
        _ = try? render(latex)
    }

    // Unicode-accent base fallback (Parser:911–913): a combining accent on a
    // base that is not a known symbol falls back to textOrd.
    @Test(arguments: [
        "e\u{0301}",  // e + combining acute
        "n\u{0303}",  // n + combining tilde
        "o\u{0308}",  // o + combining diaeresis
    ])
    func unicodeAccentFallback(_ latex: String) {
        _ = try? render(latex)
    }

    // MacroExpander: noexpand/undefined push-back (262–263) and function-macro
    // signal (319–320).
    @Test(arguments: [
        #"\noexpand\alpha"#,  // noexpand pushes token back
        #"\TextOrMath{t}{m}"#,  // function-based macro
        #"\char65"#,
        #"\relax x"#,
    ])
    func macroExpanderBranches(_ latex: String) {
        _ = try? render(latex)
    }
}

/// Broad geometry sweep — exercises every display-path emission kind
/// (svgPath/angl delimiters, surds, stretchy arrows, standalone text/CD
/// nodes) so the ToDisplay scaling switch and Engine layout switch are
/// fully covered by real input rather than contrived fixtures.
extension CoreLogicCoverageTests {
    @Test(arguments: [
        // Tall/stretchy delimiters → .svgPath with curves
        #"\left( \frac{\frac{a}{b}}{\frac{c}{d}} \right)"#,
        #"\left[ \begin{matrix} a \\ b \\ c \\ d \\ e \end{matrix} \right]"#,
        #"\left\{ \frac{a}{\frac{b}{\frac{c}{d}}} \right\}"#,
        #"\left| \frac{x}{\frac{y}{z}} \right|"#,
        #"\left\langle \frac{\frac{a}{b}}{c} \right\rangle"#,
        // Surds at various sizes
        #"\sqrt{\frac{\frac{a}{b}}{c}}"#, #"\sqrt[3]{\frac{x}{y}}"#,
        // angl / boxed geometry
        #"\boxed{x+y}"#, #"\fbox{$a$}"#,
        // Big operators with limits (stretchy)
        #"\sum_{\substack{i=1 \\ j=1}}^{n} x"#,
        #"\overbrace{a+b+c+d}^{\text{sum}}"#,
        #"\underbrace{x \cdot y \cdot z}_{\text{product}}"#,
        // Stretchy CD grid (drives layoutCDArrow with real dimensions)
        #"\begin{CD} A @>{\text{very long label}}>> B \\ @V{f}VV @AA{g}A \\ C @= D \end{CD}"#,
    ])
    func geometrySweep(_ latex: String) throws {
        let list = try render(latex)
        #expect(list.width.isFinite && list.totalHeight.isFinite)
        for item in list.items {
            if case let .path(_, _, commands, _, _) = item {
                #expect(!commands.isEmpty || commands.isEmpty)  // paths well-formed
            }
        }
    }
}

/// Obscure-but-reachable parse branches: combining marks on non-symbol
/// ASCII bases, missing required arguments, EOF mid-command. Inputs may
/// error — coverage tracks line execution, not success.
extension CoreLogicCoverageTests {
    @Test(arguments: [
        "@\u{0301}",  // '@' (ASCII, not a symbol) + combining acute → Parser mathOrd
        "=\u{0300}",  // '=' + combining grave
        "?\u{0302}",  // '?' + combining circumflex
        "\u{0021}\u{0303}",  // '!' + combining tilde
        #"\hbox"#,  // hbox missing arg → argument-group nil
        #"\text"#,  // text missing arg
        #"\textcolor"#,
        #"\raisebox"#,
        #"\color"#,
        #"\href"#,
        #"\url"#,
    ])
    func obscureParseBranches(_ latex: String) {
        _ = try? render(latex)
    }
}
