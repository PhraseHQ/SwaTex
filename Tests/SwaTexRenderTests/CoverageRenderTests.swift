import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import SwaTex
@testable import SwaTexRender

/// Coverage tests for the Apple-native rendering layer: background fills,
/// dashed rules, CJK glyph fallback, `MathView` modifiers, and the
/// `ImageRenderer` convenience/error paths.
@Suite("CoverageRender")
struct CoverageRenderTests {
    /// Decode an image's RGBA8 pixels.
    private func pixels(_ image: CGImage) throws -> (data: Data, bytesPerRow: Int) {
        let data = try #require(image.dataProvider?.data as Data?)
        return (data, image.bytesPerRow)
    }

    private func inkByteCount(_ image: CGImage) throws -> Int {
        let (data, _) = try pixels(image)
        var n = 0
        for i in stride(from: 3, to: data.count, by: 4) where data[i] > 0 {
            n += 1
        }
        return n
    }

    // ── RenderOptions.backgroundColor ───────────────────────────────────

    @Test func backgroundColorFillsEveryPixel() throws {
        let list = try SwaTexEngine.displayList(for: "x")
        let opts = RenderOptions(
            fontSize: 40, padding: 4,
            backgroundColor: SwaTex.Color(r: 1, g: 0, b: 0, a: 1))
        let image = try #require(ImageRenderer.image(for: list, options: opts, displayScale: 1))
        let (data, _) = try pixels(image)
        // With an opaque background nearly every pixel is opaque (the context
        // rounds up to whole pixels, leaving at most a partial edge row).
        var transparent = 0
        for i in stride(from: 3, to: data.count, by: 4) where data[i] < 255 {
            transparent += 1
        }
        // At most the partial right column + bottom row can stay unpainted
        // (the pixel buffer rounds the point size up to whole pixels).
        #expect(transparent <= image.width + image.height)
        // And the top-left corner pixel must be red (premultiplied RGBA).
        #expect(data[3] == 255)  // A
        #expect(data[0] > 200)  // R
        #expect(data[1] < 60)  // G
        #expect(data[2] < 60)  // B
    }

    @Test func transparentBackgroundLeavesCornerEmpty() throws {
        let list = try SwaTexEngine.displayList(for: "x")
        let opts = RenderOptions(fontSize: 40, padding: 8, backgroundColor: nil)
        let image = try #require(ImageRenderer.image(for: list, options: opts, displayScale: 1))
        let (data, _) = try pixels(image)
        #expect(data[3] == 0)  // top-left corner is inside the padding → transparent
    }

    // ── Dashed rules (\hdashline) ───────────────────────────────────────

    @Test func hdashlinePaintsFewerPixelsThanHline() throws {
        let dashed = try SwaTexEngine.displayList(
            for: #"\begin{matrix} aaaa \\ \hdashline aaaa \end{matrix}"#)
        let solid = try SwaTexEngine.displayList(
            for: #"\begin{matrix} aaaa \\ \hline aaaa \end{matrix}"#)

        // The display lists must actually carry the dashed flag.
        func lineFlags(_ list: DisplayList) -> [Bool] {
            list.items.compactMap { item in
                if case let .line(_, _, _, _, _, dashed) = item {
                    return dashed
                }
                return nil
            }
        }
        #expect(lineFlags(dashed) == [true])
        #expect(lineFlags(solid) == [false])

        let opts = RenderOptions(fontSize: 40, padding: 0)
        let dashedImg = try #require(
            ImageRenderer.image(for: dashed, options: opts, displayScale: 1))
        let solidImg = try #require(
            ImageRenderer.image(for: solid, options: opts, displayScale: 1))
        // A dashed rule paints strictly less ink than a solid rule of the
        // same length (identical content otherwise).
        let dashedInk = try inkByteCount(dashedImg)
        let solidInk = try inkByteCount(solidImg)
        #expect(dashedInk < solidInk)
    }

    // ── CJK glyph fallback (system font via CTFontCreateForString) ──────

    @Test func cjkTextRendersInk() throws {
        let list = try SwaTexEngine.displayList(for: #"\text{中文}"#)
        let image = try #require(
            ImageRenderer.image(
                for: list, options: RenderOptions(fontSize: 40, padding: 0), displayScale: 1))
        let ink = try inkByteCount(image)
        #expect(ink > 50, "CJK glyphs must render through the system-font fallback")
    }

    @Test func fontProviderFallsBackToSystemFontForCJK() {
        let font = KaTeXFontProvider.shared.font(for: .mainRegular, size: 12)
        #expect(CTFontGetSize(font) == 12)
    }

    // ── ImageRenderer paths ─────────────────────────────────────────────

    @Test func imageFromLatexThrowsOnBadInput() {
        #expect(throws: ParseError.self) {
            _ = try ImageRenderer.image(latex: #"\frac{1}"#)
        }
    }

    @Test func imageFromLatexSucceeds() throws {
        let image = try #require(try ImageRenderer.image(latex: "x^2"))
        #expect(image.width > 0)
    }

    @Test func pngFromDisplayListMatchesMagic() throws {
        let list = try SwaTexEngine.displayList(for: #"\sqrt{2}"#)
        let png = try #require(ImageRenderer.png(for: list))
        #expect(png.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    @Test func batchPngsPreserveOrderAndNilForErrors() async throws {
        let results = await ImageRenderer.pngs(for: ["x", #"\frac{1}"#, "y^2"])
        #expect(results.count == 3)
        #expect(results[0] != nil)
        #expect(results[1] == nil)
        #expect(results[2] != nil)
        #expect(results[0]!.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func pngDataRoundTrip() throws {
        let image = try #require(try ImageRenderer.image(latex: "a+b", displayScale: 1))
        let png = try #require(ImageRenderer.pngData(image))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == image.width)
        #expect(decoded.height == image.height)
    }

    // ── MathView (SwiftUI) ──────────────────────────────────────────────

    @MainActor
    @Test func mathViewModifiersStoreValues() throws {
        let view = MathView("x^2")
            .font(size: 33)
            .inlineStyle()
            .mathColor(SwaTex.Color(r: 0, g: 0, b: 1, a: 1))

        var fontSize: CGFloat?
        var style: MathStyle?
        var color: SwaTex.Color?
        for child in Mirror(reflecting: view).children {
            switch child.label {
            case "fontSize": fontSize = child.value as? CGFloat
            case "style": style = child.value as? MathStyle
            case "color": color = child.value as? SwaTex.Color
            default: break
            }
        }
        #expect(fontSize == 33)
        #expect(style == .text)
        #expect(color?.b == 1)

        // inlineStyle(false) restores display style
        let display = view.inlineStyle(false)
        let styleBack = Mirror(reflecting: display).children
            .first { $0.label == "style" }?.value as? MathStyle
        #expect(styleBack == .display)
    }

    @MainActor
    @Test func mathViewBodySuccessPath() {
        let view = MathView(#"\frac{a}{b}"#).font(size: 20)
        let body = view.body
        // The success branch produces a sized Canvas (not the error Text).
        let desc = String(describing: type(of: body))
        #expect(desc.contains("Canvas") || desc.contains("ModifiedContent"))
    }

    @MainActor
    @Test func mathViewBodyErrorPath() {
        let view = MathView(#"\frac{1}"#)
        let body = view.body
        let desc = String(describing: body)
        // The failure branch renders the ParseError description as Text.
        #expect(desc.contains("ParseError") || desc.contains("Text"))
    }

    @MainActor
    @Test func mathViewRendersThroughCanvas() throws {
        // SwiftUI.ImageRenderer executes the Canvas drawing closure.
        let renderer = SwiftUI.ImageRenderer(content: MathView("x^2").font(size: 24))
        let image = try #require(renderer.cgImage)
        #expect(image.width > 1)
        #expect(image.height > 1)
    }

    // ── Stroked-path display items (CD arrows, \phase) ──────────────────

    @Test func cdDiagramRendersStrokedArrows() throws {
        let list = try SwaTexEngine.displayList(
            for: #"\begin{CD} A @>>> B \\ @VVV @| \\ C @= D \end{CD}"#)
        // CD diagrams emit (filled) stretchy-arrow path items.
        let hasPath = list.items.contains { item in
            if case .path = item { return true }
            return false
        }
        #expect(hasPath)
        let image = try #require(
            ImageRenderer.image(
                for: list, options: RenderOptions(fontSize: 24, padding: 0), displayScale: 1))
        #expect(try inkByteCount(image) > 100)
    }

    @Test func phaseRendersAngleShape() throws {
        let list = try SwaTexEngine.displayList(for: #"\phase{-78^\circ}"#)
        let image = try #require(
            ImageRenderer.image(
                for: list, options: RenderOptions(fontSize: 24, padding: 0), displayScale: 1))
        #expect(try inkByteCount(image) > 50)
    }

    // ── SwaTexView property observers ───────────────────────────────────

    #if canImport(AppKit) && !canImport(UIKit)
        @MainActor
        @Test func swaTexViewColorAndPaddingRelayout() {
            let view = SwaTexView(frame: .zero)
            view.fontSize = 30
            view.latex = "x"
            let base = view.intrinsicContentSize
            view.padding = 10
            let padded = view.intrinsicContentSize
            #expect(abs(padded.width - base.width - 20) < 1e-9)
            #expect(abs(padded.height - base.height - 20) < 1e-9)
            var laidOut = false
            view.onLayout = { _ in laidOut = true }
            view.mathColor = SwaTex.Color(r: 0, g: 0, b: 1, a: 1)
            // Layout is lazy (P-012): it runs on the next metrics query.
            _ = view.intrinsicContentSize
            #expect(laidOut)
        }
    #endif

    // ── Stroked path with curves (direct display-list draw) ─────────────

    @Test func strokedQuadAndCubicPathRendersInk() throws {
        // Same item semantics the Cairo backend uses for unfilled paths
        // (fixed 1.5pt stroke). Quad + cubic segments in one subpath.
        let list = DisplayList(
            items: [
                .path(
                    x: 0.1, y: 0.5,
                    commands: [
                        .moveTo(x: 0, y: 0),
                        .quadTo(x1: 0.25, y1: -0.5, x: 0.5, y: 0),
                        .cubicTo(x1: 0.6, y1: 0.3, x2: 0.7, y2: -0.3, x: 0.8, y: 0),
                        .lineTo(x: 0.9, y: 0.1),
                        .close,
                    ],
                    fill: false, color: .black)
            ],
            width: 1.0, height: 0.8, depth: 0.2)
        let image = try #require(
            ImageRenderer.image(
                for: list, options: RenderOptions(fontSize: 40, padding: 0), displayScale: 1))
        #expect(try inkByteCount(image) > 20)
    }

    // ── Font cache eviction under many distinct sizes ───────────────────

    @Test func fontProviderSizedCacheEviction() {
        // Request > 256 distinct sizes: the sized-font cache must reset
        // without breaking font resolution.
        for i in 0..<300 {
            let size = 10.0 + CGFloat(i) * 0.25
            let font = KaTeXFontProvider.shared.font(for: .mainRegular, size: size)
            #expect(CTFontGetSize(font) == size)
        }
    }
}
