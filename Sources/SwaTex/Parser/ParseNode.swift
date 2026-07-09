/// Style string for \displaystyle, \textstyle etc.
public enum StyleStr: String, Hashable, Sendable {
    case display
    case text
    case script
    case scriptscript
}

/// Atom family: determines spacing behavior. Matches KaTeX's Atom type.
public enum AtomFamily: String, Hashable, Sendable {
    case bin
    case close
    case inner
    case open
    case punct
    case rel
}

/// A measurement with number and unit (e.g. "3pt", "1em").
public struct Measurement: Hashable, Sendable {
    public var number: Double
    public var unit: String

    public init(number: Double, unit: String) {
        self.number = number
        self.unit = unit
    }
}

/// Column alignment spec for array environments.
public struct AlignSpec: Sendable {
    public enum AlignType: String, Sendable {
        case align
        case separator
    }

    public var alignType: AlignType
    public var align: String?
    public var pregap: Double?
    public var postgap: Double?

    public init(alignType: AlignType, align: String? = nil, pregap: Double? = nil, postgap: Double? = nil) {
        self.alignType = alignType
        self.align = align
        self.pregap = pregap
        self.postgap = postgap
    }
}

/// Tag variant for array rows: either auto-numbered (bool) or explicit tag.
public enum ArrayTag: Sendable {
    case auto(Bool)
    case explicit([ParseNode])
}

public enum ProofLineStyle: String, Sendable {
    case solid
    case dashed
    case none
}

/// One branch of a bussproofs proof tree.
public struct ProofBranch: Sendable {
    public var conclusion: [ParseNode]
    public var premises: [ProofBranch]
    public var leftLabel: [ParseNode]?
    public var rightLabel: [ParseNode]?
    public var lineStyle: ProofLineStyle
    public var rootAtTop: Bool

    public init(
        conclusion: [ParseNode], premises: [ProofBranch],
        leftLabel: [ParseNode]? = nil, rightLabel: [ParseNode]? = nil,
        lineStyle: ProofLineStyle, rootAtTop: Bool = false
    ) {
        self.conclusion = conclusion
        self.premises = premises
        self.leftLabel = leftLabel
        self.rightLabel = rightLabel
        self.lineStyle = lineStyle
        self.rootAtTop = rootAtTop
    }
}

/// The main AST node type. Each ``Kind`` corresponds to a KaTeX ParseNode type.
///
/// Unlike the Rust port (which repeats `mode`/`loc` in every enum variant),
/// the common fields live on the struct and the per-variant payload is the
/// indirect ``Kind`` enum.
public struct ParseNode: Sendable {
    public var kind: Kind
    public var mode: Mode
    public var loc: SourceLocation?

    public init(_ kind: Kind, mode: Mode, loc: SourceLocation? = nil) {
        self.kind = kind
        self.mode = mode
        self.loc = loc
    }

    public indirect enum Kind: Sendable {
        // ── Symbol-based nodes (from symbol lookup in Parser.parseSymbol) ──
        case atom(family: AtomFamily, text: String)
        case mathOrd(text: String)
        case textOrd(text: String)
        case opToken(text: String)
        case accentToken(text: String)
        case spacing(text: String)

        // ── Structural nodes ──
        case ordGroup(body: [ParseNode], semisimple: Bool?)
        case supSub(base: ParseNode?, sup: ParseNode?, sub: ParseNode?)

        // ── Function-generated nodes ──
        case genfrac(
            continued: Bool, numer: ParseNode, denom: ParseNode,
            hasBarLine: Bool, leftDelim: String?, rightDelim: String?,
            barSize: Measurement?)
        case sqrt(body: ParseNode, index: ParseNode?)
        case accent(label: String, isStretchy: Bool?, isShifty: Bool?, base: ParseNode)
        case accentUnder(label: String, isStretchy: Bool?, isShifty: Bool?, base: ParseNode)
        case op(
            limits: Bool, alwaysHandleSupSub: Bool?, suppressBaseShift: Bool?,
            parentIsSupSub: Bool, symbol: Bool, name: String?, body: [ParseNode]?)
        case operatorName(
            body: [ParseNode], alwaysHandleSupSub: Bool, limits: Bool, parentIsSupSub: Bool)
        case font(font: String, body: ParseNode)
        case text(body: [ParseNode], font: String?)
        case color(color: String, body: [ParseNode])
        case colorToken(color: String)
        case size(value: Measurement, isBlank: Bool)
        case styling(style: StyleStr, body: [ParseNode])
        case sizing(size: UInt8, body: [ParseNode])
        case delimSizing(size: UInt8, mclass: String, delim: String)
        case leftRight(body: [ParseNode], left: String, right: String, rightColor: String?)
        case leftRightRight(delim: String, color: String?)
        case middle(delim: String)
        case overline(body: ParseNode)
        case underline(body: ParseNode)
        case rule(shift: Measurement?, width: Measurement, height: Measurement)
        case kern(dimension: Measurement)
        case phantom(body: [ParseNode])
        case vphantom(body: ParseNode)
        case smash(body: ParseNode, smashHeight: Bool, smashDepth: Bool)
        case mclass(mclass: String, body: [ParseNode], isCharacterBox: Bool)
        case array(ArrayInfo)
        case environment(name: String, nameGroup: ParseNode)
        case cr(newLine: Bool, size: Measurement?)
        case infix(replaceWith: String, size: Measurement?)
        case internalNode
        case verb(body: String, star: Bool)
        case href(href: String, body: [ParseNode])
        case url(url: String)
        case raw(string: String)
        case hbox(body: [ParseNode])
        case horizBrace(label: String, isOver: Bool, base: ParseNode)
        case enclose(label: String, backgroundColor: String?, borderColor: String?, body: ParseNode)
        case lap(alignment: String, body: ParseNode)
        case mathChoice(display: [ParseNode], text: [ParseNode], script: [ParseNode], scriptscript: [ParseNode])
        case raiseBox(dy: Measurement, body: ParseNode)
        case vcenter(body: ParseNode)
        case xArrow(label: String, body: ParseNode, below: ParseNode?)
        case pmb(mclass: String, body: [ParseNode])
        case tag(body: [ParseNode], tag: [ParseNode])
        case noNumber
        case html(attributes: [String: String], body: [ParseNode])
        case htmlMathML(html: [ParseNode], mathml: [ParseNode])
        case includeGraphics(
            alt: String, width: Measurement, height: Measurement,
            totalheight: Measurement, src: String)
        case cdLabel(side: String, label: ParseNode)
        case cdLabelParent(fragment: ParseNode)
        case cdArrow(direction: String, labelAbove: ParseNode?, labelBelow: ParseNode?)
        case proofTree(tree: ProofBranch)
    }

    /// Payload for `array` nodes, grouped because of its many fields.
    public struct ArrayInfo: Sendable {
        public var body: [[ParseNode]]
        public var rowGaps: [Measurement?]
        public var hLinesBeforeRow: [[Bool]]
        public var cols: [AlignSpec]?
        public var colSeparationType: String?
        public var hskipBeforeAndAfter: Bool?
        public var addJot: Bool?
        public var arraystretch: Double
        public var tags: [ArrayTag]?
        public var leqno: Bool?
        public var isCD: Bool?

        public init(
            body: [[ParseNode]], rowGaps: [Measurement?], hLinesBeforeRow: [[Bool]],
            cols: [AlignSpec]? = nil, colSeparationType: String? = nil,
            hskipBeforeAndAfter: Bool? = nil, addJot: Bool? = nil,
            arraystretch: Double = 1.0, tags: [ArrayTag]? = nil,
            leqno: Bool? = nil, isCD: Bool? = nil
        ) {
            self.body = body
            self.rowGaps = rowGaps
            self.hLinesBeforeRow = hLinesBeforeRow
            self.cols = cols
            self.colSeparationType = colSeparationType
            self.hskipBeforeAndAfter = hskipBeforeAndAfter
            self.addJot = addJot
            self.arraystretch = arraystretch
            self.tags = tags
            self.leqno = leqno
            self.isCD = isCD
        }
    }
}

// ── Helper methods ──────────────────────────────────────────────────────────

extension ParseNode {
    /// The KaTeX node type name (matches KaTeX's `type` field).
    public var typeName: String {
        switch kind {
        case .atom: "atom"
        case .mathOrd: "mathord"
        case .textOrd: "textord"
        case .opToken: "op-token"
        case .accentToken: "accent-token"
        case .spacing: "spacing"
        case .ordGroup: "ordgroup"
        case .supSub: "supsub"
        case .genfrac: "genfrac"
        case .sqrt: "sqrt"
        case .accent: "accent"
        case .accentUnder: "accentUnder"
        case .op: "op"
        case .operatorName: "operatorname"
        case .font: "font"
        case .text: "text"
        case .color: "color"
        case .colorToken: "color-token"
        case .size: "size"
        case .styling: "styling"
        case .sizing: "sizing"
        case .delimSizing: "delimsizing"
        case .leftRight: "leftright"
        case .leftRightRight: "leftright-right"
        case .middle: "middle"
        case .overline: "overline"
        case .underline: "underline"
        case .rule: "rule"
        case .kern: "kern"
        case .phantom: "phantom"
        case .vphantom: "vphantom"
        case .smash: "smash"
        case .mclass: "mclass"
        case .array: "array"
        case .environment: "environment"
        case .cr: "cr"
        case .infix: "infix"
        case .internalNode: "internal"
        case .verb: "verb"
        case .href: "href"
        case .url: "url"
        case .raw: "raw"
        case .hbox: "hbox"
        case .horizBrace: "horizBrace"
        case .enclose: "enclose"
        case .lap: "lap"
        case .mathChoice: "mathchoice"
        case .raiseBox: "raisebox"
        case .vcenter: "vcenter"
        case .xArrow: "xArrow"
        case .pmb: "pmb"
        case .tag: "tag"
        case .noNumber: "nonumber"
        case .html: "html"
        case .htmlMathML: "htmlmathml"
        case .includeGraphics: "includegraphics"
        case .cdLabel: "cdlabel"
        case .cdLabelParent: "cdlabelparent"
        case .cdArrow: "cdArrow"
        case .proofTree: "proofTree"
        }
    }

    /// Whether this node is a symbol node (atom or non-atom symbol).
    public var isSymbolNode: Bool {
        switch kind {
        case .atom, .mathOrd, .textOrd, .opToken, .accentToken, .spacing: true
        default: false
        }
    }

    /// The text of a symbol node.
    public var symbolText: String? {
        switch kind {
        case let .atom(_, text), let .mathOrd(text), let .textOrd(text),
            let .opToken(text), let .accentToken(text), let .spacing(text):
            text
        default:
            nil
        }
    }

    /// Normalize an argument: if it's an ordgroup with a single element, unwrap it.
    public static func normalizeArgument(_ arg: ParseNode) -> ParseNode {
        if case let .ordGroup(body, _) = arg.kind, body.count == 1 {
            return body[0]
        }
        return arg
    }

    /// Convert an argument to a list: if ordgroup, return body; otherwise wrap in array.
    public static func ordArgument(_ arg: ParseNode) -> [ParseNode] {
        if case let .ordGroup(body, _) = arg.kind {
            return body
        }
        return [arg]
    }
}
