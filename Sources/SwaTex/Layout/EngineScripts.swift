// Fraction, superscript/subscript, and radical layout (TeX Rules 15d, 18, 11).
// Port of crates/ratex-layout/src/engine.rs (lines 887–1279).

// ============================================================================
// Fraction layout (TeX Rule 15d)
// ============================================================================

func layoutFraction(
    _ numer: ParseNode, _ denom: ParseNode, _ barThickness: Double,
    _ continued: Bool, _ options: LayoutOptions
) -> LayoutBox {
    let numerS = options.style.numerator
    let denomS = options.style.denominator
    let numerStyle = options.with(style: numerS)
    let denomStyle = options.with(style: denomS)

    var numerBox = layoutNode(numer, numerStyle)
    // KaTeX genfrac.js: `\cfrac` pads the numerator with a \strut (TeXbook p.353): 8.5pt × 3.5pt.
    if continued {
        let pt = options.metrics.ptPerEm
        let hMin = 8.5 / pt
        let dMin = 3.5 / pt
        if numerBox.height < hMin {
            numerBox.height = hMin
        }
        if numerBox.depth < dMin {
            numerBox.depth = dMin
        }
    }
    let denomBox = layoutNode(denom, denomStyle)

    // Size ratios for converting child em to parent em
    let numerRatio = numerS.sizeMultiplier / options.style.sizeMultiplier
    let denomRatio = denomS.sizeMultiplier / options.style.sizeMultiplier

    let numerHeight = numerBox.height * numerRatio
    let numerDepth = numerBox.depth * numerRatio
    let denomHeight = denomBox.height * denomRatio
    let denomDepth = denomBox.depth * denomRatio
    let numerWidth = numerBox.width * numerRatio
    let denomWidth = denomBox.width * denomRatio

    let metrics = options.metrics
    let axis = metrics.axisHeight
    let rule = barThickness

    // TeX Rule 15d: choose shift amounts based on display/text mode
    var (numShift, denShift): (Double, Double) =
        if options.style.isDisplay {
            (metrics.num1, metrics.denom1)
        } else if barThickness > 0 {
            (metrics.num2, metrics.denom2)
        } else {
            (metrics.num3, metrics.denom2)
        }

    if barThickness > 0 {
        let minClearance = options.style.isDisplay ? 3 * rule : rule

        let numClearance = (numShift - numerDepth) - (axis + rule / 2)
        if numClearance < minClearance {
            numShift += minClearance - numClearance
        }

        let denClearance = (axis - rule / 2) + (denShift - denomHeight)
        if denClearance < minClearance {
            denShift += minClearance - denClearance
        }
    } else {
        let minGap =
            options.style.isDisplay
            ? 7 * metrics.defaultRuleThickness
            : 3 * metrics.defaultRuleThickness

        let gap = (numShift - numerDepth) - (denomHeight - denShift)
        if gap < minGap {
            let adjust = (minGap - gap) / 2
            numShift += adjust
            denShift += adjust
        }
    }

    return LayoutBox(
        width: max(numerWidth, denomWidth),
        height: numerHeight + numShift,
        depth: denomDepth + denShift,
        content: .fraction(
            numer: numerBox, denom: denomBox,
            numerShift: numShift, denomShift: denShift, barThickness: rule,
            numerScale: numerRatio, denomScale: denomRatio),
        color: options.color)
}

// ============================================================================
// Superscript/Subscript layout
// ============================================================================

func layoutSupSub(
    _ base: ParseNode?, _ sup: ParseNode?, _ sub: ParseNode?,
    _ options: LayoutOptions, _ inheritedFont: FontId?
) -> LayoutBox {
    func layoutChild(_ n: ParseNode, _ opts: LayoutOptions) -> LayoutBox {
        if let fid = inheritedFont {
            layoutWithFont(n, fid, opts)
        } else {
            layoutNode(n, opts)
        }
    }

    var horizBraceOver = false
    var horizBraceUnder = false
    if let base, case let .horizBrace(_, isOver, _) = base.kind {
        horizBraceOver = isOver
        horizBraceUnder = !isOver
    }
    let centerScripts = horizBraceOver || horizBraceUnder

    let baseBox = base.map { layoutChild($0, options) } ?? .empty

    let isCharBox = base.map(isCharacterBox) ?? false
    let metrics = options.metrics
    // KaTeX `supsub.js`: each script span gets `marginRight: (0.5pt/ptPerEm)/sizeMultiplier`
    // (TeX `\scriptspace`). Without this, sub/sup boxes are too narrow vs KaTeX (e.g. `pmatrix`
    // column widths and inter-column alignment in golden tests).
    let scriptSpace = 0.5 / metrics.ptPerEm / options.sizeMultiplier

    let supStyle = options.style.superscript
    let subStyle = options.style.subscript_

    let supRatio = supStyle.sizeMultiplier / options.style.sizeMultiplier
    let subRatio = subStyle.sizeMultiplier / options.style.sizeMultiplier

    let supBox = sup.map { layoutChild($0, options.with(style: supStyle)) }
    let subBox = sub.map { layoutChild($0, options.with(style: subStyle)) }

    let supHeightScaled = supBox.map { $0.height * supRatio } ?? 0
    let supDepthScaled = supBox.map { $0.depth * supRatio } ?? 0
    let subHeightScaled = subBox.map { $0.height * subRatio } ?? 0
    let subDepthScaled = subBox.map { $0.depth * subRatio } ?? 0

    // KaTeX uses the CHILD style's metrics for supDrop/subDrop, not the parent's
    let supStyleMetrics = MathConstants.forSize(supStyle.sizeIndex)
    let subStyleMetrics = MathConstants.forSize(subStyle.sizeIndex)

    // Rule 18a: initial shift from base dimensions.
    // For character boxes, supShift/subShift start at 0 (KaTeX behavior)
    var supShift =
        !isCharBox && supBox != nil
        ? baseBox.height - supStyleMetrics.supDrop * supRatio
        : 0.0

    var subShift =
        !isCharBox && subBox != nil
        ? baseBox.depth + subStyleMetrics.subDrop * subRatio
        : 0.0

    let minSupShift =
        options.style.isCramped
        ? metrics.sup3
        : options.style.isDisplay ? metrics.sup1 : metrics.sup2

    if supBox != nil && subBox != nil {
        // Rule 18c+e: both sup and sub
        supShift = max(supShift, minSupShift, supDepthScaled + 0.25 * metrics.xHeight)
        subShift = max(subShift, metrics.sub2)  // sub2 when both present

        let ruleWidth = metrics.defaultRuleThickness
        let maxWidth = 4 * ruleWidth
        let gap = (supShift - supDepthScaled) - (subHeightScaled - subShift)
        if gap < maxWidth {
            subShift = maxWidth - (supShift - supDepthScaled) + subHeightScaled
            let psi = 0.8 * metrics.xHeight - (supShift - supDepthScaled)
            if psi > 0 {
                supShift += psi
                subShift -= psi
            }
        }
    } else if subBox != nil {
        // Rule 18b: sub only
        subShift = max(subShift, metrics.sub1, subHeightScaled - 0.8 * metrics.xHeight)
    } else if supBox != nil {
        // Rule 18c,d: sup only
        supShift = max(supShift, minSupShift, supDepthScaled + 0.25 * metrics.xHeight)
    }

    // KaTeX `horizBrace.js` htmlBuilder: the script is placed using a VList with a fixed
    // 0.2em kern between the brace result and the script, plus the script's own (scaled)
    // dimensions. This overrides the default TeX Rule 18 subShift / supShift with the
    // exact KaTeX layout.
    if horizBraceOver && supBox != nil {
        supShift = baseBox.height + 0.2 + supDepthScaled
    }
    if horizBraceUnder && subBox != nil {
        subShift = baseBox.depth + 0.2 + subHeightScaled
    }

    // Superscript horizontal offset: `layoutSymbol` already uses advance width + italic
    // (KaTeX `margin-right: italic`), so we must not add `glyphItalic` again here.
    let italicCorrection = 0.0

    // KaTeX `supsub.js`: for SymbolNode bases, subscripts get `margin-left: -base.italic`
    // so they are not shifted by the base's italic correction (e.g. ∫_{A_1}).
    let subHKern = subBox != nil && !centerScripts ? -glyphItalic(baseBox) : 0.0

    // Compute total dimensions (using scaled child dimensions)
    var height = baseBox.height
    var depth = baseBox.depth
    var totalWidth = baseBox.width

    if let supB = supBox {
        height = max(height, supShift + supHeightScaled)
        if centerScripts {
            totalWidth = max(totalWidth, supB.width * supRatio + scriptSpace)
        } else {
            totalWidth = max(
                totalWidth,
                baseBox.width + italicCorrection + supB.width * supRatio + scriptSpace)
        }
    }
    if let subB = subBox {
        depth = max(depth, subShift + subDepthScaled)
        if centerScripts {
            totalWidth = max(totalWidth, subB.width * subRatio + scriptSpace)
        } else {
            totalWidth = max(
                totalWidth,
                baseBox.width + subHKern + subB.width * subRatio + scriptSpace)
        }
    }

    return LayoutBox(
        width: totalWidth, height: height, depth: depth,
        content: .supSub(
            base: baseBox, sup: supBox, sub: subBox,
            supShift: supShift, subShift: subShift,
            supScale: supRatio, subScale: subRatio,
            centerScripts: centerScripts,
            italicCorrection: italicCorrection, subHKern: subHKern),
        color: options.color)
}

// ============================================================================
// Radical (square root) layout
// ============================================================================

func layoutRadical(
    _ body: ParseNode, _ index: ParseNode?, _ options: LayoutOptions
) -> LayoutBox {
    let cramped = options.style.cramped
    let crampedOpts = options.with(style: cramped)
    var bodyBox = layoutNode(body, crampedOpts)

    // Cramped style has same sizeMultiplier as uncramped
    let bodyRatio = cramped.sizeMultiplier / options.style.sizeMultiplier
    bodyBox.height *= bodyRatio
    bodyBox.depth *= bodyRatio
    bodyBox.width *= bodyRatio

    // Ensure non-zero inner height (KaTeX: if inner.height === 0, use xHeight)
    if bodyBox.height == 0 {
        bodyBox.height = options.metrics.xHeight
    }

    let metrics = options.metrics
    let theta = metrics.defaultRuleThickness  // 0.04 for textstyle

    // KaTeX sqrt.js: `let phi = theta; if (options.style.id < Style.TEXT.id) phi = xHeight`.
    // Style ids 0–1 are DISPLAY / DISPLAY_CRAMPED; TEXT is id 2. So only display styles
    // use xHeight.
    let phi = options.style.isDisplay ? metrics.xHeight : theta

    var lineClearance = theta + phi / 4

    // Minimum delimiter height needed
    let minDelimHeight = bodyBox.height + bodyBox.depth + lineClearance + theta

    // Select surd glyph size (simplified: use known breakpoints)
    // KaTeX surd sizes: small=1.0, size1=1.2, size2=1.8, size3=2.4, size4=3.0
    let texHeight = selectSurdHeight(minDelimHeight)
    let ruleWidth = theta
    let surdFontId = surdFont(forInnerHeight: texHeight)
    let advanceWidth = surdFontId.metrics(forChar: 0x221A)?.width ?? 0.833

    // Check if delimiter is taller than needed → center the extra space
    let delimDepth = texHeight - ruleWidth
    if delimDepth > bodyBox.height + bodyBox.depth + lineClearance {
        lineClearance = (lineClearance + delimDepth - bodyBox.height - bodyBox.depth) / 2
    }

    let imgShift = texHeight - bodyBox.height - lineClearance - ruleWidth

    // Compute final box dimensions via vlist logic:
    // height = inner.height + lineClearance + 2*ruleWidth when inner.depth=0
    let height = texHeight + ruleWidth - imgShift
    let depth = imgShift > bodyBox.depth ? imgShift : bodyBox.depth

    // Root index (e.g. \sqrt[3]{x}): KaTeX uses SCRIPTSCRIPT (TeX: superscript of superscript).
    let indexKern = 0.05
    let (indexBox, indexOffset, indexScale): (LayoutBox?, Double, Double)
    if let indexNode = index {
        let rootStyle = options.style.superscript.superscript
        let rootOpts = options.with(style: rootStyle)
        let idx = layoutNode(indexNode, rootOpts)
        let indexRatio = rootStyle.sizeMultiplier / options.style.sizeMultiplier
        (indexBox, indexOffset, indexScale) = (idx, idx.width * indexRatio + indexKern, indexRatio)
    } else {
        (indexBox, indexOffset, indexScale) = (nil, 0, 1)
    }

    return LayoutBox(
        width: indexOffset + advanceWidth + bodyBox.width,
        height: height,
        depth: depth,
        content: .radical(
            body: bodyBox, index: indexBox, indexOffset: indexOffset,
            indexScale: indexScale, ruleThickness: ruleWidth, innerHeight: texHeight),
        color: options.color)
}

/// Select the surd glyph height based on the required minimum delimiter height.
/// KaTeX uses: small(1.0), Size1(1.2), Size2(1.8), Size3(2.4), Size4(3.0).
func selectSurdHeight(_ minHeight: Double) -> Double {
    let surdHeights: [Double] = [1.0, 1.2, 1.8, 2.4, 3.0]
    for h in surdHeights where h >= minHeight {
        return h
    }
    // For very tall content, use the largest + stack
    return max(surdHeights[4], minHeight)
}
