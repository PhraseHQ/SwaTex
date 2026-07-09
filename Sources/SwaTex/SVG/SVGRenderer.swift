// Serialize a ``DisplayList`` to SVG.
//
// Coordinates match the layout engine's display lists: **em** units with
// **y downward** and the baseline at `y = height` in layout space. They are
// scaled by ``SVGOptions/fontSize`` plus ``SVGOptions/padding``, same
// convention as the raster renderer.
//
// **Glyphs (default):** each ``DisplayItem/glyphPath(x:y:scale:font:charCode:color:)``
// becomes a `<text>` element using KaTeX CSS `font-family` names (`KaTeX_Main`,
// `KaTeX_Math`, …). Load KaTeX stylesheets in the host page for correct shapes.
//
// **Self-contained SVG:** set ``SVGOptions/embedGlyphs`` and supply a
// ``SVGStandaloneGlyphProvider`` to output glyphs as `<path>` or `<image>`
// instead of `<text>`. This replaces the Rust crate's `standalone`/`embed-fonts`
// Cargo features and `font_dir` option: the core Swift target bundles no font
// resources and no TTF parser, so outline extraction is pluggable (see
// SVGStandalone.swift). Color emoji prefer embedded PNG strikes and fall back
// to outline paths only when no raster strike is available.
//
// Port of RaTeX `crates/ratex-svg/src/lib.rs`.

import Foundation

/// Options controlling SVG size and stroke appearance.
public struct SVGOptions: Sendable {
    /// User units per em (matches the raster renderer's `fontSize` at DPR 1).
    public var fontSize: Double
    /// Padding on all sides, in the same user units as a pixel at DPR 1 when `fontSize` is 40.
    public var padding: Double
    /// Stroke width for unfilled ``DisplayItem/path(x:y:commands:fill:color:)``, in user units.
    public var strokeWidth: Double
    /// When ``glyphProvider`` is set and this is `true`, glyphs are emitted as
    /// outlines/images instead of KaTeX `<text>` elements.
    public var embedGlyphs: Bool
    /// Source of standalone glyph outlines/rasters. Replaces the Rust crate's
    /// `font_dir` option and `embed-fonts` feature: when `nil` (the default),
    /// output references fonts by name only.
    public var glyphProvider: (any SVGStandaloneGlyphProvider)?

    public init(
        fontSize: Double = 40.0,
        padding: Double = 10.0,
        strokeWidth: Double = 1.5,
        embedGlyphs: Bool = false,
        glyphProvider: (any SVGStandaloneGlyphProvider)? = nil
    ) {
        self.fontSize = fontSize
        self.padding = padding
        self.strokeWidth = strokeWidth
        self.embedGlyphs = embedGlyphs
        self.glyphProvider = glyphProvider
    }

    var emPx: Double {
        fontSize
    }
}

/// Renders display lists to standalone SVG document strings.
public struct SVGRenderer: Sendable {
    public var options: SVGOptions

    public init(options: SVGOptions = SVGOptions()) {
        self.options = options
    }

    /// Render a display list to a standalone SVG document string.
    public func render(_ list: DisplayList) -> String {
        renderToSVG(list, options)
    }
}

/// Render a display list to a standalone SVG document string.
///
/// Free-function form matching Rust's `ratex_svg::render_to_svg`.
public func renderToSVG(_ list: DisplayList, _ opts: SVGOptions) -> String {
    // Rust pre-renders standalone glyphs up front while holding the font-cache
    // lock (avoiding self-referential borrows of the lock guard); in Swift the
    // provider is simply invoked inline per glyph, which emits identical output.
    let em = opts.emPx
    let pad = opts.padding
    let totalH = list.height + list.depth
    let vbW = list.width * em + 2.0 * pad
    let vbH = totalH * em + 2.0 * pad

    var body = ""
    for item in list.items {
        switch item {
        case let .glyphPath(x, y, scale, font, charCode, color):
            let g = GlyphEmit(
                x: x, y: y, scale: scale, font: font, charCode: charCode, color: color)
            emitGlyphStandalone(&body, g, opts)
        case let .line(x, y, width, thickness, color, dashed):
            emitLine(
                &body, x: x, y: y, width: width, thickness: thickness, color: color, dashed: dashed,
                opts: opts)
        case let .rect(x, y, width, height, color):
            emitRect(&body, x: x, y: y, width: width, height: height, color: color, opts: opts)
        case let .path(x, y, commands, fill, color):
            emitPathItem(
                &body, x: x, y: y, commands: commands, fill: fill, color: color, opts: opts)
        }
    }

    return wrapSVG(vbW: vbW, vbH: vbH, body: body)
}

private func wrapSVG(vbW: Double, vbH: Double, body: String) -> String {
    let w = svgFormatNumber(vbW)
    let h = svgFormatNumber(vbH)
    return
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(w) \(h)\" width=\"\(w)pt\" height=\"\(h)pt\">\(body)</svg>"
}

private func tx(_ xEm: Double, _ opts: SVGOptions) -> Double {
    xEm * opts.emPx + opts.padding
}

private func ty(_ yEm: Double, _ opts: SVGOptions) -> Double {
    yEm * opts.emPx + opts.padding
}

func svgColor(_ c: Color) -> String {
    // Rust: `(component.clamp(0.0, 1.0) * 255.0).round() as u8`; the `as u8`
    // cast saturates non-finite values to 0.
    func byte(_ v: Float) -> UInt8 {
        let scaled = (min(max(v, 0.0), 1.0) * 255.0).rounded()
        guard scaled.isFinite else { return 0 }
        return UInt8(scaled)
    }
    let a = svgNormalizedAlpha(c.a)
    return "rgba(\(byte(c.r)),\(byte(c.g)),\(byte(c.b)),\(svgFormatFloat(a)))"
}

func svgNormalizedAlpha(_ alpha: Float) -> Float {
    if alpha.isFinite {
        min(max(alpha, 0.0), 1.0)
    } else {
        1.0
    }
}

/// Rust `fmt_num`: `format!("{n:.6}")`, then trim trailing zeros and the
/// trailing decimal point.
///
/// C's `%.6f` and Rust's `{:.6}` both correctly round the exact binary value
/// to six decimals with ties-to-even (a tie such as `1/128 = 0.0078125` is
/// resolved identically by both), so the two agree byte-for-byte; verified by
/// fuzzing against the Rust implementation.
func svgFormatNumber(_ n: Double) -> String {
    var s = String(format: "%.6f", n)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    if s.isEmpty || s == "-" { return "0" }
    return s
}

/// Rust `Display` formatting for `f32` (`format!("{a}")`): shortest
/// round-trip digits, plain positional notation (never scientific), and no
/// trailing `.0` on integral values.
///
/// Swift's `Float` description is also shortest round-trip but prints `1.0`
/// for integral values and switches to scientific notation for small
/// magnitudes, so both cases are rewritten here.
func svgFormatFloat(_ f: Float) -> String {
    var s = "\(f)"
    if s.contains("e") || s.contains("E") { s = svgExpandExponent(s) }
    if s.hasSuffix(".0") { s.removeLast(2) }
    return s
}

/// Rewrite `d.dddde±xx` scientific notation to plain positional notation.
private func svgExpandExponent(_ s: String) -> String {
    guard let eIdx = s.firstIndex(where: { $0 == "e" || $0 == "E" }),
        let exp = Int(s[s.index(after: eIdx)...])
    else { return s }
    var digits = String(s[..<eIdx])
    var sign = ""
    if digits.hasPrefix("-") {
        sign = "-"
        digits.removeFirst()
    }
    var pointPos: Int
    if let dot = digits.firstIndex(of: ".") {
        pointPos = digits.distance(from: digits.startIndex, to: dot)
        digits.remove(at: dot)
    } else {
        pointPos = digits.count
    }
    pointPos += exp
    if pointPos <= 0 {
        return sign + "0." + String(repeating: "0", count: -pointPos) + digits
    } else if pointPos >= digits.count {
        return sign + digits + String(repeating: "0", count: pointPos - digits.count)
    } else {
        let idx = digits.index(digits.startIndex, offsetBy: pointPos)
        return sign + digits[..<idx] + "." + digits[idx...]
    }
}

private func xmlEscapeText(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for ch in s {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        default: out.append(ch)
        }
    }
    return out
}

/// A glyph pending emission (position/scale in layout em units).
struct GlyphEmit {
    var x: Double
    var y: Double
    var scale: Double
    var font: String
    var charCode: UInt32
    var color: Color
}

/// Map internal font id string (e.g. `Main-Regular`) to KaTeX CSS `font-family` and face attributes.
func katexFace(_ font: String) -> (family: String, weight: String, style: String) {
    switch font {
    case "Main-Regular": ("KaTeX_Main", "normal", "normal")
    case "Main-Bold": ("KaTeX_Main", "bold", "normal")
    case "Main-Italic": ("KaTeX_Main", "normal", "italic")
    case "Main-BoldItalic": ("KaTeX_Main", "bold", "italic")
    case "Math-Italic": ("KaTeX_Math", "normal", "italic")
    case "Math-BoldItalic": ("KaTeX_Math", "bold", "italic")
    case "AMS-Regular": ("KaTeX_AMS", "normal", "normal")
    case "Caligraphic-Regular": ("KaTeX_Caligraphic", "normal", "normal")
    case "Fraktur-Regular": ("KaTeX_Fraktur", "normal", "normal")
    case "Fraktur-Bold": ("KaTeX_Fraktur", "bold", "normal")
    case "SansSerif-Regular": ("KaTeX_SansSerif", "normal", "normal")
    case "SansSerif-Bold": ("KaTeX_SansSerif", "bold", "normal")
    case "SansSerif-Italic": ("KaTeX_SansSerif", "normal", "italic")
    case "Script-Regular": ("KaTeX_Script", "normal", "normal")
    case "Typewriter-Regular": ("KaTeX_Typewriter", "normal", "normal")
    case "Size1-Regular": ("KaTeX_Size1", "normal", "normal")
    case "Size2-Regular": ("KaTeX_Size2", "normal", "normal")
    case "Size3-Regular": ("KaTeX_Size3", "normal", "normal")
    case "Size4-Regular": ("KaTeX_Size4", "normal", "normal")
    case "CJK-Regular": ("sans-serif", "normal", "normal")
    case "CJK-Fallback": ("sans-serif", "normal", "normal")
    // Stack so SVG `<text>` fallback works across macOS / Windows / Linux.
    case "Emoji-Fallback":
        (
            "Apple Color Emoji, \"Segoe UI Emoji\", \"Noto Color Emoji\", sans-serif", "normal",
            "normal"
        )
    default: ("KaTeX_Main", "normal", "normal")
    }
}

private func emitGlyphStandalone(_ out: inout String, _ g: GlyphEmit, _ opts: SVGOptions) {
    if opts.embedGlyphs, let provider = opts.glyphProvider {
        // Same geometry as the Rust prerender pass: pixel position and glyph
        // em size are narrowed to Float before reaching the provider.
        let em = opts.emPx
        let pad = opts.padding
        let px = Float(g.x * em + pad)
        let py = Float(g.y * em + pad)
        let glyphEm = Float(g.scale * em)
        if let glyph = provider.standaloneGlyph(
            x: px, y: py, glyphEm: glyphEm, font: g.font, charCode: g.charCode)
        {
            switch glyph {
            case let .path(d):
                let fill = svgColor(g.color)
                out += "<path d=\"\(d)\" fill=\"\(fill)\" fill-rule=\"nonzero\" stroke=\"none\"/>"
                return
            case let .image(href, x, y, w, h):
                let xS = svgFormatNumber(Double(x))
                let yS = svgFormatNumber(Double(y))
                let wS = svgFormatNumber(Double(w))
                let hS = svgFormatNumber(Double(h))
                let opacity = svgNormalizedAlpha(g.color.a)
                if opacity < 1.0 {
                    let opacityS = svgFormatNumber(Double(opacity))
                    out +=
                        "<image href=\"\(href)\" x=\"\(xS)\" y=\"\(yS)\" width=\"\(wS)\" height=\"\(hS)\" opacity=\"\(opacityS)\" preserveAspectRatio=\"none\"/>"
                } else {
                    out +=
                        "<image href=\"\(href)\" x=\"\(xS)\" y=\"\(yS)\" width=\"\(wS)\" height=\"\(hS)\" preserveAspectRatio=\"none\"/>"
                }
                return
            }
        }
    }
    emitGlyphText(&out, g, opts)
}

private func emitGlyphText(_ out: inout String, _ g: GlyphEmit, _ opts: SVGOptions) {
    let ch = Unicode.Scalar(g.charCode).map(Character.init) ?? "\u{fffd}"
    let text = xmlEscapeText(String(ch))
    let (family, weight, style) = katexFace(g.font)
    let fs = g.scale * opts.emPx
    let fill = svgColor(g.color)
    let xS = svgFormatNumber(tx(g.x, opts))
    let yS = svgFormatNumber(ty(g.y, opts))
    let fsS = svgFormatNumber(fs)
    out +=
        "<text x=\"\(xS)\" y=\"\(yS)\" font-family=\"\(family)\" font-size=\"\(fsS)\" font-weight=\"\(weight)\" font-style=\"\(style)\" fill=\"\(fill)\" dominant-baseline=\"alphabetic\">\(text)</text>"
}

private func emitLine(
    _ out: inout String,
    x: Double,
    y: Double,
    width: Double,
    thickness: Double,
    color: Color,
    dashed: Bool,
    opts: SVGOptions
) {
    let em = opts.emPx
    let x0 = tx(x, opts)
    let yc = ty(y, opts)
    let t = max(thickness * em, 1e-6)
    let w = width * em
    let stroke = svgColor(color)
    if dashed {
        let x0s = svgFormatNumber(x0)
        let ycs = svgFormatNumber(yc)
        let x1s = svgFormatNumber(x0 + w)
        let ts = svgFormatNumber(t)
        let dash = svgFormatNumber(t * 3.0)
        out +=
            "<line x1=\"\(x0s)\" y1=\"\(ycs)\" x2=\"\(x1s)\" y2=\"\(ycs)\" stroke=\"\(stroke)\" stroke-width=\"\(ts)\" stroke-dasharray=\"\(dash) \(dash)\"/>"
    } else {
        let y0 = yc - t / 2.0
        let x0s = svgFormatNumber(x0)
        let y0s = svgFormatNumber(y0)
        let ws = svgFormatNumber(w)
        let hs = svgFormatNumber(t)
        out +=
            "<rect x=\"\(x0s)\" y=\"\(y0s)\" width=\"\(ws)\" height=\"\(hs)\" fill=\"\(stroke)\"/>"
    }
}

private func emitRect(
    _ out: inout String,
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    color: Color,
    opts: SVGOptions
) {
    let em = opts.emPx
    let x0 = tx(x, opts)
    let y0 = ty(y, opts)
    let w = width * em
    let h = height * em
    let fill = svgColor(color)
    let x0s = svgFormatNumber(x0)
    let y0s = svgFormatNumber(y0)
    let ws = svgFormatNumber(w)
    let hs = svgFormatNumber(h)
    out += "<rect x=\"\(x0s)\" y=\"\(y0s)\" width=\"\(ws)\" height=\"\(hs)\" fill=\"\(fill)\"/>"
}

private func pathCommandsToD(
    originX: Double, originY: Double, em: Double, commands: some Sequence<PathCommand>
) -> String {
    var d = ""
    for cmd in commands {
        switch cmd {
        case let .moveTo(x, y):
            d += "M"
            d += svgFormatNumber(originX + x * em)
            d += " "
            d += svgFormatNumber(originY + y * em)
        case let .lineTo(x, y):
            d += "L"
            d += svgFormatNumber(originX + x * em)
            d += " "
            d += svgFormatNumber(originY + y * em)
        case let .cubicTo(x1, y1, x2, y2, x, y):
            d += "C"
            d += svgFormatNumber(originX + x1 * em)
            d += " "
            d += svgFormatNumber(originY + y1 * em)
            d += " "
            d += svgFormatNumber(originX + x2 * em)
            d += " "
            d += svgFormatNumber(originY + y2 * em)
            d += " "
            d += svgFormatNumber(originX + x * em)
            d += " "
            d += svgFormatNumber(originY + y * em)
        case let .quadTo(x1, y1, x, y):
            d += "Q"
            d += svgFormatNumber(originX + x1 * em)
            d += " "
            d += svgFormatNumber(originY + y1 * em)
            d += " "
            d += svgFormatNumber(originX + x * em)
            d += " "
            d += svgFormatNumber(originY + y * em)
        case .close:
            d += "Z"
        }
        d += " "
    }
    while d.hasSuffix(" ") { d.removeLast() }
    return d
}

private func emitPathItem(
    _ out: inout String,
    x: Double,
    y: Double,
    commands: [PathCommand],
    fill: Bool,
    color: Color,
    opts: SVGOptions
) {
    let em = opts.emPx
    let ox = tx(x, opts)
    let oy = ty(y, opts)
    let paint = svgColor(color)

    if fill {
        // Emit each subpath (split at MoveTo) as its own element so
        // `fill-rule="nonzero"` cannot cancel overlapping contours.
        var start = 0
        for i in 1..<max(commands.count, 1) {
            if case .moveTo = commands[i] {
                let seg = commands[start..<i]
                start = i
                if seg.isEmpty {
                    continue
                }
                let d = pathCommandsToD(originX: ox, originY: oy, em: em, commands: seg)
                if d.isEmpty {
                    continue
                }
                out += "<path d=\"\(d)\" fill=\"\(paint)\" fill-rule=\"nonzero\" stroke=\"none\"/>"
            }
        }
        let seg = commands[start...]
        if !seg.isEmpty {
            let d = pathCommandsToD(originX: ox, originY: oy, em: em, commands: seg)
            if !d.isEmpty {
                out += "<path d=\"\(d)\" fill=\"\(paint)\" fill-rule=\"nonzero\" stroke=\"none\"/>"
            }
        }
    } else {
        let d = pathCommandsToD(originX: ox, originY: oy, em: em, commands: commands)
        if d.isEmpty {
            return
        }
        let sw = svgFormatNumber(opts.strokeWidth)
        out +=
            "<path d=\"\(d)\" fill=\"none\" stroke=\"\(paint)\" stroke-width=\"\(sw)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
    }
}
