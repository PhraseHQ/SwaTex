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

    private let align = AlignSpec(alignType: .align, align: "c")
    private let solid = AlignSpec(alignType: .separator, align: "|")
    private let dashed = AlignSpec(alignType: .separator, align: ":")

    private func track(
        _ colWidths: [Double], _ cols: [AlignSpec]?, arraycolsep: Double = 0.5,
        hskip: Bool = true
    ) -> ArrayTrack {
        resolveArrayTrack(
            colWidths: colWidths, cols: cols, arraycolsep: arraycolsep,
            doubleRuleSep: 0.2, hskipBeforeAndAfter: hskip)
    }

    /// Positions accumulate `\doublerulesep` (0.2 em, not a binary fraction),
    /// so they are compared with a tolerance rather than for equality.
    private func isClose(
        _ got: [Double], _ want: [Double],
        _ sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) {
        #expect(got.count == want.count, "\(got) vs \(want)", sourceLocation: sourceLocation)
        for (g, w) in zip(got, want) {
            #expect(abs(g - w) < 1e-9, "\(got) vs \(want)", sourceLocation: sourceLocation)
        }
    }

    /// `\begin{array}{c|c|c}`: no column spec sets a gap, so every gap is
    /// `\arraycolsep` and `hskipBeforeAndAfter` pads both outer edges. A rule
    /// then lands halfway between two columns only because the `postgap` on its
    /// left and the `pregap` on its right happen to be equal.
    @Test func uniformColumnsPutRulesHalfwayBetweenThem() {
        let t = track([1, 2, 3], [align, solid, align, solid, align], arraycolsep: 0.25)
        isClose(t.columnXs, [0.25, 1.75, 4.25])
        isClose(t.rules.map(\.x), [1.5, 4.0])
        isClose([t.width], [7.5])
        // Column 0 ends at 1.25 and column 1 starts at 1.75, so 1.5 is both
        // where the gaps meet and the midpoint between the columns.
        isClose([t.rules[0].x], [(t.columnXs[0] + 1.0 + t.columnXs[1]) / 2.0])
    }

    /// The track gives every column an x and no more, and an empty grid is
    /// 0 em wide rather than undefined.
    @Test func trackGivesEveryColumnExactlyOneX() {
        for n in 0...3 {
            let t = track([Double](repeating: 1, count: n), nil)
            #expect(t.columnXs.count == n)
            #expect(t.rules.isEmpty)
        }
        isClose([track([], nil).width], [0.0])
    }

    /// With uneven gaps a rule is *not* at the midpoint: KaTeX emits it where
    /// the previous column's `postgap` meets this column's `pregap`. Here that
    /// is 1.0, while the gap between the columns spans 1.0 to 2.0.
    @Test func rulesSitWhereTheGapsMeetNotAtTheirMidpoint() {
        let cols = [
            AlignSpec(alignType: .align, align: "r", pregap: 0.0, postgap: 0.0),
            solid,
            AlignSpec(alignType: .align, align: "l", pregap: 1.0, postgap: 0.0),
        ]
        let t = track([1, 2], cols, arraycolsep: 0.25, hskip: false)
        isClose(t.columnXs, [0.0, 2.0])
        isClose(t.rules.map(\.x), [1.0])
        isClose([t.width], [4.0])
    }

    /// `\begin{array}{c||c}`: KaTeX puts consecutive rules in one run a
    /// `\doublerulesep` (0.2 em) apart and widens the grid by exactly that, so
    /// two rules cost 0.2 em where one costs nothing. Measured against KaTeX
    /// 0.16.11 in a browser: rule centres 0.2008 em apart, grid 0.20081 em
    /// wider than the single-rule spec.
    @Test func consecutiveRulesSitADoubleRuleSepApart() {
        let one = track([1, 1], [align, solid, align])
        let two = track([1, 1], [align, solid, solid, align])
        let three = track([1, 1], [align, solid, solid, solid, align])
        isClose(one.rules.map(\.x), [2.0])
        isClose(two.rules.map(\.x), [2.0, 2.2])
        isClose(three.rules.map(\.x), [2.0, 2.2, 2.4])
        isClose([two.width - one.width], [0.2])
        isClose([three.width - one.width], [0.4])
        // Column 1 is pushed right by the rules it now sits behind.
        isClose(one.columnXs, [0.5, 2.5])
        isClose(two.columnXs, [0.5, 2.7])
    }

    /// End to end: a cell narrower than its column is centred on the column x
    /// the track resolved. The golden fixtures assert the grid's outer
    /// dimensions, which a cell displaced inside its own column would leave
    /// untouched, so the placement is pinned here instead.
    @Test func aNarrowCellIsCentredOnItsColumn() throws {
        let m = UInt32(UInt8(ascii: "m"))
        // Column 0 holds `mm` in one row and a single `m` in the other.
        let found = glyphs(try displayList(#"\begin{array}{cc}mm&a\\m&a\end{array}"#))
            .filter { $0.char == m }
        let rows = Set(found.map(\.y))
        try #require(rows.count == 2)
        let byRow = rows.sorted().map { y in found.filter { $0.y == y }.map(\.x).sorted() }
        let pair = try #require(byRow.first { $0.count == 2 })
        let lone = try #require(byRow.first { $0.count == 1 })
        // The lone `m` starts half an `m` further right than the pair does.
        #expect(abs((lone[0] - pair[0]) - (pair[1] - pair[0]) / 2.0) < 1e-6)
    }

    /// `|` and `:` can share a boundary; each keeps its own style.
    @Test func mixedRuleKindsShareABoundary() {
        let t = track([1, 1], [align, solid, dashed, align])
        isClose(t.rules.map(\.x), [2.0, 2.2])
        #expect(t.rules.map(\.isDashed) == [false, true])
    }

    /// `\begin{array}{c|c|}` with a single cell. KaTeX restarts the rule run
    /// after every alignment descriptor, so these two rules — split by the
    /// descriptor of a column that was never laid out — get no
    /// `\doublerulesep` and land on the same x, costing no width. Measured in
    /// KaTeX 0.16.11: both centres at 1.5294/1.5302 em, grid no wider.
    @Test func rulesSplitByAnUnusedDescriptorShareOneX() {
        let t = track([1], [align, solid, align, solid])
        isClose(t.rules.map(\.x), [2.0, 2.0])
        isClose([t.width], [2.0])
    }

    /// `\begin{array}{cc|}` with a single cell: the spec declares more columns
    /// than the row fills, and KaTeX still renders the trailing rule, at the
    /// grid's right edge. SwaTex used to drop any rule past the column count.
    @Test func aTrailingRuleRendersEvenPastAShortRow() {
        let t = track([1], [align, align, solid])
        isClose(t.rules.map(\.x), [2.0])
        isClose([t.width], [2.0])
    }

    /// End to end: a solid rule is one rect spanning the array's full height,
    /// so `{c||c}` draws two of them a `\doublerulesep` apart where `{c|c}`
    /// draws one.
    @Test func doubledRulesReachTheDisplayList() throws {
        func ruleXs(_ latex: String) throws -> [Double] {
            let rects = try displayList(latex).items.compactMap {
                item -> (x: Double, height: Double)? in
                if case let .rect(x, _, _, height, _) = item { return (x, height) }
                return nil
            }
            let tallest = try #require(rects.map(\.height).max())
            return rects.filter { $0.height == tallest }.map(\.x).sorted()
        }
        let one = try ruleXs(#"\begin{array}{c|c}a&b\end{array}"#)
        let two = try ruleXs(#"\begin{array}{c||c}a&b\end{array}"#)
        #expect(one.count == 1)
        #expect(two.count == 2)
        #expect(abs((two[1] - two[0]) - 0.2) < 1e-6)
    }

    /// A column the spec does not reach falls back to `\arraycolsep` on both
    /// sides, as KaTeX's `colDescr?.pregap ?? arraycolsep` does. `cases`
    /// declares two columns with a 1 em `postgap` on the first, so a third
    /// column sits one `\arraycolsep` away rather than another 1 em.
    @Test func columnsBeyondTheSpecFallBackToArraycolsep() {
        let casesCols = [
            AlignSpec(alignType: .align, align: "l", pregap: 0.0, postgap: 1.0),
            AlignSpec(alignType: .align, align: "l", pregap: 0.0, postgap: 0.0),
        ]
        let t = track([1, 1, 1], casesCols, hskip: false)
        isClose(t.columnXs, [0.0, 2.0, 3.5])
        isClose([t.width], [4.5])
    }

    /// End to end through `cases`, whose spec declares two columns with a 1 em
    /// `postgap` on the first: a third cell is one `\arraycolsep` (0.5 em)
    /// away, not another 1 em. Identical cells make the assertion independent
    /// of glyph widths — the two advances differ by exactly the two gaps.
    @Test func casesSpacesACellBeyondItsSpecByArraycolsep() throws {
        let cellChar = UInt32(UInt8(ascii: "x"))
        let xs = glyphs(try displayList(#"\begin{cases}x&x&x\end{cases}"#))
            .filter { $0.char == cellChar }.map(\.x).sorted()
        try #require(xs.count == 3)
        #expect(abs(((xs[1] - xs[0]) - (xs[2] - xs[1])) - 0.5) < 1e-6)
    }

    /// KaTeX reads the `alignat` column count with
    /// `assertNodeType(…, "textord")`, so a letter, a sign or a nested group
    /// in the argument is a parse error there — none of them reaches
    /// `Number()`. A fractional count, which KaTeX does accept (`{2.5}` means
    /// five columns), is rejected rather than given a meaning.
    @Test(arguments: ["-1", "+2", "x", "2.5", "1e3", "{2}"])
    func alignatRejectsAColumnCountThatIsNotDigits(_ count: String) {
        let error = #expect(throws: ParseError.self) {
            _ = try displayList(#"\begin{alignedat}{\#(count)}a&=b\end{alignedat}"#)
        }
        #expect(error?.message == "Number of columns should be a positive integer")
    }

    /// `Number("")` and `Number("0")` are both 0, so KaTeX's
    /// `isAligned = !numCols` lays these rows out as `aligned` — one `\quad`
    /// between column pairs — rather than failing. SwaTex threw instead, which
    /// rejected input KaTeX renders.
    @Test(arguments: ["", "0", "000"])
    func anEmptyOrZeroColumnCountLaysOutAsAligned(_ count: String) throws {
        let aligned = try displayList(#"\begin{aligned}a&=b&c&=d\end{aligned}"#)
        let got = try displayList(#"\begin{alignedat}{\#(count)}a&=b&c&=d\end{alignedat}"#)
        #expect(abs(got.width - aligned.width) < 1e-9)
        #expect(got.items.count == aligned.items.count)
        // Not merely error-free: it is the `aligned` layout, a \quad wider than
        // the `alignat` one for the same two column pairs.
        let alignat = try displayList(#"\begin{alignedat}{2}a&=b&c&=d\end{alignedat}"#)
        #expect(abs((got.width - alignat.width) - 1.0) < 1e-6)
    }

    /// Equation 10's tag draws both digits. A symbol node lays out as a single
    /// glyph, so holding the whole number in one node drew "(1)" for 10.
    /// RaTeX 0.1.15 and earlier share the bug; fixed upstream in d7d9bd2a.
    @Test func multiDigitEquationNumbersDrawEveryDigit() throws {
        let tenRows = #"\begin{gather}a\\b\\c\\d\\e\\f\\g\\h\\i\\j\end{gather}"#
        let digits = glyphs(try displayList(tenRows))
            .compactMap { Unicode.Scalar($0.char) }
            .map(Character.init)
            .filter(\.isNumber)
        // Rows carry a…j, so every digit comes from a tag: (1)…(10). "1"
        // appears in (1) and (10), "0" only in (10).
        #expect(digits.filter { $0 == "1" }.count == 2)
        #expect(digits.filter { $0 == "0" }.count == 1)
        #expect(digits.count == 11)
    }
}
