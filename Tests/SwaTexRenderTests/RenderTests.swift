import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import SwaTex
@testable import SwaTexRender

@Suite("KaTeXFontProvider")
struct FontProviderTests {
    @Test func loadsBundledMainRegular() {
        let font = KaTeXFontProvider.shared.font(for: .mainRegular, size: 12)
        let name = CTFontCopyPostScriptName(font) as String
        #expect(name.contains("KaTeX_Main"), "loaded \(name)")
    }

    @Test func loadsAllBundledKaTeXFonts() {
        for fontId in FontId.allCases
        where ![.cjkRegular, .cjkFallback, .emojiFallback].contains(fontId) {
            let font = KaTeXFontProvider.shared.font(for: fontId, size: 10)
            let name = CTFontCopyPostScriptName(font) as String
            #expect(name.hasPrefix("KaTeX"), "\(fontId): loaded \(name)")
        }
    }

    /// The host bundle wins, and the module bundle is the fallback rather than the only
    /// route. An app cannot ship this package's resource bundle where `Bundle.module`
    /// looks for it - that path is the `.app`'s root, which `codesign` refuses - so a host
    /// copies the faces into its own `Contents/Resources/Fonts` instead.
    @Test func hostBundleIsPreferredOverTheModuleBundle() {
        // Under `swift test` the host IS the test runner, which carries no Fonts
        // directory. That is the miss the fallback exists for, and every other test in
        // this suite passes through it.
        #expect(KaTeXFontProvider.hostFontURL(named: "KaTeX_Main-Regular") == nil)

        // Point the same lookup at a bundle that DOES carry them and it resolves without
        // touching `Bundle.module`, which is what an app's Contents/Resources gives it.
        let hosted = KaTeXFontProvider.hostFontURL(named: "KaTeX_Main-Regular", in: .module)
        #expect(hosted?.lastPathComponent == "KaTeX_Main-Regular.ttf")
    }

    @Test func glyphLookupForBasicLatin() {
        let font = KaTeXFontProvider.shared.font(for: .mainRegular, size: 12)
        var chars: [UniChar] = [UniChar(UInt8(ascii: "x"))]
        var glyphs: [CGGlyph] = [0]
        #expect(CTFontGetGlyphsForCharacters(font, &chars, &glyphs, 1))
        #expect(glyphs[0] != 0)
    }

    @Test func mathAlphanumericGlyphsMapToASCIISlots() {
        // MATHEMATICAL BOLD CAPITAL A (U+1D400) lives at 'A' in KaTeX_Main-Bold.
        let scalar = FontId.mainBold.ttfGlyphScalar(forDisplayCharCode: 0x1D400)
        #expect(scalar == "A")
        let font = KaTeXFontProvider.shared.font(for: .mainBold, size: 12)
        var chars = Array(String(scalar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        #expect(CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count))
        #expect(glyphs[0] != 0)
    }
}

@Suite("DisplayListRenderer")
struct DisplayListRendererTests {
    /// A hand-built display list: "x" glyph + fraction bar + colored rect.
    private var sampleList: DisplayList {
        DisplayList(
            items: [
                .glyphPath(
                    x: 0, y: 1.0, scale: 1, font: "Main-Regular", charCode: 0x78,
                    color: .black),
                .line(x: 0, y: 0.5, width: 1.0, thickness: 0.04, color: .black, dashed: false),
                .rect(x: 0.2, y: 0.2, width: 0.3, height: 0.3, color: Color(r: 1, g: 0, b: 0)),
                .path(
                    x: 0, y: 0,
                    commands: [.moveTo(x: 0, y: 0), .lineTo(x: 1, y: 1), .close],
                    fill: true, color: .black),
            ],
            width: 1.2, height: 1.0, depth: 0.4)
    }

    @Test func metricsComputation() {
        let m = DisplayListRenderer.metrics(
            for: sampleList, options: RenderOptions(fontSize: 40, padding: 8))
        #expect(abs(m.width - (1.2 * 40 + 16)) < 0.001)
        #expect(abs(m.height - (1.4 * 40 + 16)) < 0.001)
        #expect(abs(m.baseline - (1.0 * 40 + 8)) < 0.001)
    }

    @Test func rendersToImage() throws {
        let image = try #require(
            ImageRenderer.image(for: sampleList, options: RenderOptions(fontSize: 40)))
        #expect(image.width > 0)
        #expect(image.height > 0)
    }

    @Test func rendersInkOnTransparentBackground() throws {
        let image = try #require(
            ImageRenderer.image(
                for: sampleList, options: RenderOptions(fontSize: 40), displayScale: 1))
        // Sample pixels: the glyph/lines must have produced non-transparent ink.
        let data = try #require(image.dataProvider?.data as Data?)
        var hasInk = false
        // RGBA8 premultiplied-last: alpha at every 4th byte.
        for i in stride(from: 3, to: data.count, by: 4) where data[i] > 0 {
            hasInk = true
            break
        }
        #expect(hasInk, "rendered image should contain visible ink")
    }

    @Test func pngEncoding() throws {
        let image = try #require(
            ImageRenderer.image(for: sampleList, options: RenderOptions(fontSize: 40)))
        let png = try #require(ImageRenderer.pngData(image))
        // PNG magic bytes
        #expect(png.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }
}
