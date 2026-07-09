// Array/matrix environment layout and \sizing.
// Port of crates/ratex-layout/src/engine.rs (lines 2663–2952).

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
    // align/aligned/alignedat: use thin space (3mu) so "x" and "=" are closer,
    // and cap relation spacing in cells to 3mu so spacing before/after "=" is equal.
    let alignRelationMu = 3.0
    let colGap: Double =
        switch colSeparationType {
        case "align":
            muToEm(alignRelationMu, quad: metrics.quad)
        case "alignat":
            0.0
        case "small":
            // smallmatrix: 2 × thickspace × (script_multiplier / current_multiplier)
            // KaTeX: arraycolsep = 0.2778em × (scriptMultiplier / sizeMultiplier)
            2.0 * muToEm(5.0, quad: metrics.quad) * MathStyle.script.sizeMultiplier
                / options.sizeMultiplier
        default:
            2.0 * 5.0 * pt  // 2 × arraycolsep
        }
    var cellOptions = options
    if colSeparationType == "align" || colSeparationType == "alignat" {
        cellOptions.alignRelationSpacing = alignRelationMu
    }

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

    // Detect vertical separator positions in the column spec.
    // colSeparators[i]: nil = no rule, false = solid '|', true = dashed ':'.
    let colSeparators: [Bool?] = {
        var seps = [Bool?](repeating: nil, count: numCols + 1)
        var alignCount = 0
        for spec in cols ?? [] {
            switch spec.alignType {
            case .align:
                alignCount += 1
            case .separator:
                if spec.align == "|", alignCount <= numCols {
                    seps[alignCount] = false
                } else if spec.align == ":", alignCount <= numCols {
                    seps[alignCount] = true
                }
            }
        }
        return seps
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
            let cellBox = layoutExpression(cellNodes, cellOptions, isRealGroup: true)
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

    // Extra x padding before col 0 and after last col (hskipBeforeAndAfter).
    let contentXOffset = hskipBeforeAndAfter ? colGap / 2.0 : 0.0

    // Width of the cell grid including horizontal padding (no tag column).
    let arrayInnerWidth =
        colWidths.reduce(0, +)
        + colGap * Double(numCols > 0 ? numCols - 1 : 0)
        + 2.0 * contentXOffset

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

    let totalWidth = arrayInnerWidth + tagGapEm + tagColWidth

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
                colGap: colGap,
                offset: offset,
                contentXOffset: contentXOffset,
                colSeparators: colSeparators,
                hlinesBeforeRow: hlinesPadded,
                ruleThickness: ruleThickness,
                doubleRuleSep: doubleRuleSep,
                arrayInnerWidth: arrayInnerWidth,
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
