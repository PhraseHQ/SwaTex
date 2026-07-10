// Convert a LayoutBox tree into a flat DisplayList with absolute coordinates.
//
// Ported from RaTeX `to_display.rs`.

/// Unicode √ (U+221A), same glyph KaTeX uses for `\sqrt` surd.
private let surdChar: UInt32 = 0x221A

/// Convert a LayoutBox tree into a flat DisplayList with absolute coordinates.
///
/// The coordinate system:
/// - x increases to the right
/// - y increases downward (screen coordinates)
/// - The origin (0, 0) is at the top-left of the bounding box
/// - The baseline is at y = height
public func toDisplayList(_ root: LayoutBox) -> DisplayList {
    var items: [DisplayItem] = []
    let baselineY = root.height
    let floor = stackFloorAddress(headroom: minimumLayoutStackHeadroom)
    var truncated = false
    emitBox(
        root, x: 0.0, y: baselineY, scale: 1.0, items: &items, floor: floor,
        depth: 1, truncated: &truncated)

    if items.isEmpty {
        return DisplayList(
            items: items, width: root.width, height: root.height, depth: root.depth,
            truncated: truncated)
    }

    // Compute visual bounding box from actual display items.
    // This handles cases like \smash (zero height/depth) and \mathllap (zero width)
    // where content extends beyond the nominal box dimensions.
    // Horizontal: near-zero nominal width gets full expansion; otherwise we still shift when
    // `min_x < 0` so \mathclap under large operators does not paint off the left edge.
    let (minX, maxX, minY, maxY) = computeVisualBounds(items)

    var width = root.width
    var height = root.height
    var depth = root.depth
    let totalH = root.height + root.depth

    // Expand vertical dimensions only when nominal total height is near-zero (e.g. \smash)
    if totalH < 0.01 {
        if minY < -0.001 {
            let extra = -minY
            height += extra
            for i in items.indices {
                items[i] = shiftItemY(items[i], dy: extra)
            }
        }
        let nominalBottom = height + depth
        let shiftedMaxY = minY < -0.001 ? maxY - minY : maxY
        if shiftedMaxY > nominalBottom + 0.001 {
            depth = shiftedMaxY - height
        }
    }

    // Expand horizontal dimensions when nominal width is near-zero (e.g. pure \mathllap), or when
    // ink extends left of x=0. The latter happens for `\sum_{\mathclap{…}}`: the subscript box has
    // zero advance but negative kerns center the ink, so the first glyph can sit at negative x.
    // Rasterizers (PNG) clip there; shift right so all items stay in [0, width].
    if root.width < 0.01 {
        if minX < -0.001 {
            let extra = -minX
            width += extra
            for i in items.indices {
                items[i] = shiftItemX(items[i], dx: extra)
            }
        }
        let shiftedMaxX = minX < -0.001 ? maxX - minX : maxX
        if shiftedMaxX > width + 0.001 {
            width = shiftedMaxX
        }
    } else if minX < -0.001 {
        let extra = -minX
        width = max(root.width + extra, maxX + extra)
        for i in items.indices {
            items[i] = shiftItemX(items[i], dx: extra)
        }
    }

    // Filled SVG paths (e.g. KaTeX `tallDelim` for `\vert`) can extend slightly above y=0 from
    // curve overshoot; the pixmap uses nominal height/depth only and would clip. Shift down and
    // grow depth when needed so all path ink fits. (Skip when `total_h < 0.01`: that case already
    // adjusted vertical bounds using the same `min_y`.)
    if totalH >= 0.01 && minY < -0.001 {
        let extra = -minY
        height += extra
        for i in items.indices {
            items[i] = shiftItemY(items[i], dy: extra)
        }
        let newBottom = height + depth
        let adjustedMaxY = maxY + extra
        if adjustedMaxY > newBottom + 0.001 {
            depth = adjustedMaxY - height
        }
    }

    // Expand depth when content extends below the nominal bottom but nothing went above the top.
    // This handles e.g. \smash[b] which zeroes the layout depth while content still renders below
    // the baseline — the pixmap would otherwise be too short and clip the denominator.
    if totalH >= 0.01 && minY >= -0.001 && maxY > height + depth + 0.001 {
        depth = maxY - height
    }

    return DisplayList(
        items: items, width: width, height: height, depth: depth, truncated: truncated)
}

/// Maximum `emitBox` recursion depth: the non-Darwin backstop mirroring
/// `maxLayoutRecursionDepth` (the probe is vacuously true there). The box
/// tree nests several levels per layout node, so the cap is a multiple of
/// the layout cap — a bound against runaway trees fed to the public
/// `toDisplayList(_:)`, not a tight limit.
#if canImport(Darwin)
    private let maxEmitRecursionDepth = Int.max
#else
    private let maxEmitRecursionDepth = 8192
#endif

/// Recursively emit DisplayItems for a LayoutBox at the given position.
///
/// `x`, `y` are the position of the box's baseline-left corner in absolute coordinates.
/// `scale` is the cumulative size multiplier (1.0 at root, 0.7 in script, 0.5 in scriptscript).
private func emitBox(
    _ lbox: LayoutBox, x: Double, y: Double, scale: Double, items: inout [DisplayItem],
    floor: UInt, depth: Int, truncated: inout Bool
) {
    // The emission walk recurses over the box tree, which can nest several
    // levels per input node; on a 512 KB worker thread a deeply nested (but
    // guard-passing) formula used to overflow here. Drop the subtree's items
    // instead of crashing (same degradation policy as `layoutNode`) and
    // record the truncation so callers can tell partial output from complete.
    guard depth <= maxEmitRecursionDepth, stackHasHeadroom(above: floor) else {
        truncated = true
        return
    }
    switch lbox.content {
    case .hbox(let children):
        var curX = x
        for child in children {
            emitBox(
                child, x: curX, y: y, scale: scale, items: &items, floor: floor, depth: depth + 1,
                truncated: &truncated)
            curX += child.width * scale
        }

    case .vbox(let children):
        var curY = y - lbox.height * scale
        for child in children {
            switch child.kind {
            case .box(let b):
                curY += b.height * scale
                emitBox(
                    b, x: x + child.shift * scale, y: curY, scale: scale, items: &items,
                    floor: floor, depth: depth + 1, truncated: &truncated)
                curY += b.depth * scale
            case .kern(let k):
                curY += k * scale
            }
        }

    case .glyph(let fontId, let charCode):
        items.append(
            .glyphPath(
                x: x, y: y, scale: scale,
                font: fontId.rawValue, charCode: charCode, color: lbox.color))

    case .rule(let thickness, let raise):
        // Baseline at `y` (downward screen coords); bottom of ink is `raise` em above baseline.
        let cy = y - (raise + thickness / 2.0) * scale
        items.append(
            .line(
                x: x, y: cy, width: lbox.width * scale, thickness: thickness * scale,
                color: lbox.color, dashed: false))

    case .fraction(
        let numer, let denom, let numerShift, let denomShift, let barThickness,
        let nSc, let dSc):
        let childNumerScale = scale * nSc
        let childDenomScale = scale * dSc

        var fracX = x + (lbox.width * scale - numer.width * childNumerScale) / 2.0
        emitBox(
            numer, x: fracX, y: y - numerShift * scale, scale: childNumerScale, items: &items,
            floor: floor, depth: depth + 1, truncated: &truncated)

        fracX = x + (lbox.width * scale - denom.width * childDenomScale) / 2.0
        emitBox(
            denom, x: fracX, y: y + denomShift * scale, scale: childDenomScale, items: &items,
            floor: floor, depth: depth + 1, truncated: &truncated)

        if barThickness > 0.0 {
            let metrics = MathConstants.forSize(0)
            items.append(
                .line(
                    x: x, y: y - metrics.axisHeight * scale,
                    width: lbox.width * scale, thickness: barThickness * scale,
                    color: lbox.color, dashed: false))
        }

    case .supSub(
        let base, let sup, let sub, let supShift, let subShift, let ss, let bs,
        let centerScripts, let italicCorrection, let subHKern):
        let baseX =
            centerScripts
            ? x + (lbox.width - base.width) * scale / 2.0
            : x
        emitBox(
            base, x: baseX, y: y, scale: scale, items: &items, floor: floor, depth: depth + 1,
            truncated: &truncated)
        if let supBox = sup {
            let childScale = scale * ss
            let supX =
                centerScripts
                ? x + (lbox.width * scale - supBox.width * childScale) / 2.0
                : baseX + (base.width + italicCorrection) * scale
            emitBox(
                supBox, x: supX, y: y - supShift * scale, scale: childScale, items: &items,
                floor: floor, depth: depth + 1, truncated: &truncated)
        }
        if let subBox = sub {
            let childScale = scale * bs
            let subX =
                centerScripts
                ? x + (lbox.width * scale - subBox.width * childScale) / 2.0
                : baseX + base.width * scale + subHKern * scale
            emitBox(
                subBox, x: subX, y: y + subShift * scale, scale: childScale, items: &items,
                floor: floor, depth: depth + 1, truncated: &truncated)
        }

    case .radical(
        let body, let index, let indexOffset, let indexScale, let ruleThickness,
        let innerHeight):
        let radicalWidth = lbox.width - indexOffset - body.width

        let surdX = x + indexOffset * scale

        if let indexBox = index {
            // Root index (scriptscript): KaTeX `htmlBuilder` builds a vlist with
            // `positionType: "shift", positionData: -toShift` where
            // `toShift = 0.6 * (body.height - body.depth)` and `body` is the sqrt
            // inner+vlist (same height/depth as this radical box, excluding the index).
            // That aligns the root span with the sqrt body on the math baseline, then
            // shifts the glyph upward by `toShift` — not pinned to the top of the surd.
            //
            // Horizontal: KaTeX places the index at `\mkern 5mu` (5/18 em) from the LEFT
            // of the surd glyph, matching `.sqrt > .root { margin-left: 5/18em }`.
            // Using surd_x as the reference makes this scale correctly for all surd sizes
            // and for nested radicals where each level has a different index_offset.
            let toShift = 0.6 * (lbox.height - lbox.depth)
            let indexBaselineY = y - toShift * scale
            let childScale = scale * indexScale
            emitBox(
                indexBox, x: surdX + (5.0 / 18.0) * scale, y: indexBaselineY,
                scale: childScale, items: &items, floor: floor, depth: depth + 1,
                truncated: &truncated)
        }
        let surdFontId = surdFont(forInnerHeight: innerHeight)
        let gh =
            surdFontId.metrics(forChar: surdChar).map { $0.height }
            ?? (lbox.height - ruleThickness)
        let surdShift = lbox.height - ruleThickness - gh
        let surdY = y - surdShift * scale
        items.append(
            .glyphPath(
                x: surdX, y: surdY, scale: scale,
                font: surdFontId.rawValue, charCode: surdChar, color: lbox.color))

        // Vinculum: a horizontal rule extending the glyph's top bar over the body.
        // Center it on the glyph's top bar position.
        let lineCenterY = surdY - gh * scale + (ruleThickness * scale) / 2.0
        items.append(
            .line(
                x: surdX + radicalWidth * scale, y: lineCenterY,
                width: body.width * scale, thickness: ruleThickness * scale,
                color: lbox.color, dashed: false))

        emitBox(
            body, x: surdX + radicalWidth * scale, y: y, scale: scale, items: &items, floor: floor,
            depth: depth + 1, truncated: &truncated)

    case .opLimits(
        let base, let sup, let sub, let baseShift, let supKern, let subKern, let slant,
        let ss, let bs):
        let baseX = x + (lbox.width - base.width) * scale / 2.0
        emitBox(
            base, x: baseX, y: y + baseShift * scale, scale: scale, items: &items, floor: floor,
            depth: depth + 1, truncated: &truncated)

        if let supBox = sup {
            let childScale = scale * ss
            let supX =
                x
                + (lbox.width * scale - supBox.width * childScale) / 2.0
                + slant * scale / 2.0
            let supY =
                y
                - (base.height - baseShift) * scale
                - supKern * scale
                - supBox.depth * childScale
            emitBox(
                supBox, x: supX, y: supY, scale: childScale, items: &items, floor: floor,
                depth: depth + 1, truncated: &truncated)
        }
        if let subBox = sub {
            let childScale = scale * bs
            let subX =
                x + (lbox.width * scale - subBox.width * childScale) / 2.0
                - slant * scale / 2.0
            let subY =
                y
                + (base.depth + baseShift) * scale
                + subKern * scale
                + subBox.height * childScale
            emitBox(
                subBox, x: subX, y: subY, scale: childScale, items: &items, floor: floor,
                depth: depth + 1, truncated: &truncated)
        }

    case .accent(let base, let accent, let clearance, let skew, let isBelow, let underGapEm):
        emitBox(
            base, x: x, y: y, scale: scale, items: &items, floor: floor, depth: depth + 1,
            truncated: &truncated)
        if isBelow {
            let accentX = x + (base.width - accent.width) * scale / 2.0
            let accentY = y + (base.depth + underGapEm) * scale + accent.height * scale
            emitBox(
                accent, x: accentX, y: accentY, scale: scale, items: &items, floor: floor,
                depth: depth + 1, truncated: &truncated)
        } else {
            let accentX = x + (base.width - accent.width) * scale / 2.0 + skew * scale
            // Position accent so its TOP is at (clearance + effective_accent_height) above baseline.
            // For SVG accents (height=0, depth=h), position at clearance above baseline.
            // For glyph accents (height>0, depth=0), the visual mark is at the top of the glyph.
            // Place the glyph so its top aligns with clearance + small_mark_height above baseline.
            let isSvgAccent = accent.height <= 0.001
            let accentY: Double
            if isSvgAccent {
                accentY = y - clearance * scale - accent.depth * scale
            } else {
                // Glyph accent: position baseline so top of glyph = clearance above text baseline
                // accent_y - accent.height = y - (lbox.height) where lbox.height = clearance + eff_h
                // => accent_y = y - clearance - eff_h + accent.height
                // Simpler: shift glyph so top is at y - clearance - small_gap
                accentY = y - clearance * scale + (accent.height - min(0.35, accent.height)) * scale
            }
            emitBox(
                accent, x: accentX, y: accentY, scale: scale, items: &items, floor: floor,
                depth: depth + 1, truncated: &truncated)
        }

    case .leftRight(let left, let right, let inner):
        var curX = x
        emitBox(
            left, x: curX, y: y, scale: scale, items: &items, floor: floor, depth: depth + 1,
            truncated: &truncated)
        curX += left.width * scale
        emitBox(
            inner, x: curX, y: y, scale: scale, items: &items, floor: floor, depth: depth + 1,
            truncated: &truncated)
        curX += inner.width * scale
        emitBox(
            right, x: curX, y: y, scale: scale, items: &items, floor: floor, depth: depth + 1,
            truncated: &truncated)

    case .array(let a):
        let yTop = y - a.offset * scale
        let arrayTotalHeight = (lbox.height + lbox.depth) * scale
        let lineThickness = a.ruleThickness * scale

        // Compute y positions of row boundaries (0 = top of array, num_rows = bottom).
        var boundaryYs: [Double] = []
        boundaryYs.reserveCapacity(a.cells.count + 1)
        var curBoundary = yTop
        boundaryYs.append(curBoundary)
        for (rowHeight, rowDepth) in zip(a.rowHeights, a.rowDepths) {
            curBoundary += (rowHeight + rowDepth) * scale
            boundaryYs.append(curBoundary)
        }

        // Draw horizontal lines (hlines) before/after each row.
        // Each entry in hlines vec is one \hline (false) or \hdashline (true).
        // Consecutive rules are separated by double_rule_sep (= \doublerulesep = 2pt).
        //
        // Extra space for n > 1 hlines was already added to the layout:
        //   - r == 0: added to row_heights[0], so lines start at boundary_ys[0] going down.
        //   - r >= 1: added to row_depths[r-1], so lines occupy the range
        //             [boundary_ys[r] - (n-1)*rule_step, boundary_ys[r]], above row r.
        let ruleStep = lineThickness + a.doubleRuleSep * scale
        for (r, hlines) in a.hlinesBeforeRow.enumerated() {
            if r < boundaryYs.count {
                let n = hlines.count
                let startY =
                    r == 0
                    ? boundaryYs[0]
                    : boundaryYs[r] - Double(max(n - 1, 0)) * ruleStep
                for (i, isDashed) in hlines.enumerated() {
                    items.append(
                        .line(
                            x: x, y: startY + Double(i) * ruleStep,
                            width: a.arrayInnerWidth * scale, thickness: lineThickness,
                            color: lbox.color, dashed: isDashed))
                }
            }
        }

        // Draw vertical column separator lines ('|' = solid, ':' = dashed).
        // Separator at position i has local x = content_x_offset - col_gap/2 + sum(col_widths[..i]) + col_gap * i.
        let colGapHalf = a.colGap / 2.0
        for (i, sep) in a.colSeparators.enumerated() {
            if let isDashed = sep {
                let prefixW = a.colWidths[..<i].reduce(0.0, +)
                let localX = a.contentXOffset - colGapHalf + prefixW + a.colGap * Double(i)
                let absX = x + localX * scale - lineThickness / 2.0
                if isDashed {
                    // Dashed vertical line: draw segments (dash=4t, gap=4t) top to bottom.
                    let t = lineThickness
                    let dash = 4.0 * t
                    let period = 2.0 * dash
                    var curY = yTop
                    while curY < yTop + arrayTotalHeight {
                        let segH = min(dash, yTop + arrayTotalHeight - curY)
                        items.append(
                            .rect(x: absX, y: curY, width: t, height: segH, color: lbox.color))
                        curY += period
                    }
                } else {
                    items.append(
                        .rect(
                            x: absX, y: yTop, width: lineThickness,
                            height: arrayTotalHeight, color: lbox.color))
                }
            }
        }

        // Render cells.
        var curY = yTop
        for (r, row) in a.cells.enumerated() {
            let rh = a.rowHeights[r]
            curY += rh * scale
            var curX = x + a.contentXOffset * scale
            for (c, cell) in row.enumerated() {
                let cw = a.colWidths[c]
                let align: Character = c < a.colAligns.count ? a.colAligns[c] : "c"
                let cellX: Double
                switch align {
                case "l": cellX = curX
                case "r": cellX = curX + (cw - cell.width) * scale
                default: cellX = curX + (cw - cell.width) * scale / 2.0
                }
                emitBox(
                    cell, x: cellX, y: curY, scale: scale, items: &items, floor: floor,
                    depth: depth + 1, truncated: &truncated)
                curX += cw * scale
                if c + 1 < row.count {
                    curX += a.colGap * scale
                }
            }
            if a.tagColWidth > 0.0 {
                if r < a.rowTags.count, let tb = a.rowTags[r] {
                    let tagStartEm = a.arrayInnerWidth - a.contentXOffset + a.tagGapEm
                    let tagX = x + tagStartEm * scale + (a.tagColWidth - tb.width) * scale
                    emitBox(
                        tb, x: tagX, y: curY, scale: scale, items: &items, floor: floor,
                        depth: depth + 1, truncated: &truncated)
                }
            }
            curY += a.rowDepths[r] * scale
        }

    case .svgPath(let commands, let fill):
        let scaled = commands.scaled(by: scale)
        items.append(.path(x: x, y: y, commands: scaled, fill: fill, color: lbox.color))

    case .framed(
        let body, let padding, let borderThickness, let hasBorder, let bgColor,
        let borderColor):
        let outerW = lbox.width * scale
        let outerH = lbox.height * scale
        let outerD = lbox.depth * scale
        let topY = y - outerH

        // Background fill
        if let bg = bgColor {
            items.append(.rect(x: x, y: topY, width: outerW, height: outerH + outerD, color: bg))
        }

        // Border (4 sides as Rect strips)
        if hasBorder {
            let bt = borderThickness * scale
            // Top
            items.append(.rect(x: x, y: topY, width: outerW, height: bt, color: borderColor))
            // Bottom
            items.append(
                .rect(x: x, y: y + outerD - bt, width: outerW, height: bt, color: borderColor))
            // Left
            items.append(
                .rect(x: x, y: topY, width: bt, height: outerH + outerD, color: borderColor))
            // Right
            items.append(
                .rect(
                    x: x + outerW - bt, y: topY, width: bt, height: outerH + outerD,
                    color: borderColor))
        }

        // Body content (shifted by padding + border from left baseline)
        let innerOffset = (padding + borderThickness) * scale
        emitBox(
            body, x: x + innerOffset, y: y, scale: scale, items: &items, floor: floor,
            depth: depth + 1, truncated: &truncated)

    case .raiseBox(let body, let shift):
        emitBox(
            body, x: x, y: y - shift * scale, scale: scale, items: &items, floor: floor,
            depth: depth + 1, truncated: &truncated)

    case .scaled(let body, let childScale):
        emitBox(
            body, x: x, y: y, scale: scale * childScale, items: &items, floor: floor,
            depth: depth + 1, truncated: &truncated)

    case .angl(let pathCommands, let body):
        let scaled = pathCommands.scaled(by: scale)
        items.append(.path(x: x, y: y, commands: scaled, fill: false, color: lbox.color))
        emitBox(
            body, x: x, y: y, scale: scale, items: &items, floor: floor, depth: depth + 1,
            truncated: &truncated)

    case .overline(let body, let ruleThickness):
        emitBox(
            body, x: x, y: y, scale: scale, items: &items, floor: floor, depth: depth + 1,
            truncated: &truncated)
        // Rule center is at 2.5 * rule_thickness above the body's top
        let ruleCenterY = y - (body.height + 2.5 * ruleThickness) * scale
        items.append(
            .line(
                x: x, y: ruleCenterY, width: lbox.width * scale,
                thickness: ruleThickness * scale, color: lbox.color, dashed: false))

    case .underline(let body, let ruleThickness, let offset):
        emitBox(
            body, x: x, y: y, scale: scale, items: &items, floor: floor, depth: depth + 1,
            truncated: &truncated)
        let ruleCenterY = y + (body.depth + offset) * scale
        items.append(
            .line(
                x: x, y: ruleCenterY, width: lbox.width * scale,
                thickness: ruleThickness * scale, color: lbox.color, dashed: false))

    case .proofTree(let children, let rules):
        let topY = y - lbox.height * scale
        for child in children {
            emitBox(
                child.box, x: x + child.x * scale, y: topY + child.baselineY * scale,
                scale: scale, items: &items, floor: floor, depth: depth + 1, truncated: &truncated)
        }
        for rule in rules {
            items.append(
                .line(
                    x: x + rule.x * scale, y: topY + rule.y * scale,
                    width: rule.width * scale, thickness: rule.thickness * scale,
                    color: lbox.color, dashed: rule.dashed))
        }

    case .kern, .empty:
        break

    case .degraded:
        // A layout-stage guard already dropped this subtree; surface it
        // through the same signal as emission-stage drops.
        truncated = true
    }
}

/// Compute the visual bounding box from line, rect, and path items (paths only when
/// coordinates are within a sane em range — skips huge KaTeX `viewBox` artifacts).
/// Returns (min_x, max_x, min_y, max_y) in em coordinates.
private func computeVisualBounds(_ items: [DisplayItem]) -> (Double, Double, Double, Double) {
    var minX = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude

    for item in items {
        switch item {
        // Compute glyph extent from font metrics so edge cases like \smash
        // (zero nominal height) and \mathllap (zero nominal width) are
        // correctly sized: the pixmap is dimensioned from nominal bounds,
        // but smashed/llap boxes have near-zero nominal dimensions.
        case .glyphPath(let x, let y, let scale, let font, let charCode, _):
            let fontId = FontId(rawValue: font) ?? .mainRegular
            let (w, h, d) =
                fontId.metrics(forChar: charCode)
                .map { ($0.width, $0.height, $0.depth) } ?? (0.0, 0.0, 0.0)
            minX = min(minX, x)
            maxX = max(maxX, x + w * scale)
            minY = min(minY, y - h * scale)
            maxY = max(maxY, y + d * scale)
        case .line(let x, let y, let width, let thickness, _, _):
            minX = min(minX, x)
            maxX = max(maxX, x + width)
            minY = min(minY, y - thickness / 2.0)
            maxY = max(maxY, y + thickness / 2.0)
        case .rect(let x, let y, let width, let height, _):
            minX = min(minX, x)
            maxX = max(maxX, x + width)
            minY = min(minY, y)
            maxY = max(maxY, y + height)
        // Paths in document em space (delimiters, accents): include bbox so tall `tallDelim`
        // curves are not clipped at the pixmap edge. Skip astronomical KaTeX coords (e.g. \phase).
        case .path(let px, let py, let commands, _, _):
            let maxEm = 50.0
            func consider(_ cx: Double, _ cy: Double) {
                if abs(cx) <= maxEm && abs(cy) <= maxEm {
                    let absX = px + cx
                    let absY = py + cy
                    minX = min(minX, absX)
                    maxX = max(maxX, absX)
                    minY = min(minY, absY)
                    maxY = max(maxY, absY)
                }
            }
            for cmd in commands {
                switch cmd {
                case .moveTo(let cx, let cy), .lineTo(let cx, let cy):
                    consider(cx, cy)
                case .cubicTo(let x1, let y1, let x2, let y2, let x, let y):
                    consider(x1, y1)
                    consider(x2, y2)
                    consider(x, y)
                case .quadTo(let x1, let y1, let x, let y):
                    consider(x1, y1)
                    consider(x, y)
                case .close:
                    break
                }
            }
        }
    }

    return (minX, maxX, minY, maxY)
}

private func shiftItemY(_ item: DisplayItem, dy: Double) -> DisplayItem {
    switch item {
    case .glyphPath(let x, let y, let scale, let font, let charCode, let color):
        .glyphPath(x: x, y: y + dy, scale: scale, font: font, charCode: charCode, color: color)
    case .line(let x, let y, let width, let thickness, let color, let dashed):
        .line(x: x, y: y + dy, width: width, thickness: thickness, color: color, dashed: dashed)
    case .rect(let x, let y, let width, let height, let color):
        .rect(x: x, y: y + dy, width: width, height: height, color: color)
    case .path(let x, let y, let commands, let fill, let color):
        .path(x: x, y: y + dy, commands: commands, fill: fill, color: color)
    }
}

private func shiftItemX(_ item: DisplayItem, dx: Double) -> DisplayItem {
    switch item {
    case .glyphPath(let x, let y, let scale, let font, let charCode, let color):
        .glyphPath(x: x + dx, y: y, scale: scale, font: font, charCode: charCode, color: color)
    case .line(let x, let y, let width, let thickness, let color, let dashed):
        .line(x: x + dx, y: y, width: width, thickness: thickness, color: color, dashed: dashed)
    case .rect(let x, let y, let width, let height, let color):
        .rect(x: x + dx, y: y, width: width, height: height, color: color)
    case .path(let x, let y, let commands, let fill, let color):
        .path(x: x + dx, y: y, commands: commands, fill: fill, color: color)
    }
}
