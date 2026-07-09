// Layout engine: stretchy accent fallback paths, CD (amscd commutative
// diagrams), bussproofs proof trees, and horizontal brace paths.
// Port of crates/ratex-layout/src/engine.rs (lines 4459–5750).

// ============================================================================
// Stretchy accent fallback paths
// ============================================================================

func stretchyAccentPath(_ label: String, _ width: Double, _ height: Double) -> [PathCommand] {
    if let commands = katexStretchyArrowPath(label, widthEm: width, heightEm: height) {
        return commands
    }
    let ah = height * 0.35  // arrowhead size
    let midY = -height / 2.0

    switch label {
    case "\\overleftarrow", "\\underleftarrow", "\\xleftarrow", "\\xLeftarrow":
        return [
            .moveTo(x: ah, y: midY - ah),
            .lineTo(x: 0.0, y: midY),
            .lineTo(x: ah, y: midY + ah),
            .moveTo(x: 0.0, y: midY),
            .lineTo(x: width, y: midY),
        ]
    case "\\overleftrightarrow", "\\underleftrightarrow", "\\xleftrightarrow",
        "\\xLeftrightarrow":
        return [
            .moveTo(x: ah, y: midY - ah),
            .lineTo(x: 0.0, y: midY),
            .lineTo(x: ah, y: midY + ah),
            .moveTo(x: 0.0, y: midY),
            .lineTo(x: width, y: midY),
            .moveTo(x: width - ah, y: midY - ah),
            .lineTo(x: width, y: midY),
            .lineTo(x: width - ah, y: midY + ah),
        ]
    case "\\xlongequal":
        let gap = 0.04
        return [
            .moveTo(x: 0.0, y: midY - gap),
            .lineTo(x: width, y: midY - gap),
            .moveTo(x: 0.0, y: midY + gap),
            .lineTo(x: width, y: midY + gap),
        ]
    case "\\xhookleftarrow":
        return [
            .moveTo(x: ah, y: midY - ah),
            .lineTo(x: 0.0, y: midY),
            .lineTo(x: ah, y: midY + ah),
            .moveTo(x: 0.0, y: midY),
            .lineTo(x: width, y: midY),
            .quadTo(x1: width + ah, y1: midY, x: width + ah, y: midY + ah),
        ]
    case "\\xhookrightarrow":
        return [
            .moveTo(x: 0.0 - ah, y: midY - ah),
            .quadTo(x1: 0.0 - ah, y1: midY, x: 0.0, y: midY),
            .lineTo(x: width, y: midY),
            .moveTo(x: width - ah, y: midY - ah),
            .lineTo(x: width, y: midY),
            .lineTo(x: width - ah, y: midY + ah),
        ]
    case "\\xrightharpoonup", "\\xleftharpoonup":
        let right = label.contains("right")
        if right {
            return [
                .moveTo(x: 0.0, y: midY),
                .lineTo(x: width, y: midY),
                .moveTo(x: width - ah, y: midY - ah),
                .lineTo(x: width, y: midY),
            ]
        } else {
            return [
                .moveTo(x: ah, y: midY - ah),
                .lineTo(x: 0.0, y: midY),
                .lineTo(x: width, y: midY),
            ]
        }
    case "\\xrightharpoondown", "\\xleftharpoondown":
        let right = label.contains("right")
        if right {
            return [
                .moveTo(x: 0.0, y: midY),
                .lineTo(x: width, y: midY),
                .moveTo(x: width - ah, y: midY + ah),
                .lineTo(x: width, y: midY),
            ]
        } else {
            return [
                .moveTo(x: ah, y: midY + ah),
                .lineTo(x: 0.0, y: midY),
                .lineTo(x: width, y: midY),
            ]
        }
    case "\\xrightleftharpoons", "\\xleftrightharpoons":
        let gap = 0.06
        return [
            .moveTo(x: 0.0, y: midY - gap),
            .lineTo(x: width, y: midY - gap),
            .moveTo(x: width - ah, y: midY - gap - ah),
            .lineTo(x: width, y: midY - gap),
            .moveTo(x: width, y: midY + gap),
            .lineTo(x: 0.0, y: midY + gap),
            .moveTo(x: ah, y: midY + gap + ah),
            .lineTo(x: 0.0, y: midY + gap),
        ]
    case "\\xtofrom", "\\xrightleftarrows":
        let gap = 0.06
        return [
            .moveTo(x: 0.0, y: midY - gap),
            .lineTo(x: width, y: midY - gap),
            .moveTo(x: width - ah, y: midY - gap - ah),
            .lineTo(x: width, y: midY - gap),
            .lineTo(x: width - ah, y: midY - gap + ah),
            .moveTo(x: width, y: midY + gap),
            .lineTo(x: 0.0, y: midY + gap),
            .moveTo(x: ah, y: midY + gap - ah),
            .lineTo(x: 0.0, y: midY + gap),
            .lineTo(x: ah, y: midY + gap + ah),
        ]
    case "\\overlinesegment", "\\underlinesegment":
        return [
            .moveTo(x: 0.0, y: midY),
            .lineTo(x: width, y: midY),
        ]
    default:
        return [
            .moveTo(x: 0.0, y: midY),
            .lineTo(x: width, y: midY),
            .moveTo(x: width - ah, y: midY - ah),
            .lineTo(x: width, y: midY),
            .lineTo(x: width - ah, y: midY + ah),
        ]
    }
}

// ============================================================================
// CD (amscd commutative diagram) layout
// ============================================================================

/// Wrap a horizontal arrow cell with left/right kerns (KaTeX `.cd-arrow-pad`).
private func cdWrapHpad(
    _ inner: LayoutBox, _ padL: Double, _ padR: Double, _ color: Color
) -> LayoutBox {
    let h = inner.height
    let d = inner.depth
    let w = inner.width + padL + padR
    var children: [LayoutBox] = []
    children.reserveCapacity(3)
    if padL > 0.0 {
        children.append(.kern(padL))
    }
    children.append(inner)
    if padR > 0.0 {
        children.append(.kern(padR))
    }
    return LayoutBox(
        width: w, height: h, depth: d,
        content: .hbox(children),
        color: color)
}

/// Wrap a side label for a vertical CD arrow so it is vertically centered on the shaft.
///
/// The resulting box reports `height = boxH, depth = boxD` (same as the shaft) so it
/// does not change the row's allocated height.  The label body is raised/lowered via
/// `raiseBox` so that the label's visual center aligns with the shaft's vertical center.
///
/// Derivation (screen coords, y+ downward):
///   shaft center  = (boxD − boxH) / 2
///   label center  = −shift − (labelH − labelD) / 2
///   solving gives  shift = (boxH − boxD + labelD − labelH) / 2
private func cdVcenterSideLabel(
    _ label: LayoutBox, _ boxH: Double, _ boxD: Double, _ color: Color
) -> LayoutBox {
    let shift = (boxH - boxD + label.depth - label.height) / 2.0
    return LayoutBox(
        width: label.width, height: boxH, depth: boxD,
        content: .raiseBox(body: label, shift: shift),
        color: color)
}

/// Side labels on vertical `{CD}` arrows: KaTeX `\\cdleft` / `\\cdright` both use
/// `options.style.sup()` (`cd.js` htmlBuilder), then our pipeline must scale like `opLimits`
/// scripts — `raiseBox` in `toDisplay` does not apply script size, so wrap in `scaled`.
private func cdSideLabelScaled(_ body: ParseNode, _ options: LayoutOptions) -> LayoutBox {
    let supStyle = options.style.superscript
    let supOpts = options.with(style: supStyle)
    let supRatio = supStyle.sizeMultiplier / options.style.sizeMultiplier
    let inner = layoutNode(body, supOpts)
    if abs(supRatio - 1.0) < 1e-6 {
        return inner
    } else {
        return LayoutBox(
            width: inner.width * supRatio,
            height: inner.height * supRatio,
            depth: inner.depth * supRatio,
            content: .scaled(body: inner, childScale: supRatio),
            color: options.color)
    }
}

/// Fixed total height for `\Big` (sizeToMaxHeight[2] from KaTeX), used by
/// pass-1 vertical CD arrows.
private let cdBigTotalHeight = 1.8

/// Stretch ↑ / ↓ to span the CD arrow row (`totalHeight` = height + depth in em).
///
/// Reuses the same filled KaTeX stretchy path as horizontal `\cdrightarrow` (see
/// `katexCdVertArrowFromRightarrow`) so the head/shaft match the horizontal CD
/// arrows; `makeStretchyDelim` does not stack ↑/↓ to arbitrary heights.
private func cdStretchVertArrowBox(
    _ totalHeight: Double, down: Bool, _ options: LayoutOptions
) -> LayoutBox {
    let axis = options.metrics.axisHeight
    let depth = max(totalHeight / 2.0 - axis, 0.0)
    let height = totalHeight - depth
    if let (commands, w) = katexCdVertArrowFromRightarrow(
        down: down, totalHeightEm: totalHeight, axisHeightEm: axis)
    {
        return LayoutBox(
            width: w, height: height, depth: depth,
            content: .svgPath(commands: commands, fill: true),
            color: options.color)
    }
    // Fallback (should not happen): `\cdrightarrow` is always in the stretchy table.
    if down {
        return makeStretchyDelim("\\downarrow", cdBigTotalHeight, options)
    } else {
        return makeStretchyDelim("\\uparrow", cdBigTotalHeight, options)
    }
}

/// Render a single cdArrow cell.
///
/// `targetSize`:
/// - `w > 0` for horizontal arrows: shaft length is exactly `w` em (KaTeX: per-cell natural width,
///   not the full column max — see `.katex .mtable` + `.stretchy { width: 100% }` where the cell
///   span is only as wide as content; narrow arrows stay at `max(labels, minCDarrowwidth)` and sit
///   centered in a wider column).
/// - `h > 0` for vertical arrows: shaft total height (height+depth) = `h`.
/// - `0.0` = natural size (pass 1).
///
/// `targetColWidth`: when `> 0`, center the cell in this column width (horizontal: side kerns;
/// vertical: kerns around shaft + labels).
///
/// `targetDepth` (vertical only): depth portion of `targetSize` when `> 0`, so that
/// `boxH = targetSize - targetDepth` and `boxD = targetDepth`.
func layoutCDArrow(
    _ direction: String, _ labelAbove: ParseNode?, _ labelBelow: ParseNode?,
    _ targetSize: Double, _ targetColWidth: Double, _ targetDepth: Double,
    _ options: LayoutOptions
) -> LayoutBox {
    let metrics = options.metrics
    let axis = metrics.axisHeight

    // Vertical CD: kern between side label and shaft (KaTeX `cd-label-*` sits tight; 0.25em
    // widens object columns vs `tests/golden/fixtures` CD).
    let cdVertSideKernEm = 0.11

    switch direction {
    case "right", "left", "horiz_eq":
        // ── Horizontal arrow: reuse katexStretchyPath for proper KaTeX shape ──
        let supStyle = options.style.superscript
        let subStyle = options.style.subscript_
        let supOpts = options.with(style: supStyle)
        let subOpts = options.with(style: subStyle)
        let supRatio = supStyle.sizeMultiplier / options.style.sizeMultiplier
        let subRatio = subStyle.sizeMultiplier / options.style.sizeMultiplier

        let aboveBox = labelAbove.map { layoutNode($0, supOpts) }
        let belowBox = labelBelow.map { layoutNode($0, subOpts) }

        let aboveW = aboveBox.map { $0.width * supRatio } ?? 0.0
        let belowW = belowBox.map { $0.width * subRatio } ?? 0.0

        // KaTeX `stretchy.js`: CD uses `\cdrightarrow` / `\cdleftarrow` / `\cdlongequal` (minWidth 3.0em).
        let pathLabel =
            if direction == "right" {
                "\\cdrightarrow"
            } else if direction == "left" {
                "\\cdleftarrow"
            } else {
                "\\cdlongequal"
            }
        let minShaftW = katexStretchyMinWidthEm(pathLabel) ?? 1.0
        // Based on KaTeX `.cd-arrow-pad` (0.27778 / 0.55556 script-em); slightly trimmed so
        // `naturalW` matches golden KaTeX PNGs in our box model (e.g. 0150).
        let cdLabelPadL = 0.22
        let cdLabelPadR = 0.48
        let cdPadSup = (cdLabelPadL + cdLabelPadR) * supRatio
        let cdPadSub = (cdLabelPadL + cdLabelPadR) * subRatio
        let upperNeed = aboveBox.map { _ in aboveW + cdPadSup } ?? 0.0
        let lowerNeed = belowBox.map { _ in belowW + cdPadSub } ?? 0.0
        let naturalW = max(max(upperNeed, lowerNeed), 0.0)
        let shaftW = targetSize > 0.0 ? targetSize : max(naturalW, minShaftW)

        let commands: [PathCommand]
        let actualArrowH: Double
        let fillArrow: Bool
        if let (c, h) = katexStretchyPath(pathLabel, widthEm: shaftW) {
            (commands, actualArrowH, fillArrow) = (c, h, true)
        } else {
            // Fallback hand-drawn (should not happen for these labels)
            let arrowH = 0.3
            let ah = 0.12
            let cmds: [PathCommand] =
                if direction == "horiz_eq" {
                    {
                        let gap = 0.06
                        return [
                            .moveTo(x: 0.0, y: -gap),
                            .lineTo(x: shaftW, y: -gap),
                            .moveTo(x: 0.0, y: gap),
                            .lineTo(x: shaftW, y: gap),
                        ]
                    }()
                } else if direction == "right" {
                    [
                        .moveTo(x: 0.0, y: 0.0),
                        .lineTo(x: shaftW, y: 0.0),
                        .moveTo(x: shaftW - ah, y: -ah),
                        .lineTo(x: shaftW, y: 0.0),
                        .lineTo(x: shaftW - ah, y: ah),
                    ]
                } else {
                    [
                        .moveTo(x: shaftW, y: 0.0),
                        .lineTo(x: 0.0, y: 0.0),
                        .moveTo(x: ah, y: -ah),
                        .lineTo(x: 0.0, y: 0.0),
                        .lineTo(x: ah, y: ah),
                    ]
                }
            (commands, actualArrowH, fillArrow) = (cmds, arrowH, false)
        }

        // Arrow box centered at y=0 (same as layoutXArrow)
        let arrowHalf = actualArrowH / 2.0
        let arrowBox = LayoutBox(
            width: shaftW, height: arrowHalf, depth: arrowHalf,
            content: .svgPath(commands: commands, fill: fillArrow),
            color: options.color)

        // Total height/depth for opLimits (mirrors layoutXArrow / KaTeX arrow.ts)
        let gap = 0.111
        let supH = aboveBox.map { $0.height * supRatio } ?? 0.0
        let supD = aboveBox.map { $0.depth * supRatio } ?? 0.0
        // KaTeX arrow.ts: label depth only shifts the label up when depth > 0.25
        // (at the label's own scale). Otherwise the label baseline stays fixed and
        // depth extends into the gap without increasing the cell height.
        let supDContrib = (aboveBox?.depth ?? 0.0) > 0.25 ? supD : 0.0
        let height = axis + arrowHalf + gap + supH + supDContrib
        let subHRaw = belowBox.map { $0.height * subRatio } ?? 0.0
        let subDRaw = belowBox.map { $0.depth * subRatio } ?? 0.0
        let depth =
            if belowBox != nil {
                max(arrowHalf - axis, 0.0) + gap + subHRaw + subDRaw
            } else {
                max(arrowHalf - axis, 0.0)
            }

        let inner = LayoutBox(
            width: shaftW, height: height, depth: depth,
            content: .opLimits(
                base: arrowBox, sup: aboveBox, sub: belowBox,
                baseShift: -axis, supKern: gap, subKern: gap, slant: 0.0,
                supScale: supRatio, subScale: subRatio),
            color: options.color)

        // KaTeX HTML: column width is max(cell widths); each cell stays intrinsic width and is
        // centered in the column (`col-align-c`). Match with side kerns, not by stretching the
        // shaft to the column max.
        if targetColWidth > inner.width + 1e-6 {
            let extra = targetColWidth - inner.width
            let kl = extra / 2.0
            let kr = extra - kl
            return cdWrapHpad(inner, kl, kr, options.color)
        } else {
            return inner
        }

    case "down", "up", "vert_eq":
        // Pass 1: \Big (~1.8em). Pass 2: stretch ↑/↓ / ‖ to the full arrow-row span (em).
        let bigTotal = cdBigTotalHeight  // SIZE_TO_MAX_HEIGHT[2] = 1.8em

        let shaftBox: LayoutBox =
            switch direction {
            case "vert_eq" where targetSize > 0.0:
                makeVertDelimBox(
                    max(targetSize, bigTotal), isDouble: true, isSizedDelim: false, options)
            case "vert_eq":
                makeStretchyDelim("\\Vert", bigTotal, options)
            case "down" where targetSize > 0.0:
                cdStretchVertArrowBox(max(targetSize, 1.0), down: true, options)
            case "up" where targetSize > 0.0:
                cdStretchVertArrowBox(max(targetSize, 1.0), down: false, options)
            case "down":
                cdStretchVertArrowBox(bigTotal, down: true, options)
            case "up":
                cdStretchVertArrowBox(bigTotal, down: false, options)
            default:
                cdStretchVertArrowBox(bigTotal, down: true, options)
            }
        let boxH = shaftBox.height
        let boxD = shaftBox.depth
        let shaftW = shaftBox.width

        // Side labels: KaTeX uses `style.sup()` for both left and right; scale via `scaled`
        // so `toDisplay` raiseBox does not leave them at display size (unlike `opLimits`).
        let leftBox = labelAbove.map {
            cdVcenterSideLabel(cdSideLabelScaled($0, options), boxH, boxD, options.color)
        }
        let rightBox = labelBelow.map {
            cdVcenterSideLabel(cdSideLabelScaled($0, options), boxH, boxD, options.color)
        }

        let leftW = leftBox?.width ?? 0.0
        let rightW = rightBox?.width ?? 0.0
        let leftPart = leftW + (leftW > 0.0 ? cdVertSideKernEm : 0.0)
        let rightPart = (rightW > 0.0 ? cdVertSideKernEm : 0.0) + rightW
        let innerW = leftPart + shaftW + rightPart

        // Center shaft within the column width (pass 2) using side kerns.
        let (kernLeft, kernRight, totalW): (Double, Double, Double)
        if targetColWidth > innerW {
            let extra = targetColWidth - innerW
            let kl = extra / 2.0
            let kr = extra - kl
            (kernLeft, kernRight, totalW) = (kl, kr, targetColWidth)
        } else {
            (kernLeft, kernRight, totalW) = (0.0, 0.0, innerW)
        }

        var children: [LayoutBox] = []
        if kernLeft > 0.0 {
            children.append(.kern(kernLeft))
        }
        if let lb = leftBox {
            children.append(lb)
            children.append(.kern(cdVertSideKernEm))
        }
        children.append(shaftBox)
        if let rb = rightBox {
            children.append(.kern(cdVertSideKernEm))
            children.append(rb)
        }
        if kernRight > 0.0 {
            children.append(.kern(kernRight))
        }

        return LayoutBox(
            width: totalW, height: boxH, depth: boxD,
            content: .hbox(children),
            color: options.color)

    // "none" or unknown: empty placeholder
    default:
        return .empty
    }
}

/// Layout a `\begin{CD}...\end{CD}` commutative diagram with two-pass stretching.
func layoutCD(_ body: [[ParseNode]], _ options: LayoutOptions) -> LayoutBox {
    let metrics = options.metrics
    let pt = 1.0 / metrics.ptPerEm
    // KaTeX CD uses `baselineskip = 3ex` (array.ts line 312), NOT the standard 12pt.
    let baselineskip = 3.0 * metrics.xHeight
    let arstrutH = 0.7 * baselineskip
    let arstrutD = 0.3 * baselineskip

    let numRows = body.count
    if numRows == 0 {
        return .empty
    }
    let numCols = body.map { $0.count }.max() ?? 0
    if numCols == 0 {
        return .empty
    }

    // `\jot` (3pt): added to every row depth below; include in vertical-arrow stretch span.
    let jot = 3.0 * pt

    // ── Pass 1: layout all cells at natural size ────────────────────────────
    var cellBoxes: [[LayoutBox]] = []
    cellBoxes.reserveCapacity(numRows)
    var colWidths = [Double](repeating: 0.0, count: numCols)
    var rowHeights = [Double](repeating: arstrutH, count: numRows)
    var rowDepths = [Double](repeating: arstrutD, count: numRows)

    for (r, row) in body.enumerated() {
        var rowBoxes: [LayoutBox] = []
        rowBoxes.reserveCapacity(numCols)

        for (c, cell) in row.enumerated() {
            let cbox: LayoutBox
            switch cell.kind {
            case let .cdArrow(direction, labelAbove, labelBelow):
                cbox = layoutCDArrow(
                    direction,
                    labelAbove,
                    labelBelow,
                    0.0,  // natural size in pass 1
                    0.0,  // natural column width
                    0.0,  // natural depth split
                    options)
            // KaTeX CD object cells are `styling` nodes; `sizingGroup` builds the body with
            // `buildExpression(..., false)` (see katex `functions/sizing.js`), so no inter-atom
            // math glue inside a cell — matching that avoids spurious Ord–Bin space (e.g. golden 0963).
            case let .ordGroup(cellBody, _):
                cbox = layoutExpression(cellBody, options, isRealGroup: false)
            default:
                cbox = layoutNode(cell, options)
            }

            rowHeights[r] = max(rowHeights[r], cbox.height)
            rowDepths[r] = max(rowDepths[r], cbox.depth)
            colWidths[c] = max(colWidths[c], cbox.width)
            rowBoxes.append(cbox)
        }

        // Pad missing columns
        while rowBoxes.count < numCols {
            rowBoxes.append(.empty)
        }
        cellBoxes.append(rowBoxes)
    }

    // Column targets after pass 1 (max natural width per column). Horizontal shafts use per-cell
    // `targetSize`, not this max — same as KaTeX: minCDarrowwidth is min-width on the glyph span,
    // not “stretch every row to column max”.
    let colTargetW = colWidths

    // ── Pass 2: re-layout arrow cells with target dimensions ───────────────
    for (r, row) in body.enumerated() {
        let isArrowRow = r % 2 == 1
        for (c, cell) in row.enumerated() {
            guard case let .cdArrow(direction, labelAbove, labelBelow) = cell.kind else {
                continue
            }
            let isHoriz = direction == "right" || direction == "left" || direction == "horiz_eq"
            let newBox: LayoutBox
            let colW: Double
            if !isArrowRow && c % 2 == 1 && isHoriz {
                let b = layoutCDArrow(
                    direction,
                    labelAbove,
                    labelBelow,
                    cellBoxes[r][c].width,
                    colTargetW[c],
                    0.0,
                    options)
                (newBox, colW) = (b, b.width)
            } else if isArrowRow && c % 2 == 0 {
                // Vertical arrow: KaTeX uses a fixed `\Big` delimiter, not a
                // stretchy arrow.  Match by using the pass-1 row span (without
                // \jot) so the shaft height stays at the natural row h+d.
                let vSpan = rowHeights[r] + rowDepths[r]
                let b = layoutCDArrow(
                    direction,
                    labelAbove,
                    labelBelow,
                    vSpan,
                    colWidths[c],
                    0.0,
                    options)
                (newBox, colW) = (b, b.width)
            } else {
                continue
            }
            colWidths[c] = max(colWidths[c], colW)
            cellBoxes[r][c] = newBox
        }
    }

    // KaTeX `environments/cd.js` sets `addJot: true` for CD; `array.js` adds `\jot` (3pt) to each
    // row's depth (same as `layoutArray` when `addJot` is set).
    for r in 0..<rowDepths.count {
        rowDepths[r] += jot
    }

    // ── Build the final Array LayoutBox ────────────────────────────────────
    // KaTeX CD uses `pregap: 0.25, postgap: 0.25` per column (cd.ts line 216-217),
    // giving 0.5em between adjacent columns.  `hskipBeforeAndAfter` is unset (false),
    // so no outer padding.
    let colGap = 0.5

    // Column alignment: objects are centered, arrows are centered
    let colAligns = [Character](repeating: "c", count: numCols)

    // No vertical separators for CD
    let colSeparators = [Bool?](repeating: nil, count: numCols + 1)

    var totalHeight = 0.0
    var rowPositions: [Double] = []
    rowPositions.reserveCapacity(numRows)
    for (rowHeight, rowDepth) in zip(rowHeights, rowDepths) {
        totalHeight += rowHeight
        rowPositions.append(totalHeight)
        totalHeight += rowDepth
    }

    let offset = totalHeight / 2.0 + metrics.axisHeight
    let height = offset
    let depth = totalHeight - offset

    // Total width: sum of colWidths + colGap between each
    let totalWidth =
        colWidths.reduce(0.0, +) + colGap * Double(numCols > 0 ? numCols - 1 : 0)

    // Build hlinesBeforeRow (all empty for CD)
    let hlinesBeforeRow = [[Bool]](repeating: [], count: numRows + 1)

    return LayoutBox(
        width: totalWidth, height: height, depth: depth,
        content: .array(
            ArrayLayout(
                cells: cellBoxes,
                colWidths: colWidths,
                colAligns: colAligns,
                rowHeights: rowHeights,
                rowDepths: rowDepths,
                colGap: colGap,
                offset: offset,
                contentXOffset: 0.0,
                colSeparators: colSeparators,
                hlinesBeforeRow: hlinesBeforeRow,
                ruleThickness: 0.04 * pt,
                doubleRuleSep: metrics.doubleRuleSep,
                arrayInnerWidth: totalWidth,
                tagGapEm: 0.0,
                tagColWidth: 0.0,
                rowTags: [LayoutBox?](repeating: nil, count: numRows),
                tagsLeft: false)),
        color: options.color)
}

// ============================================================================
// Bussproofs proof trees
// ============================================================================

private struct ProofTreeLayout {
    var width: Double
    var height: Double
    var depth: Double
    var rootWidth: Double
    var rootCenterX: Double
    var children: [PlacedBox]
    var rules: [ProofRule]
}

/// MathJax `bussproofs` typesets each axiom / inference **cell** with upright letters
/// (roman), not math italic. SwaTex otherwise lays out cell bodies like ordinary math
/// (`P` → Math-Italic). Wrap the cell in `\mathrm{...}` so single-letter conclusions
/// match reference PNGs; relation symbols like `\Rightarrow` from `\fCenter` still
/// fall through `layoutWithFont` to default `layoutNode` and keep correct spacing.
private func layoutProofRomanContent(
    _ nodes: [ParseNode], _ options: LayoutOptions
) -> LayoutBox {
    if nodes.isEmpty {
        return .empty
    }
    let group = ParseNode(.ordGroup(body: nodes, semisimple: nil), mode: .math)
    let wrapped = ParseNode(.font(font: "mathrm", body: group), mode: .math)
    return layoutNode(wrapped, options)
}

private func layoutProofCellContent(
    _ nodes: [ParseNode], _ options: LayoutOptions
) -> LayoutBox {
    var box = layoutProofRomanContent(nodes, options)
    box.depth = max(box.depth, 0.20)
    return box
}

func layoutProofTree(_ tree: ProofBranch, _ options: LayoutOptions) -> LayoutBox {
    let laid = layoutProofBranch(tree, options)
    return LayoutBox(
        width: laid.width, height: laid.height, depth: laid.depth,
        content: .proofTree(children: laid.children, rules: laid.rules),
        color: options.color)
}

private func layoutProofBranch(_ tree: ProofBranch, _ options: LayoutOptions) -> ProofTreeLayout {
    let metrics = options.metrics
    let ruleThickness = max(metrics.defaultRuleThickness * 2.0, 0.08)
    // Bussproofs spacing constants (in em).
    // Tune premise spacing to better match MathJax/bussproofs horizontal spread.
    //   premiseGap  → horizontal gap between sibling premises
    //   labelGap    → gap between inference rule and its left/right label
    //   verticalGap → vertical gap between rule and surrounding content
    let premiseGap = 2.0
    let labelGap = 0.08
    let verticalGap = 0.32

    let conclusion = layoutProofCellContent(tree.conclusion, options)
    let conclusionWidth = conclusion.width

    if tree.premises.isEmpty {
        let width = conclusion.width
        let height = conclusion.height
        let depth = conclusion.depth
        return ProofTreeLayout(
            width: width,
            height: height,
            depth: depth,
            rootWidth: width,
            rootCenterX: width / 2.0,
            children: [PlacedBox(box: conclusion, x: 0.0, baselineY: height)],
            rules: [])
    }

    let premiseLayouts = tree.premises.map { layoutProofBranch($0, options) }

    let premiseWidth =
        premiseLayouts.map(\.width).reduce(0.0, +)
        + premiseGap * Double(premiseLayouts.count > 0 ? premiseLayouts.count - 1 : 0)
    let premiseHeight = premiseLayouts.map(\.height).reduce(0.0, max)
    let premiseDepth = premiseLayouts.map(\.depth).reduce(0.0, max)
    let premiseTotal = premiseHeight + premiseDepth

    var premiseRootLeft = Double.infinity
    var premiseRootRight = -Double.infinity
    do {
        var cursor = 0.0
        for premise in premiseLayouts {
            let rootLeft = cursor + premise.rootCenterX - premise.rootWidth / 2.0
            let rootRight = cursor + premise.rootCenterX + premise.rootWidth / 2.0
            premiseRootLeft = min(premiseRootLeft, rootLeft)
            premiseRootRight = max(premiseRootRight, rootRight)
            cursor += premise.width + premiseGap
        }
    }
    let rulePadding = tree.premises.count > 1 ? 0.65 : 0.0
    let premiseRuleWidth = premiseRootRight - premiseRootLeft + rulePadding
    let premiseRootCenter = (premiseRootLeft + premiseRootRight) / 2.0
    let ruleWidth = max(max(premiseRuleWidth, conclusionWidth), 1.12)
    let coreWidth = max(max(premiseWidth, ruleWidth), conclusionWidth)
    let centerX = coreWidth / 2.0
    let premiseStartX = centerX - premiseWidth / 2.0
    var rootCenterX = premiseStartX + premiseRootCenter
    let ruleX = rootCenterX - ruleWidth / 2.0
    let ruleY = premiseTotal + verticalGap + ruleThickness / 2.0
    let conclusionX = rootCenterX - conclusionWidth / 2.0
    let conclusionBaselineY = ruleY + ruleThickness / 2.0 + verticalGap + conclusion.height

    var children: [PlacedBox] = []
    var rules: [ProofRule] = []
    var minX = 0.0
    var maxX = coreWidth

    if tree.rootAtTop {
        let conclusionBaselineY = conclusion.height
        let ruleY = conclusion.height + conclusion.depth + verticalGap + ruleThickness / 2.0
        let premiseTopY = ruleY + ruleThickness / 2.0 + verticalGap
        let premiseBaselineY = premiseTopY + premiseHeight

        minX = min(minX, conclusionX)
        maxX = max(maxX, conclusionX + conclusionWidth)
        children.append(
            PlacedBox(box: conclusion, x: conclusionX, baselineY: conclusionBaselineY))

        var cursor = premiseStartX
        for premise in premiseLayouts {
            let childTopY = premiseBaselineY - premise.height
            for child in premise.children {
                let x = cursor + child.x
                let y = childTopY + child.baselineY
                minX = min(minX, x)
                maxX = max(maxX, x + child.box.width)
                children.append(PlacedBox(box: child.box, x: x, baselineY: y))
            }
            for rule in premise.rules {
                minX = min(minX, cursor + rule.x)
                maxX = max(maxX, cursor + rule.x + rule.width)
                rules.append(
                    ProofRule(
                        x: cursor + rule.x,
                        y: childTopY + rule.y,
                        width: rule.width,
                        thickness: rule.thickness,
                        dashed: rule.dashed))
            }
            cursor += premise.width + premiseGap
        }

        if tree.lineStyle != .none {
            rules.append(
                ProofRule(
                    x: ruleX, y: ruleY, width: ruleWidth, thickness: ruleThickness,
                    dashed: tree.lineStyle == .dashed))
        }

        if let label = tree.leftLabel {
            let labelOpts = options.with(style: options.style.textEquivalent)
            let labelBox = layoutProofRomanContent(label, labelOpts)
            let x = ruleX - labelGap - labelBox.width
            let baselineY = ruleY + (labelBox.height - labelBox.depth) / 2.0
            minX = min(minX, x)
            maxX = max(maxX, x + labelBox.width)
            children.append(PlacedBox(box: labelBox, x: x, baselineY: baselineY))
        }

        if let label = tree.rightLabel {
            let labelOpts = options.with(style: options.style.textEquivalent)
            let labelBox = layoutProofRomanContent(label, labelOpts)
            let x = ruleX + ruleWidth + labelGap
            let baselineY = ruleY + (labelBox.height - labelBox.depth) / 2.0
            minX = min(minX, x)
            maxX = max(maxX, x + labelBox.width)
            children.append(PlacedBox(box: labelBox, x: x, baselineY: baselineY))
        }

        if minX < 0.0 {
            let shiftX = -minX
            for i in 0..<children.count {
                children[i].x += shiftX
            }
            for i in 0..<rules.count {
                rules[i].x += shiftX
            }
            rootCenterX += shiftX
        }

        return ProofTreeLayout(
            width: maxX - minX,
            height: conclusionBaselineY,
            depth: max(
                children
                    .map { $0.baselineY + $0.box.depth - conclusionBaselineY }
                    .reduce(0.0, max),
                0.0),
            rootWidth: conclusionWidth,
            rootCenterX: rootCenterX,
            children: children,
            rules: rules)
    }

    var cursor = premiseStartX
    for premise in premiseLayouts {
        let baselineY = premiseHeight
        let childTopY = baselineY - premise.height
        for child in premise.children {
            let x = cursor + child.x
            let y = childTopY + child.baselineY
            minX = min(minX, x)
            maxX = max(maxX, x + child.box.width)
            children.append(PlacedBox(box: child.box, x: x, baselineY: y))
        }
        for rule in premise.rules {
            minX = min(minX, cursor + rule.x)
            maxX = max(maxX, cursor + rule.x + rule.width)
            rules.append(
                ProofRule(
                    x: cursor + rule.x,
                    y: childTopY + rule.y,
                    width: rule.width,
                    thickness: rule.thickness,
                    dashed: rule.dashed))
        }
        cursor += premise.width + premiseGap
    }

    minX = min(minX, conclusionX)
    maxX = max(maxX, conclusionX + conclusionWidth)
    children.append(PlacedBox(box: conclusion, x: conclusionX, baselineY: conclusionBaselineY))

    if tree.lineStyle != .none {
        rules.append(
            ProofRule(
                x: ruleX, y: ruleY, width: ruleWidth, thickness: ruleThickness,
                dashed: tree.lineStyle == .dashed))
    }

    if let label = tree.leftLabel {
        let labelOpts = options.with(style: options.style.textEquivalent)
        let labelBox = layoutProofRomanContent(label, labelOpts)
        let x = ruleX - labelGap - labelBox.width
        let baselineY = ruleY + (labelBox.height - labelBox.depth) / 2.0
        minX = min(minX, x)
        maxX = max(maxX, x + labelBox.width)
        children.append(PlacedBox(box: labelBox, x: x, baselineY: baselineY))
    }

    if let label = tree.rightLabel {
        let labelOpts = options.with(style: options.style.textEquivalent)
        let labelBox = layoutProofRomanContent(label, labelOpts)
        let x = ruleX + ruleWidth + labelGap
        let baselineY = ruleY + (labelBox.height - labelBox.depth) / 2.0
        minX = min(minX, x)
        maxX = max(maxX, x + labelBox.width)
        children.append(PlacedBox(box: labelBox, x: x, baselineY: baselineY))
    }

    if minX < 0.0 {
        let shift = -minX
        for i in 0..<children.count {
            children[i].x += shift
        }
        for i in 0..<rules.count {
            rules[i].x += shift
        }
        rootCenterX += shift
    }

    return ProofTreeLayout(
        width: maxX - minX,
        height: conclusionBaselineY,
        depth: children
            .map { $0.baselineY + $0.box.depth - conclusionBaselineY }
            .reduce(0.0, max),
        rootWidth: conclusionWidth,
        rootCenterX: rootCenterX,
        children: children,
        rules: rules)
}

// ============================================================================
// Horizontal brace paths
// ============================================================================

func horizBracePath(_ width: Double, _ height: Double, _ isOver: Bool) -> [PathCommand] {
    let mid = width / 2.0
    let q = height * 0.6
    if isOver {
        return [
            .moveTo(x: 0.0, y: 0.0),
            .quadTo(x1: 0.0, y1: -q, x: mid * 0.4, y: -q),
            .lineTo(x: mid - 0.05, y: -q),
            .lineTo(x: mid, y: -height),
            .lineTo(x: mid + 0.05, y: -q),
            .lineTo(x: width - mid * 0.4, y: -q),
            .quadTo(x1: width, y1: -q, x: width, y: 0.0),
        ]
    } else {
        return [
            .moveTo(x: 0.0, y: 0.0),
            .quadTo(x1: 0.0, y1: q, x: mid * 0.4, y: q),
            .lineTo(x: mid - 0.05, y: q),
            .lineTo(x: mid, y: height),
            .lineTo(x: mid + 0.05, y: q),
            .lineTo(x: width - mid * 0.4, y: q),
            .quadTo(x1: width, y1: q, x: width, y: 0.0),
        ]
    }
}
