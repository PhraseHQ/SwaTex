// \html-style attributes, text/verb/pmb, fonts, overline/underline/href,
// spacing commands, measurement conversion, and math-class helpers.
// Port of crates/ratex-layout/src/engine.rs (lines 2954–3959).

/// Trim ASCII/Unicode whitespace from both ends of a substring (Rust `str::trim`).
private func trimmed(_ s: Substring) -> Substring {
    var t = s.drop(while: \.isWhitespace)
    while let last = t.last, last.isWhitespace {
        t = t.dropLast()
    }
    return t
}

struct HtmlStyle {
    var color: Color?
    var fontSizeScale: Double?
    var bold = false
    var italic = false
    var backgroundColor: Color?
    var underline = false
}

func layoutHtml(
    _ attributes: [String: String], _ body: [ParseNode], _ options: LayoutOptions
) -> LayoutBox {
    let style = attributes["style"].map(parseHtmlStyle) ?? HtmlStyle()

    let bodyOptions =
        switch style.color {
        case let .some(color): options.with(color: color)
        case nil: options
        }
    let fontId: FontId? =
        switch (style.bold, style.italic) {
        case (true, true): .mainBoldItalic
        case (true, false): .mainBold
        case (false, true): .mainItalic
        case (false, false): nil
        }

    let bodyNode = ParseNode(
        .ordGroup(body: body, semisimple: nil),
        mode: body.first?.mode ?? .math)
    var lbox =
        switch fontId {
        case let .some(fontId): layoutWithFont(bodyNode, fontId, bodyOptions)
        case nil: layoutExpression(body, bodyOptions, isRealGroup: true)
        }

    if let scale = style.fontSizeScale, abs(scale - 1.0) >= 0.001 {
        lbox = LayoutBox(
            width: lbox.width * scale,
            height: lbox.height * scale,
            depth: lbox.depth * scale,
            content: .scaled(body: lbox, childScale: scale),
            color: bodyOptions.color)
    }

    if let backgroundColor = style.backgroundColor {
        lbox = LayoutBox(
            width: lbox.width,
            height: lbox.height,
            depth: lbox.depth,
            content: .framed(
                body: lbox,
                padding: 0.0,
                borderThickness: 0.0,
                hasBorder: false,
                bgColor: backgroundColor,
                borderColor: .black),
            color: bodyOptions.color)
    }

    if style.underline {
        lbox = layoutUnderlineLaidOut(lbox, options, bodyOptions.color)
    }

    if options.leftrightDelimHeight == nil, bodyContainsMiddle(body, bodyOptions.style) {
        let total = 1.2  // SIZE_TO_MAX_HEIGHT[1] (`sizeToMaxHeight` in EngineDelims.swift)
        let axis = bodyOptions.metrics.axisHeight
        let height = total / 2.0 + axis
        let depth = total - height
        lbox.height = max(lbox.height, height)
        lbox.depth = max(lbox.depth, depth)
    }

    return lbox
}

func parseHtmlStyle(_ style: String) -> HtmlStyle {
    var parsed = HtmlStyle()
    for declaration in style.split(separator: ";") {
        guard let colon = declaration.firstIndex(of: ":") else {
            continue
        }
        let property = trimmed(declaration[..<colon]).lowercased()
        let value = String(trimmed(declaration[declaration.index(after: colon)...]))
        switch property {
        case "color": parsed.color = Color.parse(value)
        case "font-size": parsed.fontSizeScale = parseCssFontSize(value)
        case "font-weight": parsed.bold = isCssBold(value)
        case "font-style": parsed.italic = isCssItalic(value)
        case "background", "background-color": parsed.backgroundColor = Color.parse(value)
        case "text-decoration", "text-decoration-line":
            parsed.underline = value.split(whereSeparator: \.isWhitespace)
                .contains { $0.lowercased() == "underline" }
        default: break
        }
    }
    return parsed
}

func parseCssFontSize(_ value: String) -> Double? {
    let value = trimmed(value[...]).lowercased().filter { $0 != " " }
    func parseNumber(_ s: Substring) -> Double? {
        guard let n = Double(s), n.isFinite, n > 0 else { return nil }
        return n
    }
    if value.hasSuffix("px") {
        return parseNumber(value.dropLast(2)).map { $0 / 16.0 }
    } else if value.hasSuffix("em") {
        // Matches the Rust `strip_suffix("em").or_else(strip_suffix("rem"))`: any
        // "rem" value also ends in "em", so "1.5rem" leaves "1.5r" → nil there too.
        return parseNumber(value.dropLast(2))
    } else if value.hasSuffix("%") {
        return parseNumber(value.dropLast(1)).map { $0 / 100.0 }
    }
    return nil
}

func isCssBold(_ value: String) -> Bool {
    let value = trimmed(value[...])
    if value.lowercased() == "bold" || value.lowercased() == "bolder" {
        return true
    }
    if let weight = UInt16(value) {
        return weight >= 600
    }
    return false
}

func isCssItalic(_ value: String) -> Bool {
    let value = trimmed(value[...]).lowercased()
    return value == "italic" || value == "oblique"
}

/// Layout \verb and \verb* — verbatim text in typewriter font.
/// \verb* shows spaces as a visible character (U+2423 OPEN BOX).
func layoutVerb(_ body: String, _ star: Bool, _ options: LayoutOptions) -> LayoutBox {
    let metrics = options.metrics
    var children: [LayoutBox] = []
    for c in body.unicodeScalars {
        let ch: Unicode.Scalar =
            if star && c == " " {
                "\u{2423}"  // OPEN BOX, visible space
            } else {
                c
            }
        let code = ch.value
        let (fontId, w, h, d): (FontId, Double, Double, Double)
        if let m = FontId.typewriterRegular.metrics(forChar: code) {
            (fontId, w, h, d) = (.typewriterRegular, m.width, m.height, m.depth)
        } else if let m = FontId.mainRegular.metrics(forChar: code) {
            (fontId, w, h, d) = (.mainRegular, m.width, m.height, m.depth)
        } else {
            (fontId, w, h, d) = (.typewriterRegular, 0.5, metrics.xHeight, 0.0)
        }
        children.append(
            LayoutBox(
                width: w, height: h, depth: d,
                content: .glyph(fontId: fontId, charCode: code),
                color: options.color))
    }
    var hbox = makeHBox(children)
    hbox.color = options.color
    return hbox
}

/// Lay out `\text{…}` / `HBox` contents as a simple horizontal row.
///
/// KaTeX's HTML builder may merge consecutive text symbols into **one** DOM text run; the
/// browser then applies OpenType kerning (GPOS) on that run. We place each character using
/// bundled TeX metrics only (no GPOS), so compared to Puppeteer+KaTeX PNGs, long `\text{…}`
/// strings can appear slightly wider with a small cumulative horizontal shift — not a wrong
/// font file, but a shaping model difference.
func layoutText(_ body: [ParseNode], _ options: LayoutOptions) -> LayoutBox {
    var children: [LayoutBox] = []
    for node in body {
        switch node.kind {
        case let .textOrd(text), let .mathOrd(text):
            children.append(layoutSymbol(text, node.mode, options))
        case let .spacing(text):
            children.append(layoutSpacingCommand(text, options))
        default:
            children.append(layoutNode(node, options))
        }
    }
    return makeHBox(children)
}

/// Layout \pmb — poor man's bold via CSS-style text shadow.
/// Renders the body twice: once normally, once offset by (0.02em, 0.01em).
func layoutPmb(_ body: [ParseNode], _ options: LayoutOptions) -> LayoutBox {
    let base = layoutExpression(body, options, isRealGroup: true)
    let w = base.width
    let h = base.height
    let d = base.depth

    // Shadow copy shifted right 0.02em, down 0.01em — same content, same color
    let shadow = layoutExpression(body, options, isRealGroup: true)
    let shadowShiftX = 0.02
    // let shadowShiftY = 0.01 (unused, see below)

    // Combine: place shadow first (behind), then base on top
    // Shadow is placed at an HBox offset — we use a VBox/kern trick:
    // Instead, represent as HBox where shadow overlaps base via negative kern
    let kernBack = LayoutBox.kern(-w)
    let kernX = LayoutBox.kern(shadowShiftX)

    // We create: [shadow | kern(-w) | base] in an HBox
    // But shadow needs to be shifted down by shadow_shift_y.
    // Use a raised box trick: wrap shadow in a VBox with a small kern.
    // Simplest approximation: just render body once (the shadow is < 1px at normal size)
    // but with a tiny kern to hint at bold width.
    // Better: use a simple 2-layer HBox with overlap.
    let children = [kernX, shadow, kernBack, base]
    // Width should be original base width, not doubled
    let hbox = makeHBox(children)
    // Return a box with original dimensions (shadow overflow is clipped)
    return LayoutBox(
        width: w, height: h, depth: d,
        content: hbox.content, color: options.color)
}

// ============================================================================
// Fonts
// ============================================================================

func layoutFont(_ font: String, _ body: ParseNode, _ options: LayoutOptions) -> LayoutBox {
    let fontId: FontId? =
        switch font {
        case "mathrm", "\\mathrm", "textrm", "\\textrm", "rm", "\\rm": .mainRegular
        case "mathbf", "\\mathbf", "textbf", "\\textbf", "bf", "\\bf": .mainBold
        case "mathit", "\\mathit", "it", "\\it": .mathItalic
        case "textit", "\\textit", "\\emph": .mainItalic
        case "mathsf", "\\mathsf", "textsf", "\\textsf": .sansSerifRegular
        case "mathtt", "\\mathtt", "texttt", "\\texttt": .typewriterRegular
        case "mathcal", "\\mathcal", "cal", "\\cal": .caligraphicRegular
        case "mathfrak", "\\mathfrak", "frak", "\\frak": .frakturRegular
        case "mathscr", "\\mathscr": .scriptRegular
        case "mathbb", "\\mathbb": .amsRegular
        case "boldsymbol", "\\boldsymbol", "bm", "\\bm": .mathBoldItalic
        default: nil
        }

    if let fid = fontId {
        return layoutWithFont(body, fid, options)
    }
    return layoutNode(body, options)
}

func layoutWithFont(_ node: ParseNode, _ fontId: FontId, _ options: LayoutOptions) -> LayoutBox {
    switch node.kind {
    case let .ordGroup(body, _):
        let kern = options.interGlyphKernEm
        var children: [LayoutBox] = []
        children.reserveCapacity(body.count * 2)
        for (i, n) in body.enumerated() {
            if i > 0, kern > 0 {
                children.append(.kern(kern))
            }
            children.append(layoutWithFont(n, fontId, options))
        }
        return makeHBox(children)

    case let .supSub(base, sup, sub):
        if let baseNode = base, shouldUseOpLimits(baseNode, options) {
            return layoutOpWithLimits(baseNode, sup, sub, options)
        }
        return layoutSupSub(base, sup, sub, options, fontId)

    case let .mathOrd(text), let .textOrd(text), let .atom(_, text):
        let ch = resolveSymbolChar(text, node.mode)
        let charCode = ch.value
        let metricCp = FontId.mathAlphanumeric(charCode)?.metric ?? charCode
        if let m = fontId.metrics(forChar: metricCp) {
            return LayoutBox(
                // Text mode: no italic correction (it's a typographic hint for math sub/sup).
                width: node.mode == .math ? m.width + m.italic : m.width,
                height: m.height,
                depth: m.depth,
                content: .glyph(fontId: fontId, charCode: charCode),
                color: options.color)
        }
        // Glyph not in requested font — fall back to default math rendering
        return layoutNode(node, options)

    default:
        return layoutNode(node, options)
    }
}

// ============================================================================
// Overline / Underline
// ============================================================================

func layoutOverline(_ body: ParseNode, _ options: LayoutOptions) -> LayoutBox {
    let cramped = options.with(style: options.style.cramped)
    let bodyBox = layoutNode(body, cramped)
    let metrics = options.metrics
    let rule = metrics.defaultRuleThickness

    // Total height: body height + 2*rule clearance + rule thickness = body.height + 3*rule
    let height = bodyBox.height + 3.0 * rule
    return LayoutBox(
        width: bodyBox.width,
        height: height,
        depth: bodyBox.depth,
        content: .overline(body: bodyBox, ruleThickness: rule),
        color: options.color)
}

func layoutUnderline(_ body: ParseNode, _ options: LayoutOptions) -> LayoutBox {
    let bodyBox = layoutNode(body, options)
    let metrics = options.metrics
    let rule = metrics.defaultRuleThickness
    let offset = 4.0 * rule

    let depth = bodyBox.depth + offset + 0.5 * rule
    return LayoutBox(
        width: bodyBox.width,
        height: bodyBox.height,
        depth: depth,
        content: .underline(body: bodyBox, ruleThickness: rule, offset: offset),
        color: options.color)
}

/// `\href` / `\url`: link color on the glyphs and an underline in the same color (KaTeX-style).
func layoutHref(_ body: [ParseNode], _ options: LayoutOptions) -> LayoutBox {
    let linkColor = Color(name: "blue") ?? Color(r: 0, g: 0, b: 1)
    // Slight tracking matches KaTeX/browser monospace link width in golden PNGs.
    let bodyOpts = options.with(color: linkColor).with(interGlyphKernEm: 0.05)
    let bodyBox = layoutExpression(body, bodyOpts, isRealGroup: true)
    if boxContainsFont(bodyBox, .typewriterRegular) {
        return layoutLinkUnderlineLaidOut(bodyBox, options, linkColor)
    }
    return layoutUnderlineLaidOut(bodyBox, options, linkColor)
}

/// Same geometry as ``layoutUnderline(_:_:)``, but for an already computed inner box.
func layoutUnderlineLaidOut(
    _ bodyBox: LayoutBox, _ options: LayoutOptions, _ color: Color
) -> LayoutBox {
    let metrics = options.metrics
    let rule = metrics.defaultRuleThickness
    return layoutUnderlineLaidOutWithRule(bodyBox, rule, 2.5 * rule, color)
}

func layoutUnderlineLaidOutWithRule(
    _ bodyBox: LayoutBox, _ rule: Double, _ offset: Double, _ color: Color
) -> LayoutBox {
    let depth = bodyBox.depth + offset + 0.5 * rule
    return LayoutBox(
        width: bodyBox.width,
        height: bodyBox.height,
        depth: depth,
        content: .underline(body: bodyBox, ruleThickness: rule, offset: offset),
        color: color)
}

func boxContainsFont(_ lbox: LayoutBox, _ fontId: FontId) -> Bool {
    switch lbox.content {
    case let .glyph(fid, _):
        fid == fontId
    case let .hbox(children):
        children.contains { boxContainsFont($0, fontId) }
    case let .scaled(body, _), let .raiseBox(body, _):
        boxContainsFont(body, fontId)
    default:
        false
    }
}

func linkUnderlineSkipCuts(
    _ lbox: LayoutBox, _ x: Double, _ scale: Double, _ cuts: inout [(Double, Double)]
) {
    switch lbox.content {
    case let .hbox(children):
        var curX = x
        for child in children {
            linkUnderlineSkipCuts(child, curX, scale, &cuts)
            curX += child.width * scale
        }
    case let .glyph(_, charCode):
        if let ch = Unicode.Scalar(charCode),
            ch == "g" || ch == "j" || ch == "p" || ch == "q" || ch == "y"
        {
            let pad = min(0.04 * scale, lbox.width * scale / 3.0)
            cuts.append((x + pad, x + lbox.width * scale - pad))
        }
    case let .scaled(body, childScale):
        linkUnderlineSkipCuts(body, x, scale * childScale, &cuts)
    case let .raiseBox(body, _):
        linkUnderlineSkipCuts(body, x, scale, &cuts)
    default:
        break
    }
}

func linkUnderlineSegments(_ bodyBox: LayoutBox) -> [(Double, Double)] {
    var cuts: [(Double, Double)] = []
    linkUnderlineSkipCuts(bodyBox, 0.0, 1.0, &cuts)
    if cuts.isEmpty {
        return [(0.0, bodyBox.width)]
    }
    cuts.sort { $0.0 < $1.0 }

    var segments: [(Double, Double)] = []
    var x = 0.0
    for (cutL, cutR) in cuts {
        let l = min(max(cutL, 0.0), bodyBox.width)
        let r = min(max(cutR, 0.0), bodyBox.width)
        if l > x + 0.02 {
            segments.append((x, l - x))
        }
        x = max(x, r)
    }
    if bodyBox.width > x + 0.02 {
        segments.append((x, bodyBox.width - x))
    }
    if segments.isEmpty {
        return [(0.0, bodyBox.width)]
    }
    return segments
}

func layoutLinkUnderlineLaidOut(
    _ bodyBox: LayoutBox, _ options: LayoutOptions, _ color: Color
) -> LayoutBox {
    let metrics = options.metrics
    let rule = metrics.defaultRuleThickness
    let offset = 2.5 * rule
    let segments = linkUnderlineSegments(bodyBox)
    if segments.count <= 1 {
        return layoutUnderlineLaidOutWithRule(bodyBox, rule, offset, color)
    }

    let height = bodyBox.height
    let depth = bodyBox.depth + offset + 0.5 * rule
    let ruleY = height + bodyBox.depth + offset
    let width = bodyBox.width
    return LayoutBox(
        width: width,
        height: height,
        depth: depth,
        content: .proofTree(
            children: [PlacedBox(box: bodyBox, x: 0.0, baselineY: height)],
            rules: segments.map { (x, width) in
                ProofRule(x: x, y: ruleY, width: width, thickness: rule, dashed: false)
            }),
        color: color)
}

// ============================================================================
// Spacing commands
// ============================================================================

func layoutSpacingCommand(_ text: String, _ options: LayoutOptions) -> LayoutBox {
    let metrics = options.metrics
    let mu = metrics.cssEmPerMu

    let width: Double =
        switch text {
        case "\\,", "\\thinspace": 3.0 * mu
        case "\\:", "\\medspace": 4.0 * mu
        case "\\;", "\\thickspace": 5.0 * mu
        case "\\!", "\\negthinspace": -3.0 * mu
        case "\\negmedspace": -4.0 * mu
        case "\\negthickspace": -5.0 * mu
        case " ", "~", "\\nobreakspace", "\\ ", "\\space":
            // KaTeX renders these by placing the U+00A0 glyph (char 160) via mathsym.
            // Look up its width from MainRegular; fall back to 0.25em (the font-defined value).
            // Literal space in `\text{ … }` becomes SpacingNode with text " ".
            FontId.mainRegular.metrics(forChar: 160)?.width ?? 0.25
        case "\\quad": metrics.quad
        case "\\qquad": 2.0 * metrics.quad
        case "\\enspace": metrics.quad / 2.0
        default: 0.0
        }

    return .kern(width)
}

// ============================================================================
// Measurement conversion
// ============================================================================

func measurementToEm(_ m: Measurement, _ options: LayoutOptions) -> Double {
    let metrics = options.metrics
    return switch m.unit {
    case "em": m.number
    case "ex": m.number * metrics.xHeight
    case "mu": m.number * metrics.cssEmPerMu
    case "pt": m.number / metrics.ptPerEm
    case "mm": m.number * 7227.0 / 2540.0 / metrics.ptPerEm
    case "cm": m.number * 7227.0 / 254.0 / metrics.ptPerEm
    case "in": m.number * 72.27 / metrics.ptPerEm
    case "bp": m.number * 803.0 / 800.0 / metrics.ptPerEm
    case "pc": m.number * 12.0 / metrics.ptPerEm
    case "dd": m.number * 1238.0 / 1157.0 / metrics.ptPerEm
    case "cc": m.number * 14856.0 / 1157.0 / metrics.ptPerEm
    case "nd": m.number * 685.0 / 642.0 / metrics.ptPerEm
    case "nc": m.number * 1370.0 / 107.0 / metrics.ptPerEm
    case "sp": m.number / 65536.0 / metrics.ptPerEm
    default: m.number
    }
}

// ============================================================================
// Math class determination
// ============================================================================

/// Determine the math class of a ParseNode for spacing purposes.
func nodeMathClass(_ node: ParseNode) -> MathClass? {
    switch node.kind {
    case .mathOrd, .textOrd:
        return .ord
    case let .atom(family, _):
        return familyToMathClass(family)
    case .opToken, .op, .operatorName:
        return .op
    case .ordGroup:
        return .ord
    // KaTeX genfrac.js: with delimiters (e.g. \binom) → mord; without (e.g. \frac) → minner.
    case let .genfrac(_, _, _, _, leftDelim, rightDelim, _):
        let hasDelim =
            leftDelim.map { !$0.isEmpty && $0 != "." } ?? false
            || rightDelim.map { !$0.isEmpty && $0 != "." } ?? false
        return hasDelim ? .ord : .inner
    case .sqrt:
        return .ord
    case let .supSub(base, _, _):
        return base.flatMap(nodeMathClass)
    case let .mclass(mclass, _, _):
        return mclassStrToMathClass(mclass)
    case .spacing:
        return nil
    case .kern:
        return nil
    case let .htmlMathML(html, _):
        // Derive math class from the first meaningful child in the HTML branch
        for child in html {
            if let cls = nodeMathClass(child) {
                return cls
            }
        }
        return nil
    case let .html(_, body):
        for child in body {
            if let cls = nodeMathClass(child) {
                return cls
            }
        }
        return nil
    case .lap:
        return nil
    case .leftRight:
        return .inner
    case .accentToken:
        return .ord
    // \xrightarrow etc. are mathrel in TeX/KaTeX; without this they collapse to Ord–Ord (no kern).
    case .xArrow:
        return .rel
    // CD arrows are structural; treat as Rel for spacing.
    case .cdArrow:
        return .rel
    case let .delimSizing(_, mclass, _):
        return mclassStrToMathClass(mclass)
    case .middle:
        return .ord
    default:
        return .ord
    }
}

func mclassStrToMathClass(_ mclass: String) -> MathClass {
    switch mclass {
    case "mord": .ord
    case "mop": .op
    case "mbin": .bin
    case "mrel": .rel
    case "mopen": .open
    case "mclose": .close
    case "mpunct": .punct
    case "minner": .inner
    default: .ord
    }
}

/// Check if a ParseNode is a single character box (affects sup/sub positioning).
/// KaTeX `getBaseElem` (`utils.js`): unwrap `ordgroup` / `color` with a single child, and `font`.
/// Used for TeX "character box" checks in superscript Rule 18a (`supsub.js`).
func getBaseElem(_ node: ParseNode) -> ParseNode {
    switch node.kind {
    case let .ordGroup(body, _) where body.count == 1:
        getBaseElem(body[0])
    case let .color(_, body) where body.count == 1:
        getBaseElem(body[0])
    case let .html(_, body) where body.count == 1:
        getBaseElem(body[0])
    case let .font(_, body):
        getBaseElem(body)
    default:
        node
    }
}

func isCharacterBox(_ node: ParseNode) -> Bool {
    switch getBaseElem(node).kind {
    case .mathOrd, .textOrd, .atom, .accentToken: true
    default: false
    }
}

func familyToMathClass(_ family: AtomFamily) -> MathClass {
    switch family {
    case .bin: .bin
    case .rel: .rel
    case .open: .open
    case .close: .close
    case .punct: .punct
    case .inner: .inner
    }
}
