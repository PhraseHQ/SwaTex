import Testing

@testable import SwaTex

/// Coverage for the Layout engine files (and Parser/Environments.swift):
/// each test targets a specific previously-uncovered branch, noted by
/// file/line. Pipeline inputs are preferred; direct component tests are
/// used where no top-level LaTeX input reaches the branch.
@Suite("LayoutCoverage")
struct LayoutCoverageTests {

    private func rendered(
        _ latex: String, style: MathStyle = .display
    ) throws(ParseError) -> DisplayList {
        try SwaTexEngine.displayList(for: latex, style: style)
    }

    // ── Engine.swift 183–186: multiline (\\) inside a \middle two-pass
    //    left-right group rebases the boxFor cache indices per row ─────────
    @Test func multilineInsideMiddleLeftRight() throws {
        let list = try rendered(#"\left( a \middle| b \\ c \right)"#)
        #expect(list.width > 0)
    }

    // ── EngineAccent.swift 202: nested \bar/\= accent clearance ──────────
    @Test(arguments: [#"\bar{\bar{x}}"#, #"\bar{\hat{x}}"#, #"\={\'{x}}"#])
    func nestedBarAccentClearance(_ latex: String) throws {
        let list = try rendered(latex)
        #expect(list.width > 0)
    }

    // ── EngineScripts.swift 77–80: barless fraction min-gap adjustment ───
    @Test(arguments: [
        #"{\displaystyle\int \atop \displaystyle\int}"#,
        #"{\hat{A} \atop \hat{B}}"#,
        #"x_{j \atop q}"#,
        #"{g \atop \hat{X}}"#,
    ])
    func atopMinGapAdjustment(_ latex: String) throws {
        let list = try rendered(latex)
        #expect(list.height > 0)
    }

    // ── EngineArrays.swift 134: hLinesBeforeRow shorter than rows+1 is
    //    padded (parser always emits rows+1; layout() must not rely on it) ─
    @Test func arrayNodeWithMissingHlineEntries() {
        let cell = ParseNode(
            .ordGroup(body: [ParseNode(.mathOrd(text: "x"), mode: .math)], semisimple: nil),
            mode: .math)
        let info = ParseNode.ArrayInfo(
            body: [[cell]], rowGaps: [nil], hLinesBeforeRow: [])
        let node = ParseNode(.array(info), mode: .math)
        let box = layout([node], options: LayoutOptions())
        #expect(box.width > 0)
    }

    // ── EngineOps.swift 143 / 161 / 253: op-char fallback, non-op base
    //    delegation, and limits with neither sup nor sub ───────────────────
    @Test func resolveOpCharFallsBackToFirstScalar() {
        #expect(resolveOpChar("\\notarealopname") == "\\")
        #expect(resolveOpChar("") == "?")
    }

    @Test func opWithLimitsNonOpBaseDelegatesToSupSub() {
        let base = ParseNode(.mathOrd(text: "x"), mode: .math)
        let sup = ParseNode(.mathOrd(text: "2"), mode: .math)
        let box = layoutOpWithLimits(base, sup, nil, LayoutOptions())
        #expect(box.width > 0)
    }

    @Test func opWithLimitsNoScriptsReturnsBase() {
        let base = ParseNode(
            .op(
                limits: true, alwaysHandleSupSub: nil, suppressBaseShift: nil,
                parentIsSupSub: false, symbol: true, name: "\\sum", body: nil),
            mode: .math)
        let box = layoutOpWithLimits(base, nil, nil, LayoutOptions())
        #expect(box.width > 0)
    }

    // ── EngineSymbols.swift 119: math-mode char with metrics only in the
    //    Size fonts (\@char produces a textord) ──────────────────────────
    @Test func charCommandSizeFontMetricsBorrow() throws {
        let display = try rendered(#"\@char{8721}"#, style: .display)
        let inline = try rendered(#"\@char{8721}"#, style: .text)
        #expect(display.width > 0 && inline.width > 0)
    }

    // ── EngineSymbols.swift 189: isArrowAccent default branch ────────────
    @Test func isArrowAccentRejectsNonArrowLabels() {
        #expect(!isArrowAccent("\\widehat"))
        #expect(!isArrowAccent("\\overbrace"))
    }

    // ── EngineMisc.swift 80: isSingleCharBody unwraps styling nodes ──────
    @Test func cancelSingleCharThroughStyling() throws {
        let list = try rendered(#"\cancel{\displaystyle x}"#)
        #expect(list.width > 0)
    }

    // ── EngineMisc.swift 142: layoutCancel default label → no commands ───
    @Test func cancelUnknownLabelProducesNoStrikeCommands() {
        let body = ParseNode(.mathOrd(text: "x"), mode: .math)
        let box = layoutCancel("\\notastrike", body, LayoutOptions())
        #expect(box.width > 0)
    }

    // ── EngineMisc.swift 364–369: xArrow label outside the KaTeX stretchy
    //    table falls back to the generated arrow path ──────────────────────
    @Test func xArrowUnknownLabelFallbackPath() {
        let body = ParseNode(.mathOrd(text: "a"), mode: .math)
        let node = ParseNode(
            .xArrow(label: "\\xnotintable", body: body, below: nil), mode: .math)
        let box = layout([node], options: LayoutOptions())
        #expect(box.width > 0)
    }

    // ── EngineTextStyles.swift 94: CSS declaration without a colon ───────
    @Test func htmlStyleDeclarationWithoutColonIsSkipped() {
        let parsed = parseHtmlStyle("color;font-size:2em")
        #expect(parsed.color == nil)
    }

    // ── EngineTextStyles.swift 164–166: \texttt char fallback fonts ──────
    @Test(arguments: [#"\texttt{×}"#, #"\texttt{中}"#, #"\texttt{±}"#])
    func textttNonTypewriterChars(_ latex: String) throws {
        let list = try rendered(latex)
        #expect(list.width > 0)
    }

    // ── EngineTextStyles.swift 403 / 415 / 433 / 446: link underline
    //    segments and skip-cut recursion ───────────────────────────────────
    @Test(arguments: [
        #"\href{https://a.io}{x}"#,  // no descenders → single full segment
        #"\href{https://a.io}{g}"#,  // descender cut covering the whole width
        #"\href{https://a.io}{go}"#,  // mixed cut + segment
        #"\href{https://a.io}{a\raisebox{1pt}{g}b}"#,  // raiseBox recursion
    ])
    func hrefUnderlineSegments(_ latex: String) throws {
        let list = try rendered(latex)
        #expect(list.width > 0)
    }

    // ── EngineTextStyles.swift 557–558 / 564–565 / 571: nodeMathClass
    //    fall-through branches ────────────────────────────────────────────
    @Test func nodeMathClassFallThroughs() {
        let spacing = ParseNode(.spacing(text: "\\,"), mode: .math)
        let htmlMathML = ParseNode(
            .htmlMathML(html: [spacing], mathml: []), mode: .math)
        #expect(nodeMathClass(htmlMathML) == nil)
        let html = ParseNode(.html(attributes: [:], body: [spacing]), mode: .math)
        #expect(nodeMathClass(html) == nil)
        let accentTok = ParseNode(.accentToken(text: "´"), mode: .math)
        #expect(nodeMathClass(accentTok) == .ord)
    }

    // ── EngineTextStyles.swift 609: getBaseElem unwraps single-child html ─
    @Test func getBaseElemUnwrapsHtmlNode() throws {
        let list = try rendered(#"\htmlClass{c}{i}^2"#)
        #expect(list.width > 0)
    }

    // ── EngineDelims.swift 42–76: nodeContainsMiddle traversal over node
    //    kinds the pipeline rarely nests inside \left…\right ───────────────
    @Test func nodeContainsMiddleTraversesRareContainers() {
        let middle = ParseNode(.middle(delim: "|"), mode: .math)
        let ord = ParseNode(.mathOrd(text: "x"), mode: .math)

        let htmlMathML = ParseNode(
            .htmlMathML(html: [middle], mathml: []), mode: .math)
        #expect(nodeContainsMiddle(htmlMathML, .display))

        let tagged = ParseNode(.tag(body: [ord], tag: [middle]), mode: .math)
        #expect(nodeContainsMiddle(tagged, .display))

        let cell = ParseNode(.ordGroup(body: [ord], semisimple: nil), mode: .math)
        let info = ParseNode.ArrayInfo(
            body: [[cell]], rowGaps: [nil], hLinesBeforeRow: [[false], [false]],
            tags: [.explicit([middle])])
        let array = ParseNode(.array(info), mode: .math)
        #expect(nodeContainsMiddle(array, .display))

        let branch = ProofBranch(
            conclusion: [middle],
            premises: [
                ProofBranch(conclusion: [ord], premises: [], lineStyle: .solid)
            ],
            lineStyle: .solid)
        let proof = ParseNode(.proofTree(tree: branch), mode: .math)
        #expect(nodeContainsMiddle(proof, .display))

        let env = ParseNode(.environment(name: "matrix", nameGroup: middle), mode: .math)
        #expect(nodeContainsMiddle(env, .display))

        let cdLabel = ParseNode(.cdLabel(side: "left", label: middle), mode: .math)
        #expect(nodeContainsMiddle(cdLabel, .display))

        let cdParent = ParseNode(.cdLabelParent(fragment: middle), mode: .math)
        #expect(nodeContainsMiddle(cdParent, .display))

        #expect(!nodeContainsMiddle(ord, .display))
    }

    // ── EngineDelims.swift 324: mapVertPathYToBaseline quad commands ─────
    @Test func mapVertPathQuadCommands() {
        let cmds: [PathCommand] = [
            .moveTo(x: 0, y: 0),
            .quadTo(x1: 0.5, y1: 0.5, x: 1.0, y: 1.0),
            .close,
        ]
        let mapped = mapVertPathYToBaseline(cmds, 1.0, 0.0, 1000)
        #expect(mapped.count == 3)
    }

    // ── EngineDelims.swift 533: sized delimiter with no metrics in the
    //    Size font nor Main-Regular → fixed fallback box ────────────────────
    @Test func sizedDelimMissingGlyphMetricsFallback() {
        let box = layoutDelimSizing(1, "☃", LayoutOptions())
        #expect(box.width == 0.4 && box.height == 0.7 && box.depth == 0.2)
    }

    // ── StackedDelim.swift 163 / 274: stack builders called with a kind
    //    they do not handle return nil ─────────────────────────────────────
    @Test func stackedDelimBuildersRejectForeignKinds() {
        let opts = LayoutOptions()
        #expect(makeTallSvgDelim(.brace(open: true), heightTotal: 3.0, options: opts) == nil)
        #expect(makeGlyphStackDelim(.paren(open: true), heightTotal: 3.0, options: opts) == nil)
    }

    // ── StackedDelim.swift 133: tallDelimSvgPath unknown label ───────────
    @Test func tallDelimSvgPathUnknownLabelIsEmpty() {
        #expect(tallDelimSvgPath("bogus", midTh: 100).isEmpty)
    }

    // ── KaTeXSvg.swift 72–74: twohead uniform scaling of quad commands ───
    @Test func scaleTwoheadUniformQuad() {
        let cmd = PathCommand.quadTo(x1: 100, y1: 100, x: 200, y: 0)
        if case let .quadTo(x1, _, x, _) = scaleCmdTwoheadUniform(
            cmd, s: 0.001, vbCy: 50, xShift: 1.0)
        {
            #expect(x1 == 1.1 && x == 1.2)
        } else {
            Issue.record("expected quadTo")
        }
    }

    // ── KaTeXSvg.swift 411: scaleCmdXY quad commands ─────────────────────
    @Test func scaleXYQuad() {
        let cmd = PathCommand.quadTo(x1: 1, y1: 2, x: 3, y: 4)
        if case let .quadTo(x1, y1, x, y) = scaleCmdXY(cmd, sx: 2.0, sy: 0.5) {
            #expect(x1 == 2 && y1 == 1 && x == 6 && y == 2)
        } else {
            Issue.record("expected quadTo")
        }
    }

    // ── KaTeXSvg.swift 129–131 / 156–164 / 173–174: contour flattening of
    //    implicit-move subpaths, quads, and trailing open contours ─────────
    @Test func flattenContoursQuadAndImplicitBreaks() {
        // Two subpaths without Z between them → moveTo flushes the current
        // contour; the trailing contour has no Z → flushed at the end.
        let cmds = parseSvgPath("M0 0L1 1M2 2Q3 3 4 2L5 5")
        let contours = flattenPathToContours(cmds)
        #expect(contours.count == 2)
        // Quad flattening adds 16 sample points.
        #expect(contours[1].count == 1 + 16 + 1)
    }

    // ── KaTeXSvg.swift 91: clipPathToRect skips degenerate contours ──────
    @Test func clipSkipsSinglePointContours() {
        let cmds = parseSvgPath("M0.5 0.5ZM0 0L1 0L1 1L0 1Z")
        let out = clipPathToRect(cmds, xMin: 0.0, xMax: 1.0, yMin: 0.0, yMax: 1.0)
        #expect(!out.isEmpty)
    }

    // ── KaTeXSvg.swift 221: Liang–Barsky rejects a segment whose entry
    //    parameter exceeds its exit parameter (corner miss) ────────────────
    @Test func clipRejectsCornerMissSegment() {
        let cmds: [PathCommand] = [
            .moveTo(x: -1.0, y: 0.5),
            .lineTo(x: 0.5, y: 2.0),
            .close,
        ]
        let out = clipPathToRect(cmds, xMin: 0.0, xMax: 1.0, yMin: 0.0, yMax: 1.0)
        #expect(out.isEmpty)
    }

    // ── KaTeXSvg.swift 442: parseSvgPath memo clear-on-overflow ──────────
    @Test func svgPathMemoOverflowClears() {
        for i in 0..<600 {
            _ = parseSvgPath("M\(i) 0L\(i) 1")
        }
        #expect(parseSvgPath("M0 0L0 1").count == 2)
    }

    // ── KaTeXSvg.swift 578 / 636: unknown command bytes are skipped and
    //    missing numeric arguments read as 0 ──────────────────────────────
    @Test func svgPathParserToleratesMalformedData() {
        // Unknown command byte "X" is skipped (the numbers then reparse via
        // the implicit-repeat rule; only the skip branch is under test).
        #expect(parseSvgPath("X 1 2").count <= 1)
        let cmds = parseSvgPath("M")
        if case let .moveTo(x, y)? = cmds.first {
            #expect(x == 0 && y == 0)
        } else {
            Issue.record("expected moveTo(0,0)")
        }
    }

    // ── KaTeXSvg.swift 1034–1043: CD vertical-arrow mapping of cubic,
    //    quad, and close commands ─────────────────────────────────────────
    @Test func cdVertMappingHandlesAllCommandKinds() {
        let cmds: [PathCommand] = [
            .moveTo(x: 0, y: 0),
            .lineTo(x: 1, y: 0),
            .cubicTo(x1: 1, y1: 1, x2: 2, y2: 1, x: 2, y: 0),
            .quadTo(x1: 3, y1: 1, x: 4, y: 0),
            .close,
        ]
        let mapped = mapPathXYHorizontalToVerticalCd(cmds) { x, y in (y, x) }
        #expect(mapped.count == 5)
        if case let .quadTo(x1, y1, x, y) = mapped[3] {
            #expect(x1 == 1 && y1 == 3 && x == 0 && y == 4)
        } else {
            Issue.record("expected quadTo")
        }
    }

    // ── Environments.swift: array column alignment forms ─────────────────
    @Test func arrayUnbracedSymbolColalign() throws {
        let list = try rendered(#"\begin{array}c a\end{array}"#)
        #expect(list.width > 0)
    }

    @Test func arrayInvalidColalignThrows() {
        #expect(throws: ParseError.self) {
            try SwaTexEngine.displayList(for: #"\begin{array}\frac ab d\end{array}"#)
        }
    }

    @Test func subarrayUnbracedSymbolColalign() throws {
        let list = try rendered(#"\begin{subarray}c a\end{subarray}"#)
        #expect(list.width > 0)
    }

    @Test func subarrayInvalidColalignThrows() {
        #expect(throws: ParseError.self) {
            try SwaTexEngine.displayList(for: #"\begin{subarray}\frac ab d\end{subarray}"#)
        }
    }

    // ── Environments.swift 160: empty \tag{} suppresses numbering ────────
    @Test func emptyTagSuppressesNumber() throws {
        let list = try rendered(#"\begin{align}a\tag{}\end{align}"#)
        #expect(list.width > 0)
    }

    // ── Environments.swift 125–126: tag/nonumber write-back into an
    //    unstyled cell (style-nil environment) ─────────────────────────────
    @Test(arguments: [
        #"\begin{matrix}a\nonumber\end{matrix}"#,
        #"\begin{array}{c}a\nonumber\end{array}"#,
    ])
    func nonumberInUnstyledCell(_ latex: String) throws {
        let list = try rendered(latex)
        #expect(list.width > 0)
    }

    // ── Environments.swift 229: \arraystretch defined as a text macro ────
    @Test func arraystretchTextMacro() throws {
        let parser = Parser(#"\begin{array}{c}a\\b\end{array}"#)
        parser.gullet.setTextMacro("\\arraystretch", "2.0")
        let nodes = try parser.parse()
        let box = layout(nodes, options: LayoutOptions())
        #expect(box.height + box.depth > 0)
    }

    // ── Environments.swift 284–293: trailing empty rows across styles ────
    @Test(arguments: [
        #"\begin{matrix}a\\\end{matrix}"#,
        #"\begin{smallmatrix}a\\\end{smallmatrix}"#,
        #"\begin{aligned}a\\\end{aligned}"#,
        #"\begin{array}{c}a\\\end{array}"#,
    ])
    func trailingEmptyRows(_ latex: String) throws {
        let list = try rendered(latex)
        #expect(list.width > 0)
    }

    // ── Environments.swift 633: aligned row wider than the first row ─────
    @Test func alignedLaterRowAddsColumns() throws {
        let list = try rendered(#"\begin{aligned}a\\b&=c&d\end{aligned}"#)
        #expect(list.width > 0)
    }

    // ── Environments.swift 966 / 973 / 981: CD row shapes ────────────────
    @Test(arguments: [
        #"\begin{CD}A @>>> B\\@VVV @.\\C @= D\end{CD}"#,
        #"\begin{CD}A @>>> B\\@. @VVV\\C @>>> D\end{CD}"#,
        #"\begin{CD}A @>a>> B @>>b> C\end{CD}"#,
    ])
    func cdRowShapes(_ latex: String) throws {
        let list = try rendered(latex)
        #expect(list.width > 0)
    }

    // ── Environments.swift 160: \tag*{} (starred, empty) → suppressed ────
    @Test func emptyStarredTagSuppressesNumber() throws {
        let list = try rendered(#"\begin{align}a\tag*{}\end{align}"#)
        #expect(list.width > 0)
    }

    // ── Environments.swift 966 / 973 / 981: cdStructureRow cell shapes the
    //    tokenizer cannot produce at row edges (lexer eats leading spaces) ──
    @Test func cdStructureRowDirectShapes() {
        let arrow = ParseNode(
            .cdArrow(direction: "down", labelAbove: nil, labelBelow: nil), mode: .math)
        let empty = ParseNode(.ordGroup(body: [], semisimple: nil), mode: .math)
        let sup = ParseNode(
            .supSub(base: ParseNode(.mathOrd(text: "x"), mode: .math), sup: nil, sub: nil),
            mode: .math)

        // Leading empty cell before the first arrow → contains/filter skip it.
        let arrowRow = cdStructureRow([empty, arrow, empty, arrow], .math)
        #expect(arrowRow.count == 3)

        // A cell that is neither CdArrow nor OrdGroup → object row unchanged.
        let objectRow = cdStructureRow([sup, arrow], .math)
        #expect(objectRow.count == 2)
    }

    // ── EngineAccent.swift 154–155: non-shifty, non-arrow accent skew 0 ──
    @Test func nonShiftyAccentZeroSkew() {
        let base = ParseNode(.mathOrd(text: "x"), mode: .math)
        let box = layoutAccent("\\'", base, false, false, false, LayoutOptions())
        #expect(box.width > 0)
    }

    // ── EngineTextStyles.swift 164–166: \verb char font fallbacks ────────
    @Test(arguments: [#"\verb|×|"#, #"\verb|中|"#, #"\verb|±|"#])
    func verbNonTypewriterChars(_ latex: String) throws {
        let list = try rendered(latex)
        #expect(list.width > 0)
    }

    // ── EngineTextStyles.swift 403 / 415 / 433 / 446: typewriter link
    //    underline segments (only \url / typewriter bodies take this path) ─
    @Test(arguments: [
        #"\url{aa}"#,  // no descenders → single full-width segment
        #"\url{g}"#,  // descender cut spanning nearly the whole width
        #"\url{ag.io}"#,  // mixed cuts and segments
        #"\href{https://x.io}{\texttt{a\raisebox{1pt}{g}b}}"#,  // raiseBox recursion
        #"\href{https://x.io}{\tiny\texttt{g}}"#,  // scaled recursion, all-cut width
        #"\href{https://x.io}{\scriptsize\texttt{ag}}"#,  // scaled recursion + segments
    ])
    func urlUnderlineSegments(_ latex: String) throws {
        let list = try rendered(latex)
        #expect(list.width > 0)
    }

    // ── EngineTextStyles.swift 609/611: getBaseElem unwraps single-child
    //    color and html wrappers ───────────────────────────────────────────
    @Test func getBaseElemUnwrapsColorAndHtml() {
        let inner = ParseNode(.mathOrd(text: "i"), mode: .math)
        let html = ParseNode(.html(attributes: [:], body: [inner]), mode: .math)
        let color = ParseNode(.color(color: "red", body: [inner]), mode: .math)
        for wrapped in [html, color] {
            if case .mathOrd = getBaseElem(wrapped).kind {
            } else {
                Issue.record("expected unwrap to mathOrd")
            }
        }
    }

    // ── KaTeXSvg.swift 221: Liang–Barsky y-min rejection after t1 was
    //    tightened by the x-max clip ───────────────────────────────────────
    @Test func clipRejectsSegmentBelowRect() {
        let cmds: [PathCommand] = [
            .moveTo(x: 0.5, y: -2.0),
            .lineTo(x: 1.5, y: 0.0),
            .close,
        ]
        let out = clipPathToRect(cmds, xMin: 0.0, xMax: 1.0, yMin: 0.0, yMax: 1.0)
        #expect(out.isEmpty)
    }

    // ── EngineSymbols.swift: every math-alphanumeric codepoint maps to a
    //    font with metrics (guards the INTENTIONALLY UNCOVERED fallback) ───
    @Test func mathAlphanumericAlwaysHasMetrics() {
        for cp in UInt32(0x1D400)...0x1D7FF {
            if let (font, metric) = FontId.mathAlphanumeric(cp) {
                #expect(font.metrics(forChar: metric) != nil)
            }
        }
    }

    // ── Environments.swift 1093: \prftree with no argument ───────────────
    @Test func prftreeMissingArgumentThrows() {
        #expect(throws: ParseError.self) {
            try SwaTexEngine.displayList(for: #"\prftree"#)
        }
    }
}
