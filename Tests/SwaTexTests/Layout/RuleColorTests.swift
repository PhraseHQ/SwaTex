import Testing

@testable import SwaTex

/// KaTeX renders `\rule` (and synthesized rule bars) in the current color;
/// the leaf's own color is what the display walk emits. Found by the final
/// pre-release review: rules stayed black under `\textcolor` and in
/// dark-mode dynamic-color rendering.
@Suite("RuleColor")
struct RuleColorTests {
    private func firstLineColor(_ latex: String, color: Color = .black) throws -> Color? {
        let list = try SwaTexEngine.displayList(for: latex, color: color)
        for item in list.items {
            if case let .line(_, _, _, _, c, _) = item { return c }
        }
        return nil
    }

    @Test func ruleTakesEngineColor() throws {
        let red = Color(r: 1, g: 0, b: 0, a: 1)
        #expect(try firstLineColor(#"\rule{20pt}{2pt}"#, color: red) == red)
        #expect(try firstLineColor(#"\rule{20pt}{2pt}"#) == .black)
    }

    @Test func ruleTakesTextcolor() throws {
        let c = try firstLineColor(#"\textcolor{blue}{\rule{20pt}{2pt}}"#)
        #expect(c == Color(r: 0, g: 0, b: 1, a: 1))
    }

    @Test func imageofBarTakesEngineColor() throws {
        let red = Color(r: 1, g: 0, b: 0, a: 1)
        let c = try firstLineColor("⊷", color: red)
        #expect(c == red)
    }
}
