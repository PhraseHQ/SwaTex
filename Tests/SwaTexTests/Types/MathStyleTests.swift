import Testing

@testable import SwaTex

// Exhaustive tests against KaTeX Style.ts lookup tables.
@Suite("MathStyle")
struct MathStyleTests {
    @Test func numeratorAllStyles() {
        // KaTeX: fracNum = [T, Tc, S, Sc, SS, SSc, SS, SSc]
        #expect(MathStyle.display.numerator == .text)
        #expect(MathStyle.displayCramped.numerator == .textCramped)
        #expect(MathStyle.text.numerator == .script)
        #expect(MathStyle.textCramped.numerator == .scriptCramped)
        #expect(MathStyle.script.numerator == .scriptScript)
        #expect(MathStyle.scriptCramped.numerator == .scriptScriptCramped)
        #expect(MathStyle.scriptScript.numerator == .scriptScript)
        #expect(MathStyle.scriptScriptCramped.numerator == .scriptScriptCramped)
    }

    @Test func denominatorAllStyles() {
        // KaTeX: fracDen = [Tc, Tc, Sc, Sc, SSc, SSc, SSc, SSc]
        #expect(MathStyle.display.denominator == .textCramped)
        #expect(MathStyle.displayCramped.denominator == .textCramped)
        #expect(MathStyle.text.denominator == .scriptCramped)
        #expect(MathStyle.textCramped.denominator == .scriptCramped)
        #expect(MathStyle.script.denominator == .scriptScriptCramped)
        #expect(MathStyle.scriptCramped.denominator == .scriptScriptCramped)
        #expect(MathStyle.scriptScript.denominator == .scriptScriptCramped)
        #expect(MathStyle.scriptScriptCramped.denominator == .scriptScriptCramped)
    }

    @Test func superscriptAllStyles() {
        // KaTeX: sup = [S, Sc, S, Sc, SS, SSc, SS, SSc]
        #expect(MathStyle.display.superscript == .script)
        #expect(MathStyle.displayCramped.superscript == .scriptCramped)
        #expect(MathStyle.text.superscript == .script)
        #expect(MathStyle.textCramped.superscript == .scriptCramped)
        #expect(MathStyle.script.superscript == .scriptScript)
        #expect(MathStyle.scriptCramped.superscript == .scriptScriptCramped)
        #expect(MathStyle.scriptScript.superscript == .scriptScript)
        #expect(MathStyle.scriptScriptCramped.superscript == .scriptScriptCramped)
    }

    @Test func subscriptAllStyles() {
        // KaTeX: sub = [Sc, Sc, Sc, Sc, SSc, SSc, SSc, SSc]
        #expect(MathStyle.display.subscript_ == .scriptCramped)
        #expect(MathStyle.displayCramped.subscript_ == .scriptCramped)
        #expect(MathStyle.text.subscript_ == .scriptCramped)
        #expect(MathStyle.textCramped.subscript_ == .scriptCramped)
        #expect(MathStyle.script.subscript_ == .scriptScriptCramped)
        #expect(MathStyle.scriptCramped.subscript_ == .scriptScriptCramped)
        #expect(MathStyle.scriptScript.subscript_ == .scriptScriptCramped)
        #expect(MathStyle.scriptScriptCramped.subscript_ == .scriptScriptCramped)
    }

    @Test func crampedAllStyles() {
        // KaTeX: cramp = [Dc, Dc, Tc, Tc, Sc, Sc, SSc, SSc]
        #expect(MathStyle.display.cramped == .displayCramped)
        #expect(MathStyle.displayCramped.cramped == .displayCramped)
        #expect(MathStyle.text.cramped == .textCramped)
        #expect(MathStyle.textCramped.cramped == .textCramped)
        #expect(MathStyle.script.cramped == .scriptCramped)
        #expect(MathStyle.scriptCramped.cramped == .scriptCramped)
        #expect(MathStyle.scriptScript.cramped == .scriptScriptCramped)
        #expect(MathStyle.scriptScriptCramped.cramped == .scriptScriptCramped)
    }

    @Test func textAllStyles() {
        // KaTeX: text = [D, Dc, T, Tc, T, Tc, T, Tc]
        #expect(MathStyle.display.textEquivalent == .display)
        #expect(MathStyle.displayCramped.textEquivalent == .displayCramped)
        #expect(MathStyle.text.textEquivalent == .text)
        #expect(MathStyle.textCramped.textEquivalent == .textCramped)
        #expect(MathStyle.script.textEquivalent == .text)
        #expect(MathStyle.scriptCramped.textEquivalent == .textCramped)
        #expect(MathStyle.scriptScript.textEquivalent == .text)
        #expect(MathStyle.scriptScriptCramped.textEquivalent == .textCramped)
    }

    @Test func isDisplay() {
        #expect(MathStyle.display.isDisplay)
        #expect(MathStyle.displayCramped.isDisplay)
        #expect(!MathStyle.text.isDisplay)
        #expect(!MathStyle.script.isDisplay)
    }

    @Test func isTight() {
        #expect(!MathStyle.display.isTight)
        #expect(!MathStyle.text.isTight)
        #expect(MathStyle.script.isTight)
        #expect(MathStyle.scriptCramped.isTight)
        #expect(MathStyle.scriptScript.isTight)
        #expect(MathStyle.scriptScriptCramped.isTight)
    }

    @Test func sizeIndex() {
        #expect(MathStyle.display.sizeIndex == 0)
        #expect(MathStyle.text.sizeIndex == 0)
        #expect(MathStyle.script.sizeIndex == 1)
        #expect(MathStyle.scriptScript.sizeIndex == 2)
    }

    @Test func sizeMultiplier() {
        #expect(abs(MathStyle.display.sizeMultiplier - 1.0) < .ulpOfOne)
        #expect(abs(MathStyle.text.sizeMultiplier - 1.0) < .ulpOfOne)
        #expect(abs(MathStyle.script.sizeMultiplier - 0.7) < .ulpOfOne)
        #expect(abs(MathStyle.scriptScript.sizeMultiplier - 0.5) < .ulpOfOne)
    }
}
