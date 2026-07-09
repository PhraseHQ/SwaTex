import Testing

@testable import SwaTex

// Port of engine.rs `cjk_font_switching_tests` — exercises `\text{…}` (layoutText)
// end-to-end: characters without bundled KaTeX metrics must switch to CJK-Regular
// so renderers can load them from a system Unicode font.
@Suite("CJK font switching")
struct CjkFontSwitchingTests {
    private func firstGlyphFontName(_ latex: String) throws -> String? {
        let ast = try Parser(latex).parse()
        let lbox = layout(ast, options: LayoutOptions())
        let dl = toDisplayList(lbox)
        for item in dl.items {
            if case let .glyphPath(_, _, _, font, _, _) = item {
                return font
            }
        }
        return nil
    }

    @Test func cjkInTextUsesCjkRegular() throws {
        #expect(try firstGlyphFontName(#"\text{中}"#) == "CJK-Regular")
    }

    @Test func emojiInTextUsesCjkRegular() throws {
        #expect(try firstGlyphFontName(#"\text{😊}"#) == "CJK-Regular")
    }

    @Test func latinInTextIsNotCjk() throws {
        #expect(try firstGlyphFontName(#"\text{a}"#) != "CJK-Regular")
    }

    @Test func hiraganaInTextUsesCjkRegular() throws {
        #expect(try firstGlyphFontName(#"\text{あ}"#) == "CJK-Regular")
    }
}
