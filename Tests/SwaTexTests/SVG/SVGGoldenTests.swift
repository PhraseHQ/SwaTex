import SwaTex
import Testing

/// Byte-exact golden tests against output captured from the Rust
/// `ratex-svg` crate (`render_to_svg`, default non-embed build).
///
/// The Rust repository's `tests/golden_svg.rs` suite rasterizes standalone
/// SVG with resvg and ink-scores it against KaTeX PNG fixtures; that pipeline
/// (parser → layout → fonts → rasterizer) is not portable here, so these
/// inline display-list fixtures pin the exact SVG serialization instead.
@Suite("SVGGolden")
struct SVGGoldenTests {
    @Test func emptyListDefaultOptions() {
        let list = DisplayList(items: [], width: 2.0, height: 1.0, depth: 0.5)
        let svg = SVGRenderer().render(list)
        #expect(
            svg
                == #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 80" width="100pt" height="80pt"></svg>"#
        )
    }

    @Test func oneOfEachItemKind() {
        let list = DisplayList(
            items: [
                .line(x: 0.0, y: 0.5, width: 1.0, thickness: 0.04, color: .black, dashed: false),
                .rect(x: 0.0, y: 0.0, width: 0.5, height: 0.2, color: Color(r: 1, g: 0, b: 0)),
                .path(
                    x: 0.0, y: 0.0,
                    commands: [.moveTo(x: 0.0, y: 0.0), .lineTo(x: 1.0, y: 0.0)],
                    fill: false, color: .black),
                .glyphPath(
                    x: 0.1, y: 0.8, scale: 1.0, font: "Math-Italic",
                    charCode: UInt32(UInt8(ascii: "x")), color: .black),
            ],
            width: 2.0, height: 1.0, depth: 0.0)
        let svg = renderToSVG(list, SVGOptions(fontSize: 10.0, padding: 0.0, strokeWidth: 1.0))
        #expect(
            svg
                == #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 10" width="20pt" height="10pt"><rect x="0" y="4.8" width="10" height="0.4" fill="rgba(0,0,0,1)"/><rect x="0" y="0" width="5" height="2" fill="rgba(255,0,0,1)"/><path d="M0 0 L10 0" fill="none" stroke="rgba(0,0,0,1)" stroke-width="1" stroke-linecap="round" stroke-linejoin="round"/><text x="1" y="8" font-family="KaTeX_Math" font-size="10" font-weight="normal" font-style="italic" fill="rgba(0,0,0,1)" dominant-baseline="alphabetic">x</text></svg>"#
        )
    }

    @Test func dashedLineAlphaFillSubpathsAndEscaping() {
        let list = DisplayList(
            items: [
                .line(
                    x: 0.0, y: 0.25, width: 0.5, thickness: 0.05,
                    color: Color(r: 0, g: 0, b: 1, a: 0.5), dashed: true),
                .rect(
                    x: 0.1, y: 0.3, width: 0.25, height: 0.125,
                    color: Color(r: 1, g: 0, b: 0, a: 0.25)),
                .path(
                    x: 0.0, y: 0.1,
                    commands: [
                        .moveTo(x: 0.0, y: 0.0),
                        .lineTo(x: 0.5, y: 0.0),
                        .quadTo(x1: 0.75, y1: 0.25, x: 0.5, y: 0.5),
                        .close,
                        .moveTo(x: 1.0, y: 1.0),
                        .cubicTo(x1: 1.0, y1: 0.5, x2: 1.5, y2: 0.5, x: 1.5, y: 1.0),
                        .close,
                    ],
                    fill: true, color: Color(r: 0, g: 0.5, b: 0)),
                .glyphPath(
                    x: 0.0, y: 1.0, scale: 0.7, font: "Main-Regular",
                    charCode: UInt32(UInt8(ascii: "<")), color: .black),
                .glyphPath(
                    x: 0.5, y: 1.0, scale: 1.0, font: "Emoji-Fallback",
                    charCode: 0x1F600, color: .black),
            ],
            width: 2.5, height: 1.25, depth: 0.25)
        let svg = renderToSVG(list, SVGOptions(fontSize: 8.0, padding: 2.0, strokeWidth: 1.5))
        #expect(
            svg
                == #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 16" width="24pt" height="16pt"><line x1="2" y1="4" x2="6" y2="4" stroke="rgba(0,0,255,0.5)" stroke-width="0.4" stroke-dasharray="1.2 1.2"/><rect x="2.8" y="4.4" width="2" height="1" fill="rgba(255,0,0,0.25)"/><path d="M2 2.8 L6 2.8 Q8 4.8 6 6.8 Z" fill="rgba(0,128,0,1)" fill-rule="nonzero" stroke="none"/><path d="M10 10.8 C10 6.8 14 6.8 14 10.8 Z" fill="rgba(0,128,0,1)" fill-rule="nonzero" stroke="none"/><text x="2" y="10" font-family="KaTeX_Main" font-size="5.6" font-weight="normal" font-style="normal" fill="rgba(0,0,0,1)" dominant-baseline="alphabetic">&lt;</text><text x="6" y="10" font-family="Apple Color Emoji, 'Segoe UI Emoji', 'Noto Color Emoji', sans-serif" font-size="8" font-weight="normal" font-style="normal" fill="rgba(0,0,0,1)" dominant-baseline="alphabetic">😀</text></svg>"#
        )
    }

    @Test func strokedMultiContourPathAndUnknownFontFallback() {
        let list = DisplayList(
            items: [
                .path(
                    x: 0.2, y: 0.2,
                    commands: [
                        .moveTo(x: 0.0, y: 0.0),
                        .cubicTo(x1: 0.1, y1: 0.2, x2: 0.3, y2: 0.2, x: 0.4, y: 0.0),
                        .moveTo(x: 0.5, y: 0.5),
                        .lineTo(x: 0.6, y: 0.5),
                    ],
                    fill: false, color: Color(r: 0.2, g: 0.4, b: 0.6, a: 1.0)),
                .glyphPath(
                    x: 1.0 / 3.0, y: 0.9, scale: 1.0, font: "Bogus-Font",
                    charCode: 0x26, color: .black),
            ],
            width: 1.0, height: 1.0, depth: 0.0)
        let svg = renderToSVG(list, SVGOptions())
        #expect(
            svg
                == #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 60 60" width="60pt" height="60pt"><path d="M18 18 C22 26 30 26 34 18 M38 38 L42 38" fill="none" stroke="rgba(51,102,153,1)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><text x="23.333333" y="46" font-family="KaTeX_Main" font-size="40" font-weight="normal" font-style="normal" fill="rgba(0,0,0,1)" dominant-baseline="alphabetic">&amp;</text></svg>"#
        )
    }
}
