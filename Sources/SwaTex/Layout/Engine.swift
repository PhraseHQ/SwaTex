// Layout engine core: expression layout, spacing, and the per-node dispatcher.
// Port of crates/ratex-layout/src/engine.rs (part 1: lines 1–650).

/// TeX `\nulldelimiterspace` = 1.2pt = 0.12em (at 10pt design size).
/// KaTeX wraps every `\frac` / `\atop` in mopen+mclose nulldelimiter spans of this width.
let nullDelimiterSpace = 0.12

func styleStrToMathStyle(_ style: StyleStr) -> MathStyle {
    switch style {
    case .display: .display
    case .text: .text
    case .script: .script
    case .scriptscript: .scriptScript
    }
}

/// Main entry point: lay out a list of ParseNodes into a LayoutBox.
public func layout(_ nodes: [ParseNode], options: LayoutOptions) -> LayoutBox {
    layoutExpression(nodes, options, isRealGroup: true)
}

/// KaTeX `binLeftCanceller` / `binRightCanceller` (TeXbook p.442–446, Rules 5–6).
/// Binary operators become ordinary in certain contexts so spacing matches TeX/KaTeX.
func applyBinCancellation(_ raw: [MathClass?]) -> [MathClass?] {
    let n = raw.count
    var eff = raw
    for i in 0..<n where raw[i] == .bin {
        let prev = i == 0 ? nil : raw[i - 1]
        let leftCancel =
            switch prev {
            case nil, .bin, .open, .rel, .op, .punct: true
            default: false
            }
        if leftCancel {
            eff[i] = .ord
        }
    }
    for i in 0..<n where raw[i] == .bin {
        let next = i + 1 < n ? raw[i + 1] : nil
        let rightCancel =
            switch next {
            case nil, .rel, .close, .punct: true
            default: false
            }
        if rightCancel {
            eff[i] = .ord
        }
    }
    return eff
}

/// KaTeX HTML: `\middle` delimiters are built with class `delimsizing`, which
/// `getTypeOfDomTree` does not map to a math atom type, so **no** implicit
/// table glue is inserted next to them (buildHTML.js). SwaTex must match that or
/// `\frac` (Inner) gains spurious 3mu on each side of every `\middle\vert`.
private func nodeIsMiddleFence(_ node: ParseNode) -> Bool {
    if case .middle = node.kind { return true }
    return false
}

/// Lay out an expression (list of nodes) as a horizontal sequence with spacing.
func layoutExpression(
    _ nodes: [ParseNode], _ options: LayoutOptions, isRealGroup: Bool
) -> LayoutBox {
    if nodes.isEmpty {
        return .empty
    }

    // Check for line breaks (\\, \newline) — split into rows stacked in a VBox
    let hasCr = nodes.contains { node in
        if case .cr = node.kind { return true }
        return false
    }
    if hasCr {
        return layoutMultiline(nodes, options, isRealGroup: isRealGroup)
    }

    let rawClasses = nodes.map(nodeMathClass)
    let effClasses = applyBinCancellation(rawClasses)

    var children: [LayoutBox] = []
    var prevClass: MathClass?
    // Index of the last node that contributed `prevClass` (for `\middle` glue suppression).
    var prevClassNodeIdx: Int?

    for (i, node) in nodes.enumerated() {
        let lbox = layoutNode(node, options)
        let curClass = i < effClasses.count ? effClasses[i] : nil

        if isRealGroup, let prev = prevClass, let cur = curClass {
            let prevMiddle = prevClassNodeIdx.map { nodeIsMiddleFence(nodes[$0]) } ?? false
            let curMiddle = nodeIsMiddleFence(node)
            var mu =
                prevMiddle || curMiddle
                ? 0.0
                : atomSpacing(prev, cur, tight: options.style.isTight)
            if let cap = options.alignRelationSpacing, prev == .rel || cur == .rel {
                mu = min(mu, cap)
            }
            if mu > 0 {
                children.append(.kern(muToEm(mu, quad: options.metrics.quad)))
            }
        }

        if curClass != nil {
            prevClass = curClass
            prevClassNodeIdx = i
        }

        children.append(lbox)
    }

    return makeHBox(children)
}

/// Layout an expression containing line-break nodes (\\, \newline) as a VBox.
private func layoutMultiline(
    _ nodes: [ParseNode], _ options: LayoutOptions, isRealGroup: Bool
) -> LayoutBox {
    let metrics = options.metrics
    let pt = 1.0 / metrics.ptPerEm
    let baselineskip = 12.0 * pt  // standard TeX baselineskip
    let lineskip = 1.0 * pt  // minimum gap between lines

    // Split nodes at Cr boundaries
    var rows: [ArraySlice<ParseNode>] = []
    var start = 0
    for (i, node) in nodes.enumerated() {
        if case .cr = node.kind {
            rows.append(nodes[start..<i])
            start = i + 1
        }
    }
    rows.append(nodes[start...])

    let rowBoxes = rows.map { layoutExpression(Array($0), options, isRealGroup: isRealGroup) }

    let totalWidth = rowBoxes.map(\.width).reduce(0, max)

    var vchildren: [VBoxChild] = []
    var h = rowBoxes.first?.height ?? 0
    let d = rowBoxes.last?.depth ?? 0
    for (i, row) in rowBoxes.enumerated() {
        if i > 0 {
            // TeX baselineskip: gap = baselineskip - prevDepth - curHeight
            let prevDepth = rowBoxes[i - 1].depth
            let gap = max(baselineskip - prevDepth - row.height, lineskip)
            vchildren.append(VBoxChild(.kern(gap)))
            h += gap + row.height + prevDepth
        }
        vchildren.append(VBoxChild(.box(row)))
    }

    return LayoutBox(
        width: totalWidth, height: h, depth: d,
        content: .vbox(vchildren), color: options.color)
}

/// Lay out a single ParseNode.
func layoutNode(_ node: ParseNode, _ options: LayoutOptions) -> LayoutBox {
    switch node.kind {
    case let .mathOrd(text), let .textOrd(text), let .atom(_, text), let .opToken(text):
        return layoutSymbol(text, node.mode, options)

    case let .ordGroup(body, _):
        return layoutExpression(body, options, isRealGroup: true)

    case let .supSub(base, sup, sub):
        if let baseNode = base, shouldUseOpLimits(baseNode, options) {
            return layoutOpWithLimits(baseNode, sup, sub, options)
        }
        return layoutSupSub(base, sup, sub, options, nil)

    case let .genfrac(continued, numer, denom, hasBarLine, leftDelim, rightDelim, barSize):
        let barThickness =
            hasBarLine
            ? barSize.map { measurementToEm($0, options) } ?? options.metrics.defaultRuleThickness
            : 0.0
        let frac = layoutFraction(numer, denom, barThickness, continued, options)

        let hasLeft = leftDelim.map { !$0.isEmpty && $0 != "." } ?? false
        let hasRight = rightDelim.map { !$0.isEmpty && $0 != "." } ?? false

        if hasLeft || hasRight {
            let totalH = genfracDelimTargetHeight(options)
            let leftBox = makeStretchyDelim(leftDelim ?? ".", totalH, options)
            let rightBox = makeStretchyDelim(rightDelim ?? ".", totalH, options)

            return LayoutBox(
                width: leftBox.width + frac.width + rightBox.width,
                height: max(frac.height, leftBox.height, rightBox.height),
                depth: max(frac.depth, leftBox.depth, rightBox.depth),
                content: .leftRight(left: leftBox, right: rightBox, inner: frac),
                color: options.color)
        } else {
            let rightNds = continued ? 0.0 : nullDelimiterSpace
            return makeHBox([.kern(nullDelimiterSpace), frac, .kern(rightNds)])
        }

    case let .sqrt(body, index):
        return layoutRadical(body, index, options)

    case let .op(limits, _, suppressBaseShift, _, symbol, name, body):
        return layoutOp(name, symbol, body, limits, suppressBaseShift ?? false, options)

    case let .operatorName(body, _, _, _):
        return layoutOperatorName(body, options)

    case let .spacing(text):
        return layoutSpacingCommand(text, options)

    case let .kern(dimension):
        return .kern(measurementToEm(dimension, options))

    case let .color(color, body):
        let newColor = Color.parse(color) ?? options.color
        let newOpts = options.with(color: newColor)
        var lbox = layoutExpression(body, newOpts, isRealGroup: true)
        lbox.color = newColor
        return lbox

    case let .styling(style, body):
        let newStyle = styleStrToMathStyle(style)
        let ratio = newStyle.sizeMultiplier / options.style.sizeMultiplier
        let newOpts = options.with(style: newStyle)
        let inner = layoutExpression(body, newOpts, isRealGroup: true)
        if abs(ratio - 1) < 0.001 {
            return inner
        }
        return LayoutBox(
            width: inner.width * ratio,
            height: inner.height * ratio,
            depth: inner.depth * ratio,
            content: .scaled(body: inner, childScale: ratio),
            color: options.color)

    case let .accent(label, isStretchy, isShifty, base):
        // Some text accents (e.g. \c cedilla) place the mark below
        let isBelow = label == "\\c"
        return layoutAccent(
            label, base, isStretchy ?? false, isShifty ?? false, isBelow, options)

    case let .accentUnder(label, isStretchy, _, base):
        return layoutAccent(label, base, isStretchy ?? false, false, true, options)

    case let .leftRight(body, left, right, _):
        return layoutLeftRight(body, left, right, options)

    case let .delimSizing(size, _, delim):
        return layoutDelimSizing(size, delim, options)

    case let .array(info):
        if info.isCD ?? false {
            return layoutCD(info.body, options)
        }
        return layoutArray(
            info.body, info.cols, info.arraystretch, info.addJot ?? false,
            info.rowGaps, info.hLinesBeforeRow, info.colSeparationType,
            info.hskipBeforeAndAfter ?? false, info.tags, info.leqno ?? false,
            options)

    case let .cdArrow(direction, labelAbove, labelBelow):
        // A `.cdArrow` inside `\begin{CD}` is laid out by `layoutCD` with
        // real cell dimensions; this standalone case (covered by
        // DirectUnitTests) uses zero labels/dimensions.
        return layoutCDArrow(direction, labelAbove, labelBelow, 0, 0, 0, options)

    case let .proofTree(tree):
        return layoutProofTree(tree, options)

    case let .sizing(size, body):
        return layoutSizing(size, body, options)

    case let .text(body, font):
        if let f = font {
            let group = ParseNode(.ordGroup(body: body, semisimple: nil), mode: node.mode)
            return layoutFont(f, group, options)
        }
        // Every pipeline producer of `.text` sets `font` to the command
        // name; the nil-font path (covered by DirectUnitTests) lays out the
        // body as plain text.
        return layoutText(body, options)

    case let .font(font, body):
        return layoutFont(font, body, options)

    case let .href(_, body):
        return layoutHref(body, options)

    case let .overline(body):
        return layoutOverline(body, options)

    case let .underline(body):
        return layoutUnderline(body, options)

    case let .rule(shift, w, h):
        let width = measurementToEm(w, options)
        let inkH = measurementToEm(h, options)
        let raise = shift.map { measurementToEm($0, options) } ?? 0
        // KaTeX renders rules in the current color (the leaf's own color is
        // what the display walk emits — there is no parent inheritance).
        return .rule(
            width: width,
            height: max(raise + inkH, 0),
            depth: max(-raise, 0),
            thickness: inkH,
            raise: raise,
            color: options.color)

    case let .phantom(body):
        let inner = layoutExpression(body, options, isRealGroup: true)
        return LayoutBox(
            width: inner.width, height: inner.height, depth: inner.depth,
            content: .empty, color: .black)

    case let .vphantom(body):
        let inner = layoutNode(body, options)
        return LayoutBox(
            width: 0, height: inner.height, depth: inner.depth,
            content: .empty, color: .black)

    case let .smash(body, smashHeight, smashDepth):
        var inner = layoutNode(body, options)
        if smashHeight {
            inner.height = 0
        }
        if smashDepth {
            inner.depth = 0
        }
        return inner

    case let .middle(delim):
        if let h = options.leftrightDelimHeight {
            return makeStretchyDelim(delim, h, options)
        }
        // First pass inside \left...\right: reserve width but don't affect inner height.
        let placeholder = makeStretchyDelim(delim, 1.0, options)
        return LayoutBox(
            width: placeholder.width, height: 0, depth: 0,
            content: .empty, color: options.color)

    case let .htmlMathML(html, _):
        return layoutExpression(html, options, isRealGroup: true)

    case let .html(attributes, body):
        return layoutHtml(attributes, body, options)

    case let .mclass(_, body, _):
        return layoutExpression(body, options, isRealGroup: true)

    case let .mathChoice(display, text, script, scriptscript):
        let branch =
            switch options.style {
            case .display, .displayCramped: display
            case .text, .textCramped: text
            case .script, .scriptCramped: script
            case .scriptScript, .scriptScriptCramped: scriptscript
            }
        return layoutExpression(branch, options, isRealGroup: true)

    case let .lap(alignment, body):
        let inner = layoutNode(body, options)
        let shift =
            switch alignment {
            case "llap": -inner.width
            case "clap": -inner.width / 2
            default: 0.0  // rlap: no shift
            }
        var children: [LayoutBox] = []
        if shift != 0 {
            children.append(.kern(shift))
        }
        let h = inner.height
        let d = inner.depth
        children.append(inner)
        return LayoutBox(
            width: 0, height: h, depth: d,
            content: .hbox(children), color: options.color)

    case let .horizBrace(label, isOver, base):
        return layoutHorizBrace(base, isOver, label, options)

    case let .xArrow(label, body, below):
        return layoutXArrow(label, body, below, options)

    case let .pmb(_, body):
        return layoutPmb(body, options)

    case let .hbox(body):
        return layoutText(body, options)

    case let .enclose(label, backgroundColor, borderColor, body):
        return layoutEnclose(label, backgroundColor, borderColor, body, options)

    case let .raiseBox(dy, body):
        return layoutRaiseBox(measurementToEm(dy, options), body, options)

    case let .vcenter(body):
        // Vertically center on the math axis
        let inner = layoutNode(body, options)
        let axis = options.metrics.axisHeight
        let total = inner.height + inner.depth
        let height = total / 2 + axis
        return LayoutBox(
            width: inner.width, height: height, depth: total - height,
            content: inner.content, color: inner.color)

    case let .verb(body, star):
        return layoutVerb(body, star, options)

    case let .tag(_, tag):
        let textOpts = options.with(style: options.style.textEquivalent)
        return layoutExpression(tag, textOpts, isRealGroup: true)

    // Fallback for unhandled node types: produce empty box
    default:
        return .empty
    }
}
