/// Layout options passed through the layout tree.
public struct LayoutOptions: Sendable {
    public var style: MathStyle
    public var color: Color
    /// When set (e.g. in align/aligned), cap relation spacing to this many mu
    /// for consistency.
    public var alignRelationSpacing: Double?
    /// When inside `\left...\right`, the stretch height for `\middle`
    /// delimiters (second pass only).
    public var leftrightDelimHeight: Double?
    /// Extra horizontal kern between glyphs (em), e.g. for `\url` / `\href`
    /// to match browser tracking.
    public var interGlyphKernEm: Double

    /// Layout recursion depth, incremented per `layoutNode` level. Guards
    /// against stack overflow on pathologically nested input (mirrors the
    /// parser's recursion-count guard; see `StackGuard.swift`).
    var layoutDepth: Int = 0
    /// Stack floor for the layout walk's headroom probe, computed once at
    /// the `layout()` entry point on the laying-out thread. 0 disables the
    /// probe (direct internal calls, non-Darwin platforms).
    var stackFloor: UInt = 0
    /// Nesting depth of `\left…\middle…\right` stretch passes. Bounds the
    /// second (stretch) layout pass so adversarially nested `\middle`
    /// groups degrade instead of doing exponential work.
    var middlePassDepth: Int = 0

    public init(
        style: MathStyle = .display,
        color: Color = .black,
        alignRelationSpacing: Double? = nil,
        leftrightDelimHeight: Double? = nil,
        interGlyphKernEm: Double = 0
    ) {
        self.style = style
        self.color = color
        self.alignRelationSpacing = alignRelationSpacing
        self.leftrightDelimHeight = leftrightDelimHeight
        self.interGlyphKernEm = interGlyphKernEm
    }

    public var metrics: MathConstants {
        MathConstants.forSize(style.sizeIndex)
    }

    public var sizeMultiplier: Double {
        style.sizeMultiplier
    }

    public func with(style: MathStyle) -> LayoutOptions {
        var copy = self
        copy.style = style
        return copy
    }

    public func with(color: Color) -> LayoutOptions {
        var copy = self
        copy.color = color
        return copy
    }

    public func with(interGlyphKernEm: Double) -> LayoutOptions {
        var copy = self
        copy.interGlyphKernEm = interGlyphKernEm
        return copy
    }
}
