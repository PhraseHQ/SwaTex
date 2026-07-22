// Stacked stretchy delimiters for `\left`/`\right` when a single Size4 glyph is too short.
// Mirrors KaTeX `delimiter.ts`: `stackLargeDelimiters` use `makeStackedDelim` past the large-font stage.
//
// Ported from RaTeX `stacked_delim.rs`.

private let lap = 0.008

enum StackDelimKind {
    case brace(open: Bool)
    case bracket(open: Bool)
    case paren(open: Bool)
    case lFloor
    case rFloor
    case lCeil
    case rCeil
    case group(open: Bool)
}

private func normalizeForStack(_ delim: String) -> String {
    switch delim {
    case "{": "\\{"
    case "}": "\\}"
    default: delim
    }
}

private func classifyStackable(_ delim: String) -> StackDelimKind? {
    let d = normalizeForStack(delim)
    switch d {
    case "\\{", "\\lbrace": return .brace(open: true)
    case "\\}", "\\rbrace": return .brace(open: false)
    case "[", "\\lbrack": return .bracket(open: true)
    case "]", "\\rbrack": return .bracket(open: false)
    case "(", "\\lparen": return .paren(open: true)
    case ")", "\\rparen": return .paren(open: false)
    case "\\lfloor", "\u{230a}": return .lFloor
    case "\\rfloor", "\u{230b}": return .rFloor
    case "\\lceil", "\u{2308}": return .lCeil
    case "\\rceil", "\u{2309}": return .rCeil
    case "\\lgroup", "\u{27ee}": return .group(open: true)
    case "\\rgroup", "\u{27ef}": return .group(open: false)
    default: return nil
    }
}

/// KaTeX `stackNeverDelimiters`.
func isStackNeverDelim(_ delim: String) -> Bool {
    switch delim {
    case "<", ">", "\\langle", "\\rangle", "/", "\\backslash", "\\lt", "\\gt",
        "\u{27e8}", "\u{27e9}":
        true
    default:
        false
    }
}

private func size4Glyph(_ charCode: UInt32, _ options: LayoutOptions) -> LayoutBox {
    guard let m = FontId.size4Regular.metrics(forChar: charCode) else {
        // INTENTIONALLY UNCOVERED (fatalError guard): callers pass only the
        // U+23A7–U+23AD brace/group piece codepoints, all present in the
        // bundled Size4 metrics (checked by the callers' own `guard`s
        // before any piece is built). A fatalError cannot be exercised by a
        // test without crashing the process.
        fatalError("stacked delim piece")
    }
    return LayoutBox(
        width: m.width, height: m.height, depth: m.depth,
        content: .glyph(fontId: .size4Regular, charCode: charCode),
        color: options.color)
}

private func heightDepth(_ m: CharMetrics) -> Double {
    m.height + m.depth
}

private func braceRepeatSvg(innerHeightEm: Double, options: LayoutOptions) -> LayoutBox {
    guard let m = FontId.size4Regular.metrics(forChar: 0x23aa) else {
        // INTENTIONALLY UNCOVERED (fatalError guard): U+23AA is present in
        // the bundled Size4 metrics; a fatalError cannot be exercised by a
        // test without crashing the process.
        fatalError("brace repeat")
    }
    let x0 = 384.0 / 1000.0
    let x1 = 504.0 / 1000.0
    let cmds: [PathCommand] = [
        .moveTo(x: x0, y: -innerHeightEm),
        .lineTo(x: x1, y: -innerHeightEm),
        .lineTo(x: x1, y: 0.0),
        .lineTo(x: x0, y: 0.0),
        .close,
    ]
    return LayoutBox(
        width: m.width, height: innerHeightEm, depth: 0.0,
        content: .svgPath(commands: cmds, fill: true),
        color: options.color)
}

private func axisCenterStackedVBox(_ body: LayoutBox, _ options: LayoutOptions) -> LayoutBox {
    let hVis = body.height + body.depth
    let axis = options.metrics.axisHeight * options.sizeMultiplier
    let shift = axis - hVis / 2.0
    let depth = max(hVis / 2.0 - axis, 0.0)
    return LayoutBox(
        width: body.width, height: hVis / 2.0 + axis, depth: depth,
        content: .raiseBox(body: body, shift: shift),
        color: options.color)
}

func tallDelimSvgPath(_ label: String, midTh: Int) -> String {
    let m = midTh
    switch label {
    case "lbrack":
        return
            "M403 1759 V84 H666 V0 H319 V1759 v\(m) v1759 h347 v-84 H403z M403 1759 V0 H319 V1759 v\(m) v1759 h84z"
    case "rbrack":
        return
            "M347 1759 V0 H0 V84 H263 V1759 v\(m) v1759 H0 v84 H347z M347 1759 V0 H263 V1759 v\(m) v1759 h84z"
    case "lfloor":
        return
            "M319 602 V0 H403 V602 v\(m) v1715 h263 v84 H319z M319 602 V0 H403 V602 v\(m) v1715 H319z"
    case "rfloor":
        return
            "M319 602 V0 H403 V602 v\(m) v1799 H0 v-84 H319z M319 602 V0 H403 V602 v\(m) v1715 H319z"
    case "lceil":
        return
            "M403 1759 V84 H666 V0 H319 V1759 v\(m) v602 h84z M403 1759 V0 H319 V1759 v\(m) v602 h84z"
    case "rceil":
        return
            "M347 1759 V0 H0 V84 H263 V1759 v\(m) v602 h84z M347 1759 V0 h-84 V1759 v\(m) v602 h84z"
    case "lparen":
        let m84 = m + 84
        let m92 = m + 92
        return
            "M863,9c0,-2,-2,-5,-6,-9c0,0,-17,0,-17,0c-12.7,0,-19.3,0.3,-20,1c-5.3,5.3,-10.3,11,-15,17c-242.7,294.7,-395.3,682,-458,1162c-21.3,163.3,-33.3,349,-36,557 l0,\(m84)c0.2,6,0,26,0,60c2,159.3,10,310.7,24,454c53.3,528,210,949.7,470,1265c4.7,6,9.7,11.7,15,17c0.7,0.7,7,1,19,1c0,0,18,0,18,0c4,-4,6,-7,6,-9c0,-2.7,-3.3,-8.7,-10,-18c-135.3,-192.7,-235.5,-414.3,-300.5,-665c-65,-250.7,-102.5,-544.7,-112.5,-882c-2,-104,-3,-167,-3,-189 l0,-\(m92)c0,-162.7,5.7,-314,17,-454c20.7,-272,63.7,-513,129,-723c65.3,-210,155.3,-396.3,270,-559c6.7,-9.3,10,-15.3,10,-18z"
    case "rparen":
        let m9 = m + 9
        let m144 = m + 144
        return
            "M76,0c-16.7,0,-25,3,-25,9c0,2,2,6.3,6,13c21.3,28.7,42.3,60.3,63,95c96.7,156.7,172.8,332.5,228.5,527.5c55.7,195,92.8,416.5,111.5,664.5c11.3,139.3,17,290.7,17,454c0,28,1.7,43,3.3,45l0,\(m9)c-3,4,-3.3,16.7,-3.3,38c0,162,-5.7,313.7,-17,455c-18.7,248,-55.8,469.3,-111.5,664c-55.7,194.7,-131.8,370.3,-228.5,527c-20.7,34.7,-41.7,66.3,-63,95c-2,3.3,-4,7,-6,11c0,7.3,5.7,11,17,11c0,0,11,0,11,0c9.3,0,14.3,-0.3,15,-1c5.3,-5.3,10.3,-11,15,-17c242.7,-294.7,395.3,-681.7,458,-1161c21.3,-164.7,33.3,-350.7,36,-558 l0,-\(m144)c-2,-159.3,-10,-310.7,-24,-454c-53.3,-528,-210,-949.7,-470,-1265c-4.7,-6,-9.7,-11.7,-15,-17c-0.7,-0.7,-6.7,-1,-18,-1z"
    default:
        return ""
    }
}

private func svgLabelFor(_ kind: StackDelimKind) -> String {
    switch kind {
    case .bracket(open: true): "lbrack"
    case .bracket(open: false): "rbrack"
    case .paren(open: true): "lparen"
    case .paren(open: false): "rparen"
    case .lFloor: "lfloor"
    case .rFloor: "rfloor"
    case .lCeil: "lceil"
    case .rCeil: "rceil"
    default: ""
    }
}

private func widthEmForLabel(_ label: String) -> Double {
    switch label {
    case "lparen", "rparen": 0.875
    default: 0.667
    }
}

func makeTallSvgDelim(
    _ kind: StackDelimKind, heightTotal: Double, options: LayoutOptions
) -> LayoutBox? {
    let label = svgLabelFor(kind)
    if label.isEmpty {
        return nil
    }

    let topC: UInt32
    let botC: UInt32
    switch kind {
    case .bracket(open: true): (topC, botC) = (0x23a1, 0x23a3)
    case .bracket(open: false): (topC, botC) = (0x23a4, 0x23a6)
    case .paren(open: true): (topC, botC) = (0x239b, 0x239d)
    case .paren(open: false): (topC, botC) = (0x239e, 0x23a0)
    case .lFloor: (topC, botC) = (0x23a2, 0x23a3)
    case .rFloor: (topC, botC) = (0x23a5, 0x23a6)
    case .lCeil: (topC, botC) = (0x23a1, 0x23a2)
    case .rCeil: (topC, botC) = (0x23a4, 0x23a5)
    default: return nil
    }

    let topM = FontId.size4Regular.metrics(forChar: topC).map(heightDepth) ?? 0.0
    let botM = FontId.size4Regular.metrics(forChar: botC).map(heightDepth) ?? 0.0
    let minH = topM + botM
    let midEm = max(heightTotal - minH, 0.0)
    let midTh = Int((midEm * 1000.0).rounded())

    let d = tallDelimSvgPath(label, midTh: midTh)
    let raw = parseSvgPathData(d)
    if raw.isEmpty {
        // INTENTIONALLY UNCOVERED (defensive-fallback KEEP): `label` comes
        // from `svgLabelFor`, whose non-empty outputs are exactly the eight
        // keys `tallDelimSvgPath` renders, and each template produces a
        // non-empty parseable path for every `midTh`. Kept so a template
        // regression degrades to glyph stacking rather than drawing garbage.
        return nil
    }
    // The KaTeX SVG paths use a top-origin coordinate system (y=0 at top, y=height_total
    // at bottom).  RaTeX places SvgPath items at the box baseline, so y=0 maps to the
    // baseline and positive y extends downward.  Shift every y by -height_total so the
    // path spans [-height_total, 0] (above baseline to baseline), matching the declared
    // LayoutBox dimensions (height=height_total, depth=0).
    // One fused pass; bit-identical to .scaled(by:).shiftedY(-heightTotal)
    // (the intermediate +0.0/*1.0 steps are exact IEEE identities given
    // heightTotal > 0), without the intermediate array.
    let cmds = raw.map { $0.mapPoints(sx: 0.001, sy: 0.001, dy: -heightTotal) }
    let w = widthEmForLabel(label)
    let inner = LayoutBox(
        width: w, height: heightTotal, depth: 0.0,
        content: .svgPath(commands: cmds, fill: true),
        color: options.color)
    return axisCenterStackedVBox(inner, options)
}

func makeGlyphStackDelim(
    _ kind: StackDelimKind, heightTotal: Double, options: LayoutOptions
) -> LayoutBox? {
    func lapKern(_ k: Double) -> VBoxChild {
        VBoxChild(.kern(-k), shift: 0.0)
    }
    func bx(_ lb: LayoutBox) -> VBoxChild {
        VBoxChild(.box(lb), shift: 0.0)
    }

    switch kind {
    case .brace(let open):
        let (topC, midC, botC, _): (UInt32, UInt32, UInt32, UInt32) =
            open
            ? (0x23a7, 0x23a8, 0x23a9, 0x23aa)
            : (0x23ab, 0x23ac, 0x23ad, 0x23aa)
        guard let top = FontId.size4Regular.metrics(forChar: topC),
            let mid = FontId.size4Regular.metrics(forChar: midC),
            let bot = FontId.size4Regular.metrics(forChar: botC)
        else {
            // INTENTIONALLY UNCOVERED (defensive-fallback KEEP): the brace
            // piece codepoints U+23A7/U+23A8/U+23A9/U+23AB/U+23AC/U+23AD are
            // all present in the bundled Size4 metrics, so the guard never
            // fails. Kept so a metrics regression degrades to no stacked
            // delimiter instead of crashing.
            return nil
        }
        let topHt = heightDepth(top)
        let midHt = heightDepth(mid)
        let botHt = heightDepth(bot)
        let minH = topHt + midHt + botHt
        let innerH = max((heightTotal - minH) / 2.0, 0.0) + 2.0 * lap

        let ch: [VBoxChild] = [
            bx(size4Glyph(topC, options)),
            lapKern(lap),
            bx(braceRepeatSvg(innerHeightEm: innerH, options: options)),
            lapKern(lap),
            bx(size4Glyph(midC, options)),
            lapKern(lap),
            bx(braceRepeatSvg(innerHeightEm: innerH, options: options)),
            lapKern(lap),
            bx(size4Glyph(botC, options)),
        ]

        return axisCenterStackedVBox(makeVBox(ch), options)
    case .group(let open):
        let (topC, botC, _): (UInt32, UInt32, UInt32) =
            open
            ? (0x23a7, 0x23a9, 0x23aa)
            : (0x23ab, 0x23ad, 0x23aa)
        guard let top = FontId.size4Regular.metrics(forChar: topC),
            let bot = FontId.size4Regular.metrics(forChar: botC)
        else {
            // INTENTIONALLY UNCOVERED (defensive-fallback KEEP): the group
            // piece codepoints U+23A7/U+23A9/U+23AB/U+23AD are all present
            // in the bundled Size4 metrics, so the guard never fails. Kept
            // so a metrics regression degrades to no stacked delimiter
            // instead of crashing.
            return nil
        }
        let topHt = heightDepth(top)
        let botHt = heightDepth(bot)
        let minH = topHt + botHt
        let innerH = max(heightTotal - minH, 0.0) + 2.0 * lap

        let ch: [VBoxChild] = [
            bx(size4Glyph(topC, options)),
            lapKern(lap),
            bx(braceRepeatSvg(innerHeightEm: innerH, options: options)),
            lapKern(lap),
            bx(size4Glyph(botC, options)),
        ]

        return axisCenterStackedVBox(makeVBox(ch), options)
    default:
        return nil
    }
}

/// If fixed-size glyphs cannot reach `totalHeight`, build a stacked / SVG delimiter.
func makeStackedDelimIfNeeded(
    _ delim: String, totalHeight: Double, bestGlyphTotal: Double, options: LayoutOptions
) -> LayoutBox? {
    if isStackNeverDelim(delim) {
        return nil
    }
    if bestGlyphTotal + 1e-6 >= totalHeight {
        return nil
    }
    guard let kind = classifyStackable(delim) else {
        return nil
    }

    switch kind {
    case .brace, .group:
        return makeGlyphStackDelim(kind, heightTotal: totalHeight, options: options)
    case .bracket, .paren, .lFloor, .rFloor, .lCeil, .rCeil:
        return makeTallSvgDelim(kind, heightTotal: totalHeight, options: options)
    }
}
