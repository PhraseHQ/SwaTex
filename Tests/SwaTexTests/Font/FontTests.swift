import Testing

@testable import SwaTex

@Suite("FontId")
struct FontIdTests {
    @Test func cjkRegularParse() {
        #expect(FontId(rawValue: "CJK-Regular") == .cjkRegular)
    }

    @Test func cjkRegularAsString() {
        #expect(FontId.cjkRegular.rawValue == "CJK-Regular")
    }

    @Test func cjkRegularDescription() {
        #expect("\(FontId.cjkRegular)" == "CJK-Regular")
    }

    @Test func parseUnknownFont() {
        #expect(FontId(rawValue: "NotARealFont") == nil)
    }

    @Test func allVariantsRoundtrip() {
        for v in FontId.allCases {
            #expect(FontId(rawValue: v.rawValue) == v, "roundtrip failed for \(v)")
        }
    }
}

@Suite("FontMetrics")
struct FontMetricsTests {
    @Test func mainRegularLowercaseA() throws {
        let m = try #require(FontId.mainRegular.metrics(forChar: 97))
        #expect(abs(m.height - 0.43056) < 0.001, "height of 'a': \(m.height)")
        #expect(abs(m.depth) < 0.001, "depth of 'a': \(m.depth)")
        #expect(m.width > 0, "width of 'a' should be positive")
    }

    @Test func mainRegularUppercaseA() throws {
        let m = try #require(FontId.mainRegular.metrics(forChar: 65))
        #expect(abs(m.height - 0.68333) < 0.001, "height of 'A': \(m.height)")
        #expect(abs(m.depth) < 0.001)
    }

    @Test func mainRegularDigit0() throws {
        let m = try #require(FontId.mainRegular.metrics(forChar: 48))
        #expect(m.height > 0)
        #expect(m.width > 0)
    }

    @Test func mathItalicLowercaseA() throws {
        let m = try #require(FontId.mathItalic.metrics(forChar: 97))
        #expect(m.height > 0)
        #expect(m.width > 0)
    }

    @Test func nonexistentChar() {
        #expect(FontId.mainRegular.metrics(forChar: 99999) == nil)
    }

    @Test func spaceChar() throws {
        let m = try #require(FontId.mainRegular.metrics(forChar: 32))
        #expect(abs(m.width - 0.25) < 0.001, "space width: \(m.width)")
    }

    @Test func amsRegular() throws {
        let m = try #require(FontId.amsRegular.metrics(forChar: 65))
        #expect(abs(m.height - 0.68889) < 0.001)
    }

    @Test func extraCharMapCyrillic() throws {
        // Cyrillic А (U+0410) maps to Latin A.
        // Direct lookup returns nil (no Cyrillic in metric table).
        #expect(FontId.mainRegular.metrics(forChar: 0x0410) == nil)
        // Fallback lookup should work.
        let m = try #require(FontId.mainRegular.metricsWithFallback(forChar: 0x0410))
        #expect(m.height > 0)
    }

    @Test func mathConstantsTextstyle() {
        let mc = MathConstants.forSize(0)
        #expect(abs(mc.axisHeight - 0.25) < 0.001)
        #expect(abs(mc.defaultRuleThickness - 0.04) < 0.001)
        #expect(mc.num1 > mc.num2)
        #expect(mc.sup1 > mc.sup2)
        #expect(abs(mc.quad - 1.0) < 0.001)
        #expect(abs(mc.ptPerEm - 10.0) < 0.001)
    }

    @Test func mathConstantsScriptstyle() {
        let mc = MathConstants.forSize(1)
        #expect(abs(mc.axisHeight - 0.25) < 0.001)
        #expect(abs(mc.quad - 1.171) < 0.001)
        #expect(abs(mc.defaultRuleThickness - 0.049) < 0.001)
    }

    @Test func mathConstantsScriptscriptstyle() {
        let mc = MathConstants.forSize(2)
        #expect(abs(mc.quad - 1.472) < 0.001)
        #expect(abs(mc.num1 - 0.925) < 0.001)
    }

    @Test func cssEmPerMu() {
        let mc = MathConstants.forSize(0)
        #expect(abs(mc.cssEmPerMu - 1.0 / 18.0) < 0.0001)
    }

    @Test func textModeFallbackCJK() throws {
        // CJK character '中' (U+4E2D) has no metrics, but in text mode
        // it should fall back to 'M' metrics.
        let ch: UInt32 = 0x4E2D
        #expect(FontId.mainRegular.metrics(forChar: ch) == nil)
        #expect(FontId.mainRegular.metricsWithFallback(forChar: ch) == nil)

        let m = try #require(FontId.mainRegular.metrics(forChar: ch, isTextMode: true))
        let mRef = try #require(FontId.mainRegular.metrics(forChar: 77))  // 'M'
        #expect(abs(m.height - mRef.height) < .ulpOfOne)
        #expect(abs(m.width - mRef.width) < .ulpOfOne)
    }

    @Test func textModeFallbackNotInMath() {
        #expect(FontId.mainRegular.metrics(forChar: 0x4E2D, isTextMode: false) == nil)
    }

    @Test func textModeFallbackDevanagari() throws {
        // Devanagari (Brahmic script) U+0900-U+097F
        let m = try #require(FontId.mainRegular.metrics(forChar: 0x0915, isTextMode: true))  // क
        #expect(m.height > 0)
    }
}

@Suite("Symbols")
struct SymbolsTests {
    @Test func getEquiv() throws {
        let sym = try #require(SymbolInfo(name: "\\equiv", mode: .math))
        #expect(sym.group == .rel)
        #expect(sym.font == .main)
        #expect(sym.codepoint == "\u{2261}")
    }

    @Test func getAlpha() throws {
        let sym = try #require(SymbolInfo(name: "\\alpha", mode: .math))
        #expect(sym.group == .mathOrd)
        #expect(sym.codepoint == "\u{03B1}")
    }

    @Test func getPlus() throws {
        let sym = try #require(SymbolInfo(name: "+", mode: .math))
        #expect(sym.group == .bin)
    }

    @Test func getLparen() throws {
        let sym = try #require(SymbolInfo(name: "\\lparen", mode: .math))
        #expect(sym.group == .open)
        #expect(sym.codepoint == "(")
    }

    @Test func getRparen() throws {
        let sym = try #require(SymbolInfo(name: "\\rparen", mode: .math))
        #expect(sym.group == .close)
        #expect(sym.codepoint == ")")
    }

    @Test func getSum() throws {
        let sym = try #require(SymbolInfo(name: "\\sum", mode: .math))
        #expect(sym.group == .opToken)
    }

    @Test func getInt() throws {
        let sym = try #require(SymbolInfo(name: "\\int", mode: .math))
        #expect(sym.group == .opToken)
    }

    @Test func fracIsNotASymbol() {
        // \frac is a command, not a symbol
        #expect(SymbolInfo(name: "\\frac", mode: .math) == nil)
    }

    @Test func textModeHash() throws {
        let sym = try #require(SymbolInfo(name: "\\#", mode: .text))
        #expect(sym.group == .textOrd)
    }

    @Test func mathForall() throws {
        let sym = try #require(SymbolInfo(name: "\\forall", mode: .math))
        #expect(sym.codepoint == "\u{2200}")
    }

    @Test func amsSymbol() throws {
        let sym = try #require(SymbolInfo(name: "\\beth", mode: .math))
        #expect(sym.font == .ams)
        #expect(sym.codepoint == "\u{2136}")
    }

    @Test func equalsIsRel() throws {
        let sym = try #require(SymbolInfo(name: "=", mode: .math))
        #expect(sym.group == .rel)
    }

    @Test func byCodepoint() throws {
        let sym = try #require(SymbolInfo(codepoint: "\u{2261}", mode: .math))
        #expect(sym.name == "\\equiv")
    }

    @Test func nonexistent() {
        #expect(SymbolInfo(name: "\\nonexistent_command_xyz", mode: .math) == nil)
    }

    @Test func digitsAreTextord() throws {
        // In KaTeX, digits in math mode are classified as "textord"
        for d in UInt8(ascii: "0")...UInt8(ascii: "9") {
            let name = String(Unicode.Scalar(d))
            let sym = try #require(SymbolInfo(name: name, mode: .math))
            #expect(sym.group == .textOrd, "digit \(name) should be textord")
        }
    }

    @Test func lettersAreMathord() throws {
        for ch in UInt8(ascii: "a")...UInt8(ascii: "z") {
            let name = String(Unicode.Scalar(ch))
            let sym = try #require(SymbolInfo(name: name, mode: .math))
            #expect(sym.group == .mathOrd, "letter \(name) should be mathord")
        }
    }

    @Test func acceptUnicodeCharByName() throws {
        // KaTeX acceptUnicodeChar: symbol can be looked up by replace (Unicode char) as name
        let sym = try #require(SymbolInfo(name: "α", mode: .math))
        #expect(sym.name == "\\alpha")
        #expect(sym.group == .mathOrd)
        #expect(sym.codepoint == "α")
    }
}

@Suite("MathAlpha")
struct MathAlphaTests {
    @Test func ttfCmapMapsMathBoldAToASCIIAOnMainBold() {
        // MATHEMATICAL BOLD CAPITAL A
        let cp: UInt32 = 0x1D400
        #expect(
            FontId.mainBold.ttfGlyphScalar(forDisplayCharCode: cp) == "A",
            "KaTeX Main-Bold.ttf cmap uses 'A', not U+1D400")
        #expect(FontId.mainRegular.ttfGlyphScalar(forDisplayCharCode: cp) == "\u{1D400}")
    }

    @Test func ttfCmapHyphenUnchanged() {
        #expect(FontId.mainBold.ttfGlyphScalar(forDisplayCharCode: UInt32(UInt8(ascii: "-"))) == "-")
    }
}
