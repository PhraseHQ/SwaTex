import Testing

@testable import SwaTex

// engine.rs has no #[cfg(test)] module covering lines 4459–5750 (its two test
// modules cover missing_glyph_width_em and CJK font switching, outside this
// range). These are Swift-side sanity checks of the pure path builders.

@Suite("EngineCDProof")
struct EngineCDProofTests {
    @Test func horizBraceOverShape() {
        let cmds = horizBracePath(2.0, 0.5, true)
        #expect(cmds.count == 7)
        // Starts and ends on the baseline (y = 0), tip reaches -height.
        guard case .moveTo(let x0, let y0) = cmds[0] else {
            Issue.record("expected MoveTo")
            return
        }
        #expect(x0 == 0.0 && y0 == 0.0)
        guard case .lineTo(let xm, let ym) = cmds[3] else {
            Issue.record("expected LineTo tip")
            return
        }
        #expect(abs(xm - 1.0) < 1e-12)
        #expect(abs(ym - -0.5) < 1e-12)
        guard case .quadTo(_, _, let xe, let ye) = cmds[6] else {
            Issue.record("expected QuadTo end")
            return
        }
        #expect(abs(xe - 2.0) < 1e-12)
        #expect(ye == 0.0)
    }

    @Test func horizBraceUnderMirrorsOver() {
        let over = horizBracePath(1.5, 0.4, true)
        let under = horizBracePath(1.5, 0.4, false)
        #expect(over.count == under.count)
        // Under brace tip is at +height (below baseline in path coords).
        guard case .lineTo(_, let yOver) = over[3], case .lineTo(_, let yUnder) = under[3] else {
            Issue.record("expected LineTo tips")
            return
        }
        #expect(abs(yOver + yUnder) < 1e-12)
    }

    @Test func stretchyAccentFallbackLeftArrow() {
        // \xLeftarrow is not in the katexImagesData table variants used by the
        // hand-drawn fallback (katexStretchyArrowPath handles xLeftarrow), so
        // use a label that is guaranteed to fall through: an unknown one.
        let cmds = stretchyAccentPath("\\notARealAccent", 2.0, 0.4)
        // Default branch: shaft + right arrowhead (5 commands).
        #expect(cmds.count == 5)
        guard case .moveTo(let x, let y) = cmds[0] else {
            Issue.record("expected MoveTo")
            return
        }
        #expect(x == 0.0)
        #expect(abs(y - -0.2) < 1e-12)  // midY = -height/2
    }

    @Test func stretchyAccentXlongequalTwoLines() {
        // \xlongequal IS in the KaTeX table, so it returns the SVG path;
        // just check it yields a non-empty command list.
        let cmds = stretchyAccentPath("\\xlongequal", 3.0, 0.4)
        #expect(!cmds.isEmpty)
    }
}
