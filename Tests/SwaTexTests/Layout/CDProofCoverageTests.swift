import Testing

@testable import SwaTex

/// Exercises every reachable CD-arrow direction and prooftree line-style /
/// root-orientation branch. The hand-drawn stretchy-accent fallbacks at the
/// top of `EngineCDProof.swift` are intentionally NOT covered — they are
/// shadowed by the generated KaTeX SVG table for every real arrow (P-013
/// defensive-fallback KEEP; see the marker there).
@Suite("CDProofCoverage")
struct CDProofCoverageTests {
    private func render(_ latex: String) throws -> DisplayList {
        try SwaTexEngine.displayList(for: latex)
    }

    // ── CD arrows: all directions + labels + equals + vertical ──────────

    @Test(arguments: [
        #"\begin{CD} A @>f>> B \end{CD}"#,  // right, labeled
        #"\begin{CD} A @>>> B \end{CD}"#,  // right, unlabeled
        #"\begin{CD} A @<g<< B \end{CD}"#,  // left
        #"\begin{CD} A @= B \end{CD}"#,  // horizontal equals
        #"\begin{CD} A @. B \end{CD}"#,  // empty cell
        #"\begin{CD} A \\ @VVV \\ B \end{CD}"#,  // vertical down
        #"\begin{CD} A \\ @AAA \\ B \end{CD}"#,  // vertical up
        #"\begin{CD} A \\ @V f V g V \\ B \end{CD}"#,  // vertical with two labels
        #"\begin{CD} A \\ @| \\ B \end{CD}"#,  // vertical equals
        #"\begin{CD} A @>f>g> B \\ @AAA @VVV \\ C @<<< D \end{CD}"#,  // full grid
    ])
    func cdArrowDirections(_ latex: String) throws {
        let list = try render(latex)
        #expect(list.width > 0 && list.totalHeight > 0)
    }

    // ── prooftree: inference arities, labels, line styles, roots ────────

    @Test(arguments: [
        #"\begin{prooftree}\AxiomC{A}\UnaryInfC{B}\end{prooftree}"#,
        #"\begin{prooftree}\AxiomC{A}\AxiomC{B}\BinaryInfC{C}\end{prooftree}"#,
        #"\begin{prooftree}\AxiomC{A}\AxiomC{B}\AxiomC{C}\TrinaryInfC{D}\end{prooftree}"#,
        #"\begin{prooftree}\AXC{A}\AXC{B}\AXC{C}\AXC{D}\QuaternaryInfC{E}\end{prooftree}"#,
        #"\begin{prooftree}\AxiomC{A}\LeftLabel{L}\RightLabel{R}\UnaryInfC{B}\end{prooftree}"#,
        #"\begin{prooftree}\AxiomC{A}\dashedLine\UnaryInfC{B}\end{prooftree}"#,
        #"\begin{prooftree}\AxiomC{A}\noLine\UnaryInfC{B}\end{prooftree}"#,
        #"\begin{prooftree}\AxiomC{A}\solidLine\UnaryInfC{B}\end{prooftree}"#,
        #"\begin{prooftree}\rootAtTop\AxiomC{A}\UnaryInfC{B}\end{prooftree}"#,
        #"\begin{prooftree}\rootAtBottom\AxiomC{A}\UnaryInfC{B}\end{prooftree}"#,
        // Deeper tree, mixed arities:
        #"\begin{prooftree}\AxiomC{A}\UnaryInfC{B}\AxiomC{C}\BinaryInfC{D}\UnaryInfC{E}\end{prooftree}"#,
    ])
    func prooftreeVariants(_ latex: String) throws {
        let list = try render(latex)
        #expect(list.width > 0 && list.totalHeight > 0)
    }

    // ── xArrows (the stretchy arrows the fallback shadows) render via
    //    the SVG table — confirm they produce output ─────────────────────

    @Test(arguments: [
        #"\xleftarrow{f}"#, #"\xrightarrow{g}"#, #"\xLeftarrow{a}"#,
        #"\xRightarrow{b}"#, #"\xleftrightarrow{c}"#, #"\xhookleftarrow{d}"#,
        #"\xmapsto{e}"#, #"\xrightharpoonup{h}"#, #"\xtwoheadrightarrow{i}"#,
    ])
    func stretchyArrowsRenderViaTable(_ latex: String) throws {
        let list = try render(latex)
        #expect(list.items.count > 0)
    }
}
