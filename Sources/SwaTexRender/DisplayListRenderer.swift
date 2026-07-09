import CoreGraphics
import CoreText
import Foundation
import SwaTex
import Synchronization

/// Options controlling display-list rendering.
public struct RenderOptions: Sendable {
    /// Font size in points (1 em = `fontSize` points).
    public var fontSize: CGFloat
    /// Padding around the formula in points.
    public var padding: CGFloat
    /// Background color; `nil` renders on a transparent background.
    public var backgroundColor: SwaTex.Color?

    public init(
        fontSize: CGFloat = 40, padding: CGFloat = 8,
        backgroundColor: SwaTex.Color? = nil
    ) {
        self.fontSize = fontSize
        self.padding = padding
        self.backgroundColor = backgroundColor
    }
}

/// Pixel-space metrics of a rendered display list.
public struct RenderMetrics: Sendable {
    public var width: CGFloat
    public var height: CGFloat
    /// Distance from the top edge to the baseline, in points.
    public var baseline: CGFloat
}

/// Renders a ``DisplayList`` into a `CGContext` with CoreText glyph drawing.
///
/// The display list is in em units with y increasing downward and the baseline
/// at `y = displayList.height`. This renderer mirrors the Cairo backend's item
/// semantics exactly:
/// - `line`: `y` is the vertical center of the stroke.
/// - `rect`: `y` is the top edge; width/height clamped to ≥ 1 point.
/// - `path`: command coordinates are in em, offset by the item origin.
/// - `glyphPath`: `(x, y)` is the pen position on the baseline.
public enum DisplayListRenderer {
    /// Compute the output metrics for a display list.
    public static func metrics(for list: DisplayList, options: RenderOptions) -> RenderMetrics {
        let em = options.fontSize
        let pad = options.padding
        return RenderMetrics(
            width: max(CGFloat(list.width) * em + 2 * pad, 1),
            height: max(CGFloat(list.totalHeight) * em + 2 * pad, 1),
            baseline: max(CGFloat(list.height) * em + pad, 0))
    }

    /// Draw the display list into `ctx`.
    ///
    /// `ctx` is expected in standard CG orientation (origin bottom-left,
    /// y up) covering `metrics(for:options:)` size; this function converts
    /// to the display list's top-left/y-down space internally.
    public static func draw(
        _ list: DisplayList, in ctx: CGContext, options: RenderOptions
    ) {
        let m = metrics(for: list, options: options)
        let em = options.fontSize
        let pad = options.padding

        ctx.saveGState()
        defer { ctx.restoreGState() }

        if let bg = options.backgroundColor {
            ctx.setFillColor(cgColor(bg))
            // Fill the ENTIRE canvas, not just the metrics rect: bitmap
            // dimensions are ceil'd to whole pixels, so filling
            // m.width × m.height points would leave a sub-pixel transparent
            // sliver at the top/right edges (found by FastPNGTests
            // opaqueBackground: top-left buffer pixel had alpha 32).
            ctx.fill(ctx.boundingBoxOfClipPath)
        }

        // Flip to top-left origin, y down (Cairo-style), so display-list
        // coordinates can be used directly.
        ctx.translateBy(x: 0, y: m.height)
        ctx.scaleBy(x: 1, y: -1)

        // Glyph-run batching: consecutive glyphs sharing (font, size, color)
        // are drawn with ONE CTFontDrawGlyphs call under a single flip
        // transform — mathematically identical to per-glyph
        // translate+scale+draw (CTM · T(p) · S(1,−1) at origin ≡
        // CTM · S(1,−1) at (pₓ, −p_y)), and CoreText's fast path.
        // See P-011 in the performance log.
        var run = GlyphRun()

        // Consecutive glyph items overwhelmingly share one (font, size):
        // memoize the name → FontId string switch and the provider's
        // mutex-guarded sized-font lookup across loop iterations (P-017).
        var lastFontName: String? = nil
        var lastFontId = FontId.mainRegular
        var lastSize: CGFloat = .nan
        var lastCTFont: CTFont? = nil

        for item in list.items {
            if case let .glyphPath(x, y, scale, font, charCode, color) = item {
                let fontId: FontId
                if font == lastFontName {
                    fontId = lastFontId
                } else {
                    fontId = FontId(rawValue: font) ?? .mainRegular
                    lastFontName = font
                    lastFontId = fontId
                    lastSize = .nan
                }
                let size = CGFloat(scale) * em
                let point = CGPoint(x: CGFloat(x) * em + pad, y: CGFloat(y) * em + pad)
                let scalar = fontId.ttfGlyphScalar(forDisplayCharCode: charCode)
                let ctFont: CTFont
                if size == lastSize, let cached = lastCTFont {
                    ctFont = cached
                } else {
                    ctFont = KaTeXFontProvider.shared.font(for: fontId, size: size)
                    lastSize = size
                    lastCTFont = ctFont
                }
                let glyph = KaTeXFontProvider.shared.cachedGlyph(
                    for: fontId, scalar: scalar, in: ctFont)

                if glyph != 0 {
                    if !run.accepts(font: ctFont, color: color) {
                        run.flush(into: ctx)
                        run.begin(font: ctFont, color: color)
                    }
                    run.append(glyph: glyph, at: point)
                } else {
                    // System-font fallback (CJK/emoji) — slow path, per glyph.
                    run.flush(into: ctx)
                    drawFallbackGlyph(ctx, at: point, scalar: scalar, color: color, size: size)
                }
                continue
            }

            run.flush(into: ctx)
            switch item {
            case .glyphPath:
                break  // handled above

            case let .line(x, y, width, thickness, color, dashed):
                drawLine(
                    ctx, x: CGFloat(x) * em + pad, y: CGFloat(y) * em + pad,
                    width: CGFloat(width) * em, thickness: CGFloat(thickness) * em,
                    color: color, dashed: dashed)

            case let .rect(x, y, width, height, color):
                ctx.setFillColor(cgColor(color))
                ctx.fill(
                    CGRect(
                        x: CGFloat(x) * em + pad, y: CGFloat(y) * em + pad,
                        width: max(CGFloat(width) * em, 1),
                        height: max(CGFloat(height) * em, 1)))

            case let .path(x, y, commands, fill, color):
                drawPath(
                    ctx, x: CGFloat(x) * em + pad, y: CGFloat(y) * em + pad,
                    commands: commands, fill: fill, color: color, em: em)
            }
        }

        run.flush(into: ctx)
    }

    // MARK: - Glyph runs

    /// Accumulates consecutive glyphs sharing one (CTFont, color) into a
    /// single `CTFontDrawGlyphs` call.
    private struct GlyphRun {
        private var font: CTFont?
        private var color = SwaTex.Color.black
        private var glyphs: [CGGlyph] = []
        private var positions: [CGPoint] = []

        func accepts(font: CTFont, color: SwaTex.Color) -> Bool {
            self.font === font && self.color == color
        }

        mutating func begin(font: CTFont, color: SwaTex.Color) {
            self.font = font
            self.color = color
        }

        mutating func append(glyph: CGGlyph, at penDown: CGPoint) {
            glyphs.append(glyph)
            // Positions are in the run's y-up space (see flush).
            positions.append(CGPoint(x: penDown.x, y: -penDown.y))
        }

        mutating func flush(into ctx: CGContext) {
            defer {
                font = nil
                glyphs.removeAll(keepingCapacity: true)
                positions.removeAll(keepingCapacity: true)
            }
            guard let font, !glyphs.isEmpty else { return }

            ctx.saveGState()
            ctx.setFillColor(cgColor(color))
            ctx.setAlpha(CGFloat(color.a))
            // One flip for the whole run: the context is y-down, CoreText
            // draws y-up. CTM·S(1,−1) applied to (pₓ, −p_y) equals the
            // per-glyph CTM·T(p)·S(1,−1) at the origin, so rasterization is
            // identical to the unbatched form.
            ctx.scaleBy(x: 1, y: -1)
            ctx.textMatrix = .identity
            CTFontDrawGlyphs(font, glyphs, positions, glyphs.count, ctx)
            ctx.restoreGState()
        }
    }

    /// Slow path for glyphs missing from the bundled KaTeX fonts
    /// (CJK, emoji): resolve a system font per scalar and draw individually.
    private static func drawFallbackGlyph(
        _ ctx: CGContext, at point: CGPoint, scalar: Unicode.Scalar,
        color: SwaTex.Color, size: CGFloat
    ) {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? KaTeXFontProvider.shared.font(for: .mainRegular, size: size)
        let str = String(scalar) as CFString
        let font = CTFontCreateForString(base, str, CFRange(location: 0, length: 1))

        var utf16 = Array(String(scalar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        let found = CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, utf16.count)
        guard found, let glyph = glyphs.first, glyph != 0 else { return }

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setFillColor(cgColor(color))
        ctx.setAlpha(CGFloat(color.a))
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        var g = glyph
        var position = CGPoint(x: point.x, y: -point.y)
        CTFontDrawGlyphs(font, &g, &position, 1, ctx)
    }

    private static func drawLine(
        _ ctx: CGContext, x: CGFloat, y: CGFloat, width: CGFloat,
        thickness: CGFloat, color: SwaTex.Color, dashed: Bool
    ) {
        let t = max(thickness, 0.5)
        ctx.setFillColor(cgColor(color))
        if dashed {
            ctx.saveGState()
            ctx.setStrokeColor(cgColor(color))
            ctx.setLineWidth(t)
            ctx.setLineDash(phase: 0, lengths: [t * 3, t * 3])
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + width, y: y))
            ctx.strokePath()
            ctx.restoreGState()
        } else {
            ctx.fill(CGRect(x: x, y: y - t / 2, width: width, height: t))
        }
    }

    private static func drawPath(
        _ ctx: CGContext, x: CGFloat, y: CGFloat, commands: [PathCommand],
        fill: Bool, color: SwaTex.Color, em: CGFloat
    ) {
        ctx.setFillColor(cgColor(color))
        ctx.setStrokeColor(cgColor(color))
        if fill {
            // Match the Cairo backend: fill each MoveTo-separated subpath
            // independently.
            var start = 0
            for i in 1..<max(commands.count, 1) {
                if case .moveTo = commands[i] {
                    drawPathSegment(
                        ctx, x: x, y: y, commands: commands[start..<i], fill: true, em: em)
                    start = i
                }
            }
            drawPathSegment(ctx, x: x, y: y, commands: commands[start...], fill: true, em: em)
        } else {
            drawPathSegment(ctx, x: x, y: y, commands: commands[...], fill: false, em: em)
        }
    }

    private static func drawPathSegment(
        _ ctx: CGContext, x: CGFloat, y: CGFloat,
        commands: ArraySlice<PathCommand>, fill: Bool, em: CGFloat
    ) {
        guard !commands.isEmpty else { return }
        ctx.beginPath()
        for command in commands {
            switch command {
            case let .moveTo(cx, cy):
                ctx.move(to: CGPoint(x: x + CGFloat(cx) * em, y: y + CGFloat(cy) * em))
            case let .lineTo(cx, cy):
                ctx.addLine(to: CGPoint(x: x + CGFloat(cx) * em, y: y + CGFloat(cy) * em))
            case let .cubicTo(x1, y1, x2, y2, cx, cy):
                ctx.addCurve(
                    to: CGPoint(x: x + CGFloat(cx) * em, y: y + CGFloat(cy) * em),
                    control1: CGPoint(x: x + CGFloat(x1) * em, y: y + CGFloat(y1) * em),
                    control2: CGPoint(x: x + CGFloat(x2) * em, y: y + CGFloat(y2) * em))
            case let .quadTo(x1, y1, cx, cy):
                ctx.addQuadCurve(
                    to: CGPoint(x: x + CGFloat(cx) * em, y: y + CGFloat(cy) * em),
                    control: CGPoint(x: x + CGFloat(x1) * em, y: y + CGFloat(y1) * em))
            case .close:
                ctx.closePath()
            }
        }
        if fill {
            ctx.fillPath()
        } else {
            // Match the Cairo backend's fixed 1.5pt stroke for unfilled paths.
            ctx.setLineWidth(1.5)
            ctx.strokePath()
        }
    }

    // CGColor(srgbRed:…) resolves the sRGB color space and allocates on
    // every call, and profiles showed it at ~12 % of renderer time (P-017) —
    // display lists set a color per item. Formulas overwhelmingly use one
    // color, so a tiny shared cache (CGColor is immutable and thread-safe)
    // turns this into a dictionary hit. Bounded: pathological color churn
    // (e.g. per-glyph rainbow) clears rather than grows.
    private static let colorCache = Mutex<[SwaTex.Color: CGColor]>([:])

    static func cgColor(_ color: SwaTex.Color) -> CGColor {
        colorCache.withLock { cache in
            if let cached = cache[color] {
                return cached
            }
            let made = CGColor(
                srgbRed: CGFloat(color.r), green: CGFloat(color.g),
                blue: CGFloat(color.b), alpha: CGFloat(color.a))
            if cache.count >= 256 {
                cache.removeAll(keepingCapacity: true)
            }
            cache[color] = made
            return made
        }
    }
}
