import SwaTex
import SwiftUI

/// The typographic ascent (top-of-view → math baseline, in points) of a
/// ``MathView``, published on every render for custom `Layout`s:
///
/// ```swift
/// struct FlowLayout: Layout {
///     func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
///                        subviews: Subviews, cache: inout Cache) {
///         for subview in subviews {
///             let ascent = subview[MathViewAscentKey.self]
///             // ascent > 0 for MathView; 0 for other views
///         }
///     }
/// }
/// ```
public struct MathViewAscentKey: LayoutValueKey {
    public static let defaultValue: CGFloat = 0
}

/// A SwiftUI view that renders a LaTeX math formula natively — no WebView
/// (from the team behind [Phrase](https://phrase.so)).
///
/// ```swift
/// MathView(#"\frac{-b \pm \sqrt{b^2-4ac}}{2a}"#)
///     .font(size: 24)
/// ```
///
/// The math baseline is reported through `.firstTextBaseline` /
/// `.lastTextBaseline`, so inline formulas align with surrounding text:
///
/// ```swift
/// HStack(alignment: .firstTextBaseline) {
///     Text("Euler:")
///     MathView(#"e^{i\pi}+1=0"#).font(size: 17).inlineStyle()
/// }
/// ```
///
/// Parsing and layout run once per `latex`/configuration change; drawing is a
/// lightweight Canvas pass over the flat display list.
public struct MathView: View {
    private let latex: String
    private var fontSize: CGFloat = 20
    private var style: MathStyle = .display
    private var color: SwaTex.Color = .black
    private var dynamicColor: SwiftUI.Color?

    /// `Color.resolve(in:)` needs the full environment; only consulted when
    /// a dynamic color is set.
    @Environment(\.self) private var environment

    public init(_ latex: String) {
        self.latex = latex
    }

    /// Set the font size in points (1 em = `size` points).
    public func font(size: CGFloat) -> MathView {
        var copy = self
        copy.fontSize = size
        return copy
    }

    /// Use inline (text) style instead of display style.
    public func inlineStyle(_ inline: Bool = true) -> MathView {
        var copy = self
        copy.style = inline ? .text : .display
        return copy
    }

    /// Set the formula color as a static RGBA value.
    public func mathColor(_ color: SwaTex.Color) -> MathView {
        var copy = self
        copy.color = color
        copy.dynamicColor = nil
        return copy
    }

    /// Set the formula color as a SwiftUI `Color`. Dynamic colors
    /// (`.primary`, asset-catalog colors, …) resolve against the current
    /// environment and adapt to dark mode automatically.
    ///
    /// Disfavored so that member names both color types share
    /// (`.mathColor(.black)`) keep resolving to the `SwaTex.Color`
    /// overload exactly as in 0.1.0 — without this, such calls become
    /// ambiguous and existing code stops compiling. SwiftUI-only members
    /// (`.primary`, `Color(...)`) still select this overload.
    @_disfavoredOverload
    public func mathColor(_ color: SwiftUI.Color) -> MathView {
        var copy = self
        copy.dynamicColor = color
        return copy
    }

    private var effectiveColor: SwaTex.Color {
        guard let dynamicColor else { return color }
        let resolved = dynamicColor.resolve(in: environment)
        return SwaTex.Color(
            r: resolved.red, g: resolved.green, b: resolved.blue, a: resolved.opacity)
    }

    /// Parse + layout are memoized through ``FormulaCache/shared``: SwiftUI
    /// evaluates `body` on every parent update, and without the cache each
    /// evaluation would re-run the full engine (~70 µs). A cache hit is a
    /// dictionary lookup.
    private func rendered(color: SwaTex.Color) -> Result<DisplayList, ParseError> {
        Result { () throws(ParseError) -> DisplayList in
            try SwaTexEngine.displayList(
                for: latex, style: style, color: color, cache: .shared)
        }
    }

    public var body: some View {
        switch rendered(color: effectiveColor) {
        case .success(let list):
            let options = RenderOptions(fontSize: fontSize, padding: 0)
            let metrics = DisplayListRenderer.metrics(for: list, options: options)
            Canvas { context, _ in
                context.withCGContext { cg in
                    // GraphicsContext's CGContext is top-left origin (flipped);
                    // DisplayListRenderer expects bottom-left. Flip back.
                    cg.translateBy(x: 0, y: metrics.height)
                    cg.scaleBy(x: 1, y: -1)
                    DisplayListRenderer.draw(list, in: cg, options: options)
                }
            }
            .frame(width: metrics.width, height: metrics.height)
            // Report the math baseline so HStack(alignment:
            // .firstTextBaseline) and Text baseline alignment work.
            .alignmentGuide(.firstTextBaseline) { _ in metrics.baseline }
            .alignmentGuide(.lastTextBaseline) { _ in metrics.baseline }
            // Published for custom Layouts (see MathViewAscentKey).
            .layoutValue(key: MathViewAscentKey.self, value: metrics.baseline)
            .accessibilityLabel(Text(latex))
        case .failure(let error):
            Text(error.description)
                .font(.caption.monospaced())
                .foregroundStyle(.red)
                .accessibilityLabel(Text("LaTeX error: \(error.message)"))
        }
    }
}
