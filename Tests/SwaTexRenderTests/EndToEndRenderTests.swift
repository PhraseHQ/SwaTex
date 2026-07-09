import CoreGraphics
import Foundation
import Testing

@testable import SwaTex
@testable import SwaTexRender

@Suite("EndToEndRender")
struct EndToEndRenderTests {
    @Test(arguments: [
        #"x^2 + y^2 = z^2"#,
        #"\frac{-b \pm \sqrt{b^2-4ac}}{2a}"#,
        #"\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}"#,
        #"\int_0^1 x^2\,dx = \frac{1}{3}"#,
        #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#,
        #"\lim_{x \to 0} \frac{\sin x}{x} = 1"#,
        #"\ce{H2SO4 + 2NaOH -> Na2SO4 + 2H2O}"#,
        #"\left( \frac{a}{b} \right)^n"#,
        #"\hat{x} + \vec{v} + \tilde{y}"#,
        #"\mathbb{R} \subset \mathbb{C}, \mathcal{L}(f)"#,
    ])
    func rendersFormulaToInk(_ latex: String) throws {
        let image = try #require(
            try ImageRenderer.image(latex: latex, options: RenderOptions(fontSize: 40)))
        #expect(image.width > 10)
        #expect(image.height > 10)

        // The render must contain actual ink (non-transparent pixels).
        let data = try #require(image.dataProvider?.data as Data?)
        var inkPixels = 0
        for i in stride(from: 3, to: data.count, by: 4) where data[i] > 0 {
            inkPixels += 1
        }
        #expect(inkPixels > 50, "\(latex): only \(inkPixels) ink pixels")
    }

    @Test func displayVsInlineStyleDiffer() throws {
        let latex = #"\sum_{n=1}^{\infty} \frac{1}{n^2}"#
        let display = try SwaTexEngine.displayList(for: latex, style: .display)
        let inline = try SwaTexEngine.displayList(for: latex, style: .text)
        // Display style places limits above/below and uses larger operators,
        // so it must be taller than inline style.
        #expect(display.totalHeight > inline.totalHeight)
    }

    @Test func coloredFormula() throws {
        let list = try SwaTexEngine.displayList(
            for: #"\textcolor{red}{x} + y"#)
        let hasRedGlyph = list.items.contains { item in
            if case let .glyphPath(_, _, _, _, _, color) = item {
                return color.r > 0.9 && color.g < 0.1
            }
            return false
        }
        #expect(hasRedGlyph)
    }

    @Test func svgAndPNGFromSameList() throws {
        let list = try SwaTexEngine.displayList(for: #"\frac{a}{b}"#)
        let svg = SVGRenderer().render(list)
        #expect(svg.hasPrefix("<svg"))
        #expect(svg.contains("KaTeX"))
        let image = try #require(ImageRenderer.image(for: list))
        #expect(image.width > 0)
    }
}
