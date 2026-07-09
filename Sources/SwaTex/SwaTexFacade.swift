/// High-level convenience API: LaTeX in, display list out.
///
/// The full pipeline is `parse → layout → toDisplayList`. The resulting
/// ``DisplayList`` is in **em units**; renderers multiply by the font size.
public enum SwaTexEngine {
    /// Parse and lay out a LaTeX math string.
    ///
    /// - Parameters:
    ///   - latex: LaTeX source (outer `$...$` / `$$...$$` are stripped).
    ///   - style: initial math style (`.display` for display mode, `.text`
    ///     for inline mode).
    ///   - color: initial text color.
    /// - Returns: a flat display list in em units.
    public static func displayList(
        for latex: String,
        style: MathStyle = .display,
        color: Color = .black
    ) throws(ParseError) -> DisplayList {
        let nodes = try parseLaTeX(latex)
        let options = LayoutOptions(style: style, color: color)
        let box = layout(nodes, options: options)
        return toDisplayList(box)
    }
}
