/// Port of RaTeX crates/ratex-parser/src/environments.rs
/// Defines the environments registry (EnvSpec / EnvContext) and all
/// environment handlers (array, matrix, cases, aligned, gathered, alignat,
/// subarray, smallmatrix, CD, prooftree, etc.).

// ── Environment registry ─────────────────────────────────────────────────

/// Context passed to environment handlers.
struct EnvContext {
    var mode: Mode
    var envName: String
    var parser: Parser
}

/// Handler function signature for environments.
typealias EnvHandler =
    @Sendable (
        _ ctx: inout EnvContext,
        _ args: [ParseNode],
        _ optArgs: [ParseNode?]
    ) throws(ParseError) -> ParseNode

/// Specification for a registered environment.
struct EnvSpec: Sendable {
    var numArgs: Int
    var numOptionalArgs: Int
    var handler: EnvHandler
}

/// The global environment registry: environment name → spec.
///
/// Built once, lazily and thread-safely (`static let` is the Swift
/// equivalent of Rust's `LazyLock`).
enum Environments {
    static let registry: [String: EnvSpec] = {
        var map: [String: EnvSpec] = [:]
        registerArray(&map)
        registerMatrix(&map)
        registerCases(&map)
        registerAlign(&map)
        registerGathered(&map)
        registerEquation(&map)
        registerSmallmatrix(&map)
        registerAlignat(&map)
        registerSubarray(&map)
        registerCD(&map)
        registerProoftree(&map)
        return map
    }()
}

// ── ArrayConfig ──────────────────────────────────────────────────────────

struct ArrayConfig {
    var hskipBeforeAndAfter: Bool?
    var addJot: Bool?
    var cols: [AlignSpec]?
    var arraystretch: Double?
    var colSeparationType: String?
    var singleRow: Bool
    var emptySingleRow: Bool
    var maxNumCols: Int?
    var leqno: Bool?
    var autoNumber: Bool

    init(
        hskipBeforeAndAfter: Bool? = nil, addJot: Bool? = nil,
        cols: [AlignSpec]? = nil, arraystretch: Double? = nil,
        colSeparationType: String? = nil, singleRow: Bool = false,
        emptySingleRow: Bool = false, maxNumCols: Int? = nil,
        leqno: Bool? = nil, autoNumber: Bool = false
    ) {
        self.hskipBeforeAndAfter = hskipBeforeAndAfter
        self.addJot = addJot
        self.cols = cols
        self.arraystretch = arraystretch
        self.colSeparationType = colSeparationType
        self.singleRow = singleRow
        self.emptySingleRow = emptySingleRow
        self.maxNumCols = maxNumCols
        self.leqno = leqno
        self.autoNumber = autoNumber
    }
}

// ── parseArray ───────────────────────────────────────────────────────────

/// Pull a trailing `\tag{…}` or `\nonumber`/`\notag` off the last cell of a row.
/// Returns `.auto(true)` when the row is eligible for auto-numbering.
/// The `autoNumber` parameter controls the default when no marker is found.
private func extractTrailingTagFromLastCell(
    _ row: inout [ParseNode], autoNumber: Bool
) throws(ParseError) -> ArrayTag {
    let defaultTag: ArrayTag = .auto(autoNumber)
    guard !row.isEmpty else {
        // INTENTIONALLY UNCOVERED (defensive guard KEEP): the only caller
        // (`parseArray`) appends the just-parsed cell to `row` before
        // calling, so `row` is never empty here.
        return defaultTag
    }
    let lastIdx = row.count - 1

    // Locate the inner node (unwrap a single-element styling wrapper).
    var isStyled = false
    var inner = row[lastIdx]
    if case let .styling(_, stylingBody) = row[lastIdx].kind {
        if stylingBody.count != 1 {
            // INTENTIONALLY UNCOVERED (defensive guard KEEP): `parseArray`
            // builds styled cells as `.styling(style, [cell])` — exactly one
            // element — so this mismatch cannot occur.
            return defaultTag
        }
        isStyled = true
        inner = stylingBody[0]
    }

    guard case let .ordGroup(obodyOrig, semisimple) = inner.kind else {
        // INTENTIONALLY UNCOVERED (defensive guard KEEP): `parseArray` cells
        // are always an `.ordGroup`, optionally wrapped in `.styling` — the
        // unwrapped inner node is an `.ordGroup` in both shapes.
        return defaultTag
    }
    var obody = obodyOrig

    // Write a mutated ordgroup body back into the row (Rust mutates in place).
    func writeBack(_ obody: [ParseNode]) {
        var newInner = inner
        newInner.kind = .ordGroup(body: obody, semisimple: semisimple)
        if isStyled {
            if case let .styling(style, _) = row[lastIdx].kind {
                row[lastIdx].kind = .styling(style: style, body: [newInner])
            }
        } else {
            // INTENTIONALLY UNCOVERED (defensive branch KEEP): every
            // `parseArray` caller passes a non-nil cell style (`dCellStyle`
            // never returns nil; the rest pass `.display`/`.script`), so
            // cells are always styling-wrapped and `isStyled` is true.
            row[lastIdx] = newInner
        }
    }

    // Look for \tag
    var tagIndices: [Int] = []
    // Look for \nonumber / \notag
    var nonumberIndices: [Int] = []
    for (i, n) in obody.enumerated() {
        if case .tag = n.kind {
            tagIndices.append(i)
        }
        if case .noNumber = n.kind {
            nonumberIndices.append(i)
        }
    }

    // Can't have both \tag and \nonumber in the same row
    if !tagIndices.isEmpty && !nonumberIndices.isEmpty {
        throw ParseError("Cannot use both \\tag and \\nonumber in the same row")
    }

    // Handle \tag
    if !tagIndices.isEmpty {
        if tagIndices.count > 1 {
            throw ParseError("Multiple \\tag in a row")
        }
        let idx = tagIndices[0]
        if idx != obody.count - 1 {
            throw ParseError("\\tag must appear at the end of the row after the equation body")
        }
        let popped = obody.removeLast()
        writeBack(obody)
        if case let .tag(_, tag) = popped.kind {
            if tag.isEmpty {
                return .auto(false)
            } else {
                return .explicit(tag)
            }
        }
        // INTENTIONALLY UNCOVERED (defensive fallthrough KEEP): `popped` is
        // the node at `tagIndices[0]`, which was collected by matching
        // `case .tag` above, so the `if case .tag` always binds.
        return defaultTag
    } else if !nonumberIndices.isEmpty {
        // Handle \nonumber / \notag
        if nonumberIndices.count > 1 {
            throw ParseError("Multiple \\nonumber in a row")
        }
        let idx = nonumberIndices[0]
        if idx != obody.count - 1 {
            throw ParseError("\\nonumber must appear at the end of the row")
        }
        obody.removeLast()  // discard the NoNumber node
        writeBack(obody)
        return .auto(false)
    } else {
        // Neither \tag nor \nonumber
        return defaultTag
    }
}

private func getHlines(_ parser: Parser) throws(ParseError) -> [Bool] {
    var hlineInfo: [Bool] = []
    try parser.consumeSpaces()

    var nxt = try parser.fetch().text
    if nxt == "\\relax" {
        parser.consume()
        try parser.consumeSpaces()
        nxt = try parser.fetch().text
    }
    while nxt == "\\hline" || nxt == "\\hdashline" {
        parser.consume()
        hlineInfo.append(nxt == "\\hdashline")
        try parser.consumeSpaces()
        nxt = try parser.fetch().text
    }
    return hlineInfo
}

private func dCellStyle(_ envName: String) -> StyleStr? {
    if envName.hasPrefix("d") {
        .display
    } else {
        .text
    }
}

func parseArray(
    _ parser: Parser, _ config: ArrayConfig, _ style: StyleStr?
) throws(ParseError) -> ParseNode {
    parser.gullet.beginGroup()

    if !config.singleRow {
        parser.gullet.setTextMacro("\\cr", "\\\\\\relax")
    }

    let arraystretch: Double
    if let s = config.arraystretch {
        arraystretch = s
    } else {
        // Check if \arraystretch is defined as a macro (e.g., via \def\arraystretch{1.5})
        if let def = parser.gullet.getMacro("\\arraystretch") {
            let s: String
            switch def {
            case .text(let text):
                s = text
            case .tokens(let tokens, _, _):
                // Tokens are stored in reverse order (stack convention for expansion)
                s = tokens.reversed().map(\.text).joined()
            case .function:
                s = ""
            }
            arraystretch = Double(s) ?? 1.0
        } else {
            arraystretch = 1.0
        }
    }

    parser.gullet.beginGroup()

    var row: [ParseNode] = []
    var body: [[ParseNode]] = []
    var rowTags: [ArrayTag] = []
    var rowGaps: [Measurement?] = []
    var hLinesBeforeRow: [[Bool]] = []

    hLinesBeforeRow.append(try getHlines(parser))

    while true {
        let breakToken = config.singleRow ? "\\end" : "\\\\"
        let cellBody = try parser.parseExpression(
            breakOnInfix: false, breakOnTokenText: breakToken)
        parser.gullet.endGroup()
        parser.gullet.beginGroup()

        var cell = ParseNode(.ordGroup(body: cellBody, semisimple: nil), mode: parser.mode)

        if let s = style {
            cell = ParseNode(.styling(style: s, body: [cell]), mode: parser.mode)
        }

        row.append(cell)
        let next = try parser.fetch().text

        if next == "&" {
            if let max = config.maxNumCols, row.count >= max {
                throw ParseError("Too many tab characters: &")
            }
            parser.consume()
        } else if next == "\\end" {
            // Check for trailing empty row and remove it
            let isEmptyTrailing: Bool
            if let s = style {
                if s == .text || s == .display {
                    if case let .styling(_, sb) = cell.kind,
                        let first = sb.first,
                        case let .ordGroup(ob, _) = first.kind
                    {
                        isEmptyTrailing = ob.isEmpty
                    } else {
                        // INTENTIONALLY UNCOVERED (defensive branch KEEP):
                        // styled cells are always `.styling(_, [ordGroup])`
                        // (built a few lines above), so the pattern in the
                        // `if` always matches.
                        isEmptyTrailing = false
                    }
                } else {
                    isEmptyTrailing = false
                }
            } else if case let .ordGroup(ob, _) = cell.kind {
                // INTENTIONALLY UNCOVERED (defensive branch KEEP, this
                // branch and the `else` below): every `parseArray` caller
                // passes a non-nil style (`dCellStyle` never returns nil),
                // so the `style == nil` arm is unreachable.
                isEmptyTrailing = ob.isEmpty
            } else {
                isEmptyTrailing = false
            }

            let rowTag = try extractTrailingTagFromLastCell(&row, autoNumber: config.autoNumber)
            rowTags.append(rowTag)
            body.append(row)

            if isEmptyTrailing && (body.count > 1 || !config.emptySingleRow) {
                body.removeLast()
                rowTags.removeLast()
            }

            if hLinesBeforeRow.count < body.count + 1 {
                hLinesBeforeRow.append([])
            }
            break
        } else if next == "\\\\" {
            parser.consume()
            let size: ParseNode?
            if parser.gullet.future().text != " " {
                size = try parser.parseSizeGroup(optional: true)
            } else {
                size = nil
            }
            var gap: Measurement?
            if let s = size, case let .size(value, _) = s.kind {
                gap = value
            }
            rowGaps.append(gap)

            let rowTag = try extractTrailingTagFromLastCell(&row, autoNumber: config.autoNumber)
            rowTags.append(rowTag)
            body.append(row)
            hLinesBeforeRow.append(try getHlines(parser))
            row = []
        } else {
            throw ParseError("Expected & or \\\\ or \\cr or \\end, got '\(next)'")
        }
    }

    parser.gullet.endGroup()
    parser.gullet.endGroup()

    // Post-process row tags for auto-numbering
    let tags: [ArrayTag]?
    if config.autoNumber {
        var processed: [ArrayTag] = []
        processed.reserveCapacity(rowTags.count)
        var anyVisible = false
        for rawTag in rowTags {
            switch rawTag {
            case .explicit(let nodes):
                if !nodes.isEmpty {
                    // Explicit \tag{...}: step counter, keep tag content as-is
                    parser.equationCounter += 1
                    processed.append(.explicit(nodes))
                    anyVisible = true
                } else {
                    // INTENTIONALLY UNCOVERED (defensive branch KEEP):
                    // `.explicit` tags come only from
                    // `extractTrailingTagFromLastCell`, which returns
                    // `.auto(false)` for empty tag bodies (and non-starred
                    // `\tag{…}` always adds parens), so `.explicit([])`
                    // cannot occur.
                    // Empty \tag{}: treat as suppressed
                    processed.append(.auto(false))
                }
            case .auto(let visible):
                if visible {
                    // Auto-number this row: step counter, generate "(N)"
                    parser.equationCounter += 1
                    let numStr = String(parser.equationCounter)
                    let tagNodes = [
                        ParseNode(.mathOrd(text: "("), mode: .math),
                        ParseNode(.mathOrd(text: numStr), mode: .math),
                        ParseNode(.mathOrd(text: ")"), mode: .math),
                    ]
                    processed.append(.explicit(tagNodes))
                    anyVisible = true
                } else {
                    // Suppressed by \nonumber or empty \tag{}: no counter step, no tag
                    processed.append(.auto(false))
                }
            }
        }
        tags = anyVisible ? processed : nil
    } else {
        // Not an auto-numbering environment: keep original behavior
        let hasVisibleExplicit = rowTags.contains { tag in
            if case let .explicit(nodes) = tag {
                return !nodes.isEmpty
            }
            return false
        }
        tags = hasVisibleExplicit ? rowTags : nil
    }

    return ParseNode(
        .array(
            ParseNode.ArrayInfo(
                body: body,
                rowGaps: rowGaps,
                hLinesBeforeRow: hLinesBeforeRow,
                cols: config.cols,
                colSeparationType: config.colSeparationType,
                hskipBeforeAndAfter: config.hskipBeforeAndAfter,
                addJot: config.addJot,
                arraystretch: arraystretch,
                tags: tags,
                leqno: config.leqno,
                isCD: nil)),
        mode: parser.mode)
}

// ── array / darray ───────────────────────────────────────────────────────

private func handleArray(
    _ ctx: inout EnvContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let colalign: [ParseNode]
    if case let .ordGroup(ordBody, _) = args[0].kind {
        colalign = ordBody
    } else if args[0].isSymbolNode {
        // INTENTIONALLY UNCOVERED (defensive branches KEEP, this arm and
        // the `else` throw): environment arguments are produced by
        // `Parser.parseArgumentGroup`, which always wraps the expression in
        // an `.ordGroup`, so `args[0]` matches the first pattern. Kept to
        // mirror KaTeX's handler, which also accepts a bare symbol node.
        colalign = [args[0]]
    } else {
        throw ParseError("Invalid column alignment for array")
    }

    var cols: [AlignSpec] = []
    for nde in colalign {
        guard let ca = nde.symbolText else {
            throw ParseError("Expected column alignment character")
        }
        switch ca {
        case "l", "c", "r":
            cols.append(AlignSpec(alignType: .align, align: ca))
        case "|":
            cols.append(AlignSpec(alignType: .separator, align: "|"))
        case ":":
            cols.append(AlignSpec(alignType: .separator, align: ":"))
        default:
            throw ParseError("Unknown column alignment: \(ca)")
        }
    }

    let maxNumCols = cols.count
    let config = ArrayConfig(
        hskipBeforeAndAfter: true,
        cols: cols,
        maxNumCols: maxNumCols)
    return try parseArray(ctx.parser, config, dCellStyle(ctx.envName))
}

private func registerArray(_ map: inout [String: EnvSpec]) {
    for name in ["array", "darray"] {
        map[name] = EnvSpec(numArgs: 1, numOptionalArgs: 0, handler: handleArray)
    }
}

// ── matrix variants ──────────────────────────────────────────────────────

private func handleMatrix(
    _ ctx: inout EnvContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let baseName = String(ctx.envName.filter { $0 != "*" })
    let delimiters: (String, String)? =
        switch baseName {
        case "matrix": nil
        case "pmatrix": ("(", ")")
        case "bmatrix": ("[", "]")
        case "Bmatrix": ("\\{", "\\}")
        case "vmatrix": ("|", "|")
        case "Vmatrix": ("\\Vert", "\\Vert")
        default: nil
        }

    var colAlign = "c"

    // mathtools starred matrix: parse optional [l|c|r] alignment
    if ctx.envName.hasSuffix("*") {
        ctx.parser.gullet.consumeSpaces()
        if ctx.parser.gullet.future().text == "[" {
            ctx.parser.gullet.popToken()
            ctx.parser.gullet.consumeSpaces()
            let alignTok = ctx.parser.gullet.popToken()
            if !["l", "c", "r"].contains(alignTok.text) {
                throw ParseError("Expected l or c or r", token: alignTok)
            }
            colAlign = alignTok.text
            ctx.parser.gullet.consumeSpaces()
            let close = ctx.parser.gullet.popToken()
            if close.text != "]" {
                throw ParseError("Expected ]", token: close)
            }
        }
    }

    let config = ArrayConfig(
        hskipBeforeAndAfter: false,
        cols: [AlignSpec(alignType: .align, align: colAlign)])

    var res = try parseArray(ctx.parser, config, dCellStyle(ctx.envName))

    // Fix cols to match actual number of columns
    if case .array(var info) = res.kind {
        let numCols = info.body.map(\.count).max() ?? 0
        info.cols = (0..<numCols).map { _ in
            AlignSpec(alignType: .align, align: colAlign)
        }
        res.kind = .array(info)
    }

    if let (left, right) = delimiters {
        return ParseNode(
            .leftRight(body: [res], left: left, right: right, rightColor: nil),
            mode: ctx.mode)
    }
    return res
}

private func registerMatrix(_ map: inout [String: EnvSpec]) {
    for name in [
        "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "matrix*", "pmatrix*",
        "bmatrix*", "Bmatrix*", "vmatrix*", "Vmatrix*",
    ] {
        map[name] = EnvSpec(numArgs: 0, numOptionalArgs: 0, handler: handleMatrix)
    }
}

// ── cases / dcases / rcases / drcases ────────────────────────────────────

private func handleCases(
    _ ctx: inout EnvContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let config = ArrayConfig(
        cols: [
            AlignSpec(alignType: .align, align: "l", pregap: 0.0, postgap: 1.0),
            AlignSpec(alignType: .align, align: "l", pregap: 0.0, postgap: 0.0),
        ],
        arraystretch: 1.2)

    let res = try parseArray(ctx.parser, config, dCellStyle(ctx.envName))

    let (left, right) =
        if ctx.envName.contains("r") {
            (".", "\\}")
        } else {
            ("\\{", ".")
        }

    return ParseNode(
        .leftRight(body: [res], left: left, right: right, rightColor: nil),
        mode: ctx.mode)
}

private func registerCases(_ map: inout [String: EnvSpec]) {
    for name in ["cases", "dcases", "rcases", "drcases"] {
        map[name] = EnvSpec(numArgs: 0, numOptionalArgs: 0, handler: handleCases)
    }
}

// ── align / align* / aligned / split / alignat / alignat* / alignedat ────

private func handleAligned(
    _ ctx: inout EnvContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let isSplit = ctx.envName == "split"
    let isAlignat = ctx.envName.contains("at")
    let sepType = isAlignat ? "alignat" : "align"
    let autoNumber =
        !ctx.envName.hasSuffix("*")
        && !isSplit
        && ctx.envName != "aligned"
        && ctx.envName != "alignedat"

    let config = ArrayConfig(
        addJot: true,
        colSeparationType: sepType,
        emptySingleRow: true,
        maxNumCols: isSplit ? 2 : nil,
        autoNumber: autoNumber)

    var res = try parseArray(ctx.parser, config, .display)

    // Extract explicit column count from first arg (alignat only)
    var numMaths = 0
    var explicitCols = 0
    if let first = args.first, case let .ordGroup(ordBody, _) = first.kind {
        var argStr = ""
        for node in ordBody {
            if let t = node.symbolText {
                argStr += t
            }
        }
        // Mirrors Rust's `parse::<usize>()`: negative counts are rejected
        // (Swift's `Int(_:)` would accept them and the negative column count
        // would trap in `0..<numCols` below). A count whose doubling would
        // overflow is likewise treated as unparseable instead of trapping.
        if let n = Int(argStr), n >= 0, n <= Int.max / 2 {
            // DoS guard (deliberate divergence, like the recursion stack
            // guard): the column loop below materializes 2n specs and the
            // layout stage iterates them per row — a hostile
            // `\begin{alignat}{999999999}` hung the process (KaTeX/RaTeX
            // share the quirk). Real documents use single digits.
            if n > 256 {
                throw ParseError("alignat column count too large: \(n) (maximum 256)")
            }
            numMaths = n
            explicitCols = n * 2
        }
    }
    let isAligned = explicitCols == 0

    // Determine actual number of columns
    var numCols: Int
    if case let .array(info) = res.kind {
        numCols = info.body.map(\.count).max() ?? 0
    } else {
        // INTENTIONALLY UNCOVERED (defensive branch KEEP): `res` comes from
        // `parseArray`, which always returns an `.array` node.
        numCols = 0
    }

    if case .array(var info) = res.kind {
        for r in info.body.indices {
            // Prepend empty group at every even-indexed cell (2nd, 4th, ...)
            var i = 1
            while i < info.body[r].count {
                if case .styling(let style, var stylingBody) = info.body[r][i].kind {
                    if !stylingBody.isEmpty,
                        case .ordGroup(var ogBody, let semisimple) = stylingBody[0].kind
                    {
                        ogBody.insert(
                            ParseNode(.ordGroup(body: [], semisimple: nil), mode: ctx.mode),
                            at: 0)
                        stylingBody[0].kind = .ordGroup(body: ogBody, semisimple: semisimple)
                        info.body[r][i].kind = .styling(style: style, body: stylingBody)
                    }
                }
                i += 2
            }

            if !isAligned {
                let curMaths = info.body[r].count / 2
                if numMaths < curMaths {
                    throw ParseError(
                        "Too many math in a row: expected \(numMaths), but got \(curMaths)")
                }
            } else if numCols < info.body[r].count {
                // INTENTIONALLY UNCOVERED (Rust-port artifact KEEP):
                // `numCols` is initialized to the maximum row width above
                // and the loop never grows a row, so no row exceeds it.
                // RaTeX computes the running maximum here instead; the
                // assignment is kept to match the port line-for-line.
                numCols = info.body[r].count
            }
        }
        res.kind = .array(info)
    }

    if !isAligned {
        numCols = explicitCols
    }

    var cols: [AlignSpec] = []
    for i in 0..<numCols {
        let (align, pregap): (String, Double) =
            if i % 2 == 1 {
                ("l", 0.0)
            } else if i > 0 && isAligned {
                ("r", 1.0)
            } else {
                ("r", 0.0)
            }
        cols.append(AlignSpec(alignType: .align, align: align, pregap: pregap, postgap: 0.0))
    }

    if case .array(var info) = res.kind {
        info.cols = cols
        info.colSeparationType = isAligned ? "align" : "alignat"
        res.kind = .array(info)
    }

    return res
}

private func registerAlign(_ map: inout [String: EnvSpec]) {
    for name in ["align", "align*", "aligned", "split"] {
        map[name] = EnvSpec(numArgs: 0, numOptionalArgs: 0, handler: handleAligned)
    }
}

// ── gathered / gather / gather* ──────────────────────────────────────────

private func handleGathered(
    _ ctx: inout EnvContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let autoNumber = !ctx.envName.hasSuffix("*") && ctx.envName != "gathered"
    let config = ArrayConfig(
        addJot: true,
        cols: [AlignSpec(alignType: .align, align: "c")],
        colSeparationType: "gather",
        emptySingleRow: true,
        autoNumber: autoNumber)
    return try parseArray(ctx.parser, config, .display)
}

private func registerGathered(_ map: inout [String: EnvSpec]) {
    for name in ["gathered", "gather", "gather*"] {
        map[name] = EnvSpec(numArgs: 0, numOptionalArgs: 0, handler: handleGathered)
    }
}

// ── equation / equation* ─────────────────────────────────────────────────

private func handleEquation(
    _ ctx: inout EnvContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let autoNumber = !ctx.envName.hasSuffix("*")
    let config = ArrayConfig(
        singleRow: true,
        emptySingleRow: true,
        maxNumCols: 1,
        autoNumber: autoNumber)
    return try parseArray(ctx.parser, config, .display)
}

private func registerEquation(_ map: inout [String: EnvSpec]) {
    for name in ["equation", "equation*"] {
        map[name] = EnvSpec(numArgs: 0, numOptionalArgs: 0, handler: handleEquation)
    }
}

// ── smallmatrix ──────────────────────────────────────────────────────────

private func handleSmallmatrix(
    _ ctx: inout EnvContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let config = ArrayConfig(arraystretch: 0.5)
    var res = try parseArray(ctx.parser, config, .script)
    if case .array(var info) = res.kind {
        info.colSeparationType = "small"
        res.kind = .array(info)
    }
    return res
}

private func registerSmallmatrix(_ map: inout [String: EnvSpec]) {
    map["smallmatrix"] = EnvSpec(numArgs: 0, numOptionalArgs: 0, handler: handleSmallmatrix)
}

// ── alignat / alignat* / alignedat ──────────────────────────────────────

private func registerAlignat(_ map: inout [String: EnvSpec]) {
    for name in ["alignat", "alignat*", "alignedat"] {
        map[name] = EnvSpec(numArgs: 1, numOptionalArgs: 0, handler: handleAligned)
    }
}

// ── CD (amscd commutative diagrams) ──────────────────────────────────────

private func handleCD(
    _ ctx: inout EnvContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    // Collect all raw tokens until \end
    var raw: [Token] = []
    while true {
        let tok = ctx.parser.gullet.future()
        if tok.text == "\\end" || tok.text == "EOF" {
            break
        }
        ctx.parser.gullet.popToken()
        raw.append(tok)
    }

    // Split into rows at \\ or \cr
    let rows = cdSplitRows(raw)

    var body: [[ParseNode]] = []
    var rowGaps: [Measurement?] = []
    var hLinesBeforeRow: [[Bool]] = []
    hLinesBeforeRow.append([])

    for rowToks in rows {
        // Skip purely-whitespace rows
        if rowToks.allSatisfy({ $0.text == " " }) {
            continue
        }
        let cells = try cdParseRow(ctx.parser, rowToks)
        if !cells.isEmpty {
            body.append(cells)
            rowGaps.append(nil)
            hLinesBeforeRow.append([])
        }
    }

    if body.isEmpty {
        body.append([])
        hLinesBeforeRow.append([])
    }

    return ParseNode(
        .array(
            ParseNode.ArrayInfo(
                body: body,
                rowGaps: rowGaps,
                hLinesBeforeRow: hLinesBeforeRow,
                cols: nil,
                colSeparationType: "CD",
                hskipBeforeAndAfter: false,
                addJot: nil,
                arraystretch: 1.0,
                tags: nil,
                leqno: nil,
                isCD: true)),
        mode: ctx.mode)
}

private func registerCD(_ map: inout [String: EnvSpec]) {
    map["CD"] = EnvSpec(numArgs: 0, numOptionalArgs: 0, handler: handleCD)
}

/// Split a flat token list into rows at `\\` or `\cr` boundaries.
private func cdSplitRows(_ tokens: [Token]) -> [[Token]] {
    var rows: [[Token]] = []
    var current: [Token] = []
    for tok in tokens {
        if tok.text == "\\\\" || tok.text == "\\cr" {
            rows.append(current)
            current = []
        } else {
            current.append(tok)
        }
    }
    if !current.isEmpty {
        rows.append(current)
    }
    return rows
}

/// Collect tokens from `tokens[start...]` up to (but not including) the first
/// token whose text equals `delimiter`.  Returns (collectedTokens, tokensConsumed).
/// `tokensConsumed` includes the delimiter itself if found.
private func cdCollectUntil(
    _ tokens: [Token], _ start: Int, _ delimiter: String
) -> ([Token], Int) {
    var result: [Token] = []
    var i = start
    while i < tokens.count {
        if tokens[i].text == delimiter {
            i += 1  // consume the delimiter
            break
        }
        result.append(tokens[i])
        i += 1
    }
    return (result, i - start)
}

/// Collect tokens from `tokens[start...]` up to (but not including) the next `@`.
private func cdCollectUntilAt(_ tokens: [Token], _ start: Int) -> ([Token], Int) {
    var result: [Token] = []
    var i = start
    while i < tokens.count && tokens[i].text != "@" {
        result.append(tokens[i])
        i += 1
    }
    return (result, i - start)
}

/// Use the parser to parse a token slice as a math OrdGroup.
/// Tokens must be in forward order; this function reverses them internally for subparse().
private func cdParseTokens(
    _ parser: Parser, _ tokens: [Token]
) throws(ParseError) -> ParseNode {
    // Filter pure whitespace
    let hasContent = tokens.contains { $0.text != " " }
    if !hasContent {
        return ParseNode(.ordGroup(body: [], semisimple: nil), mode: parser.mode)
    }
    // subparse() expects tokens in reverse order (stack convention)
    var rev = tokens
    rev.reverse()
    let body = try parser.subparse(rev)
    return ParseNode(.ordGroup(body: body, semisimple: nil), mode: parser.mode)
}

/// Parse one row of a CD environment from its raw token list.
/// Returns the list of ParseNode cells for the grid row.
private func cdParseRow(
    _ parser: Parser, _ rowTokens: [Token]
) throws(ParseError) -> [ParseNode] {
    let toks = rowTokens
    let n = toks.count
    var cells: [ParseNode] = []
    var i = 0

    while i < n {
        // Skip spaces at start of each cell
        while i < n && toks[i].text == " " {
            i += 1
        }
        if i >= n {
            break
        }

        if toks[i].text == "@" {
            i += 1  // consume `@`
            if i >= n {
                throw ParseError("Unexpected end of CD row after @")
            }
            let dir = toks[i].text
            i += 1  // consume direction char

            let mode = parser.mode
            let arrow: ParseNode
            switch dir {
            case ">", "<":
                let (aboveToks, c1) = cdCollectUntil(toks, i, dir)
                i += c1
                let (belowToks, c2) = cdCollectUntil(toks, i, dir)
                i += c2
                let labelAbove = try cdParseTokens(parser, aboveToks)
                let labelBelow = try cdParseTokens(parser, belowToks)
                arrow = ParseNode(
                    .cdArrow(
                        direction: dir == ">" ? "right" : "left",
                        labelAbove: labelAbove,
                        labelBelow: labelBelow),
                    mode: mode)
            case "V", "A":
                let (leftToks, c1) = cdCollectUntil(toks, i, dir)
                i += c1
                let (rightToks, c2) = cdCollectUntil(toks, i, dir)
                i += c2
                let labelAbove = try cdParseTokens(parser, leftToks)
                let labelBelow = try cdParseTokens(parser, rightToks)
                arrow = ParseNode(
                    .cdArrow(
                        direction: dir == "V" ? "down" : "up",
                        labelAbove: labelAbove,
                        labelBelow: labelBelow),
                    mode: mode)
            case "=":
                arrow = ParseNode(
                    .cdArrow(direction: "horiz_eq", labelAbove: nil, labelBelow: nil),
                    mode: mode)
            case "|":
                arrow = ParseNode(
                    .cdArrow(direction: "vert_eq", labelAbove: nil, labelBelow: nil),
                    mode: mode)
            case ".":
                arrow = ParseNode(
                    .cdArrow(direction: "none", labelAbove: nil, labelBelow: nil),
                    mode: mode)
            default:
                throw ParseError("Unknown CD directive: @\(dir)")
            }
            cells.append(arrow)
        } else {
            // Object cell: collect until next `@`
            let (objToks, consumed) = cdCollectUntilAt(toks, i)
            i += consumed
            let obj = try cdParseTokens(parser, objToks)
            cells.append(obj)
        }
    }

    // Post-process: structure cells into the (2n-1) grid pattern.
    return cdStructureRow(cells, parser.mode)
}

/// Given the raw parsed cells of one CD row, produce the correctly-structured grid row.
///
/// Object rows already alternate: obj, h-arrow, obj, h-arrow, …, obj.
/// Arrow rows contain only CdArrow nodes (plus whitespace OrdGroups which we strip),
/// and need empty OrdGroup fillers inserted between consecutive arrows.
func cdStructureRow(_ cells: [ParseNode], _ mode: Mode) -> [ParseNode] {
    // Detect arrow row: all cells are either CdArrow or empty OrdGroup
    let isArrowRow =
        cells.allSatisfy { c in
            switch c.kind {
            case .cdArrow:
                return true
            case let .ordGroup(ordBody, _):
                return ordBody.isEmpty
            default:
                return false
            }
        }
        && cells.contains { c in
            if case .cdArrow = c.kind {
                return true
            }
            return false
        }

    if isArrowRow {
        let arrows = cells.filter { c in
            if case .cdArrow = c.kind {
                return true
            }
            return false
        }

        if arrows.isEmpty {
            // INTENTIONALLY UNCOVERED (defensive guard KEEP): `isArrowRow`
            // requires `cells.contains` a `.cdArrow`, so the filter above
            // always keeps at least one arrow.
            return []
        }

        func empty() -> ParseNode {
            ParseNode(.ordGroup(body: [], semisimple: nil), mode: mode)
        }

        var result: [ParseNode] = []
        result.reserveCapacity(arrows.count * 2 - 1)
        for (idx, arrow) in arrows.enumerated() {
            if idx > 0 {
                result.append(empty())
            }
            result.append(arrow)
        }
        return result
    } else {
        // Object row: already in correct format
        return cells
    }
}

// ── subarray ────────────────────────────────────────────────────────────

private func handleSubarray(
    _ ctx: inout EnvContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let colalign: [ParseNode]
    if case let .ordGroup(ordBody, _) = args[0].kind {
        colalign = ordBody
    } else if args[0].isSymbolNode {
        // INTENTIONALLY UNCOVERED (defensive branches KEEP, this arm and
        // the `else` throw): environment arguments are produced by
        // `Parser.parseArgumentGroup`, which always wraps the expression in
        // an `.ordGroup`, so `args[0]` matches the first pattern. Kept to
        // mirror KaTeX's handler, which also accepts a bare symbol node.
        colalign = [args[0]]
    } else {
        throw ParseError("Invalid column alignment for subarray")
    }

    var cols: [AlignSpec] = []
    for nde in colalign {
        guard let ca = nde.symbolText else {
            throw ParseError("Expected column alignment character")
        }
        switch ca {
        case "l", "c":
            cols.append(AlignSpec(alignType: .align, align: ca))
        default:
            throw ParseError("Unknown column alignment: \(ca)")
        }
    }

    if cols.count > 1 {
        throw ParseError("{subarray} can contain only one column")
    }

    let config = ArrayConfig(
        hskipBeforeAndAfter: false,
        cols: cols,
        arraystretch: 0.5)

    let res = try parseArray(ctx.parser, config, .script)

    if case let .array(info) = res.kind {
        if !info.body.isEmpty && info.body[0].count > 1 {
            throw ParseError("{subarray} can contain only one column")
        }
    }

    return res
}

private func registerSubarray(_ map: inout [String: EnvSpec]) {
    map["subarray"] = EnvSpec(numArgs: 1, numOptionalArgs: 0, handler: handleSubarray)
}

// ── prooftree (bussproofs subset) ───────────────────────────────────────
//
// Implemented: \AxiomC, \UnaryInfC, \BinaryInfC, \TrinaryInfC, \QuaternaryInfC,
//   \QuinaryInfC (and their abbreviations \AXC, \UIC, \BIC, \TIC),
//   \LeftLabel/\RightLabel (and \LL, \RL), \fCenter,
//   line styles: \solidLine, \dashedLine, \noLine (and \always* variants),
//   \rootAtTop, \rootAtBottom (and \always* variants).
//
// Not yet implemented: \InsertBetweenHyps, \ScoreTree, \Cell, \noCell.

private func handleProoftree(
    _ ctx: inout EnvContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    try parseProoftree(ctx.parser)
}

private func registerProoftree(_ map: inout [String: EnvSpec]) {
    map["prooftree"] = EnvSpec(numArgs: 0, numOptionalArgs: 0, handler: handleProoftree)
}

private func proofCommandArity(_ name: String) -> Int? {
    switch name {
    case "\\UnaryInfC", "\\UnaryInf", "\\UIC": 1
    case "\\BinaryInfC", "\\BinaryInf", "\\BIC": 2
    case "\\TrinaryInfC", "\\TrinaryInf", "\\TIC": 3
    case "\\QuaternaryInfC", "\\QuaternaryInf": 4
    case "\\QuinaryInfC", "\\QuinaryInf": 5
    default: nil
    }
}

private func parseProoftreeArg(
    _ parser: Parser, _ command: String
) throws(ParseError) -> [ParseNode] {
    guard let arg = try parser.parseArgumentGroup(optional: false, mode: nil) else {
        // INTENTIONALLY UNCOVERED (defensive guard KEEP): with
        // `optional: false`, `scanArgument` never returns nil — a missing
        // argument makes `consumeArg` throw before this guard is reached.
        throw ParseError("Expected argument for \(command)")
    }
    return ParseNode.ordArgument(arg)
}

private func parseProoftree(_ parser: Parser) throws(ParseError) -> ParseNode {
    var stack: [ProofBranch] = []
    var leftLabel: [ParseNode]?
    var rightLabel: [ParseNode]?
    var nextLineStyle = ProofLineStyle.solid
    var defaultLineStyle = ProofLineStyle.solid
    var nextRootAtTop = false
    var defaultRootAtTop = false

    while true {
        try parser.consumeSpaces()
        let token = try parser.fetch()
        let command = token.text

        if command == "\\end" {
            break
        }
        parser.consume()

        switch command {
        case "\\AxiomC", "\\Axiom", "\\AXC":
            let conclusion = try parseProoftreeArg(parser, command)
            stack.append(
                ProofBranch(
                    conclusion: conclusion,
                    premises: [],
                    leftLabel: nil,
                    rightLabel: nil,
                    lineStyle: .none,
                    rootAtTop: false))
        case "\\LeftLabel", "\\LL":
            leftLabel = try parseProoftreeArg(parser, command)
        case "\\RightLabel", "\\RL":
            rightLabel = try parseProoftreeArg(parser, command)
        case "\\singleLine", "\\solidLine":
            nextLineStyle = .solid
        case "\\dashedLine":
            nextLineStyle = .dashed
        case "\\noLine":
            nextLineStyle = .none
        case "\\alwaysSingleLine", "\\alwaysSolidLine":
            defaultLineStyle = .solid
            nextLineStyle = .solid
        case "\\alwaysDashedLine":
            defaultLineStyle = .dashed
            nextLineStyle = .dashed
        case "\\alwaysNoLine":
            defaultLineStyle = .none
            nextLineStyle = .none
        case "\\rootAtTop":
            nextRootAtTop = true
        case "\\rootAtBottom":
            nextRootAtTop = false
        case "\\alwaysRootAtTop":
            defaultRootAtTop = true
            nextRootAtTop = true
        case "\\alwaysRootAtBottom":
            defaultRootAtTop = false
            nextRootAtTop = false
        default:
            if let arity = proofCommandArity(command) {
                if stack.count < arity {
                    throw ParseError(
                        "\(command) needs \(arity) premise(s), but only \(stack.count) available")
                }
                let conclusion = try parseProoftreeArg(parser, command)
                let start = stack.count - arity
                let premises = Array(stack[start...])
                stack.removeSubrange(start...)
                stack.append(
                    ProofBranch(
                        conclusion: conclusion,
                        premises: premises,
                        leftLabel: leftLabel,
                        rightLabel: rightLabel,
                        lineStyle: nextLineStyle,
                        rootAtTop: nextRootAtTop))
                leftLabel = nil
                rightLabel = nil
                nextLineStyle = defaultLineStyle
                nextRootAtTop = defaultRootAtTop
            } else {
                throw ParseError(
                    "\(command) valid only as a supported bussproofs command within prooftree")
            }
        }
    }

    if stack.count != 1 {
        throw ParseError(
            "prooftree ended with \(stack.count) proof stack item(s), expected 1")
    }

    if leftLabel != nil || rightLabel != nil {
        throw ParseError(
            "prooftree has a \\LeftLabel or \\RightLabel without a following inference command")
    }

    return ParseNode(.proofTree(tree: stack.removeLast()), mode: parser.mode)
}
