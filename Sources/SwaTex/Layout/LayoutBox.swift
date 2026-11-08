/// A TeX box: the fundamental unit of layout.
///
/// Every mathematical element is represented as a box with three dimensions:
/// - `width`: horizontal extent
/// - `height`: ascent above baseline
/// - `depth`: descent below baseline
///
/// All values are in **em** units relative to the current font size.
public struct LayoutBox: Sendable {
    public var width: Double
    public var height: Double
    public var depth: Double
    public var content: BoxContent
    public var color: Color

    public init(
        width: Double, height: Double, depth: Double,
        content: BoxContent, color: Color = .black
    ) {
        self.width = width
        self.height = height
        self.depth = depth
        self.content = content
        self.color = color
    }

    public static var empty: LayoutBox {
        LayoutBox(width: 0, height: 0, depth: 0, content: .empty)
    }

    /// Zero-size marker for a subtree a recursion guard dropped
    /// (see ``BoxContent/degraded``).
    static var degradedBox: LayoutBox {
        LayoutBox(width: 0, height: 0, depth: 0, content: .degraded)
    }

    public static func kern(_ width: Double) -> LayoutBox {
        LayoutBox(width: width, height: 0, depth: 0, content: .kern)
    }

    public static func rule(
        width: Double, height: Double, depth: Double, thickness: Double, raise: Double,
        color: Color = .black
    ) -> LayoutBox {
        LayoutBox(
            width: width, height: height, depth: depth,
            content: .rule(thickness: thickness, raise: raise),
            color: color)
    }

    public var totalHeight: Double {
        height + depth
    }

    public func with(color: Color) -> LayoutBox {
        var copy = self
        copy.color = color
        return copy
    }

    /// Adjust height/depth for a delimiter to match a target size.
    public func withAdjustedDelim(height: Double, depth: Double) -> LayoutBox {
        var copy = self
        copy.height = height
        copy.depth = depth
        return copy
    }
}

/// What a ``LayoutBox`` contains.
public indirect enum BoxContent: Sendable {
    /// Horizontal list of child boxes laid out left-to-right.
    case hbox([LayoutBox])

    /// Vertical list of child boxes laid out top-to-bottom.
    case vbox([VBoxChild])

    /// A single glyph character.
    case glyph(fontId: FontId, charCode: UInt32)

    /// Filled rectangle from `\rule[<raise>]{width}{height}`.
    /// `thickness` is the ink height; `raise` is the distance (in em) from the
    /// baseline to the bottom edge of the rectangle, positive toward the top of the line.
    case rule(thickness: Double, raise: Double)

    /// Empty space (kern).
    case kern

    /// A fraction: numerator over denominator with optional bar.
    case fraction(
        numer: LayoutBox, denom: LayoutBox,
        numerShift: Double, denomShift: Double, barThickness: Double,
        numerScale: Double, denomScale: Double)

    /// Superscript/subscript layout.
    ///
    /// - `centerScripts`: place scripts centered on the base width
    ///   (e.g. `\overbrace` / `\underbrace`).
    /// - `italicCorrection`: italic correction of the base character (em).
    ///   Superscript x is offset by this amount beyond base.width, matching
    ///   KaTeX's margin-right on italic math symbols.
    /// - `subHKern`: horizontal kern (em) applied to the subscript: KaTeX uses
    ///   `margin-left: -base.italic` on `SymbolNode` bases so subscripts are
    ///   not pushed out by the base's italic correction.
    case supSub(
        base: LayoutBox, sup: LayoutBox?, sub: LayoutBox?,
        supShift: Double, subShift: Double, supScale: Double, subScale: Double,
        centerScripts: Bool, italicCorrection: Double, subHKern: Double)

    /// A radical (square root).
    ///
    /// - `indexOffset`: horizontal offset (in em) of the surd/body from the
    ///   left edge when index is present.
    /// - `indexScale`: `scriptscript` size relative to the surrounding math
    ///   style (for drawing the index).
    case radical(
        body: LayoutBox, index: LayoutBox?, indexOffset: Double,
        indexScale: Double, ruleThickness: Double, innerHeight: Double)

    /// An operator with limits above/below (e.g. `\sum_{i=0}^{n}`).
    case opLimits(
        base: LayoutBox, sup: LayoutBox?, sub: LayoutBox?,
        baseShift: Double, supKern: Double, subKern: Double, slant: Double,
        supScale: Double, subScale: Double)

    /// An accent above or below its base.
    ///
    /// - `underGapEm`: KaTeX `accentunder.js`: extra em gap between base
    ///   bottom and under-accent (e.g. 0.12 for `\utilde`).
    case accent(
        base: LayoutBox, accent: LayoutBox, clearance: Double, skew: Double,
        isBelow: Bool, underGapEm: Double)

    /// A stretchy delimiter (`\left`, `\right`) wrapping inner content.
    case leftRight(left: LayoutBox, right: LayoutBox, inner: LayoutBox)

    /// A matrix/array: rows × columns of cells.
    case array(ArrayLayout)

    /// An SVG-style path (arrows, braces, etc.).
    case svgPath(commands: [PathCommand], fill: Bool)

    /// A framed/colored box (fbox, colorbox, fcolorbox).
    /// body is the inner content; padding and border add to the outer dimensions.
    case framed(
        body: LayoutBox, padding: Double, borderThickness: Double,
        hasBorder: Bool, bgColor: Color?, borderColor: Color)

    /// A raised/lowered box (raisebox).
    /// shift > 0 moves content up, shift < 0 moves content down.
    case raiseBox(body: LayoutBox, shift: Double)

    /// A scaled box (for \scriptstyle, \scriptscriptstyle in inline context).
    /// The child is rendered at childScale relative to the parent.
    case scaled(body: LayoutBox, childScale: Double)

    /// Actuarial angle `\angl{body}`: path (horizontal roof + vertical bar)
    /// and body share the same baseline.
    case angl(pathCommands: [PathCommand], body: LayoutBox)

    /// `\overline{body}`: body with a horizontal rule drawn above it.
    /// The rule sits `2 * ruleThickness` above the body's top (clearance),
    /// and is `ruleThickness` thick.
    case overline(body: LayoutBox, ruleThickness: Double)

    /// `\underline{body}`: body with a horizontal rule drawn below it.
    /// The rule sits `2 * ruleThickness` below the body's bottom (clearance),
    /// and is `ruleThickness` thick.
    case underline(body: LayoutBox, ruleThickness: Double, offset: Double)

    /// Bussproofs-style proof tree with absolutely placed child boxes and
    /// inference rules.
    case proofTree(children: [PlacedBox], rules: [ProofRule])

    /// Empty placeholder.
    case empty

    /// A subtree dropped by a recursion guard on stack exhaustion. Behaves
    /// like `empty` everywhere except emission, which converts it into
    /// ``DisplayList/truncated`` — degradation travels *in the tree*, so the
    /// signal costs nothing on paths that never degrade (layout runs on
    /// threads with unknown stack; an iterative parse can admit accent
    /// chains deeper than any small stack fits, see `layoutNode`).
    case degraded
}

/// A vertical rule from an array's column spec: `|` draws solid, `:` dashed.
public struct ArrayRule: Sendable {
    /// x the rule is centered on (em from the grid's left edge).
    public var x: Double
    /// True for `:`; `|` renders solid.
    public var isDashed: Bool

    public init(x: Double, isDashed: Bool) {
        self.x = x
        self.isDashed = isDashed
    }
}

/// Resolved horizontal track of an array: where every column sits, where every
/// vertical rule is drawn, and how wide the grid comes out.
///
/// KaTeX's array builder emits one flat run per column —
/// `[rule…][pregap][column][postgap]` — in which a column's own `pregap` and
/// `postgap` fall back to `\arraycolsep`, the gaps at the grid's two outer
/// edges exist only when `hskipBeforeAndAfter` is set, and consecutive rules in
/// one run sit a `\doublerulesep` apart (`environments/array.ts`,
/// `htmlBuilder`). `resolveArrayTrack` walks that run once; these positions are
/// then the single source of truth for cell placement, rule placement and grid
/// width, so nothing downstream re-derives a position from gap widths.
public struct ArrayTrack: Sendable {
    /// Left edge of each column's cell box (em); one entry per column.
    public var columnXs: [Double]
    /// Every rule the column spec asks for, in spec order. A rule takes no
    /// width of its own, so one column boundary can carry several.
    public var rules: [ArrayRule]
    /// Width of the cell grid, outer gaps included; excludes the tag column.
    public var width: Double

    public init(columnXs: [Double], rules: [ArrayRule], width: Double) {
        self.columnXs = columnXs
        self.rules = rules
        self.width = width
    }
}

/// Layout data for a matrix/array, grouped because of its many fields.
public struct ArrayLayout: Sendable {
    public var cells: [[LayoutBox]]
    public var colWidths: [Double]
    /// Per-column alignment: "l", "c", or "r".
    public var colAligns: [Character]
    public var rowHeights: [Double]
    public var rowDepths: [Double]
    /// Resolved x of every column and of every vertical rule.
    public var track: ArrayTrack
    public var offset: Double
    /// For each row boundary (0 = before row 0, ..., numRows = after last
    /// row), the list of hlines: false = solid, true = dashed.
    public var hlinesBeforeRow: [[Bool]]
    /// Thickness of array rules in em.
    public var ruleThickness: Double
    /// Gap between consecutive \hline or \hdashline rules (= \doublerulesep, in em).
    public var doubleRuleSep: Double
    /// Horizontal gap between grid and tag column (em).
    public var tagGapEm: Double
    /// Width reserved for tags; tags are right-aligned in this column (em).
    public var tagColWidth: Double
    /// Per-row tag layout; length matches number of rows.
    public var rowTags: [LayoutBox?]
    /// When true, tags sit left of the grid (leqno-style).
    public var tagsLeft: Bool

    public init(
        cells: [[LayoutBox]], colWidths: [Double], colAligns: [Character],
        rowHeights: [Double], rowDepths: [Double], track: ArrayTrack, offset: Double,
        hlinesBeforeRow: [[Bool]] = [], ruleThickness: Double = 0.04,
        doubleRuleSep: Double = 0.2,
        tagGapEm: Double = 0, tagColWidth: Double = 0, rowTags: [LayoutBox?] = [],
        tagsLeft: Bool = false
    ) {
        self.cells = cells
        self.colWidths = colWidths
        self.colAligns = colAligns
        self.rowHeights = rowHeights
        self.rowDepths = rowDepths
        self.track = track
        self.offset = offset
        self.hlinesBeforeRow = hlinesBeforeRow
        self.ruleThickness = ruleThickness
        self.doubleRuleSep = doubleRuleSep
        self.tagGapEm = tagGapEm
        self.tagColWidth = tagColWidth
        self.rowTags = rowTags
        self.tagsLeft = tagsLeft
    }
}

/// A box placed at an absolute position (proof trees).
public struct PlacedBox: Sendable {
    public var box: LayoutBox
    public var x: Double
    public var baselineY: Double

    public init(box: LayoutBox, x: Double, baselineY: Double) {
        self.box = box
        self.x = x
        self.baselineY = baselineY
    }
}

/// An inference rule line in a proof tree.
public struct ProofRule: Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var thickness: Double
    public var dashed: Bool

    public init(x: Double, y: Double, width: Double, thickness: Double, dashed: Bool) {
        self.x = x
        self.y = y
        self.width = width
        self.thickness = thickness
        self.dashed = dashed
    }
}

/// A child element in a vertical box.
public struct VBoxChild: Sendable {
    public enum Kind: Sendable {
        case box(LayoutBox)
        case kern(Double)
    }

    public var kind: Kind
    public var shift: Double

    public init(_ kind: Kind, shift: Double = 0) {
        self.kind = kind
        self.shift = shift
    }
}
