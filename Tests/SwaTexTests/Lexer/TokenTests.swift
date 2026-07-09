import Testing

@testable import SwaTex

@Suite("Token")
struct TokenTests {
    @Test func tokenCreation() {
        let tok = Token("\\frac", start: 0, end: 5)
        #expect(tok.text == "\\frac")
        #expect(tok.loc.start == 0)
        #expect(tok.loc.end == 5)
    }

    @Test func isCommand() {
        #expect(Token("\\frac", start: 0, end: 5).isCommand)
        #expect(Token("\\ ", start: 0, end: 2).isCommand)
        #expect(!Token("a", start: 0, end: 1).isCommand)
        #expect(!Token("{", start: 0, end: 1).isCommand)
    }

    @Test func isEOF() {
        #expect(Token.eof(at: 10).isEOF)
        #expect(!Token("x", start: 0, end: 1).isEOF)
    }

    @Test func commandName() {
        #expect(Token("\\frac", start: 0, end: 5).commandName == "frac")
        #expect(Token("\\alpha", start: 0, end: 6).commandName == "alpha")
        #expect(Token("\\ ", start: 0, end: 2).commandName == " ")
        #expect(Token("a", start: 0, end: 1).commandName == nil)
    }

    @Test func isSpace() {
        #expect(Token(" ", start: 0, end: 1).isSpace)
        #expect(!Token("a", start: 0, end: 1).isSpace)
        #expect(!Token("\\ ", start: 0, end: 2).isSpace)
    }

    @Test func noexpandDefaultFalse() {
        let tok = Token("\\foo", start: 0, end: 4)
        #expect(!tok.noexpand)
        #expect(!tok.treatAsRelax)
    }

    @Test func range() {
        let t1 = Token("a", start: 0, end: 1)
        let t2 = Token("c", start: 4, end: 5)
        let spanned = t1.range(to: t2, text: "abc")
        #expect(spanned.text == "abc")
        #expect(spanned.loc.start == 0)
        #expect(spanned.loc.end == 5)
    }

    @Test func sourceLocationRange() {
        let a = SourceLocation(start: 0, end: 5)
        let b = SourceLocation(start: 10, end: 15)
        let r = SourceLocation.range(a, b)
        #expect(r.start == 0)
        #expect(r.end == 15)
    }
}
