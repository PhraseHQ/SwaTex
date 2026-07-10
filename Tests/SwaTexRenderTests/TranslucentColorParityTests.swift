import CoreGraphics
import Foundation
import SwaTex
import Testing

@testable import SwaTexRender

/// Glyph translucency must composite once (alpha a), matching rules/paths and
/// the SVG backend. Regression: glyphs used to get the color's alpha via the
/// fill color AND `ctx.setAlpha`, compositing at a².
@Suite("TranslucentColorParity")
struct TranslucentColorParityTests {
    private func maxAlpha(_ latex: String, alpha: Float) throws -> Int {
        let list = try SwaTexEngine.displayList(
            for: latex, style: .display, color: SwaTex.Color(r: 0, g: 0, b: 0, a: alpha))
        let image = try #require(
            ImageRenderer.image(for: list, options: RenderOptions(fontSize: 40)))
        let data = try #require(image.dataProvider?.data as Data?)
        var maxA = 0
        for i in stride(from: 3, to: data.count, by: 4) {
            maxA = max(maxA, Int(data[i]))
        }
        return maxA
    }

    @Test func glyphAlphaIsAppliedOnce() throws {
        let full = try maxAlpha("x", alpha: 1.0)
        let half = try maxAlpha("x", alpha: 0.5)
        #expect(full > 200, "opaque glyph should reach near-full coverage")
        let ratio = Double(half) / Double(full)
        // One alpha application → ~0.5; the a² bug produced ~0.25.
        #expect(abs(ratio - 0.5) < 0.08, "glyph alpha ratio was \(ratio), expected ≈0.5")
    }

    @Test func glyphAndRuleAlphaMatch() throws {
        // \frac draws a rule (fraction bar) and glyphs in the same color; at
        // 50 % alpha their peak coverage must agree (the bar is solid ink, a
        // glyph's interior is too at 40 pt).
        let maxA = try maxAlpha(#"\frac{x}{y}"#, alpha: 0.5)
        // Peak alpha anywhere in the render (bar or glyph) ≈ 128; under the
        // old bug glyph peaks sat at ~64 while the bar was ~128.
        #expect(maxA > 115 && maxA < 141, "peak alpha \(maxA), expected ≈128")
    }

    @Test func bmpEmojiAlphaIsAppliedOnce() throws {
        // Color-bitmap glyphs (Apple Color Emoji) ignore the fill color, so
        // the context alpha is their single alpha source. Regression:
        // removing setAlpha for path glyphs also removed it here, rendering
        // translucent BMP emoji (U+231A ⌚) fully opaque.
        let full = try maxAlpha("\\text{\u{231A}}", alpha: 1.0)
        let half = try maxAlpha("\\text{\u{231A}}", alpha: 0.5)
        #expect(full > 200, "opaque emoji should reach near-full coverage")
        let ratio = Double(half) / Double(full)
        #expect(abs(ratio - 0.5) < 0.08, "emoji alpha ratio was \(ratio), expected ≈0.5")
    }

    @Test func nonBmpEmojiResolvesColorFontAndAlpha() throws {
        // Non-BMP emoji (U+1F600 😀) need the full UTF-16 range in
        // CTFontCreateForString: covering only the high surrogate cascaded
        // to monochrome LastResort instead of the color emoji font.
        let full = try maxAlpha("\\text{\u{1F600}}", alpha: 1.0)
        let half = try maxAlpha("\\text{\u{1F600}}", alpha: 0.5)
        #expect(full > 200, "opaque emoji should reach near-full coverage")
        let ratio = Double(half) / Double(full)
        #expect(abs(ratio - 0.5) < 0.08, "emoji alpha ratio was \(ratio), expected ≈0.5")
    }
}
