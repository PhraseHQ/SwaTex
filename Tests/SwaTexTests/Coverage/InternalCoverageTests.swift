import Foundation
import Testing

@testable import SwaTex

/// Direct unit tests of internal helper APIs whose branches are hard to reach
/// through full formulas: SVG path parsing, SVG float formatting, LayoutBox
/// helpers, MacroExpander primitives, and Codable error paths.
@Suite("InternalCoverage")
struct InternalCoverageTests {
    // ── parseSvgPath: quadratic Bézier commands ─────────────────────────

    @Test func parseSvgPathQuadraticAbsolute() {
        let cmds = parseSvgPath("M0 0Q10 20 30 0")
        #expect(cmds.count == 2)
        guard case let .quadTo(x1, y1, x, y) = cmds[1] else {
            Issue.record("expected quadTo, got \(cmds[1])")
            return
        }
        #expect(x1 == 10 && y1 == 20 && x == 30 && y == 0)
    }

    @Test func parseSvgPathQuadraticRelative() {
        let cmds = parseSvgPath("M10 10q5 -5 10 0")
        #expect(cmds.count == 2)
        guard case let .quadTo(x1, y1, x, y) = cmds[1] else {
            Issue.record("expected quadTo, got \(cmds[1])")
            return
        }
        // relative: control = (10+5, 10-5), end = (10+10, 10+0)
        #expect(x1 == 15 && y1 == 5 && x == 20 && y == 10)
    }

    @Test func parseSvgPathImplicitRepeat() {
        // A second coordinate pair after Q repeats the command
        let cmds = parseSvgPath("M0 0Q1 1 2 0 3 -1 4 0")
        let quads = cmds.filter {
            if case .quadTo = $0 { return true }
            return false
        }
        #expect(quads.count == 2)
    }

    // ── katexStretchyPath: overgroup/undergroup table entries ───────────

    @Test(arguments: ["\\overgroup", "\\undergroup"])
    func katexStretchyPathGroupGlyphs(_ label: String) throws {
        let result = try #require(katexStretchyPath(label, widthEm: 1.5))
        #expect(abs(result.heightEm - 0.342) < 1e-9)
        #expect(!result.commands.isEmpty)
    }

    // ── SVG float formatting (scientific-notation expansion) ────────────

    @Test func svgFormatFloatExpandsExponents() {
        #expect(svgFormatFloat(Float(1e-7)) == "0.0000001")
        #expect(svgFormatFloat(Float(-1e-7)) == "-0.0000001")
        #expect(svgFormatFloat(Float(1e10)) == "10000000000")
        #expect(svgFormatFloat(Float(-2.5e8)) == "-250000000")
        #expect(svgFormatFloat(Float(0.5)) == "0.5")
        #expect(svgFormatFloat(Float(3.0)) == "3")
        #expect(svgFormatFloat(Float(-4.0)) == "-4")
    }

    // ── LayoutBox helpers ───────────────────────────────────────────────

    @Test func layoutBoxHelpers() {
        let box = LayoutBox(
            width: 2.0, height: 1.5, depth: 0.5,
            content: .hbox([]), color: .black)
        #expect(box.totalHeight == 2.0)

        let red = SwaTex.Color(r: 1, g: 0, b: 0, a: 1)
        let colored = box.with(color: red)
        #expect(colored.color == red)
        #expect(colored.width == box.width)

        let adjusted = box.withAdjustedDelim(height: 3.0, depth: 1.0)
        #expect(adjusted.height == 3.0)
        #expect(adjusted.depth == 1.0)
        #expect(adjusted.width == box.width)
    }

    // ── MacroExpander primitives ────────────────────────────────────────

    @Test func setTopTextReplacesNextToken() {
        let me = MacroExpander("xy", mode: .math)
        me.setTopText("z")
        #expect(me.popToken().text == "z")
        #expect(me.popToken().text == "y")
    }

    @Test func isExpandableClassifiesNames() {
        let me = MacroExpander("", mode: .math)
        #expect(me.isExpandable("\\frac"))  // registry function, not primitive
        #expect(!me.isExpandable("\\notdefinedxyz"))
        #expect(!me.isExpandable("x"))
    }

    // ── Codable error paths ─────────────────────────────────────────────

    @Test func pathCommandDecodingRejectsUnknownType() {
        let json = Data(#"{"type":"Bogus"}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PathCommand.self, from: json)
        }
    }

    @Test func displayItemDecodingRejectsUnknownType() {
        let json = Data(#"{"type":"bogus"}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(DisplayItem.self, from: json)
        }
    }

    @Test func pathCommandRoundTrip() throws {
        let cmds: [PathCommand] = [
            .moveTo(x: 1, y: 2),
            .lineTo(x: 3, y: 4),
            .cubicTo(x1: 1, y1: 2, x2: 3, y2: 4, x: 5, y: 6),
            .quadTo(x1: 1, y1: 2, x: 3, y: 4),
            .close,
        ]
        let data = try JSONEncoder().encode(cmds)
        let decoded = try JSONDecoder().decode([PathCommand].self, from: data)
        #expect(decoded == cmds)
    }
}
