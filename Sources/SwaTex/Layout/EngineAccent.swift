// Accent layout.
// Port of crates/ratex-layout/src/engine.rs (lines 1680–2014).

/// `\vec` KaTeX SVG: nudge slightly right to match KaTeX reference.
private let vecSkewExtraRightEm = 0.018

/// Extract the italic correction of the base glyph.
/// Used by superscripts: KaTeX adds margin-right = italic correction to italic math
/// characters, so the superscript starts at advanceWidth + italicCorrection (not just
/// advanceWidth).
func glyphItalic(_ lb: LayoutBox) -> Double {
    switch lb.content {
    case let .glyph(fontId, charCode):
        fontId.metrics(forChar: charCode)?.italic ?? 0
    case let .hbox(children):
        children.last.map(glyphItalic) ?? 0
    default:
        0
    }
}

/// KaTeX `groupLength` for wide SVG accents: `ordgroup.body.length`, else 1.
func accentOrdgroupLen(_ base: ParseNode) -> Int {
    if case let .ordGroup(body, _) = base.kind {
        return max(body.count, 1)
    }
    return 1
}

/// Extract the skew (italic correction) of the innermost/last glyph in a box.
/// Used by shifty accents (\hat, \tilde…) to horizontally centre the mark
/// over italic math letters (e.g. M in MathItalic has skew ≈ 0.083em).
func glyphSkew(_ lb: LayoutBox) -> Double {
    switch lb.content {
    case let .glyph(fontId, charCode):
        fontId.metrics(forChar: charCode)?.skew ?? 0
    case let .hbox(children):
        children.last.map(glyphSkew) ?? 0
    default:
        0
    }
}

func layoutAccent(
    _ label: String, _ base: ParseNode, _ isStretchy: Bool, _ isShifty: Bool,
    _ isBelow: Bool, _ options: LayoutOptions
) -> LayoutBox {
    let bodyBox = layoutNode(base, options)
    let baseW = max(bodyBox.width, 0.5)

    // Special handling for \textcircled: draw a circle around the content
    if label == "\\textcircled" {
        return layoutTextcircled(bodyBox, options)
    }

    // Try KaTeX exact SVG paths first (widehat, widetilde, overgroup, etc.).
    // The path width must stay inside the accent box; renderers size their canvas from
    // DisplayList.width, so drawing wider than the box clips in an enclosing HBox.
    let accentTargetW = baseW
    if let (commands, w, h, fill) = katexAccentPath(
        label, baseWidthEm: accentTargetW, groupLen: accentOrdgroupLen(base))
    {
        // KaTeX paths use SVG coords (y down): height=0, depth=h
        let accentBox = LayoutBox(
            width: w, height: 0, depth: h,
            content: .svgPath(commands: commands, fill: fill),
            color: options.color)
        // KaTeX `accent.ts` uses `clearance = min(body.height, xHeight)` for ordinary
        // accents. That matches fixed-size `\vec` (svgData.vec); using it for *width-scaled*
        // SVG accents (\widehat, \widetilde, \overgroup, …) pulls the path down onto the
        // base (golden 0604/0885/0886). Slightly tighter than 0.08em — aligns wide SVG hats
        // with KaTeX PNG crops (e.g. 0935).
        let gap = 0.065
        let underGapEm = isBelow && label == "\\utilde" ? 0.12 : 0.0
        let clearance: Double =
            if isBelow {
                bodyBox.height + bodyBox.depth + gap
            } else if label == "\\vec" {
                // KaTeX: clearance = min(body.height, xHeight) is used as *overlap*
                // (kern down). Equivalent position:
                // vec bottom = body.height - overlap = max(0, body.height - xHeight).
                max(bodyBox.height - options.metrics.xHeight, 0)
            } else {
                bodyBox.height + gap
            }
        let (height, depth): (Double, Double) =
            if isBelow {
                (bodyBox.height, bodyBox.depth + h + gap + underGapEm)
            } else if label == "\\vec" {
                // Box height = clearance + H_EM, matching KaTeX VList height.
                (clearance + h, bodyBox.depth)
            } else {
                (bodyBox.height + gap + h, bodyBox.depth)
            }
        let vecSkew =
            label == "\\vec"
            ? (isShifty ? glyphSkew(bodyBox) : 0) + vecSkewExtraRightEm
            : 0.0
        return LayoutBox(
            width: bodyBox.width, height: height, depth: depth,
            content: .accent(
                base: bodyBox, accent: accentBox, clearance: clearance,
                skew: vecSkew, isBelow: isBelow, underGapEm: underGapEm),
            color: options.color)
    }

    // Arrow-type stretchy accents (overrightarrow, etc.)
    let useArrowPath = isStretchy && isArrowAccent(label)

    let accentBox: LayoutBox
    if useArrowPath {
        let (commands, arrowH, fillArrow): ([PathCommand], Double, Bool)
        if let (c, h) = katexStretchyPath(label, widthEm: baseW) {
            (commands, arrowH, fillArrow) = (c, h, true)
        } else {
            let h = 0.3
            let c = stretchyAccentPath(label, baseW, h)
            let fill = label == "\\xtwoheadrightarrow" || label == "\\xtwoheadleftarrow"
            (commands, arrowH, fillArrow) = (c, h, fill)
        }
        accentBox = LayoutBox(
            width: baseW, height: arrowH / 2, depth: arrowH / 2,
            content: .svgPath(commands: commands, fill: fillArrow),
            color: options.color)
    } else {
        // Try text mode first for text accents (\c, \', \`, etc.), fall back to math
        let accentChar: Unicode.Scalar = {
            let ch = resolveSymbolChar(label, .text)
            if ch == (label.unicodeScalars.first ?? "?") {
                // Text mode didn't resolve (returned first char of label, likely '\')
                // so try math mode
                return resolveSymbolChar(label, .math)
            }
            return ch
        }()
        let accentCode = accentChar.value
        let accentMetrics = FontId.mainRegular.metrics(forChar: accentCode)
        let (accentW, accentH, accentD) =
            accentMetrics.map { ($0.width, $0.height, $0.depth) } ?? (bodyBox.width, 0.25, 0.0)
        accentBox = LayoutBox(
            width: accentW, height: accentH, depth: accentD,
            content: .glyph(fontId: .mainRegular, charCode: accentCode),
            color: options.color)
    }

    let skew: Double =
        if useArrowPath {
            0
        } else if isShifty {
            // For shifty accents (\hat, \tilde, etc.) shift by the BASE character's skew,
            // which encodes the italic correction in math-italic fonts (e.g. M → 0.083em).
            glyphSkew(bodyBox)
        } else {
            0
        }

    // gap = clearance between body top and bottom of accent SVG.
    // For arrow accents, the SVG path is centered (height=h/2, depth=h/2).
    // The gap prevents the visible arrowhead / harpoon tip from overlapping the base top.
    //
    // KaTeX stretchy arrows with vb_height 522 have h/2 ≈ 0.261em; default gap=0.12 left
    // too little room for tall caps (`\overleftrightarrow{AB}`, `\overleftarrow{AB}`,
    // `\overleftharpoon{AB}`, …).  `\Overrightarrow` uses a taller glyph (vb 560) and keeps
    // the slightly smaller kern used in prior tuning.
    let gap: Double = useArrowPath ? (label == "\\Overrightarrow" ? 0.21 : 0.26) : 0.0

    let clearance: Double
    if isBelow {
        clearance = bodyBox.height + bodyBox.depth + accentBox.depth + gap
    } else if useArrowPath {
        clearance = bodyBox.height + gap
    } else {
        // Clearance = how high above baseline the accent is positioned.
        // - For simple letters (M, b, o): bodyBox.height is the letter top → use directly.
        // - For a body that is itself an above-accent (\r{a}, `\tilde{\tilde{x}}`, …):
        //   use the same kern basis as a plain base (`max(0, body.height - xHeight) +
        //   correction`, with `\bar`/`\=` exceptions) instead of `innerClearance + ε`,
        //   which double-counted stacked accent depths and inflated nested spacing vs KaTeX.
        var baseClearance: Double
        if case let .accent(_, innerAccent, innerCl, _, innerIsBelow, _) = bodyBox.content,
            !innerIsBelow
        {
            // For SVG accents (height≈0, e.g. \vec): bodyBox.height = clearance + H_EM,
            // which matches KaTeX's body.height. Use min(body.height, xHeight) exactly as
            // KaTeX does: clearance = min(body.height, xHeight).
            if innerAccent.height <= 0.001 {
                // For SVG accents like \vec: KaTeX places the outer glyph accent with
                // its baseline at body.height - min(body.height, xHeight) above formula
                // baseline, i.e. max(0, body.height - xHeight).
                // ToDisplay shifts the glyph DOWN by (accentH - min(0.35, accentH))
                // so we pre-add that correction to land at the right position.
                let katexPos = max(bodyBox.height - options.metrics.xHeight, 0)
                let correction = max(accentBox.height - min(0.35, accentBox.height), 0)
                baseClearance = katexPos + correction
            } else {
                // `innerCl` already includes the inner accent glyph's depth. Using
                // `innerCl + ε` stacked another full kern on top (e.g. `\tilde{\tilde{x}}`
                // blew up to ~1.32em vs KaTeX ~0.90em). KaTeX recomputes clearance from the
                // built inner span via `min(body.height, xHeight)`; matching the non-nested
                // glyph path (`max(0, body.height - xHeight) + correction`) tracks that.
                if label == "\\bar" || label == "\\=" {
                    baseClearance = bodyBox.height
                } else {
                    // `\hat{x}` / `\dot{x}` / … enforce a 0.78056em strut so
                    // `bodyBox.height` exceeds the ink top, while KaTeX's nested accent
                    // still uses the inner span height (~0.6944em) for clearance.
                    // `\tilde{x}` keeps body ≈ visual top, so we keep `bodyBox.height`
                    // when it is not strut-inflated.
                    let innerVisualTop = innerCl + min(0.35, innerAccent.height)
                    let hForKern =
                        bodyBox.height > innerVisualTop + 0.002 ? innerVisualTop : bodyBox.height
                    let katexPos = max(hForKern - options.metrics.xHeight, 0)
                    let correction = max(accentBox.height - min(0.35, accentBox.height), 0)
                    baseClearance = katexPos + correction
                }
            }
        } else {
            // KaTeX positions glyph accents by kerning DOWN by
            // min(body.height, xHeight), so the accent baseline sits at
            //   max(0, body.height - xHeight)
            // above the formula baseline.  This keeps the accent within the
            // body's height bounds for normal-height bases and produces a
            // formula height == bodyHeight (accent adds no extra height),
            // matching KaTeX's VList.
            //
            // \bar / \= (macron) are an exception: for x-height bases (a, e, o, …)
            // body.height ≈ xHeight so katexPos ≈ 0 and the bar sits on the letter
            // (golden \text{\={a}}).  Tie macron clearance to full body height like
            // the pre-62f7ba53 engine, then apply the same small kern as before.
            if label == "\\bar" || label == "\\=" {
                baseClearance = bodyBox.height
            } else {
                let katexPos = max(bodyBox.height - options.metrics.xHeight, 0)
                let correction = max(accentBox.height - min(0.35, accentBox.height), 0)
                baseClearance = katexPos + correction
            }
        }
        // KaTeX VList places the accent so its depth-bottom edge sits at the kern
        // position.  The accent baseline is therefore depth higher than that edge.
        // Without this term, glyphs with non-zero depth (notably \tilde, depth=0.35)
        // are positioned too low, overlapping the base character.
        baseClearance += accentBox.depth
        clearance =
            label == "\\bar" || label == "\\=" ? max(baseClearance - 0.12, 0) : baseClearance
    }

    let (height, depth): (Double, Double)
    if isBelow {
        height = bodyBox.height
        depth = bodyBox.depth + accentBox.height + accentBox.depth + gap
    } else if useArrowPath {
        height = bodyBox.height + gap + accentBox.height
        depth = bodyBox.depth
    } else {
        // ToDisplay shifts every glyph accent DOWN by max(0, accent.height - 0.35),
        // so the actual visual top of the accent mark = clearance + min(0.35, accent.height).
        // Use this for the layout height so nested accents (e.g. \hat{\r{a}}) see the
        // correct base height instead of the over-estimated clearance + accent.height.
        // For \hat, \bar, \dot, \ddot: also enforce KaTeX's 0.78056em strut so that
        // short bases (xHeight ≈ 0.43) produce consistent line spacing.
        let accentAboveStrutHeightEm = 0.78056
        let accentVisualTop = clearance + min(0.35, accentBox.height)
        let h: Double =
            switch label {
            case "\\hat", "\\bar", "\\=", "\\dot", "\\ddot":
                max(accentVisualTop, accentAboveStrutHeightEm)
            default:
                max(bodyBox.height, accentVisualTop)
            }
        height = h
        depth = bodyBox.depth
    }

    return LayoutBox(
        width: bodyBox.width, height: height, depth: depth,
        content: .accent(
            base: bodyBox, accent: accentBox, clearance: clearance,
            skew: skew, isBelow: isBelow, underGapEm: 0),
        color: options.color)
}
