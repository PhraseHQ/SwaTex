import Testing

@testable import SwaTex

/// Coverage for reachable-but-untested constructs, each formula targeting a
/// specific previously-uncovered branch (file/line noted). Unreachable
/// defensive fallbacks stay uncovered by design (P-013).
@Suite("ReachableGaps")
struct ReachableGapsTests {

    private func rendered(_ latex: String) throws(ParseError) -> DisplayList {
        try SwaTexEngine.displayList(for: latex)
    }

    // ── Genfrac.swift: \above, \genfrac delimiter/style/bar variants ────

    @Test(arguments: [
        #"{a \above 1pt b}"#,  // barSize from \above
        #"{a \above 0pt b}"#,  // zero bar → nil barSize
        #"\genfrac(]{0pt}{2}{a}{b}"#,  // explicit delims + zero thickness + style
        #"\genfrac{}{}{}{}{a}{b}"#,  // empty delims/thickness/style
        #"\genfrac{[}{)}{1pt}{0}{a}{b}"#,
        #"\cfrac{a}{b}"#,
        #"{a \atop b}"#,
        #"{a \choose b}"#,
        #"{a \brack b}"#,
        #"{a \brace b}"#,
    ])
    func genfracVariants(_ latex: String) throws {
        let list = try rendered(latex)
        #expect(list.width > 0 && list.items.count > 0)
    }

    // ── EngineDelims.swift: \middle detection inside styling/html nodes,
    //    null delimiters (`\bigl.`) ────────────────────────────────────────

    @Test(arguments: [
        #"\left( \displaystyle a \middle| b \right)"#,  // middle in styling body
        #"\left( \htmlClass{c}{a \middle| b} \right)"#,  // middle in html node
        #"\bigl. x \bigr|"#,  // null sized delimiter → kern(0)
        #"\left. x \right|"#,
    ])
    func middleAndNullDelims(_ latex: String) throws {
        let list = try rendered(latex)
        #expect(list.width > 0)
    }

    // ── EngineMisc.swift: single-char accent bodies, brace/arrow widths,
    //    \utilde shifted-path variant ─────────────────────────────────────

    @Test(arguments: [
        #"\widehat{{a}}"#,  // nested ordgroup single-char body
        #"\widehat{\mathbf{a}}"#,
        #"\overbrace{}"#,  // empty brace body
        #"\overbrace{aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}^{x}"#,
        #"\underbrace{y}_{z}"#,
        #"\xtwoheadrightarrow{ab}"#,
        #"\xtwoheadleftarrow{ab}"#,
        #"\utilde{abc}"#,
        #"\undergroup{abc}"#,
    ])
    func accentAndBraceGeometry(_ latex: String) throws {
        let list = try rendered(latex)
        #expect(list.height + list.depth > 0)
    }

    // ── EngineOps.swift: operator name edges, \nolimits scripts ─────────

    @Test(arguments: [
        #"\operatorname{}"#,  // empty operator name
        #"\operatorname*{op}_a^b"#,
        #"\lim\nolimits_{x\to 0} f"#,
        #"\mathop{x}"#,  // op with no scripts
        #"\int\limits_0^1"#,
    ])
    func operatorEdges(_ latex: String) throws {
        _ = try rendered(latex)
    }

    // ── EngineTextStyles.swift: typewriter fallback widths, underline
    //    over links ────────────────────────────────────────────────────────

    @Test(arguments: [
        #"\texttt{中文}"#,  // CJK in typewriter → fallback metrics
        #"\underline{\href{https://x.y}{ab}}"#,  // underline skip-cuts over link
        #"\underline{a\href{https://x.y}{b}c}"#,
        #"\underline{\underline{x}}"#,
    ])
    func textStyleEdges(_ latex: String) throws {
        _ = try rendered(latex)
    }

    // ── Parser.swift: recursion limit, expected-group errors, Unicode
    //    sup/sub multi-scalar bases ────────────────────────────────────────

    @Test func deepNestingHitsRecursionLimit() {
        let deep = String(repeating: "{", count: 3000) + "x"
            + String(repeating: "}", count: 3000)
        #expect(throws: ParseError.self) {
            _ = try rendered(deep)
        }
    }

    @Test(arguments: [
        #"\textcolor{red}²"#,  // Unicode sup after non-symbol base
        #"\text{ab}²"#,
        #"≠²"#,
    ])
    func unicodeSupSubBases(_ latex: String) throws {
        _ = try? rendered(latex)  // some are errors; branch coverage either way
    }

    // ── MacroExpander.swift: string-body macros with #1 args (Settings
    //    macros path), \noexpand of undefined inside \edef ────────────────

    @Test func stringBodyMacroWithArgs() throws {
        // `.text` macro definitions re-lex their body and count #n args
        // (getExpansion's `.text` path, arg-count loop). Only reachable via
        // the internal string-macro API (builtins are pre-tokenized, P-009).
        let parser = Parser(#"\twice{7}"#)
        parser.gullet.setTextMacro("\\twice", "#1+#1")
        let nodes = try parser.parse()
        #expect(!nodes.isEmpty)
    }

    @Test func noexpandUndefinedInsideEdef() throws {
        _ = try rendered(#"\edef\x{\noexpand\undefinedthing}\def\undefinedthing{9}\x"#)
    }

    // ── MhChemActions.swift: \pu inside rm slots, signed 1/2 fractions,
    //    tex-math tails in halves ─────────────────────────────────────────

    @Test(arguments: [
        #"\pu{123 kJ//mol}"#,
        #"\pu{-1/2 m}"#,
        #"\ce{+1/2A}"#,
        #"\ce{$a$/2$b$}"#,
        #"\ce{{\mu}}"#,
        #"\pu{\mu mol}"#,
    ])
    func mhchemRareActions(_ latex: String) throws {
        _ = try? rendered(latex)
    }

    // ── Environments.swift: tags, trailing rows, column specs ───────────

    @Test(arguments: [
        #"\begin{align}a&=b\tag{7}\\c&=d\notag\end{align}"#,
        #"\begin{gather}x\\\end{gather}"#,  // empty trailing row
        #"\begin{array}{c}a\\\hline\end{array}"#,  // trailing \hline
        #"\begin{alignat}{2}a&=b&c&=d\end{alignat}"#,
        #"\begin{subarray}{l}a\\b\end{subarray}"#,
    ])
    func environmentEdges(_ latex: String) throws {
        _ = try? rendered(latex)
    }
}

// Second pass: tag extraction defaults, trailing-row shapes, texttt
// fallback metrics, underline-over-link variants, \pu braced rm bodies.
extension ReachableGapsTests {
    @Test(arguments: [
        #"\begin{align}a&b\end{align}"#,
        #"\begin{align}&\end{align}"#,
        #"\begin{align}a\tag{}\end{align}"#,
        #"\begin{align}a\tag*{xy}\end{align}"#,
        #"\begin{align}a&=b\\ \end{align}"#,
        #"\begin{align}a&=b\\{}\end{align}"#,
        #"\begin{gather}a b c\end{gather}"#,
        #"\begin{equation}x\end{equation}"#,
        #"\begin{array}{}\end{array}"#,
        #"\begin{array}{{c}}a\end{array}"#,
    ])
    func tagAndRowShapes(_ latex: String) throws {
        _ = try? SwaTexEngine.displayList(for: latex)
    }

    @Test(arguments: [
        #"\texttt{±}"#,
        #"\texttt{§¶}"#,
        #"\underline{\href{https://a}{\scriptsize gy}}"#,
        #"\underline{\href{https://a}{\raisebox{1pt}{g}}}"#,
        #"\underline{\,}"#,
        #"\text{\underline{g}}"#,
        #"a\underline{=}b"#,
        #"x\overline{<}y"#,
    ])
    func textStyleSecondPass(_ latex: String) throws {
        _ = try? SwaTexEngine.displayList(for: latex)
    }

    @Test(arguments: [
        #"\pu{{K}}"#,
        #"\pu{{kg} m}"#,
        #"\pu{{J}//{s}}"#,
        #"\pu{123 {abc}x}"#,
        #"\ce{^{}}"#,
    ])
    func mhchemBracedRm(_ latex: String) throws {
        _ = try? SwaTexEngine.displayList(for: latex)
    }
}
