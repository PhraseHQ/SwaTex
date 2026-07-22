// Enclose (\fbox/\cancel/\phase/\angl), \raisebox, horizontal braces, xarrows,
// \textcircled, \imageof/\origof, and path helpers.
// Port of crates/ratex-layout/src/engine.rs (lines 3196–3509, 3961–4458).

/// Layout \fbox, \colorbox, \fcolorbox — framed/colored box.
/// Also handles \phase, \cancel, \sout, \bcancel, \xcancel.
func layoutEnclose(
    _ label: String, _ backgroundColor: String?, _ borderColor: String?,
    _ body: ParseNode, _ options: LayoutOptions
) -> LayoutBox {
    // \phase: angle mark (diagonal line) below the body with underline
    if label == "\\phase" {
        return layoutPhase(body, options)
    }

    // \angl: actuarial angle — arc/roof above the body (KaTeX actuarialangle-style)
    if label == "\\angl" {
        return layoutAngl(body, options)
    }

    // \cancel, \bcancel, \xcancel, \sout: strike-through overlays
    if label == "\\cancel" || label == "\\bcancel" || label == "\\xcancel" || label == "\\sout" {
        return layoutCancel(label, body, options)
    }

    // KaTeX defaults: fboxpad = 3pt, fboxrule = 0.4pt
    let metrics = options.metrics
    let padding = 3.0 / metrics.ptPerEm
    let borderThickness = 0.4 / metrics.ptPerEm

    let hasBorder = label == "\\fbox" || label == "\\fcolorbox"

    let bg = backgroundColor.flatMap { Color(name: $0) ?? Color(hex: $0) }
    let border = borderColor.flatMap { Color(name: $0) ?? Color(hex: $0) } ?? .black

    let inner = layoutNode(body, options)
    let outerPad = padding + (hasBorder ? borderThickness : 0.0)

    let width = inner.width + 2.0 * outerPad
    let height = inner.height + outerPad
    let depth = inner.depth + outerPad

    return LayoutBox(
        width: width,
        height: height,
        depth: depth,
        content: .framed(
            body: inner,
            padding: padding,
            borderThickness: borderThickness,
            hasBorder: hasBorder,
            bgColor: bg,
            borderColor: border),
        color: options.color)
}

/// Layout \raisebox{dy}{body} — shift content vertically.
func layoutRaiseBox(_ shift: Double, _ body: ParseNode, _ options: LayoutOptions) -> LayoutBox {
    let inner = layoutNode(body, options)
    // Positive shift moves content up → height increases, depth decreases
    let height = inner.height + shift
    let depth = max(inner.depth - shift, 0.0)
    let width = inner.width
    return LayoutBox(
        width: width,
        height: height,
        depth: depth,
        content: .raiseBox(body: inner, shift: shift),
        color: options.color)
}

/// Returns true if the parse node is a single character box (atom / mathord / textord),
/// mirroring KaTeX's `isCharacterBox` + `getBaseElem` logic.
func isSingleCharBody(_ node: ParseNode) -> Bool {
    switch node.kind {
    // Unwrap single-element ord-groups and styling nodes.
    case let .ordGroup(body, _) where body.count == 1:
        isSingleCharBody(body[0])
    case let .styling(_, body) where body.count == 1:
        isSingleCharBody(body[0])
    // Bare character nodes.
    case .atom, .mathOrd, .textOrd:
        true
    default:
        false
    }
}

/// Layout \cancel, \bcancel, \xcancel, \sout — body with strike-through line(s) overlay.
///
/// Matches KaTeX `enclose.ts` + `stretchy.ts` geometry:
///   • single char  → v_pad = 0.2em, h_pad = 0   (line corner-to-corner of w × (h+d+0.4) box)
///   • multi char   → v_pad = 0,     h_pad = 0.2em (cancel-pad: line extends 0.2em each side)
func layoutCancel(_ label: String, _ body: ParseNode, _ options: LayoutOptions) -> LayoutBox {
    let inner = layoutNode(body, options)
    let w = max(inner.width, 0.01)
    let h = inner.height
    let d = inner.depth

    // \sout uses no padding — the line spans exactly the content width/height.
    // KaTeX cancel padding: single character gets vertical extension, multi-char gets horizontal.
    let single = isSingleCharBody(body)
    let (vPad, hPad): (Double, Double) =
        if label == "\\sout" {
            (0.0, 0.0)
        } else if single {
            (0.2, 0.0)
        } else {
            (0.0, 0.2)
        }

    // Path coordinates: y=0 at baseline, y<0 above (height), y>0 below (depth).
    // \cancel  = "/" diagonal: bottom-left → top-right
    // \bcancel = "\" diagonal: top-left → bottom-right
    let commands: [PathCommand]
    switch label {
    case "\\cancel":
        commands = [
            .moveTo(x: -hPad, y: d + vPad),  // bottom-left
            .lineTo(x: w + hPad, y: -h - vPad),  // top-right
        ]
    case "\\bcancel":
        commands = [
            .moveTo(x: -hPad, y: -h - vPad),  // top-left
            .lineTo(x: w + hPad, y: d + vPad),  // bottom-right
        ]
    case "\\xcancel":
        commands = [
            .moveTo(x: -hPad, y: d + vPad),
            .lineTo(x: w + hPad, y: -h - vPad),
            .moveTo(x: -hPad, y: -h - vPad),
            .lineTo(x: w + hPad, y: d + vPad),
        ]
    case "\\sout":
        // Horizontal line at –0.5× x-height, extended to content edges.
        let midY = -0.5 * options.metrics.xHeight
        commands = [
            .moveTo(x: 0.0, y: midY),
            .lineTo(x: w, y: midY),
        ]
    default:
        commands = []
    }

    let lineW = w + 2.0 * hPad
    let lineH = h + vPad
    let lineD = d + vPad
    let lineBox = LayoutBox(
        width: lineW,
        height: lineH,
        depth: lineD,
        content: .svgPath(commands: commands, fill: false),
        color: options.color)

    // The line box starts at hbox x=0 and its path spans [-hPad, w+hPad], so
    // the content origin (x=0) is hPad in from the box's left edge. Pull the
    // body back by the full line-box width so its ink registers at x=0 and the
    // strike extends hPad past each side symmetrically (KaTeX cancel-pad).
    let bodyKern = -lineW
    let bodyShifted = makeHBox([.kern(bodyKern), inner])
    return LayoutBox(
        width: w,
        height: h,
        depth: d,
        content: .hbox([lineBox, bodyShifted]),
        color: options.color)
}

/// Layout \phase{body} — angle notation: body with a diagonal angle mark + underline.
/// Matches KaTeX `enclose.ts` + `phasePath(y)` (steinmetz): dynamic viewBox height, `x = y/2` at the peak.
func layoutPhase(_ body: ParseNode, _ options: LayoutOptions) -> LayoutBox {
    let metrics = options.metrics
    let inner = layoutNode(body, options)
    // KaTeX: lineWeight = 0.6pt, clearance = 0.35ex; angleHeight = inner.h + inner.d + both
    let lineWeight = 0.6 / metrics.ptPerEm
    let clearance = 0.35 * metrics.xHeight
    let angleHeight = inner.height + inner.depth + lineWeight + clearance
    let leftPad = angleHeight / 2.0 + lineWeight
    let width = inner.width + leftPad

    // KaTeX: viewBoxHeight = floor(1000 * angleHeight * scale); base sizing uses scale → 1 here.
    let ySvg = max((1000.0 * angleHeight).rounded(.down), 80.0)

    // Vertical: viewBox height ySvg → angleHeight em (baseline mapping below).
    let sy = angleHeight / ySvg
    // Horizontal: KaTeX SVG uses preserveAspectRatio xMinYMin slice — scale follows viewBox height,
    // so x grows ~sy per SVG unit (not width/400000). That keeps the left angle visible; clip to `width`.
    let sx = sy
    let rightX = min(400_000.0 * sx, width)

    // Baseline: peak at svg y=0 → -inner.height; bottom at y=ySvg → inner.depth + lineWeight + clearance
    let bottomY = inner.depth + lineWeight + clearance
    func vy(_ ySv: Double) -> Double {
        bottomY - (ySvg - ySv) * sy
    }

    // phasePath(y): M400000 y H0 L y/2 0 l65 45 L145 y-80 H400000z
    let xPeak = ySvg / 2.0
    let commands: [PathCommand] = [
        .moveTo(x: rightX, y: vy(ySvg)),
        .lineTo(x: 0.0, y: vy(ySvg)),
        .lineTo(x: xPeak * sx, y: vy(0.0)),
        .lineTo(x: (xPeak + 65.0) * sx, y: vy(45.0)),
        .lineTo(x: 145.0 * sx, y: vy(ySvg - 80.0)),
        .lineTo(x: rightX, y: vy(ySvg - 80.0)),
        .close,
    ]

    let bodyShifted = makeHBox([.kern(leftPad), inner])

    let pathHeight = inner.height
    let pathDepth = bottomY

    return LayoutBox(
        width: width,
        height: pathHeight,
        depth: pathDepth,
        content: .hbox([
            LayoutBox(
                width: width,
                height: pathHeight,
                depth: pathDepth,
                content: .svgPath(commands: commands, fill: true),
                color: options.color),
            .kern(-width),
            bodyShifted,
        ]),
        color: options.color)
}

/// Layout \angl{body} — actuarial angle: horizontal roof line above body + vertical bar on the right (KaTeX/fixture style).
/// Path and body share the same baseline; vertical bar runs from roof down through baseline to bottom of body.
func layoutAngl(_ body: ParseNode, _ options: LayoutOptions) -> LayoutBox {
    let inner = layoutNode(body, options)
    let w = max(inner.width, 0.3)
    // Roof line a bit higher: body_height + clearance
    let clearance = 0.1
    let arcH = inner.height + clearance

    // Path: horizontal roof (0,-arc_h) to (w,-arc_h), then vertical (w,-arc_h) down to (w, depth) so bar extends below baseline
    let pathCommands: [PathCommand] = [
        .moveTo(x: 0.0, y: -arcH),
        .lineTo(x: w, y: -arcH),
        .lineTo(x: w, y: inner.depth + 0.3),
    ]

    let height = arcH
    let depth = inner.depth
    return LayoutBox(
        width: w,
        height: height,
        depth: depth,
        content: .angl(pathCommands: pathCommands, body: inner),
        color: options.color)
}

// ============================================================================
// Horizontal brace layout (\overbrace, \underbrace)
// ============================================================================

func layoutHorizBrace(
    _ base: ParseNode, _ isOver: Bool, _ label: String, _ options: LayoutOptions
) -> LayoutBox {
    let bodyBox = layoutNode(base, options)
    let w = max(bodyBox.width, 0.5)

    let isBracket = label.drop(while: { $0 == "\\" }).hasSuffix("bracket")

    // `\overbrace`/`\underbrace` and mathtools `\overbracket`/`\underbracket`: KaTeX stretchy SVG (filled paths).
    let stretchKey =
        if isBracket {
            isOver ? "overbracket" : "underbracket"
        } else {
            isOver ? "overbrace" : "underbrace"
        }

    let (rawCommands, braceH, braceFill): ([PathCommand], Double, Bool)
    if let (c, h) = katexStretchyPath(stretchKey, widthEm: w) {
        (rawCommands, braceH, braceFill) = (c, h, true)
    } else {
        // INTENTIONALLY UNCOVERED (defensive-fallback KEEP): `stretchKey` is
        // always one of overbrace/underbrace/overbracket/underbracket, all
        // present in `katexImageData` with path names that resolve in
        // `pathForName`, so `katexStretchyPath` never returns nil here. Kept
        // as the correct behavior if the generated table loses an entry.
        let h = 0.35
        (rawCommands, braceH, braceFill) = (horizBracePath(w, h, isOver), h, false)
    }

    // Shift y-coordinates: centered commands → SVG-downward convention (height=0, depth=brace_h).
    // The raw path is centered at y=0 (range ±brace_h/2). Shift by +brace_h/2 so that:
    //   overbrace: peak at y=0 (top), feet at y=+brace_h (bottom)
    //   underbrace: feet at y=0 (top), peak at y=+brace_h (bottom)
    // Both use height=0, depth=brace_h so the rendering code's SVG accent path handles them.
    let yShift = braceH / 2.0
    let commands = rawCommands.shiftedY(yShift)

    let braceBox = LayoutBox(
        width: w,
        height: 0.0,
        depth: braceH,
        content: .svgPath(commands: commands, fill: braceFill),
        color: options.color)

    let gap = 0.1
    let (height, depth) =
        if isOver {
            (bodyBox.height + braceH + gap, bodyBox.depth)
        } else {
            (bodyBox.height, bodyBox.depth + braceH + gap)
        }

    let clearance =
        if isOver {
            height - braceH
        } else {
            bodyBox.height + bodyBox.depth + gap
        }
    let totalW = bodyBox.width

    return LayoutBox(
        width: totalW,
        height: height,
        depth: depth,
        content: .accent(
            base: bodyBox,
            accent: braceBox,
            clearance: clearance,
            skew: 0.0,
            isBelow: !isOver,
            underGapEm: 0.0),
        color: options.color)
}

// ============================================================================
// XArrow layout (\xrightarrow, \xleftarrow, etc.)
// ============================================================================

func layoutXArrow(
    _ label: String, _ body: ParseNode, _ below: ParseNode?, _ options: LayoutOptions
) -> LayoutBox {
    let supStyle = options.style.superscript
    let subStyle = options.style.subscript_
    let supRatio = supStyle.sizeMultiplier / options.style.sizeMultiplier
    let subRatio = subStyle.sizeMultiplier / options.style.sizeMultiplier

    let supOpts = options.with(style: supStyle)
    let bodyBox = layoutNode(body, supOpts)
    let bodyW = bodyBox.width * supRatio

    let belowBox = below.map { b in
        let subOpts = options.with(style: subStyle)
        return layoutNode(b, subOpts)
    }
    let belowW = belowBox.map { $0.width * subRatio } ?? 0.0

    // KaTeX `katexImagesData` minWidth on the stretchy SVG, plus `.x-arrow-pad { padding: 0 0.5em }`
    // on each label row (em = that row's font). In parent em: +0.5·sup_ratio + 0.5·sup_ratio, etc.
    let minW = katexStretchyMinWidthEm(label) ?? 1.0
    let upperW = bodyW + supRatio
    let lowerW = belowBox != nil ? belowW + subRatio : 0.0
    let arrowW = max(max(upperW, lowerW), minW)
    let arrowH = 0.3

    let (commands, actualArrowH, fillArrow): ([PathCommand], Double, Bool)
    if let (c, h) = katexStretchyPath(label, widthEm: arrowW) {
        (commands, actualArrowH, fillArrow) = (c, h, true)
    } else {
        (commands, actualArrowH, fillArrow) = (
            stretchyAccentPath(label, arrowW, arrowH),
            arrowH,
            label == "\\xtwoheadrightarrow" || label == "\\xtwoheadleftarrow"
        )
    }
    let arrowBox = LayoutBox(
        width: arrowW,
        height: actualArrowH / 2.0,
        depth: actualArrowH / 2.0,
        content: .svgPath(commands: commands, fill: fillArrow),
        color: options.color)

    // KaTeX positions xarrows centered on the math axis, with a 0.111em (2mu) gap
    // between the arrow and the text above/below (see amsmath.dtx reference).
    let metrics = options.metrics
    let axis = metrics.axisHeight  // 0.25em
    let arrowHalf = actualArrowH / 2.0
    let gap = 0.111  // 2mu gap (KaTeX constant)

    // Center the arrow on the math axis by shifting it up.
    let baseShift = -axis

    // sup_kern: gap between arrow top and text bottom.
    // In the OpLimits renderer:
    //   sup_y = y - (arrow_half - base_shift) - sup_kern - sup_box.depth * ratio
    //         = y - (arrow_half + axis) - sup_kern - sup_box.depth * ratio
    // KaTeX: text_baseline = -(axis + arrow_half + gap)
    //   (with extra -= depth when depth > 0.25, but that's rare for typical text)
    // Matching: sup_kern = gap
    let supKern = gap
    let subKern = gap

    let supH = bodyBox.height * supRatio
    let supD = bodyBox.depth * supRatio

    // Height: from baseline to top of upper text
    let height = axis + arrowHalf + gap + supH + supD
    // Depth: arrow bottom below baseline = arrow_half - axis
    var depth = max(arrowHalf - axis, 0.0)

    if let bel = belowBox {
        let subH = bel.height * subRatio
        let subD = bel.depth * subRatio
        // Lower text positioned symmetrically below the arrow
        depth = (arrowHalf - axis) + gap + subH + subD
    }

    return LayoutBox(
        width: arrowW,
        height: height,
        depth: depth,
        content: .opLimits(
            base: arrowBox,
            sup: bodyBox,
            sub: belowBox,
            baseShift: baseShift,
            supKern: supKern,
            subKern: subKern,
            slant: 0.0,
            supScale: supRatio,
            subScale: subRatio),
        color: options.color)
}

// ============================================================================
// \textcircled layout
// ============================================================================

func layoutTextcircled(_ bodyBox: LayoutBox, _ options: LayoutOptions) -> LayoutBox {
    // Draw a circle around the content, similar to KaTeX's CSS-based approach
    let pad = 0.1  // padding around the content
    let totalH = bodyBox.height + bodyBox.depth
    let radius = max(max(bodyBox.width, totalH) / 2.0 + pad, 0.35)
    let diameter = radius * 2.0

    // Build a circle path using cubic Bezier approximation
    let cx = radius
    let cy = -(bodyBox.height - totalH / 2.0)  // center at vertical center of content
    let k = 0.5523  // cubic Bezier approximation of circle: 4*(sqrt(2)-1)/3
    let r = radius

    let circleCommands: [PathCommand] = [
        .moveTo(x: cx + r, y: cy),
        .cubicTo(x1: cx + r, y1: cy - k * r, x2: cx + k * r, y2: cy - r, x: cx, y: cy - r),
        .cubicTo(x1: cx - k * r, y1: cy - r, x2: cx - r, y2: cy - k * r, x: cx - r, y: cy),
        .cubicTo(x1: cx - r, y1: cy + k * r, x2: cx - k * r, y2: cy + r, x: cx, y: cy + r),
        .cubicTo(x1: cx + k * r, y1: cy + r, x2: cx + r, y2: cy + k * r, x: cx + r, y: cy),
        .close,
    ]

    let circleBox = LayoutBox(
        width: diameter,
        height: r - min(cy, 0.0),
        depth: max(r + cy, 0.0),
        content: .svgPath(commands: circleCommands, fill: false),
        color: options.color)

    // Center the content inside the circle
    let contentShift = (diameter - bodyBox.width) / 2.0
    // Shift content to the right to center it
    let children = [
        circleBox,
        LayoutBox.kern(-diameter + contentShift),
        bodyBox,
    ]

    let height = r - min(cy, 0.0)
    let depth = max(r + cy, 0.0)

    return LayoutBox(
        width: diameter,
        height: height,
        depth: depth,
        content: .hbox(children),
        color: options.color)
}

// ============================================================================
// \imageof / \origof  (U+22B7 / U+22B6)
// ============================================================================

/// Synthesise \imageof (•—○) or \origof (○—•).
///
/// Neither glyph exists in any KaTeX font.  We build each symbol as an HBox
/// of three pieces:
///   disk  : filled circle SVG path
///   bar   : Rule (horizontal segment at circle-centre height)
///   ring  : stroked circle SVG path
///
/// The ordering is reversed for \origof.
///
/// Dimensions are calibrated against the KaTeX reference PNG (DPR=2, 20px font):
///   ink bbox ≈ 0.700w × 0.225h em, centre ≈ 0.263em above baseline.
///
/// Coordinate convention in path commands:
///   origin = baseline-left of the box, x right, y positive → below baseline.
func layoutImageofOrigof(imageof: Bool, _ options: LayoutOptions) -> LayoutBox {
    // Disk radius: filled circle ink height = 2·r = 0.225em  →  r = 0.1125em
    let r = 0.1125
    // Circle centre above baseline (negative = above in path coords).
    // Calibrated to the math axis (≈0.25em) so both symbols sit at the same height
    // as the reference KaTeX rendering.
    let cy = -0.2625
    // Cubic-Bezier circle approximation constant (4*(√2−1)/3)
    let k = 0.5523
    // Each circle sub-box is 2r wide; the circle centre sits at x = r within it.
    let cx = r

    // Box height/depth: symbol sits entirely above baseline.
    let h = r + abs(cy)  // 0.1125 + 0.2625 = 0.375
    let d = 0.0

    // The renderer strokes rings with width = 1.5 × DPR pixels.
    // At the golden-test resolution (font=40px, DPR=1) that is 1.5 px = 0.0375em.
    // To keep the ring's outer ink edge coincident with the disk's outer edge,
    // draw the ring path at r_ring = r − stroke_half so the outer ink = r − stroke_half + stroke_half = r.
    let strokeHalf = 0.01875  // 0.75px / 40px·em⁻¹
    let rRing = r - strokeHalf  // 0.09375em

    // Closed circle path (counter-clockwise) centred at (ox, cy) with radius rad.
    func circleCommands(_ ox: Double, _ rad: Double) -> [PathCommand] {
        [
            .moveTo(x: ox + rad, y: cy),
            .cubicTo(
                x1: ox + rad, y1: cy - k * rad, x2: ox + k * rad, y2: cy - rad,
                x: ox, y: cy - rad),
            .cubicTo(
                x1: ox - k * rad, y1: cy - rad, x2: ox - rad, y2: cy - k * rad,
                x: ox - rad, y: cy),
            .cubicTo(
                x1: ox - rad, y1: cy + k * rad, x2: ox - k * rad, y2: cy + rad,
                x: ox, y: cy + rad),
            .cubicTo(
                x1: ox + k * rad, y1: cy + rad, x2: ox + rad, y2: cy + k * rad,
                x: ox + rad, y: cy),
            .close,
        ]
    }

    let disk = LayoutBox(
        width: 2.0 * r,
        height: h,
        depth: d,
        content: .svgPath(commands: circleCommands(cx, r), fill: true),
        color: options.color)

    let ring = LayoutBox(
        width: 2.0 * r,
        height: h,
        depth: d,
        content: .svgPath(commands: circleCommands(cx, rRing), fill: false),
        color: options.color)

    // Connecting bar centred on the same axis as the circles.
    // Rule.raise = distance from baseline to the bottom edge of the rule.
    // bar centre at |cy| = 0.2625em  →  raise = 0.2625 − bar_th/2
    let barLen = 0.25
    let barTh = 0.04
    let barRaise = abs(cy) - barTh / 2.0  // 0.2625 − 0.02 = 0.2425

    let bar = LayoutBox.rule(
        width: barLen, height: h, depth: d, thickness: barTh, raise: barRaise,
        color: options.color)

    let children = imageof ? [disk, bar, ring] : [ring, bar, disk]

    // Total width = 2r (disk) + bar_len + 2r (ring) = 0.225 + 0.25 + 0.225 = 0.700em
    let totalWidth = 4.0 * r + barLen
    return LayoutBox(
        width: totalWidth,
        height: h,
        depth: d,
        content: .hbox(children),
        color: options.color)
}

// ============================================================================
// Path generation helpers
// ============================================================================

/// Build path commands for a horizontal ellipse (circle overlay for \oiint, \oiiint).
/// Box-local coords: origin at baseline-left, x right, y down (positive = below baseline).
/// Ellipse is centered in the box and spans most of the integral width.
func ellipseOverlayPath(_ width: Double, _ height: Double, _ depth: Double) -> [PathCommand] {
    let cx = width / 2.0
    let cy = (depth - height) / 2.0  // vertical center
    let a = width * 0.402  // horizontal semi-axis (0.36 * 1.2)
    let b = 0.3  // vertical semi-axis (0.1 * 2)
    let k = 0.62  // Bezier factor: larger = fuller ellipse (0.5523 ≈ exact circle)
    return [
        .moveTo(x: cx + a, y: cy),
        .cubicTo(x1: cx + a, y1: cy - k * b, x2: cx + k * a, y2: cy - b, x: cx, y: cy - b),
        .cubicTo(x1: cx - k * a, y1: cy - b, x2: cx - a, y2: cy - k * b, x: cx - a, y: cy),
        .cubicTo(x1: cx - a, y1: cy + k * b, x2: cx - k * a, y2: cy + b, x: cx, y: cy + b),
        .cubicTo(x1: cx + k * a, y1: cy + b, x2: cx + a, y2: cy + k * b, x: cx + a, y: cy),
        .close,
    ]
}
