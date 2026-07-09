import Testing

@testable import SwaTex

/// Port of the unit tests in RaTeX `crates/ratex-svg/src/lib.rs`.
@Suite("SVGRenderer")
struct SVGRendererTests {
    @Test func emptyListProducesSvg() {
        let list = DisplayList(items: [], width: 2.0, height: 1.0, depth: 0.5)
        let svg = SVGRenderer().render(list)
        #expect(svg.hasPrefix("<svg "))
        #expect(svg.contains("viewBox=\"0 0 100 80\""))
        #expect(svg.hasSuffix("</svg>"))
    }

    @Test func lineRectPathGlyphRoundtripStructure() {
        let list = DisplayList(
            items: [
                .line(x: 0.0, y: 0.5, width: 1.0, thickness: 0.04, color: .black, dashed: false),
                .rect(x: 0.0, y: 0.0, width: 0.5, height: 0.2, color: Color(r: 1, g: 0, b: 0)),
                .path(
                    x: 0.0, y: 0.0,
                    commands: [
                        .moveTo(x: 0.0, y: 0.0),
                        .lineTo(x: 1.0, y: 0.0),
                    ],
                    fill: false,
                    color: .black),
                .glyphPath(
                    x: 0.1, y: 0.8, scale: 1.0, font: "Math-Italic",
                    charCode: UInt32(UInt8(ascii: "x")), color: .black),
            ],
            width: 2.0, height: 1.0, depth: 0.0)
        let svg = renderToSVG(
            list,
            SVGOptions(fontSize: 10.0, padding: 0.0, strokeWidth: 1.0, embedGlyphs: false))
        #expect(svg.contains("<rect"))
        #expect(svg.contains("<path"))
        #expect(svg.contains("<text"))
        #expect(svg.contains("KaTeX_Math"))
        #expect(svg.contains("fill=\"rgba(255,0,0,1)\"") || svg.contains("fill=\"rgba(255,0,0,1"))
    }

    // The Rust `embed_glyphs_use_path_when_katex_fonts_present` /
    // `embedded_emoji_image_uses_color_alpha_as_opacity` tests load KaTeX
    // `.ttf` files from disk; the Swift core has no font parser, so the
    // equivalents below exercise the pluggable provider seam instead.

    /// Fixed provider standing in for the Rust `standalone` font pipeline.
    struct StubProvider: SVGStandaloneGlyphProvider {
        var glyph: SVGStandaloneGlyph?

        func standaloneGlyph(x: Float, y: Float, glyphEm: Float, font: String, charCode: UInt32)
            -> SVGStandaloneGlyph?
        {
            glyph
        }
    }

    @Test func embedGlyphsUsePathWhenProviderResolves() {
        let list = DisplayList(
            items: [
                .glyphPath(
                    x: 0.1, y: 0.8, scale: 1.0, font: "Math-Italic",
                    charCode: UInt32(UInt8(ascii: "x")), color: .black)
            ],
            width: 1.0, height: 1.0, depth: 0.0)
        let svg = renderToSVG(
            list,
            SVGOptions(
                fontSize: 10.0, padding: 0.0, strokeWidth: 1.0, embedGlyphs: true,
                glyphProvider: StubProvider(glyph: .path("M1 8 L2 8 Z"))))
        #expect(svg.contains("<path"))
        #expect(svg.contains("fill-rule=\"nonzero\""))
        #expect(!svg.contains("<text"))
        #expect(
            svg.contains(
                "<path d=\"M1 8 L2 8 Z\" fill=\"rgba(0,0,0,1)\" fill-rule=\"nonzero\" stroke=\"none\"/>"
            ))
    }

    @Test func embeddedEmojiImageUsesColorAlphaAsOpacity() {
        let list = DisplayList(
            items: [
                .glyphPath(
                    x: 0.0, y: 1.0, scale: 1.0, font: "Emoji-Fallback",
                    charCode: 0x1F600, color: Color(r: 1, g: 0, b: 0, a: 0.5))
            ],
            width: 1.2, height: 2.0, depth: 0.0)
        let svg = renderToSVG(
            list,
            SVGOptions(
                fontSize: 10.0, padding: 0.0, strokeWidth: 1.0, embedGlyphs: true,
                glyphProvider: StubProvider(
                    glyph: .image(href: "data:image/png;base64,AAAA", x: 0, y: 0.5, w: 10, h: 10))))
        #expect(svg.contains("<image"))
        #expect(svg.contains("opacity=\"0.5\""), "\(svg)")
        #expect(svg.contains("href=\"data:image/png;base64,AAAA\""))
        #expect(svg.contains("preserveAspectRatio=\"none\""))
    }

    @Test func opaqueEmbeddedImageOmitsOpacity() {
        let list = DisplayList(
            items: [
                .glyphPath(
                    x: 0, y: 1, scale: 1, font: "Emoji-Fallback", charCode: 0x1F600, color: .black)
            ],
            width: 1.0, height: 1.0, depth: 0.0)
        let svg = renderToSVG(
            list,
            SVGOptions(
                fontSize: 10.0, padding: 0.0, embedGlyphs: true,
                glyphProvider: StubProvider(
                    glyph: .image(href: "data:image/png;base64,AAAA", x: 0, y: 0, w: 10, h: 10))))
        #expect(!svg.contains("opacity="))
    }

    @Test func embedGlyphsFallsBackToTextWhenProviderReturnsNil() {
        let list = DisplayList(
            items: [
                .glyphPath(
                    x: 0, y: 0.8, scale: 1, font: "Main-Regular",
                    charCode: UInt32(UInt8(ascii: "a")), color: .black)
            ],
            width: 1.0, height: 1.0, depth: 0.0)
        let svg = renderToSVG(
            list,
            SVGOptions(
                fontSize: 10.0, padding: 0.0, embedGlyphs: true,
                glyphProvider: StubProvider(glyph: nil)))
        #expect(svg.contains("<text"))
        #expect(svg.contains("KaTeX_Main"))
    }

    @Test func embedGlyphsWithoutProviderEmitsText() {
        // Rust: `embed_glyphs` without `font_dir` (non-embed build) keeps `<text>`.
        let list = DisplayList(
            items: [
                .glyphPath(
                    x: 0, y: 0.8, scale: 1, font: "Main-Regular",
                    charCode: UInt32(UInt8(ascii: "a")), color: .black)
            ],
            width: 1.0, height: 1.0, depth: 0.0)
        let svg = renderToSVG(list, SVGOptions(fontSize: 10.0, padding: 0.0, embedGlyphs: true))
        #expect(svg.contains("<text"))
    }
}

/// Number/color formatting parity with the Rust implementation
/// (`fmt_num`, `color_to_svg`).
@Suite("SVGFormatting")
struct SVGFormattingTests {
    @Test func formatNumberMatchesRustFmtNum() {
        // `format!("{n:.6}")` then trim trailing zeros / point.
        #expect(svgFormatNumber(0.04) == "0.04")
        #expect(svgFormatNumber(100.0) == "100")
        #expect(svgFormatNumber(0.0) == "0")
        #expect(svgFormatNumber(-0.0) == "-0")  // Rust keeps "-0" (only "-" maps to "0")
        #expect(svgFormatNumber(1.0 / 3.0) == "0.333333")
        #expect(svgFormatNumber(0.0078125) == "0.007812")  // exact tie, half-to-even
        #expect(svgFormatNumber(-1.5) == "-1.5")
        #expect(svgFormatNumber(1e-7) == "0")  // rounds to 0.000000
        #expect(svgFormatNumber(1e20) == "100000000000000000000")
    }

    @Test func colorMatchesRustColorToSvg() {
        #expect(svgColor(.black) == "rgba(0,0,0,1)")
        #expect(svgColor(Color(r: 1, g: 0, b: 0)) == "rgba(255,0,0,1)")
        #expect(svgColor(Color(r: 0, g: 0, b: 1, a: 0.5)) == "rgba(0,0,255,0.5)")
        #expect(svgColor(Color(r: 1, g: 0, b: 0, a: 0.25)) == "rgba(255,0,0,0.25)")
        // 127.5 rounds away from zero:
        #expect(svgColor(Color(r: 0, g: 0.5, b: 0)) == "rgba(0,128,0,1)")
        #expect(svgColor(Color(r: 0.2, g: 0.4, b: 0.6)) == "rgba(51,102,153,1)")
        // Out-of-range components clamp; non-finite alpha normalizes to 1.
        #expect(svgColor(Color(r: -1, g: 2, b: 0, a: .nan)) == "rgba(0,255,0,1)")
        #expect(svgColor(Color(r: 0, g: 0, b: 0, a: -1)) == "rgba(0,0,0,0)")
    }

    @Test func floatFormattingMatchesRustDisplay() {
        // Rust `{}` on f32: shortest round-trip, no exponent, no trailing ".0".
        #expect(svgFormatFloat(1.0) == "1")
        #expect(svgFormatFloat(0.5) == "0.5")
        #expect(svgFormatFloat(0.3) == "0.3")
        #expect(svgFormatFloat(0.123456) == "0.123456")
        #expect(svgFormatFloat(1e-5) == "0.00001")
        #expect(svgFormatFloat(1.5e-7) == "0.00000015")
        #expect(svgFormatFloat(0.0001) == "0.0001")
    }
}

/// Port of `standalone::outline_to_d` geometry (contour splitting, Z joins).
@Suite("SVGStandaloneOutline")
struct SVGStandaloneOutlineTests {
    @Test func emptyOutlineReturnsNil() {
        #expect(svgOutlinePathData(x: 0, y: 0, scale: 1, curves: []) == nil)
    }

    @Test func contiguousCurvesShareOneContour() {
        let d = svgOutlinePathData(
            x: 10, y: 20, scale: 2,
            curves: [
                .line(SVGOutlinePoint(x: 0, y: 0), SVGOutlinePoint(x: 1, y: 0)),
                .quad(
                    SVGOutlinePoint(x: 1, y: 0), SVGOutlinePoint(x: 2, y: 1),
                    SVGOutlinePoint(x: 1, y: 2)),
                .cubic(
                    SVGOutlinePoint(x: 1, y: 2), SVGOutlinePoint(x: 0.5, y: 2),
                    SVGOutlinePoint(x: 0, y: 1), SVGOutlinePoint(x: 0, y: 0)),
            ])
        // y is flipped (py - y * scale) and each contour is closed with Z.
        #expect(d == "M10 20 L12 20 Q14 18 12 16 C11 16 10 18 10 20 Z")
    }

    @Test func penJumpStartsNewContourWithZ() {
        let d = svgOutlinePathData(
            x: 0, y: 0, scale: 1,
            curves: [
                .line(SVGOutlinePoint(x: 0, y: 0), SVGOutlinePoint(x: 1, y: 0)),
                .line(SVGOutlinePoint(x: 5, y: 5), SVGOutlinePoint(x: 6, y: 5)),
            ])
        #expect(d == "M0 0 L1 0 Z M5 -5 L6 -5 Z")
    }

    @Test func subThresholdGapDoesNotSplitContour() {
        // The 0.01 tolerance treats float noise as a continuous pen position.
        let d = svgOutlinePathData(
            x: 0, y: 0, scale: 1,
            curves: [
                .line(SVGOutlinePoint(x: 0, y: 0), SVGOutlinePoint(x: 1, y: 0)),
                .line(SVGOutlinePoint(x: 1.005, y: 0.005), SVGOutlinePoint(x: 2, y: 0)),
            ])
        #expect(d == "M0 0 L1 0 L2 0 Z")
    }
}
