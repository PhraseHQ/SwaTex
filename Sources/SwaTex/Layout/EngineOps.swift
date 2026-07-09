// Operator layout (TeX Rule 13) and \operatorname.
// Port of crates/ratex-layout/src/engine.rs (lines 1284–1678).

private let noSuccessor: Set<String> = ["\\smallint"]

/// Check if a SupSub's base should use limits (above/below) positioning.
func shouldUseOpLimits(_ base: ParseNode, _ options: LayoutOptions) -> Bool {
    switch base.kind {
    case let .op(limits, alwaysHandleSupSub, _, _, _, _, _):
        limits && (options.style.isDisplay || (alwaysHandleSupSub ?? false))
    case let .operatorName(_, alwaysHandleSupSub, limits, _):
        alwaysHandleSupSub && (options.style.isDisplay || limits)
    default:
        false
    }
}

/// Lay out an Op node (without limits — standalone or nolimits mode).
///
/// In KaTeX, baseShift is applied via CSS `position:relative;top:` which
/// does NOT alter the box dimensions. So we return the original glyph
/// dimensions unchanged — the visual shift is handled at render time.
func layoutOp(
    _ name: String?, _ symbol: Bool, _ body: [ParseNode]?,
    _ limits: Bool, _ suppressBaseShift: Bool, _ options: LayoutOptions
) -> LayoutBox {
    var (baseBox, _) = buildOpBase(name, symbol, body, options)

    // Center symbol operators on the math axis (TeX Rule 13a)
    if symbol && !suppressBaseShift {
        let axis = options.metrics.axisHeight
        let shift = (baseBox.height - baseBox.depth) / 2 - axis
        if abs(shift) > 0.001 {
            baseBox.height -= shift
            baseBox.depth += shift
        }
    }

    // For user-defined \mathop{content} (e.g. \vcentcolon), center the content
    // on the math axis via a RaiseBox so the glyph physically moves up/down.
    // The HBox emit pass keeps all children at the same baseline, so adjusting
    // height/depth alone doesn't move the glyph.
    if !suppressBaseShift && !symbol && body != nil {
        let axis = options.metrics.axisHeight
        let delta = (baseBox.height - baseBox.depth) / 2 - axis
        if abs(delta) > 0.001 {
            let w = baseBox.width
            // delta < 0 → center is below axis → raise (positive RaiseBox shift)
            let raise = -delta
            baseBox = LayoutBox(
                width: w,
                height: max(baseBox.height + raise, 0),
                depth: max(baseBox.depth - raise, 0),
                content: .raiseBox(body: baseBox, shift: raise),
                color: options.color)
        }
    }

    return baseBox
}

/// Build the base glyph/text for an operator.
/// Returns (baseBox, slant) where slant is the italic correction.
func buildOpBase(
    _ name: String?, _ symbol: Bool, _ body: [ParseNode]?, _ options: LayoutOptions
) -> (base: LayoutBox, slant: Double) {
    if symbol {
        let large = options.style.isDisplay && !noSuccessor.contains(name ?? "")
        let fontId: FontId = large ? .size2Regular : .size1Regular

        let opName = name ?? ""
        let ch = resolveOpChar(opName)
        let charCode = ch.value

        let metrics = fontId.metrics(forChar: charCode)
        let (width, height, depth, italic) =
            metrics.map { ($0.width, $0.height, $0.depth, $0.italic) } ?? (1.0, 0.75, 0.25, 0.0)
        // Include italic correction in width so limits centered above/below don't overlap
        // the operator's right-side extension (e.g. integral ∫ has non-zero italic).
        let widthWithItalic = width + italic

        let base = LayoutBox(
            width: widthWithItalic, height: height, depth: depth,
            content: .glyph(fontId: fontId, charCode: charCode),
            color: options.color)

        // \oiint and \oiiint: overlay an ellipse on the integral (∬/∭) like \oint's circle.
        // resolveOpChar already maps them to ∬/∭; add the circle overlay here.
        if opName == "\\oiint" || opName == "\\oiiint" {
            let w = base.width
            let ellipseCommands = ellipseOverlayPath(w, base.height, base.depth)
            let overlayBox = LayoutBox(
                width: w, height: base.height, depth: base.depth,
                content: .svgPath(commands: ellipseCommands, fill: false),
                color: options.color)
            let withOverlay = makeHBox([base, .kern(-w), overlayBox])
            return (withOverlay, italic)
        }

        return (base, italic)
    } else if let bodyNodes = body {
        return (layoutExpression(bodyNodes, options, isRealGroup: true), 0)
    } else {
        return (layoutOpText(name ?? "", options), 0)
    }
}

/// Render a text operator name like \sin, \cos, \lim.
func layoutOpText(_ name: String, _ options: LayoutOptions) -> LayoutBox {
    let text = name.hasPrefix("\\") ? String(name.dropFirst()) : name
    var children: [LayoutBox] = []
    for ch in text.unicodeScalars {
        let charCode = ch.value
        let metrics = FontId.mainRegular.metrics(forChar: charCode)
        let (width, height, depth) =
            metrics.map { ($0.width, $0.height, $0.depth) } ?? (0.5, 0.43, 0.0)
        children.append(
            LayoutBox(
                width: width, height: height, depth: depth,
                content: .glyph(fontId: .mainRegular, charCode: charCode),
                color: options.color))
    }
    return makeHBox(children)
}

/// Compute the vertical shift to center an op symbol on the math axis (Rule 13).
func computeOpBaseShift(_ base: LayoutBox, _ options: LayoutOptions) -> Double {
    (base.height - base.depth) / 2 - options.metrics.axisHeight
}

/// Resolve an op command name to its Unicode character.
func resolveOpChar(_ name: String) -> Unicode.Scalar {
    // \oiint and \oiiint: use ∬/∭ as base glyph; circle overlay is drawn in buildOpBase
    // (same idea as \oint's circle, but U+222F/U+2230 often missing in math fonts).
    switch name {
    case "\\oiint": return "\u{222C}"  // ∬ (double integral)
    case "\\oiiint": return "\u{222D}"  // ∭ (triple integral)
    default: break
    }
    if let info = SymbolInfo(name: name, mode: .math), let cp = info.codepoint {
        return cp
    }
    return name.unicodeScalars.first ?? "?"
}

/// Lay out an Op with limits above/below (called from SupSub delegation).
func layoutOpWithLimits(
    _ baseNode: ParseNode, _ supNode: ParseNode?, _ subNode: ParseNode?,
    _ options: LayoutOptions
) -> LayoutBox {
    let name: String?
    let symbol: Bool
    let body: [ParseNode]?
    let suppressBaseShift: Bool
    switch baseNode.kind {
    case let .op(_, _, suppress, _, sym, n, b):
        (name, symbol, body, suppressBaseShift) = (n, sym, b, suppress ?? false)
    case let .operatorName(b, _, _, _):
        (name, symbol, body, suppressBaseShift) = (nil, false, b, false)
    default:
        return layoutSupSub(baseNode, supNode, subNode, options, nil)
    }

    // KaTeX-exact limit kerning (no +0.08em) for `\overset`/`\underset` only
    // (`suppressBaseShift`).
    let legacyLimitKernPadding = !suppressBaseShift

    let (baseBox, slant) = buildOpBase(name, symbol, body, options)
    // baseShift only applies to symbol operators (KaTeX: base instanceof SymbolNode)
    let baseShift =
        symbol && !suppressBaseShift ? computeOpBaseShift(baseBox, options) : 0.0

    return layoutOpLimitsInner(
        baseBox, supNode, subNode, slant, baseShift, legacyLimitKernPadding, options)
}

/// Assemble an operator with limits above/below (KaTeX's `assembleSupSub`).
///
/// `legacyLimitKernPadding`: +0.08em on limit kerns for all ops except
/// `\overset`/`\underset` (`.op(suppressBaseShift: true)`), matching KaTeX on
/// `\dddot`/`\ddddot` PNGs.
func layoutOpLimitsInner(
    _ base: LayoutBox, _ supNode: ParseNode?, _ subNode: ParseNode?,
    _ slant: Double, _ baseShift: Double, _ legacyLimitKernPadding: Bool,
    _ options: LayoutOptions
) -> LayoutBox {
    let metrics = options.metrics
    let supStyle = options.style.superscript
    let subStyle = options.style.subscript_

    let supRatio = supStyle.sizeMultiplier / options.style.sizeMultiplier
    let subRatio = subStyle.sizeMultiplier / options.style.sizeMultiplier

    let extraKern = legacyLimitKernPadding ? 0.08 : 0.0

    let supData: (elem: LayoutBox, kern: Double)? = supNode.map { s in
        let elem = layoutNode(s, options.with(style: supStyle))
        // `\overset`/`\underset`: KaTeX `assembleSupSub` uses `elem.depth` as-is. Other
        // limits (e.g. `\lim\limits_x`) keep the legacy `depth * supRatio` term so ink
        // scores stay aligned with our KaTeX PNG fixtures.
        let d = legacyLimitKernPadding ? elem.depth * supRatio : elem.depth
        let kern = max(
            metrics.bigOpSpacing1 + extraKern, metrics.bigOpSpacing3 - d + extraKern)
        return (elem, kern)
    }

    let subData: (elem: LayoutBox, kern: Double)? = subNode.map { s in
        let elem = layoutNode(s, options.with(style: subStyle))
        let h = legacyLimitKernPadding ? elem.height * subRatio : elem.height
        let kern = max(
            metrics.bigOpSpacing2 + extraKern, metrics.bigOpSpacing4 - h + extraKern)
        return (elem, kern)
    }

    let sp5 = metrics.bigOpSpacing5

    let totalHeight: Double
    let totalDepth: Double
    let totalWidth: Double
    switch (supData, subData) {
    case let (.some((supElem, supKern)), .some((subElem, subKern))):
        // Both sup and sub: VList from bottom
        // [sp5, sub, subKern, base, supKern, sup, sp5]
        let supH = supElem.height * supRatio
        let supD = supElem.depth * supRatio
        let subH = subElem.height * subRatio
        let subD = subElem.depth * subRatio

        let bottom = sp5 + subH + subD + subKern + base.depth + baseShift

        totalHeight = base.height - baseShift + supKern + supH + supD + sp5
        totalDepth = bottom
        totalWidth = max(base.width, supElem.width * supRatio, subElem.width * subRatio)
    case let (nil, .some((subElem, subKern))):
        // Sub only: VList from top
        // [sp5, sub, subKern, base]
        let subH = subElem.height * subRatio
        let subD = subElem.depth * subRatio

        totalHeight = base.height - baseShift
        totalDepth = base.depth + baseShift + subKern + subH + subD + sp5
        totalWidth = max(base.width, subElem.width * subRatio)
    case let (.some((supElem, supKern)), nil):
        // Sup only: VList from bottom
        // [base, supKern, sup, sp5]
        let supH = supElem.height * supRatio
        let supD = supElem.depth * supRatio

        totalHeight = base.height - baseShift + supKern + supH + supD + sp5
        totalDepth = base.depth + baseShift
        totalWidth = max(base.width, supElem.width * supRatio)
    case (nil, nil):
        return base
    }

    return LayoutBox(
        width: totalWidth, height: totalHeight, depth: totalDepth,
        content: .opLimits(
            base: base,
            sup: supData?.elem, sub: subData?.elem,
            baseShift: baseShift,
            supKern: supData?.kern ?? 0, subKern: subData?.kern ?? 0,
            slant: slant, supScale: supRatio, subScale: subRatio),
        color: options.color)
}

/// Lay out \operatorname body as roman text.
func layoutOperatorName(_ body: [ParseNode], _ options: LayoutOptions) -> LayoutBox {
    var children: [LayoutBox] = []
    for node in body {
        switch node.kind {
        case let .mathOrd(text), let .textOrd(text):
            let ch = text.unicodeScalars.first ?? "?"
            let charCode = ch.value
            let metrics = FontId.mainRegular.metrics(forChar: charCode)
            let (width, height, depth) =
                metrics.map { ($0.width, $0.height, $0.depth) } ?? (0.5, 0.43, 0.0)
            children.append(
                LayoutBox(
                    width: width, height: height, depth: depth,
                    content: .glyph(fontId: .mainRegular, charCode: charCode),
                    color: options.color))
        default:
            children.append(layoutNode(node, options))
        }
    }
    return makeHBox(children)
}
