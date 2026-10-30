import Testing

@testable import SwaTex

/// Regression tests for layout-correctness fixes that intentionally diverge
/// from the RaTeX (Rust) reference, aligning with KaTeX/TeX instead:
/// `\cancel` body registration, `\vcenter` ink movement, TeXbook Rule 5
/// bin cancellation over effective (already-resolved) classes, and the
/// column and relation spacing of align environments.
@Suite("LayoutFixRegression")
struct LayoutFixRegressionTests {
    private func displayList(_ latex: String) throws -> DisplayList {
        try SwaTexEngine.displayList(for: latex)
    }

    private func glyphs(_ dl: DisplayList) -> [(x: Double, y: Double, char: UInt32)] {
        dl.items.compactMap {
            if case let .glyphPath(x, y, _, _, charCode, _) = $0 {
                return (x, y, charCode)
            }
            return nil
        }
    }

    /// Multi-char `\cancel{…}`: the strike line extends `hPad` (0.2 em) past
    /// the body on BOTH sides. Regression: the body used to render 0.2 em too
    /// far right, overlapping the following atom.
    @Test func cancelBodyRegistersAtContentOrigin() throws {
        let dl = try displayList(#"\cancel{xy}"#)
        let pathX = dl.items.compactMap { item -> Double? in
            if case let .path(x, _, _, _, _) = item { return x }
            return nil
        }
        let firstGlyphX = try #require(glyphs(dl).map(\.x).min())
        let lineX = try #require(pathX.first)
        // The path box's origin sits hPad (0.2 em) right of its ink start
        // (its commands begin at x = −hPad), and the body ink must start at
        // the same origin — i.e. hPad in from the strike's left end.
        // Regression: the body used to start another 0.2 em further right.
        #expect(abs(firstGlyphX - lineX) < 1e-4)
    }

    /// `\vcenter` must physically move the ink to the math axis, not just
    /// re-declare box height/depth (regression: glyphs stayed on the
    /// baseline while the box claimed to be centered).
    @Test func vcenterMovesInkToAxis() throws {
        let centered = try displayList(#"a\vcenter{xx}b"#)
        let plain = try displayList(#"axxb"#)
        let xChar = UInt32(UInt8(ascii: "x"))
        let aChar = UInt32(UInt8(ascii: "a"))
        // Without \vcenter, every glyph sits on the shared baseline.
        let plainXY = try #require(glyphs(plain).first { $0.char == xChar }?.y)
        let plainAY = try #require(glyphs(plain).first { $0.char == aChar }?.y)
        #expect(abs(plainXY - plainAY) < 1e-6)
        // With \vcenter, the x glyphs are raised to the math axis:
        // raise = axisHeight − (h − d)/2 for `xx` (h = x-height 0.43056, d = 0).
        let centeredXY = try #require(glyphs(centered).first { $0.char == xChar }?.y)
        let centeredAY = try #require(glyphs(centered).first { $0.char == aChar }?.y)
        let raise = 0.25 - 0.43056 / 2
        #expect(abs((centeredAY - centeredXY) - raise) < 1e-4, "vcenter ink must move up by raise")
    }

    /// TeXbook Rule 5: a Bin whose predecessor is a just-cancelled Bin (now
    /// Ord) keeps its Bin class — the second `+` in `(++a` gets 4 mu of
    /// medium space on each side (regression: both `+` were cancelled and
    /// spaced as Ord, 0 mu).
    @Test func binCancellationUsesEffectivePreviousClass() throws {
        let dl = try displayList("(++a")
        // ( 0.38889 + 0.77778 + 0.77778 + a 0.52859 = 2.47304 glyph advance,
        // plus 2 × 4 mu (0.22222 em) around the second, still-binary `+`.
        #expect(abs(dl.width - 2.91748) < 1e-4)
    }

    /// Items that render `\middle|` ink: math-mode `|` resolves to U+2223
    /// (DIVIDES, 8739) as a natural-size glyph; taller bars stretch into a
    /// vertical-bar SVG path.
    private func vertBarInk(_ dl: DisplayList) -> (glyphs: Int, paths: Int) {
        var glyphs = 0
        var paths = 0
        for item in dl.items {
            switch item {
            case let .glyphPath(_, _, _, _, charCode, _)
            where charCode == 0x2223 || charCode == 0x7C:
                glyphs += 1
            case .path:
                paths += 1
            default:
                break
            }
        }
        return (glyphs, paths)
    }

    /// `\middle` hidden inside a container the containment scan didn't
    /// enumerate (`\hbox`) must still stretch in the second pass.
    /// Regression: `nodeContainsMiddle`'s `default: false` made the stretch
    /// pass reuse the hbox's first-pass box, in which the `\middle|` was a
    /// zero-ink placeholder — the bar vanished from the output.
    @Test func middleInsideHboxRendersInk() throws {
        let dl = try displayList(#"\left( \hbox{$a \middle| b$} \middle. c \right)"#)
        let ink = vertBarInk(dl)
        #expect(
            ink.glyphs + ink.paths >= 1,
            "the \\middle| inside \\hbox must produce ink (got \(dl.items.count) items)")
        // a, b, c, ( , ) and the bar — nothing may drop out.
        #expect(dl.items.count == 6)
    }

    /// Beyond `maxMiddleStretchDepth` (8) the body lays out once at natural
    /// delimiter height: every over-cap `\middle` still renders visible ink
    /// as a natural-size bar glyph. Regression: over-cap scopes reused the
    /// zero-ink first-pass placeholder, silently erasing the delimiters.
    @Test func middleBeyondStretchCapKeepsVisibleInk() throws {
        let n = 10
        let latex =
            String(repeating: #"\left({\middle| "#, count: n) + "x"
            + String(repeating: #"}\right)"#, count: n)
        // Parse depth grows with nesting; a big stack keeps the parser's
        // probe out of the picture in debug builds.
        let result = runOnThread(stackSize: 64 << 20) {
            Result { () throws(ParseError) -> DisplayList in
                try SwaTexEngine.displayList(for: latex)
            }
        }
        let dl = try result.get()
        let ink = vertBarInk(dl)
        // Every scope's bar must produce ink — the stretched eight AND the
        // over-cap two (which render at the natural fallback height). At
        // this compact size all ten fit the natural glyph, but count paths
        // too so the assertion survives metric tweaks that tip a bar into
        // the stretched-SVG range.
        #expect(
            ink.glyphs + ink.paths >= n,
            "all \(n) \\middle bars must render ink, got \(ink)")
    }

    /// Horizontal advance from the glyph before `char` to `char`, and from
    /// `char` to the glyph after it (the first `char` from the end).
    private func spacing(around char: Character, in latex: String) throws -> (
        before: Double, after: Double
    ) {
        let xs = try glyphs(displayList(latex)).sorted { $0.x < $1.x }
        let code = try #require(char.unicodeScalars.first).value
        let index = try #require(xs.lastIndex { $0.char == code })
        try #require(index > 0 && index + 1 < xs.count)
        return (xs[index].x - xs[index - 1].x, xs[index + 1].x - xs[index].x)
    }

    /// KaTeX sets `a &= b` in aligned like `a = b`: no column gap inside the
    /// pair and a thickmuskip on both sides of the relation. Regression (from
    /// RaTeX): a 3 mu cap on relation spacing, plus a 3 mu column gap outside
    /// alignat, gave 6 mu before `=` and 3 mu after it (3 mu / 3 mu in
    /// alignedat), and 3 mu around later relations.
    @Test func alignSpacesRelationsLikeInlineMath() throws {
        for (aligned, plain) in [
            (#"\begin{aligned}a&=b\end{aligned}"#, #"a=b"#),
            (#"\begin{aligned}x&=b=c\end{aligned}"#, #"x=b=c"#),
            (#"\begin{align*}a&=b\end{align*}"#, #"a=b"#),
            (#"\begin{alignedat}{1}a&=b\end{alignedat}"#, #"a=b"#),
        ] {
            let inAlign = try spacing(around: "=", in: aligned)
            let inline = try spacing(around: "=", in: plain)
            #expect(abs(inAlign.before - inline.before) < 1e-6, "\(aligned)")
            #expect(abs(inAlign.after - inline.after) < 1e-6, "\(aligned)")
        }
    }

    /// KaTeX's aligned puts one \quad (1 em) before every column pair after
    /// the first; alignedat puts nothing. Regression: aligned used a uniform
    /// 3 mu gap instead of alternating zero and one-quad gaps.
    @Test func alignedSeparatesColumnPairsByAQuad() throws {
        let cChar = UInt32(UInt8(ascii: "c"))
        let aligned = try #require(
            glyphs(displayList(#"\begin{aligned}a&=b&c&=d\end{aligned}"#)).first {
                $0.char == cChar
            }?.x)
        let alignedat = try #require(
            glyphs(displayList(#"\begin{alignedat}{2}a&=b&c&=d\end{alignedat}"#)).first {
                $0.char == cChar
            }?.x)
        #expect(abs((aligned - alignedat) - 1.0) < 1e-6)
    }

    /// A vertical rule sits in the middle of the gap in front of its column,
    /// whether the gaps are uniform (`colGap`) or uneven (`columnGaps`).
    @Test func separatorsSitInTheMiddleOfTheirGap() {
        func layout(_ columnGaps: [Double]) -> ArrayLayout {
            ArrayLayout(
                cells: [], colWidths: [1, 2, 3], colAligns: ["c", "c", "c"], rowHeights: [],
                rowDepths: [], colGap: 0.5, offset: 0, columnGaps: columnGaps)
        }
        let uniform = layout([])
        #expect((0...3).map { uniform.separatorX(before: $0) } == [-0.25, 1.25, 3.75, 7.25])
        let uneven = layout([0, 1])
        #expect((0...3).map { uneven.separatorX(before: $0) } == [-0.25, 1.0, 3.5, 7.25])
    }
}
