import Testing

@testable import SwaTex

// Ported from RaTeX `katex_svg.rs` #[cfg(test)] tests.

@Suite("KaTeXSvg")
struct KaTeXSvgTests {
    @Test func parseSimplePath() {
        let cmds = parseSvgPath("M0 0 L10 20 Z")
        #expect(cmds.count == 3)
    }

    @Test func parseKatexVecPath() {
        let cmds = scaleSvgPathThousandths(parseSvgPath(KaTeXSvgData.katexVecPath))
        #expect(cmds.count >= 8, "vec path should parse to multiple segments")
        if case .moveTo(let x, let y) = cmds[0] {
            #expect(abs(x - 0.377) < 0.001)
            #expect(abs(y - 0.02) < 0.001)
        } else {
            Issue.record("expected MoveTo")
        }
    }

    @Test func parseRelative() {
        let cmds = parseSvgPath("M10 10 l5 5")
        #expect(cmds.count == 2)
        if case .lineTo(let x, let y) = cmds[1] {
            #expect(abs(x - 15.0) < 0.01)
            #expect(abs(y - 15.0) < 0.01)
        } else {
            Issue.record("expected LineTo")
        }
    }

    @Test func parseWidehat1() {
        let cmds = parseSvgPath(KaTeXSvgData.widehat[0])
        #expect(cmds.count > 3)
    }

    @Test func katexAccentWidehat() {
        let result = katexAccentPath("\\widehat", baseWidthEm: 1.5, groupLen: 1)
        #expect(result != nil)
    }

    @Test func katexAccentOvergroup() {
        let result = katexAccentPath("\\overgroup", baseWidthEm: 1.5, groupLen: 1)
        #expect(result != nil)
    }

    @Test func tildePathCoordinates() {
        let raw = parseSvgPath(KaTeXSvgData.tilde[2])
        #expect(raw.count == 16)
        // Verify the critical cubic that was previously broken by `\` line continuation
        if case .cubicTo(let x1, let y1, _, _, _, _) = raw[7] {
            #expect(abs(x1 - 1141.3) < 0.1, "x1 should be 1141.3, got \(x1)")
            #expect(abs(y1 - 0.0) < 0.1, "y1 should be 0, got \(y1)")
        } else {
            Issue.record("expected CubicTo at index 7")
        }
    }

    @Test func katexStretchyArrowXtwohead() throws {
        let r = katexStretchyArrowPath("\\xtwoheadrightarrow", widthEm: 2.0, heightEm: 0.3)
        let cmds = try #require(r)
        #expect(!cmds.isEmpty)
        let l = katexStretchyArrowPath("\\xtwoheadleftarrow", widthEm: 2.0, heightEm: 0.3)
        let lCmds = try #require(l)
        #expect(!lCmds.isEmpty)
        #expect(katexStretchyArrowPath("\\xrightarrow", widthEm: 2.0, heightEm: 0.3) != nil)
        #expect(katexStretchyArrowPath("\\xleftarrow", widthEm: 2.0, heightEm: 0.3) != nil)
    }

    @Test func katexCdVertArrowFromRightarrowTest() throws {
        let axis = 0.25
        for down in [true, false] {
            let r = katexCdVertArrowFromRightarrow(
                down: down, totalHeightEm: 2.5, axisHeightEm: axis)
            let (cmds, w) = try #require(r, "down=\(down)")
            #expect(!cmds.isEmpty)
            #expect(
                w > 0.45 && w < 0.58,
                "lateral extent should match horizontal arrow ink height ~0.522em, got \(w)")
        }
    }
}
