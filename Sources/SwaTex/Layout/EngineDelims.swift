// Left/Right stretchy delimiters and \big/\Big/\bigg/\Bigg sizing.
// Port of crates/ratex-layout/src/engine.rs (lines 2016–2656).

/// Returns true if the node (or any descendant in the current `\left...\right`
/// scope) is a Middle node.  A nested LeftRight starts its own scope, so its
/// `\middle`s are handled by that nested layout pass.
///
/// Iterative on purpose: this pre-scan walks the whole body *before*
/// `layoutNode`'s stack guard can bound it, and adversarial trees are deep
/// without being large (a combining-accent chain nests one level per mark).
/// A worklist never grows the call stack, so no guard is needed.
///
/// The switch is exhaustive (no `default`): body-bearing kinds silently
/// defaulting to false froze `\middle` inside `\hbox` at its invisible
/// first-pass placeholder — a new node kind must state its answer.
func nodeContainsMiddle(_ node: ParseNode, _ style: MathStyle) -> Bool {
    var work: [(ParseNode, MathStyle)] = [(node, style)]
    while let (node, style) = work.popLast() {
        switch node.kind {
        case .middle:
            return true

        // A nested \left…\right scope stretches its own \middle delimiters.
        case .leftRight:
            continue

        // Leaves: symbols, tokens, and body-less commands.
        case .atom, .mathOrd, .textOrd, .opToken, .accentToken, .spacing,
            .colorToken, .size, .delimSizing, .leftRightRight, .rule, .kern,
            .cr, .infix, .internalNode, .verb, .url, .raw, .noNumber,
            .includeGraphics:
            continue

        // Same-style node lists.
        case let .ordGroup(body, _), let .mclass(_, body, _), let .color(_, body),
            let .phantom(body), let .pmb(_, body), let .href(_, body),
            let .html(_, body), let .operatorName(body, _, _, _):
            for child in body { work.append((child, style)) }
        case let .op(_, _, _, _, _, _, body):
            for child in body ?? [] { work.append((child, style)) }
        case let .htmlMathML(html, _):
            for child in html { work.append((child, style)) }
        case let .tag(body, tag):
            for child in body { work.append((child, style)) }
            for child in tag { work.append((child, style)) }
        case let .array(info):
            for row in info.body {
                for cell in row { work.append((cell, style)) }
            }
            for tag in info.tags ?? [] {
                if case let .explicit(nodes) = tag {
                    for child in nodes { work.append((child, style)) }
                }
            }
        case let .proofTree(tree):
            var branches = [tree]
            while let branch = branches.popLast() {
                for child in branch.conclusion { work.append((child, style)) }
                branches.append(contentsOf: branch.premises)
            }

        // Single same-style children.
        case let .font(_, body), let .overline(body), let .underline(body),
            let .vphantom(body), let .smash(body, _, _),
            let .enclose(_, _, _, body), let .lap(_, body),
            let .raiseBox(_, body), let .vcenter(body):
            work.append((body, style))
        case let .accent(_, _, _, base), let .accentUnder(_, _, _, base),
            let .horizBrace(_, _, base):
            work.append((base, style))
        case let .environment(_, nameGroup):
            work.append((nameGroup, style))
        case let .cdLabel(_, label):
            work.append((label, style))
        case let .cdLabelParent(fragment):
            work.append((fragment, style))

        // Style-adjusting containers (style feeds mathChoice below).
        case let .supSub(base, sup, sub):
            if let base { work.append((base, style)) }
            if let sup { work.append((sup, style.superscript)) }
            if let sub { work.append((sub, style.subscript_)) }
        case let .genfrac(_, numer, denom, _, _, _, _):
            work.append((numer, style.numerator))
            work.append((denom, style.denominator))
        case let .sqrt(body, index):
            work.append((body, style.cramped))
            if let index { work.append((index, style.superscript.superscript)) }
        case let .text(body, _), let .sizing(_, body), let .hbox(body):
            for child in body { work.append((child, style.textEquivalent)) }
        case let .styling(nodeStyle, body):
            let newStyle = styleStrToMathStyle(nodeStyle)
            for child in body { work.append((child, newStyle)) }
        case let .xArrow(_, body, below):
            work.append((body, style.superscript))
            if let below { work.append((below, style.subscript_)) }
        case let .cdArrow(_, labelAbove, labelBelow):
            if let labelAbove { work.append((labelAbove, style.superscript)) }
            if let labelBelow { work.append((labelBelow, style.subscript_)) }
        case let .mathChoice(display, text, script, scriptscript):
            let branch = style.mathChoiceBranch(
                display: display, text: text, script: script, scriptscript: scriptscript)
            for child in branch { work.append((child, style)) }
        }
    }
    return false
}

extension MathStyle {
    /// Selects the `\mathchoice` branch for this style. Shared by layout
    /// dispatch and the `\middle` containment scan so the two can never
    /// disagree about which branch renders (a divergence would let the scan
    /// miss a `\middle` the layout reaches — the invisible-delimiter class).
    func mathChoiceBranch<T>(display: T, text: T, script: T, scriptscript: T) -> T {
        switch self {
        case .display, .displayCramped: display
        case .text, .textCramped: text
        case .script, .scriptCramped: script
        case .scriptScript, .scriptScriptCramped: scriptscript
        }
    }
}

/// Returns true if any node in the slice contains a Middle node governed by the
/// current `\left...\right` pass.
func bodyContainsMiddle(_ nodes: [ParseNode], _ style: MathStyle) -> Bool {
    nodes.contains { nodeContainsMiddle($0, style) }
}

/// KaTeX genfrac HTML Rule 15e: `\binom`, `\brace`, `\brack`, `\atop` use
/// `delim1`/`delim2` from font metrics, not the `\left`/`\right` height formula
/// (`makeLeftRightDelim` vs genfrac).
func genfracDelimTargetHeight(_ options: LayoutOptions) -> Double {
    let m = options.metrics
    if options.style.isDisplay {
        return m.delim1
    } else if options.style == .scriptScript || options.style == .scriptScriptCramped {
        return options.with(style: .script).metrics.delim2
    } else {
        return m.delim2
    }
}

/// Required total height for `\left`/`\right` stretchy delimiters (TeX `\sigma_4` rule).
func leftRightDelimTotalHeight(_ inner: LayoutBox, _ options: LayoutOptions) -> Double {
    let metrics = options.metrics
    let innerHeight = inner.height
    let innerDepth = inner.depth
    let axis = metrics.axisHeight
    let maxDist = max(innerHeight - axis, innerDepth + axis)
    let delimFactor = 901.0
    let delimExtend = 5.0 / metrics.ptPerEm
    let fromFormula = max(maxDist / 500 * delimFactor, 2 * maxDist - delimExtend)
    // Ensure delimiter is at least as tall as inner content
    return max(fromFormula, innerHeight + innerDepth)
}

/// Maximum nesting of `\left…\middle…\right` stretch passes. A stretch pass
/// re-lays the `\middle`-bearing subtrees of its body, so nesting them inside
/// each other multiplies work per level; beyond this depth the body is laid
/// out ONCE with the delimiters' natural height — `\middle` still renders
/// visible (unstretched) ink, the cap only bounds work. Real formulas nest
/// a handful of levels at most — this only bounds adversarial input.
let maxMiddleStretchDepth = 8

/// Natural font-glyph height of a delimiter in em (MainRegular `|`:
/// 0.75 + 0.25). One constant shared by the `\middle` first-pass placeholder
/// width basis (Engine.swift), the over-cap fallback height below, and the
/// stack-vs-glyph threshold in `makeStretchyDelim` — these must agree or a
/// capped `\middle` renders at a height whose width basis mismatches its
/// reserved placeholder.
let naturalDelimHeightEm = 1.0

/// Delimiter height handed to `\middle` beyond `maxMiddleStretchDepth`:
/// the natural glyph height, so capped output degrades to unstretched —
/// never invisible.
private let middleFallbackDelimHeight = naturalDelimHeightEm

func layoutLeftRight(
    _ body: [ParseNode], _ leftDelim: String, _ rightDelim: String,
    _ options: LayoutOptions
) -> LayoutBox {
    let inner: LayoutBox
    let totalHeight: Double
    // Trigger on the first `\middle` (short-circuits, no allocation in the
    // common no-`\middle` case); the per-child array is built only in the
    // two-pass branch that actually consumes it.
    if bodyContainsMiddle(body, options.style) {
        var options = options
        options.middlePassDepth += 1
        if options.middlePassDepth > maxMiddleStretchDepth {
            // Past the adversarial-nesting cap: one pass at natural delim
            // height. Costs the same as the first pass it replaces, and
            // keeps every \middle visible instead of zero-ink.
            var optsCapped = options
            optsCapped.leftrightDelimHeight = middleFallbackDelimHeight
            inner = layoutExpression(body, optsCapped, isRealGroup: true)
            totalHeight = leftRightDelimTotalHeight(inner, options)
        } else {
            // First pass: layout with no delim height so \middle doesn't
            // inflate inner size. Keep each child box — subtrees without a
            // `\middle` in this scope are identical in both passes (nested
            // \left…\right groups override the delim height themselves), so
            // the stretch pass reuses them instead of exponentially
            // re-laying nested groups.
            var optsFirst = options
            optsFirst.leftrightDelimHeight = nil
            let childBoxes = body.map { layoutNode($0, optsFirst) }
            let innerFirst = layoutExpression(body, optsFirst, isRealGroup: true) { i, _ in
                childBoxes[i]
            }
            totalHeight = leftRightDelimTotalHeight(innerFirst, options)
            // Per-child containment, computed once and reused by the stretch
            // pass to decide which subtrees must re-lay (the rest are reused).
            let childHasMiddle = body.map { nodeContainsMiddle($0, options.style) }
            // Second pass: stretch \middle to match \left and \right.
            var optsSecond = options
            optsSecond.leftrightDelimHeight = totalHeight
            inner = layoutExpression(body, optsSecond, isRealGroup: true) { i, node in
                childHasMiddle[i] ? layoutNode(node, optsSecond) : childBoxes[i]
            }
        }
    } else {
        inner = layoutExpression(body, options, isRealGroup: true)
        totalHeight = leftRightDelimTotalHeight(inner, options)
    }

    let leftBox = makeStretchyDelim(leftDelim, totalHeight, options)
    let rightBox = makeStretchyDelim(rightDelim, totalHeight, options)

    return LayoutBox(
        width: leftBox.width + inner.width + rightBox.width,
        height: max(leftBox.height, rightBox.height, inner.height),
        depth: max(leftBox.depth, rightBox.depth, inner.depth),
        content: .leftRight(left: leftBox, right: rightBox, inner: inner),
        color: options.color)
}

private let delimFontSequence: [FontId] = [
    .mainRegular, .size1Regular, .size2Regular, .size3Regular, .size4Regular,
]

/// Normalize angle-bracket delimiter aliases to \langle / \rangle.
func normalizeDelim(_ delim: String) -> String {
    switch delim {
    case "<", "\\lt", "\u{27E8}": "\\langle"
    case ">", "\\gt", "\u{27E9}": "\\rangle"
    default: delim
    }
}

/// Return true if delimiter should be rendered as a single vertical bar SVG path.
func isVertDelim(_ delim: String) -> Bool {
    switch delim {
    case "|", "\\vert", "\\lvert", "\\rvert": true
    default: false
    }
}

/// Return true if delimiter should be rendered as a double vertical bar SVG path.
func isDoubleVertDelim(_ delim: String) -> Bool {
    switch delim {
    case "\\|", "\\Vert", "\\lVert", "\\rVert": true
    default: false
    }
}

/// KaTeX `delimiter.makeStackedDelim`: total span of one repeat piece
/// (U+2223 / U+2225) in Size1-Regular.
func vertRepeatPieceHeight(isDouble: Bool) -> Double {
    let code: UInt32 = isDouble ? 8741 : 8739
    return FontId.size1Regular.metrics(forChar: code).map { $0.height + $0.depth } ?? 0.5
}

/// Match KaTeX `realHeightTotal` for stack-always `|` / `\Vert` delimiters.
func katexVertRealHeight(
    _ requestedTotal: Double, isDouble: Bool, isSizedDelim: Bool
) -> Double {
    let piece = vertRepeatPieceHeight(isDouble: isDouble)
    let minH = 2 * piece
    let repeatCount = max(((requestedTotal - minH) / piece).rounded(.up), 0)
    var h = minH + repeatCount * piece
    // KaTeX's sized vertical bars are CSS SVG spans with a slightly taller ink
    // crop in browser screenshots than our native path rasterization. Keep this
    // adjustment scoped to \big/\Big/\bigg/\Bigg so ordinary stretchy \left bars
    // still follow content height directly.
    if isSizedDelim && !isDouble {
        h *= requestedTotal < 3.0 ? 1.2 : 1.135
    }
    return h
}

/// KaTeX `svgGeometry.tallDelim` paths for `"vert"` / `"doublevert"`
/// (viewBox units per em width).
func tallVertSvgPathData(midTh: Int, isDouble: Bool) -> String {
    let neg = -midTh
    if !isDouble {
        return
            "M145 15 v585 v\(midTh) v585 c2.667,10,9.667,15,21,15 c10,0,16.667,-5,20,-15 v-585 v\(neg) v-585 c-2.667,-10,-9.667,-15,-21,-15 c-10,0,-16.667,5,-20,15z M188 15 H145 v585 v\(midTh) v585 h43z"
    } else {
        return
            "M145 15 v585 v\(midTh) v585 c2.667,10,9.667,15,21,15 c10,0,16.667,-5,20,-15 v-585 v\(neg) v-585 c-2.667,-10,-9.667,-15,-21,-15 c-10,0,-16.667,5,-20,15z M188 15 H145 v585 v\(midTh) v585 h43z M367 15 v585 v\(midTh) v585 c2.667,10,9.667,15,21,15 c10,0,16.667,-5,20,-15 v-585 v\(neg) v-585 c-2.667,-10,-9.667,-15,-21,-15 c-10,0,-16.667,5,-20,15z M410 15 H367 v585 v\(midTh) v585 h43z"
    }
}

/// Map KaTeX top-origin SVG y (after ×0.001) to baseline coords
/// (top −height, bottom +depth).
func mapVertPathYToBaseline(
    _ cmds: [PathCommand], _ height: Double, _ depth: Double, _ viewBoxHeight: Int
) -> [PathCommand] {
    let spanEm = Double(viewBoxHeight) / 1000
    let total = height + depth
    let scaleY = spanEm > 0 ? total / spanEm : 1
    return cmds.map { c in
        switch c {
        case let .moveTo(x, y): .moveTo(x: x, y: -height + y * scaleY)
        case let .lineTo(x, y): .lineTo(x: x, y: -height + y * scaleY)
        case let .cubicTo(x1, y1, x2, y2, x, y):
            .cubicTo(
                x1: x1, y1: -height + y1 * scaleY,
                x2: x2, y2: -height + y2 * scaleY,
                x: x, y: -height + y * scaleY)
        case let .quadTo(x1, y1, x, y):
            .quadTo(x1: x1, y1: -height + y1 * scaleY, x: x, y: -height + y * scaleY)
        case .close: .close
        }
    }
}

func makeShortmidBox(_ options: LayoutOptions) -> LayoutBox {
    let total = 0.675
    let axis = options.metrics.axisHeight
    let depth = max(total / 2 - axis, 0)
    let height = total - depth
    let raw = parseSvgPathData(tallVertSvgPathData(midTh: 0, isDouble: false))
    let scaled = raw.scaled(by: 0.001)
    let commands = mapVertPathYToBaseline(scaled, height, depth, 1170)
    return LayoutBox(
        width: 0.22222, height: height, depth: depth,
        content: .svgPath(commands: commands, fill: true),
        color: options.color)
}

func makeTextunderscoreBox(_ options: LayoutOptions) -> LayoutBox {
    LayoutBox(
        width: 0.65, height: 0, depth: 0.31,
        content: .rule(thickness: 0.08, raise: -0.31),
        color: options.color)
}

func makeCorrespondsSymbol(_ options: LayoutOptions) -> LayoutBox {
    let width = 1.16
    let height = 0.55
    let depth = 0.24
    let ruleThickness = 0.055
    let arc = LayoutBox(
        width: width, height: 0.36, depth: 0,
        content: .svgPath(
            commands: [
                .moveTo(x: 0.02, y: 0),
                .cubicTo(x1: 0.18, y1: -0.34, x2: 0.64, y2: -0.34, x: 0.80, y: 0),
            ],
            fill: false),
        color: options.color)

    return LayoutBox(
        width: width, height: height, depth: depth,
        content: .proofTree(
            children: [PlacedBox(box: arc, x: 0, baselineY: 0.36)],
            rules: [
                ProofRule(x: 0.28, y: 0.48, width: 0.86, thickness: ruleThickness, dashed: false),
                ProofRule(x: 0.28, y: 0.68, width: 0.86, thickness: ruleThickness, dashed: false),
            ]),
        color: options.color)
}

func makeMeasuredBySymbol(_ options: LayoutOptions) -> LayoutBox {
    let width = 0.98
    let height = 0.56
    let depth = 0.30
    let ruleThickness = 0.055
    let mCode = UInt32(UInt8(ascii: "m"))
    let mMetrics = FontId.mainRegular.metrics(forChar: mCode)
    let (mWidth, mHeight, mDepth) =
        mMetrics.map { ($0.width, $0.height, $0.depth) } ?? (0.78, 0.43, 0.0)
    let mScale = 0.61
    let mGlyph = LayoutBox(
        width: mWidth, height: mHeight, depth: mDepth,
        content: .glyph(fontId: .mainRegular, charCode: mCode),
        color: options.color)
    let mBox = LayoutBox(
        width: mWidth * mScale, height: mHeight * mScale, depth: mDepth * mScale,
        content: .scaled(body: mGlyph, childScale: mScale),
        color: options.color)

    return LayoutBox(
        width: width, height: height, depth: depth,
        content: .proofTree(
            children: [
                PlacedBox(
                    box: mBox, x: (width - mWidth * mScale) / 2,
                    baselineY: 0.02 + mHeight * mScale)
            ],
            rules: [
                ProofRule(x: 0.06, y: 0.55, width: 0.86, thickness: ruleThickness, dashed: false),
                ProofRule(x: 0.06, y: 0.78, width: 0.86, thickness: ruleThickness, dashed: false),
            ]),
        color: options.color)
}

/// Build a vertical-bar delimiter LayoutBox using the same SVG as KaTeX `tallDelim`
/// (`vert` / `doublevert`). `totalHeight` is the requested full span in em
/// (`sizeToMaxHeight` for `\big`/`\Big`/…).
func makeVertDelimBox(
    _ totalHeight: Double, isDouble: Bool, isSizedDelim: Bool, _ options: LayoutOptions
) -> LayoutBox {
    let realH = katexVertRealHeight(totalHeight, isDouble: isDouble, isSizedDelim: isSizedDelim)
    let axis = options.metrics.axisHeight
    let depth = max(realH / 2 - axis, 0)
    let height = realH - depth
    let width = isDouble ? 0.556 : 0.333

    let piece = vertRepeatPieceHeight(isDouble: isDouble)
    let midEm = max(realH - 2 * piece, 0)
    let midTh = Int((midEm * 1000).rounded())
    let viewBoxHeight = Int((realH * 1000).rounded())

    let d = tallVertSvgPathData(midTh: midTh, isDouble: isDouble)
    let raw = parseSvgPathData(d)
    let scaled = raw.scaled(by: 0.001)
    let commands = mapVertPathYToBaseline(scaled, height, depth, viewBoxHeight)

    return LayoutBox(
        width: width, height: height, depth: depth,
        content: .svgPath(commands: commands, fill: true),
        color: options.color)
}

/// Select a delimiter glyph large enough for the given total height.
func makeStretchyDelim(
    _ delim: String, _ totalHeight: Double, _ options: LayoutOptions
) -> LayoutBox {
    if delim == "." || delim.isEmpty {
        return .kern(0)
    }

    // stackAlwaysDelimiters: use SVG path only when the required height exceeds
    // the natural font-glyph height (1.0em for single vert, same for double).
    // When the content is small enough, fall through to the normal font glyph.
    let vertNaturalHeight = naturalDelimHeightEm
    if isVertDelim(delim) && totalHeight > vertNaturalHeight {
        return makeVertDelimBox(totalHeight, isDouble: false, isSizedDelim: false, options)
    }
    if isDoubleVertDelim(delim) && totalHeight > vertNaturalHeight {
        return makeVertDelimBox(totalHeight, isDouble: true, isSizedDelim: false, options)
    }

    // Normalize < > to \langle \rangle for proper angle bracket glyphs
    let delim = normalizeDelim(delim)

    let ch = resolveSymbolChar(delim, .math)
    let charCode = ch.value

    var bestFont = FontId.mainRegular
    var bestW = 0.4
    var bestH = 0.7
    var bestD = 0.2

    for fontId in delimFontSequence {
        if let m = fontId.metrics(forChar: charCode) {
            bestFont = fontId
            bestW = m.width
            bestH = m.height
            bestD = m.depth
            if bestH + bestD >= totalHeight {
                break
            }
        }
    }

    let bestTotal = bestH + bestD
    if let stacked = makeStackedDelimIfNeeded(
        delim, totalHeight: totalHeight, bestGlyphTotal: bestTotal, options: options)
    {
        return stacked
    }

    return LayoutBox(
        width: bestW, height: bestH, depth: bestD,
        content: .glyph(fontId: bestFont, charCode: charCode),
        color: options.color)
}

/// Fixed total heights for \big/\Big/\bigg/\Bigg (sizeToMaxHeight from KaTeX).
private let sizeToMaxHeight: [Double] = [0.0, 1.2, 1.8, 2.4, 3.0]

/// Layout \big, \Big, \bigg, \Bigg delimiters.
func layoutDelimSizing(_ size: UInt8, _ delim: String, _ options: LayoutOptions) -> LayoutBox {
    if delim == "." || delim.isEmpty {
        return .kern(0)
    }

    // stackAlwaysDelimiters: render as SVG path at the fixed size height
    if isVertDelim(delim) {
        let total = sizeToMaxHeight[Int(min(size, 4))]
        return makeVertDelimBox(total, isDouble: false, isSizedDelim: true, options)
    }
    if isDoubleVertDelim(delim) {
        let total = sizeToMaxHeight[Int(min(size, 4))]
        return makeVertDelimBox(total, isDouble: true, isSizedDelim: true, options)
    }

    // Normalize angle brackets to proper math angle bracket glyphs
    let delim = normalizeDelim(delim)

    let ch = resolveSymbolChar(delim, .math)
    let charCode = ch.value

    let fontId: FontId =
        switch size {
        case 2: .size2Regular
        case 3: .size3Regular
        case 4: .size4Regular
        default: .size1Regular
        }

    let (width, height, depth, actualFont): (Double, Double, Double, FontId)
    if let m = fontId.metrics(forChar: charCode) {
        (width, height, depth, actualFont) = (m.width, m.height, m.depth, fontId)
    } else if let m = FontId.mainRegular.metrics(forChar: charCode) {
        (width, height, depth, actualFont) = (m.width, m.height, m.depth, .mainRegular)
    } else {
        (width, height, depth, actualFont) = (0.4, 0.7, 0.2, .mainRegular)
    }

    return LayoutBox(
        width: width, height: height, depth: depth,
        content: .glyph(fontId: actualFont, charCode: charCode),
        color: options.color)
}
