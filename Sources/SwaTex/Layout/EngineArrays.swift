// Array/matrix environment layout and \sizing.
// Port of crates/ratex-layout/src/engine.rs (lines 2663–2952).

/// Walk an array's horizontal track, following KaTeX's array builder
/// (`environments/array.ts`, `htmlBuilder`) exactly. Per column it emits the
/// vertical rules the spec places before that column, then a `pregap`, the
/// column, then a `postgap`; each gap falls back to `arraycolsep` when the
/// spec leaves it unset, and the gaps at the grid's two outer edges are
/// emitted only when `hskipBeforeAndAfter` is set.
///
/// Every environment's spacing falls out of this one walk — `align`/`alignat`
/// carry explicit zero gaps plus a 1 em `pregap` before each `aligned` column
/// pair, `cases` a 1 em `postgap` on its first column, `CD` 0.25 em on both
/// sides, and `array`/`matrix`/`smallmatrix` nothing at all, so they take
/// `arraycolsep` — which is why `colSeparationType` no longer influences
/// horizontal spacing beyond picking `arraycolsep` itself.
///
/// A rule takes no width of its own, so a boundary can carry several: KaTeX
/// puts consecutive rules in one run `doubleRuleSep` apart, and restarts the
/// run after every alignment descriptor, so rules split by a descriptor that
/// no column was laid out for end up on the same x. The walk also continues
/// past the last column while the spec still has descriptors, which is what
/// renders a trailing rule at the grid's right edge when a row holds fewer
/// cells than the spec declares columns.
func resolveArrayTrack(
    colWidths: [Double], cols: [AlignSpec]?, arraycolsep: Double,
    doubleRuleSep: Double, hskipBeforeAndAfter: Bool
) -> ArrayTrack {
    let descriptors = cols ?? []
    var columnXs: [Double] = []
    columnXs.reserveCapacity(colWidths.count)
    var rules: [ArrayRule] = []

    var x = 0.0
    var column = 0
    var next = 0
    while column < colWidths.count || next < descriptors.count {
        var firstInRun = true
        while next < descriptors.count, descriptors[next].alignType == .separator {
            if let kind = descriptors[next].align, kind == "|" || kind == ":" {
                if !firstInRun { x += doubleRuleSep }
                rules.append(ArrayRule(x: x, isDashed: kind == ":"))
                firstInRun = false
            }
            next += 1
        }

        let spec: AlignSpec? = next < descriptors.count ? descriptors[next] : nil
        next += 1

        if column < colWidths.count {
            if column > 0 || hskipBeforeAndAfter {
                x += spec.flatMap(\.pregap) ?? arraycolsep
            }
            columnXs.append(x)
            x += colWidths[column]
            if column + 1 < colWidths.count || hskipBeforeAndAfter {
                x += spec.flatMap(\.postgap) ?? arraycolsep
            }
        }
        column += 1
    }

    return ArrayTrack(columnXs: columnXs, rules: rules, width: x)
}

func layoutArray(
    _ body: [[ParseNode]], _ cols: [AlignSpec]?, _ arraystretch: Double,
    _ addJot: Bool, _ rowGaps: [Measurement?], _ hlinesBeforeRow: [[Bool]],
    _ colSeparationType: String?, _ hskipBeforeAndAfter: Bool,
    _ tags: [ArrayTag]?, _ leqno: Bool, _ options: LayoutOptions
) -> LayoutBox {
    let metrics = options.metrics
    let pt = 1.0 / metrics.ptPerEm
    let baselineskip = 12.0 * pt
    let jot = 3.0 * pt
    let arrayskip = arraystretch * baselineskip
    let arstrutH = 0.7 * arrayskip
    let arstrutD = 0.3 * arrayskip
    // \arraycolsep from article.cls — the width a column spec that leaves
    // pregap/postgap unset falls back to. {smallmatrix} uses \thickspace
    // instead (amsmath.dtx), scaled because LaTeX applies \scriptstyle to the
    // whole array while this engine applies it inside each cell.
    let arraycolsep: Double =
        colSeparationType == "small"
        ? muToEm(5.0, quad: metrics.quad) * MathStyle.script.sizeMultiplier
            / options.sizeMultiplier
        : 5.0 * pt

    let numRows = body.count
    if numRows == 0 {
        return .empty
    }

    let numCols = body.map(\.count).max() ?? 0

    // Extract per-column alignment and column separators from cols spec.
    let colAligns: [Character] = {
        let alignSpecs = (cols ?? []).filter { $0.alignType == .align }
        return (0..<numCols).map { c in
            guard c < alignSpecs.count, let a = alignSpecs[c].align, let first = a.first else {
                return "c"
            }
            return first
        }
    }()

    let ruleThickness = 0.4 * pt
    let doubleRuleSep = metrics.doubleRuleSep

    // Layout all cells
    var cellBoxes: [[LayoutBox]] = []
    cellBoxes.reserveCapacity(numRows)
    var colWidths = [Double](repeating: 0, count: numCols)
    var rowHeights: [Double] = []
    rowHeights.reserveCapacity(numRows)
    var rowDepths: [Double] = []
    rowDepths.reserveCapacity(numRows)

    for row in body {
        var rowBoxes: [LayoutBox] = []
        rowBoxes.reserveCapacity(numCols)
        var rh = arstrutH
        var rd = arstrutD

        for (c, cell) in row.enumerated() {
            let cellNodes: [ParseNode] =
                if case let .ordGroup(nodes, _) = cell.kind { nodes } else { [cell] }
            let cellBox = layoutExpression(cellNodes, options, isRealGroup: true)
            rh = max(rh, cellBox.height)
            rd = max(rd, cellBox.depth)
            if c < numCols {
                colWidths[c] = max(colWidths[c], cellBox.width)
            }
            rowBoxes.append(cellBox)
        }

        // Pad missing columns
        while rowBoxes.count < numCols {
            rowBoxes.append(.empty)
        }

        if addJot {
            rd += jot
        }

        rowHeights.append(rh)
        rowDepths.append(rd)
        cellBoxes.append(rowBoxes)
    }

    // Apply row gaps
    for (r, gap) in rowGaps.enumerated() where r < rowDepths.count {
        if let m = gap {
            let gapEm = measurementToEm(m, options)
            if gapEm > 0 {
                rowDepths[r] = max(rowDepths[r], gapEm + arstrutD)
            }
        }
    }

    // Ensure hlinesBeforeRow has numRows + 1 entries.
    var hlinesPadded = hlinesBeforeRow
    while hlinesPadded.count < numRows + 1 {
        hlinesPadded.append([])
    }

    // For n > 1 consecutive hlines before row r, add extra vertical space so the
    // lines don't overlap with content.  Each extra line needs (ruleThickness +
    // doubleRuleSep) of room.
    //   - r == 0: extra hlines appear above the first row → add to rowHeights[0].
    //   - r >= 1: extra hlines appear in the gap above row r → add to rowDepths[r-1].
    for r in 0...numRows {
        let n = hlinesPadded[r].count
        if n > 1 {
            let extra = Double(n - 1) * (ruleThickness + doubleRuleSep)
            if r == 0 {
                if numRows > 0 {
                    rowHeights[0] += extra
                }
            } else {
                rowDepths[r - 1] += extra
            }
        }
    }

    // Total height and offset (computed after extra hline spacing is applied).
    var totalHeight = 0.0
    for (rowHeight, rowDepth) in zip(rowHeights, rowDepths) {
        totalHeight += rowHeight
        totalHeight += rowDepth
    }

    let offset = totalHeight / 2.0 + metrics.axisHeight

    // Resolve where every column and every vertical rule sits; the grid's
    // width (horizontal padding included, tag column excluded) falls out of it.
    let track = resolveArrayTrack(
        colWidths: colWidths, cols: cols, arraycolsep: arraycolsep,
        doubleRuleSep: doubleRuleSep, hskipBeforeAndAfter: hskipBeforeAndAfter)

    var rowTagBoxes = [LayoutBox?](repeating: nil, count: numRows)
    var tagColWidth = 0.0
    let textOpts = options.with(style: options.style.textEquivalent)
    if let tags, tags.count == numRows {
        for (r, t) in tags.enumerated() {
            if case let .explicit(nodes) = t, !nodes.isEmpty {
                let tb = layoutExpression(nodes, textOpts, isRealGroup: true)
                tagColWidth = max(tagColWidth, tb.width)
                rowTagBoxes[r] = tb
            }
        }
    }
    let tagGapEm = tagColWidth > 0 ? textOpts.metrics.quad : 0.0
    // leqno (tags on the left) is parsed but not yet laid out; keep tags on the right.
    let tagsLeft = false
    _ = leqno

    let totalWidth = track.width + tagGapEm + tagColWidth

    let height = offset
    let depth = totalHeight - offset

    return LayoutBox(
        width: totalWidth,
        height: height,
        depth: depth,
        content: .array(
            ArrayLayout(
                cells: cellBoxes,
                colWidths: colWidths,
                colAligns: colAligns,
                rowHeights: rowHeights,
                rowDepths: rowDepths,
                track: track,
                offset: offset,
                hlinesBeforeRow: hlinesPadded,
                ruleThickness: ruleThickness,
                doubleRuleSep: doubleRuleSep,
                tagGapEm: tagGapEm,
                tagColWidth: tagColWidth,
                rowTags: rowTagBoxes,
                tagsLeft: tagsLeft)),
        color: options.color)
}

// ============================================================================
// Sizing
// ============================================================================

func layoutSizing(_ size: UInt8, _ body: [ParseNode], _ options: LayoutOptions) -> LayoutBox {
    // KaTeX sizing: size 1-11, maps to multipliers
    let multiplier: Double =
        switch size {
        case 1: 0.5
        case 2: 0.6
        case 3: 0.7
        case 4: 0.8
        case 5: 0.9
        case 6: 1.0
        case 7: 1.2
        case 8: 1.44
        case 9: 1.728
        case 10: 2.074
        case 11: 2.488
        default: 1.0
        }

    // KaTeX `Options.havingSize`: inner is built in `this.style.text()` (≥ textstyle).
    let innerOpts = options.with(style: options.style.textEquivalent)
    let inner = layoutExpression(body, innerOpts, isRealGroup: true)
    let ratio = multiplier / options.sizeMultiplier
    if abs(ratio - 1.0) < 0.001 {
        return inner
    }
    return LayoutBox(
        width: inner.width * ratio,
        height: inner.height * ratio,
        depth: inner.depth * ratio,
        content: .scaled(body: inner, childScale: ratio),
        color: options.color)
}
