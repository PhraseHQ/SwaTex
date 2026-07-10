import Foundation
import Testing

@testable import SwaTex

/// Every emitted SVG document must be well-formed XML — strict parsers
/// (browsers loading standalone .svg, resvg, librsvg) reject the whole
/// document otherwise.
@Suite("SVGWellFormedness")
struct SVGWellFormednessTests {
    private func isWellFormedXML(_ svg: String) -> Bool {
        final class Delegate: NSObject, XMLParserDelegate {}
        let parser = XMLParser(data: Data(svg.utf8))
        let delegate = Delegate()
        parser.delegate = delegate
        return parser.parse()
    }

    /// Regression: the Emoji-Fallback font-family stack used embedded double
    /// quotes inside a double-quoted attribute, producing unparseable XML.
    @Test func emojiFallbackTextIsWellFormed() {
        let list = DisplayList(
            items: [
                .glyphPath(
                    x: 0.5, y: 1.0, scale: 1.0, font: "Emoji-Fallback",
                    charCode: 0x1F600, color: .black)
            ],
            width: 2.0, height: 1.25, depth: 0.25)
        let svg = SVGRenderer().render(list)
        #expect(isWellFormedXML(svg), "emoji <text> output must parse as XML: \(svg)")
        #expect(svg.contains("'Segoe UI Emoji'"))
    }

    /// Provider-supplied `href`/`d` strings are escaped before landing in
    /// attributes, so quotes/ampersands can't inject or break markup.
    @Test func providerStringsAreAttributeEscaped() {
        struct HostileProvider: SVGStandaloneGlyphProvider {
            let glyph: SVGStandaloneGlyph
            func standaloneGlyph(
                x: Float, y: Float, glyphEm: Float, font: String, charCode: UInt32
            ) -> SVGStandaloneGlyph? { glyph }
        }
        let list = DisplayList(
            items: [
                .glyphPath(
                    x: 0.5, y: 1.0, scale: 1.0, font: "Main-Regular",
                    charCode: UInt32(UInt8(ascii: "x")), color: .black)
            ],
            width: 2.0, height: 1.25, depth: 0.25)

        let imageProvider = HostileProvider(
            glyph: .image(href: "https://e.com/a?b=1&c=\"2\"", x: 0, y: 0, w: 1, h: 1))
        var opts = SVGOptions()
        opts.embedGlyphs = true
        opts.glyphProvider = imageProvider
        let svg = renderToSVG(list, opts)
        #expect(isWellFormedXML(svg), "image href must be escaped: \(svg)")
        #expect(svg.contains("&amp;"))

        let pathProvider = HostileProvider(glyph: .path("M0 0 L1 1\" onload=\"evil"))
        opts.glyphProvider = pathProvider
        let svg2 = renderToSVG(list, opts)
        #expect(isWellFormedXML(svg2), "path d must be escaped: \(svg2)")

        // A quote fused with a combining mark is ONE grapheme cluster; a
        // Character-wise escape loop would skip it. The escaper must work at
        // scalar granularity so this still can't break out of the attribute.
        let combiningProvider = HostileProvider(
            glyph: .path("M0 0\u{0301}\" onload=\"evil"))
        opts.glyphProvider = combiningProvider
        let svg3 = renderToSVG(list, opts)
        #expect(isWellFormedXML(svg3), "quote + combining mark must be escaped: \(svg3)")
        // The escaped payload legitimately contains the text "onload" INSIDE
        // the attribute value; what must never appear is a raw quote pair
        // terminating the attribute early and forming a real attribute.
        #expect(
            !svg3.contains("\" onload=\""),
            "raw quotes must not survive escaping: \(svg3)")
    }

    /// `emitGlyphText` interpolates `katexFace` values raw on the per-glyph
    /// hot path; this pins the invariant that every face tuple is
    /// XML-attribute-safe, so a future entry with a quoted font name fails
    /// here instead of shipping unparseable SVG.
    @Test func katexFaceValuesAreAttributeSafe() {
        let fonts = [
            "Main-Regular", "Main-Bold", "Main-Italic", "Main-BoldItalic",
            "Math-Italic", "Math-BoldItalic", "AMS-Regular",
            "Caligraphic-Regular", "Fraktur-Regular", "Fraktur-Bold",
            "SansSerif-Regular", "SansSerif-Bold", "SansSerif-Italic",
            "Script-Regular", "Typewriter-Regular", "Size1-Regular",
            "Size2-Regular", "Size3-Regular", "Size4-Regular",
            "CJK-Regular", "CJK-Fallback", "Emoji-Fallback",
            "Unknown-Font-Id",  // exercises the default case
        ]
        for font in fonts {
            let (family, weight, style) = katexFace(font)
            for value in [family, weight, style] {
                let hasEscapable = value.utf8.contains { byte in
                    byte == UInt8(ascii: "&") || byte == UInt8(ascii: "<")
                        || byte == UInt8(ascii: ">") || byte == UInt8(ascii: "\"")
                }
                #expect(
                    !hasEscapable,
                    "katexFace(\(font)) value \"\(value)\" must be XML-attribute-safe")
            }
        }
    }
}
