// Glyph outlines as SVG `<path>` for self-contained documents.
//
// Port of RaTeX `crates/ratex-svg/src/standalone.rs` (Cargo feature
// `standalone`). The Rust implementation parses KaTeX `.ttf` files with
// `ab_glyph` (loaded from `SvgOptions::font_dir` or the embedded
// `ratex-katex-fonts` crate) and resolves a fallback chain
// (KaTeX face → Main-Regular → CJK → emoji raster → emoji outline →
// CJK fallback). The Swift core target bundles no fonts and no TTF parser,
// so that resolution is behind ``SVGStandaloneGlyphProvider``: a host app can
// implement it with CoreText or any other font stack. Implementations should
// map display char codes to TTF glyph characters with
// ``FontId/ttfGlyphScalar(forDisplayCharCode:)`` (Rust:
// `ratex_font::katex_ttf_glyph_char`).
//
// The geometry conversion from parsed outline curves to an SVG path `d`
// string (`outline_to_d`) is pure and is ported below as
// ``svgOutlinePathData(x:y:scale:curves:)``.

/// Vector path or color-emoji raster (`sbix` PNG as `data:image/png`),
/// matching the raster renderer's glyph pipeline.
///
/// Rust: `standalone::StandaloneGlyph`.
public enum SVGStandaloneGlyph: Hashable, Sendable {
    /// SVG path data (`d` attribute) in user space, y downward.
    case path(String)
    /// Embedded raster image (typically a `data:image/png;base64,…` URL) with
    /// its placement rectangle in user space.
    case image(href: String, x: Float, y: Float, w: Float, h: Float)
}

/// Pluggable source of standalone glyph outlines/rasters.
///
/// Replaces the Rust `standalone`/`embed-fonts` features: the renderer calls
/// this once per ``DisplayItem/glyphPath(x:y:scale:font:charCode:color:)``
/// when ``SVGOptions/embedGlyphs`` is set. Returning `nil` falls back to a
/// KaTeX `<text>` element, mirroring Rust's behavior when a glyph cannot be
/// resolved.
///
/// Same geometry as the raster renderer: SVG user space, y downward. Emoji
/// should prefer bitmap **before** outline so COLR/sbix faces do not paint
/// invisible vector masks.
///
/// Rust: `standalone::standalone_glyph(px, py, glyph_em, font_name, char_code, font_cache)`.
public protocol SVGStandaloneGlyphProvider: Sendable {
    /// - Parameters:
    ///   - x: Glyph origin x in SVG user space (Rust `px`).
    ///   - y: Baseline y in SVG user space (Rust `py`).
    ///   - glyphEm: Glyph size in user units (layout scale × options font size).
    ///   - font: Internal font id string, e.g. `"Main-Regular"` (see ``FontId``).
    ///   - charCode: Display character code from the display list.
    func standaloneGlyph(x: Float, y: Float, glyphEm: Float, font: String, charCode: UInt32)
        -> SVGStandaloneGlyph?
}

/// One quadratic/cubic segment (or line) of a glyph outline in **font units**
/// scaled to user space by the caller, y upward (font convention).
///
/// Rust: `ab_glyph::OutlineCurve`.
public enum SVGOutlineCurve: Hashable, Sendable {
    case line(SVGOutlinePoint, SVGOutlinePoint)
    case quad(SVGOutlinePoint, SVGOutlinePoint, SVGOutlinePoint)
    case cubic(SVGOutlinePoint, SVGOutlinePoint, SVGOutlinePoint, SVGOutlinePoint)

    var start: SVGOutlinePoint {
        switch self {
        case let .line(p0, _), let .quad(p0, _, _), let .cubic(p0, _, _, _): p0
        }
    }

    var end: SVGOutlinePoint {
        switch self {
        case let .line(_, p1): p1
        case let .quad(_, _, p2): p2
        case let .cubic(_, _, _, p3): p3
        }
    }
}

/// A point of an outline curve, in font units with y upward;
/// ``svgOutlinePathData(x:y:scale:curves:)`` maps it to user space
/// (`px + x * scale`, `py - y * scale`).
public struct SVGOutlinePoint: Hashable, Sendable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

/// Convert glyph outline curves to an SVG path `d` string.
///
/// Port of `standalone::outline_to_d` minus the font access: the caller
/// supplies curves in **font units, y upward** together with the scale
/// (`glyphEm / unitsPerEm`, possibly reduced to fit emoji into the 1.0 em
/// layout width — see the Rust source), and this function applies the
/// `px + p.x * scale`, `py - p.y * scale` mapping and contour splitting.
///
/// Returns `nil` when the outline produces no path data.
public func svgOutlinePathData(
    x px: Float,
    y py: Float,
    scale: Float,
    curves: [SVGOutlineCurve]
) -> String? {
    func mapX(_ p: SVGOutlinePoint) -> Float { px + p.x * scale }
    func mapY(_ p: SVGOutlinePoint) -> Float { py - p.y * scale }

    var d = ""
    var lastEnd: (x: Float, y: Float)? = nil

    for curve in curves {
        let start = (x: mapX(curve.start), y: mapY(curve.start))
        let end = (x: mapX(curve.end), y: mapY(curve.end))

        // Start a new contour whenever the pen position jumps.
        let needMove: Bool
        if let last = lastEnd {
            needMove = abs(last.x - start.x) > 0.01 || abs(last.y - start.y) > 0.01
        } else {
            needMove = true
        }

        if needMove {
            if lastEnd != nil {
                d += "Z "
            }
            d += "M\(svgFormatNumber(Double(start.x))) \(svgFormatNumber(Double(start.y))) "
        }

        switch curve {
        case let .line(_, p1):
            d += "L\(svgFormatNumber(Double(mapX(p1)))) \(svgFormatNumber(Double(mapY(p1)))) "
        case let .quad(_, p1, p2):
            d += "Q\(svgFormatNumber(Double(mapX(p1)))) \(svgFormatNumber(Double(mapY(p1)))) "
            d += "\(svgFormatNumber(Double(mapX(p2)))) \(svgFormatNumber(Double(mapY(p2)))) "
        case let .cubic(_, p1, p2, p3):
            d += "C\(svgFormatNumber(Double(mapX(p1)))) \(svgFormatNumber(Double(mapY(p1)))) "
            d += "\(svgFormatNumber(Double(mapX(p2)))) \(svgFormatNumber(Double(mapY(p2)))) "
            d += "\(svgFormatNumber(Double(mapX(p3)))) \(svgFormatNumber(Double(mapY(p3)))) "
        }

        lastEnd = end
    }

    if lastEnd != nil {
        d += "Z"
    }

    let trimmed = d.trimmingWhitespace()
    return trimmed.isEmpty ? nil : trimmed
}

extension String {
    /// `str::trim` equivalent without Foundation.
    fileprivate func trimmingWhitespace() -> String {
        var sub = Substring(self)
        while let f = sub.first, f.isWhitespace { sub.removeFirst() }
        while let l = sub.last, l.isWhitespace { sub.removeLast() }
        return String(sub)
    }
}
