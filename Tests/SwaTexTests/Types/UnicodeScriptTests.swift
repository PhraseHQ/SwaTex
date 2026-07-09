import Testing

@testable import SwaTex

@Suite("UnicodeScript")
struct UnicodeScriptTests {
    @Test func basicLatinNotMatched() {
        #expect(!UnicodeScript.supports(codepoint: UInt32(("A" as Unicode.Scalar).value)))
        #expect(!UnicodeScript.supports(codepoint: UInt32(("z" as Unicode.Scalar).value)))
    }

    @Test func latinExtended() {
        #expect(UnicodeScript.supports(codepoint: 0x0100))  // Ā
        #expect(UnicodeScript.supports(codepoint: 0x024F))  // end of Latin Extended-B
        #expect(UnicodeScript(codepoint: 0x0100) == .latin)
    }

    @Test func combiningDiacritical() {
        #expect(UnicodeScript.supports(codepoint: 0x0300))  // combining grave accent
        #expect(UnicodeScript.supports(codepoint: 0x0301))  // combining acute accent
        #expect(UnicodeScript.supports(codepoint: 0x036F))  // end of combining marks
        #expect(UnicodeScript(codepoint: 0x0301) == .latin)
    }

    @Test func cyrillic() {
        #expect(UnicodeScript.supports(codepoint: 0x0410))  // Cyrillic А
        #expect(UnicodeScript.supports(codepoint: 0x044F))  // Cyrillic я
        #expect(UnicodeScript(codepoint: 0x0410) == .cyrillic)
    }

    @Test func cjk() {
        #expect(UnicodeScript.supports(codepoint: 0x4E2D))  // 中
        #expect(UnicodeScript.supports(codepoint: 0x3042))  // Hiragana あ
        #expect(UnicodeScript(codepoint: 0x4E2D) == .cjk)
    }

    @Test func hangul() {
        #expect(UnicodeScript.supports(codepoint: 0xAC00))  // first Hangul syllable
        #expect(UnicodeScript(codepoint: 0xAC00) == .hangul)
    }

    @Test func brahmic() {
        #expect(UnicodeScript.supports(codepoint: 0x0900))  // Devanagari start
        #expect(UnicodeScript.supports(codepoint: 0x0E01))  // Thai
        #expect(UnicodeScript(codepoint: 0x0900) == .brahmic)
    }

    @Test func armenian() {
        #expect(UnicodeScript.supports(codepoint: 0x0530))
        #expect(UnicodeScript(codepoint: 0x0531) == .armenian)
    }

    @Test func georgian() {
        #expect(UnicodeScript.supports(codepoint: 0x10A0))
        #expect(UnicodeScript(codepoint: 0x10A0) == .georgian)
    }

    @Test func unsupportedCodepoint() {
        #expect(!UnicodeScript.supports(codepoint: 0xFFFF))
        #expect(UnicodeScript(codepoint: 0xFFFF) == nil)
    }
}
