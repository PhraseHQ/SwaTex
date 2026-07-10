import Testing

@testable import SwaTex

private func lexTexts(_ input: String) -> [String] {
    var lexer = Lexer(input)
    return lexer.lexAll().map(\.text)
}

@Suite("Lexer")
struct LexerTests {
    // === Basic character tokens ===

    @Test func singleLetter() {
        #expect(lexTexts("a") == ["a", "EOF"])
    }

    @Test func multipleLetters() {
        #expect(lexTexts("abc") == ["a", "b", "c", "EOF"])
    }

    @Test func digit() {
        #expect(lexTexts("123") == ["1", "2", "3", "EOF"])
    }

    @Test func emptyInput() {
        #expect(lexTexts("") == ["EOF"])
    }

    // === Control sequences ===

    @Test func controlWord() {
        #expect(lexTexts("\\frac") == ["\\frac", "EOF"])
    }

    @Test func controlWordAlpha() {
        #expect(lexTexts("\\alpha") == ["\\alpha", "EOF"])
    }

    @Test func controlWordFollowedByLetter() {
        // \frac followed by letter: control word consumes trailing space then letter is separate
        #expect(lexTexts("\\frac x") == ["\\frac", "x", "EOF"])
    }

    @Test func controlWordNoSpace() {
        // \fracx → \fracx as one control word
        #expect(lexTexts("\\fracx") == ["\\fracx", "EOF"])
    }

    @Test func controlWordBrace() {
        #expect(lexTexts("\\frac{}") == ["\\frac", "{", "}", "EOF"])
    }

    @Test func controlSymbol() {
        // \, is a control symbol (comma is not a letter)
        #expect(lexTexts("\\,") == ["\\,", "EOF"])
    }

    @Test func controlSymbolSemicolon() {
        #expect(lexTexts("\\;") == ["\\;", "EOF"])
    }

    @Test func controlSpace() {
        // \<space> → control space token "\ "
        #expect(lexTexts("\\ ") == ["\\ ", "EOF"])
    }

    @Test func doubleBackslash() {
        // \\ → control symbol "\\"
        #expect(lexTexts("\\\\") == ["\\\\", "EOF"])
    }

    // === Whitespace ===

    @Test func whitespaceCollapsed() {
        #expect(lexTexts("a   b") == ["a", " ", "b", "EOF"])
    }

    @Test func newlineAsSpace() {
        #expect(lexTexts("a\nb") == ["a", " ", "b", "EOF"])
    }

    @Test func tabAsSpace() {
        #expect(lexTexts("a\tb") == ["a", " ", "b", "EOF"])
    }

    @Test func controlWordEatsTrailingSpace() {
        // In TeX/KaTeX, `\frac  x` → \frac token, then x (spaces consumed by control word)
        #expect(lexTexts("\\frac  x") == ["\\frac", "x", "EOF"])
    }

    // === Comments ===

    @Test func commentToEOL() {
        #expect(lexTexts("a%comment\nb") == ["a", "b", "EOF"])
    }

    @Test func commentAtEnd() {
        #expect(lexTexts("a%comment") == ["a", "EOF"])
    }

    @Test func commentWithCommands() {
        #expect(lexTexts("\\alpha%skip\n\\beta") == ["\\alpha", "\\beta", "EOF"])
    }

    // === Special characters ===

    @Test func braces() {
        #expect(lexTexts("{x}") == ["{", "x", "}", "EOF"])
    }

    @Test func caretUnderscore() {
        #expect(lexTexts("a^2_3") == ["a", "^", "2", "_", "3", "EOF"])
    }

    @Test func ampersand() {
        #expect(lexTexts("a&b") == ["a", "&", "b", "EOF"])
    }

    @Test func tildeAsActive() {
        #expect(lexTexts("a~b") == ["a", "~", "b", "EOF"])
    }

    // === Complex expressions ===

    @Test func fracExpression() {
        #expect(
            lexTexts("\\frac{a^2}{b}") == ["\\frac", "{", "a", "^", "2", "}", "{", "b", "}", "EOF"])
    }

    @Test func sqrtWithOptional() {
        #expect(lexTexts("\\sqrt[3]{x}") == ["\\sqrt", "[", "3", "]", "{", "x", "}", "EOF"])
    }

    @Test func complexFraction() {
        #expect(
            lexTexts("\\frac{a + b}{c - d}") == [
                "\\frac", "{", "a", " ", "+", " ", "b", "}", "{", "c", " ", "-", " ", "d", "}",
                "EOF",
            ])
    }

    @Test func sumWithLimits() {
        #expect(
            lexTexts("\\sum_{i=0}^{n}") == [
                "\\sum", "_", "{", "i", "=", "0", "}", "^", "{", "n", "}", "EOF",
            ])
    }

    @Test func matrixRow() {
        #expect(
            lexTexts("a & b \\\\ c & d") == [
                "a", " ", "&", " ", "b", " ", "\\\\", " ", "c", " ", "&", " ", "d", "EOF",
            ])
    }

    @Test func nestedFrac() {
        #expect(
            lexTexts("\\frac{\\sqrt{a^2+b^2}}{c}") == [
                "\\frac", "{", "\\sqrt", "{", "a", "^", "2", "+", "b", "^", "2", "}", "}", "{",
                "c", "}", "EOF",
            ])
    }

    // === Unicode ===

    @Test func unicodeChar() {
        #expect(lexTexts("α") == ["α", "EOF"])
    }

    @Test func unicodeMixed() {
        #expect(lexTexts("x + α") == ["x", " ", "+", " ", "α", "EOF"])
    }

    // === Edge cases ===

    @Test func backslashAtEnd() {
        #expect(lexTexts("\\") == ["\\", "EOF"])
    }

    @Test func multipleCommands() {
        #expect(lexTexts("\\alpha\\beta") == ["\\alpha", "\\beta", "EOF"])
    }

    @Test func commandThenDigit() {
        // \frac1 → \frac, 1 (digit is not a letter, stops control word)
        #expect(lexTexts("\\frac1") == ["\\frac", "1", "EOF"])
    }

    @Test func equalsSign() {
        #expect(lexTexts("x = 1") == ["x", " ", "=", " ", "1", "EOF"])
    }

    // === Source locations ===

    @Test func sourceLocations() {
        var lexer = Lexer("\\frac{a}")
        let t1 = lexer.lex()
        #expect(t1.text == "\\frac")
        #expect(t1.loc.start == 0)
        #expect(t1.loc.end == 5)

        let t2 = lexer.lex()
        #expect(t2.text == "{")
        #expect(t2.loc.start == 5)

        let t3 = lexer.lex()
        #expect(t3.text == "a")
        #expect(t3.loc.start == 6)

        let t4 = lexer.lex()
        #expect(t4.text == "}")
        #expect(t4.loc.start == 7)
    }

    // === Sequence conformance ===

    @Test func iterator() {
        let texts = Lexer("a+b").map(\.text)
        #expect(texts == ["a", "+", "b"])
    }

    // =========================================================================
    // KaTeX katex-spec.ts: "A parser" describe block — whitespace behavior
    // =========================================================================

    /// KaTeX: `it("should not fail on an empty string")`
    @Test func katexEmptyString() {
        #expect(lexTexts("") == ["EOF"])
    }

    /// KaTeX: `it("should ignore whitespace")` — ` x y ` parseLike `xy`
    /// At the lexer level: leading/trailing/middle spaces become space tokens.
    @Test func katexWhitespaceAroundAndBetween() {
        #expect(lexTexts(" x y ") == [" ", "x", " ", "y", " ", "EOF"])
    }

    /// KaTeX: `it("should ignore whitespace in atom")` — ` x ^ y ` parseLike `x^y`
    @Test func katexWhitespaceInAtom() {
        #expect(lexTexts(" x ^ y ") == [" ", "x", " ", "^", " ", "y", " ", "EOF"])
    }

    // =========================================================================
    // KaTeX katex-spec.ts: "A comment parser" describe block
    // =========================================================================

    /// KaTeX: `it("should parse comments at the end of a line")`
    @Test func katexCommentAtEndOfLine() {
        #expect(
            lexTexts("a^2 + b^2 = c^2 % Pythagoras' Theorem\n") == [
                "a", "^", "2", " ", "+", " ", "b", "^", "2", " ", "=", " ", "c", "^", "2", " ",
                "EOF",
            ])
    }

    /// KaTeX: `it("should parse comments at the start of a line")`
    @Test func katexCommentAtStartOfLine() {
        #expect(lexTexts("% comment\n") == ["EOF"])
    }

    /// KaTeX: `it("should parse multiple lines of comments in a row")`
    @Test func katexMultipleCommentLines() {
        #expect(lexTexts("% comment 1\n% comment 2\n") == ["EOF"])
    }

    /// KaTeX: `it("should parse comments between subscript and superscript")`
    @Test func katexCommentBetweenSubSup() {
        #expect(lexTexts("x_3 %comment\n^2") == ["x", "_", "3", " ", "^", "2", "EOF"])
        #expect(lexTexts("x_3^2") == ["x", "_", "3", "^", "2", "EOF"])
    }

    /// KaTeX: `"x^ %comment\n{2}"` parseLike `"x^{2}"`
    @Test func katexCommentAfterCaret() {
        #expect(lexTexts("x^ %comment\n{2}") == ["x", "^", " ", "{", "2", "}", "EOF"])
    }

    /// KaTeX: `"x^ %comment\n\\frac{1}{2}"` parseLike `"x^\frac{1}{2}"`
    @Test func katexCommentBeforeFrac() {
        #expect(
            lexTexts("x^ %comment\n\\frac{1}{2}") == [
                "x", "^", " ", "\\frac", "{", "1", "}", "{", "2", "}", "EOF",
            ])
    }

    /// KaTeX: `it("should parse comments in size and color groups")`
    @Test func katexCommentInKern() {
        #expect(lexTexts("\\kern{1 %kern\nem}") == ["\\kern", "{", "1", " ", "e", "m", "}", "EOF"])
    }

    @Test func katexCommentInKernNoBrace() {
        #expect(lexTexts("\\kern1 %kern\nem") == ["\\kern", "1", " ", "e", "m", "EOF"])
    }

    @Test func katexCommentInColor() {
        #expect(
            lexTexts("\\color{#f00%red\n}") == ["\\color", "{", "#", "f", "0", "0", "}", "EOF"])
    }

    /// KaTeX: `it("should parse comments before an expression")`
    @Test func katexCommentBeforeExpression() {
        #expect(lexTexts("%comment\n{2}") == lexTexts("{2}"))
    }

    /// KaTeX: `it("should not produce or consume space")`
    @Test func katexCommentNoSpaceProduced() {
        // % eats everything to \n inclusive; result is "hello" directly followed by "world"
        #expect(
            lexTexts("hello% comment 1\nworld") == [
                "h", "e", "l", "l", "o", "w", "o", "r", "l", "d", "EOF",
            ])
    }

    /// KaTeX: `"hello% comment\n\nworld"` — comment eats first \n, second \n becomes space
    @Test func katexCommentThenBlankLine() {
        #expect(
            lexTexts("hello% comment\n\nworld") == [
                "h", "e", "l", "l", "o", " ", "w", "o", "r", "l", "d", "EOF",
            ])
    }

    /// KaTeX: `it("should not include comments in the output")`
    @Test func katexCommentNotInOutput() {
        #expect(lexTexts("5 % comment\n") == ["5", " ", "EOF"])
    }

    /// KaTeX: `it("should not parse a comment without newline in strict mode")`
    /// Our lexer always skips comments (strict mode is a parser concern).
    @Test func katexCommentWithoutNewline() {
        #expect(lexTexts("x%y") == ["x", "EOF"])
    }

    // =========================================================================
    // KaTeX katex-spec.ts: backslash + newline in \text
    // =========================================================================

    /// KaTeX: `it("should handle backslash followed by newline")`
    @Test func katexBackslashWhitespaceSequence() {
        // \<space> is control space (eats trailing whitespace too)
        #expect(lexTexts("\\ \t\r \n \t\r ") == ["\\ ", "EOF"])
    }

    // =========================================================================
    // KaTeX Lexer.ts: additional behaviors from source code analysis
    // =========================================================================

    /// Combining diacritical marks (U+0300-U+036F) are grouped with their base
    /// character into a single token, matching KaTeX's regex behavior.
    @Test func combiningDiacriticalMark() {
        #expect(lexTexts("a\u{0301}") == ["a\u{0301}", "EOF"])
    }

    @Test func multipleCombiningMarks() {
        #expect(lexTexts("a\u{0301}\u{0303}") == ["a\u{0301}\u{0303}", "EOF"])
    }

    @Test func combiningMarkBetweenChars() {
        #expect(lexTexts("a\u{0301}b") == ["a\u{0301}", "b", "EOF"])
    }

    /// Ord characters from KaTeX's test
    @Test func katexOrdCharacters() {
        #expect(lexTexts("1234") == ["1", "2", "3", "4", "EOF"])
    }

    /// Various special symbols should be individual tokens
    @Test func katexSpecialSymbols() {
        #expect(lexTexts("|/@.\"'") == ["|", "/", "@", ".", "\"", "'", "EOF"])
    }

    /// KaTeX includes `@` in control word characters: `\\[a-zA-Z@]+`.
    /// This is needed for internal macros like `\@ifstar`, `\@firstoftwo`.
    @Test func atSignInControlWord() {
        #expect(lexTexts("\\foo@bar") == ["\\foo@bar", "EOF"])
    }

    @Test func atIfstar() {
        #expect(lexTexts("\\@ifstar") == ["\\@ifstar", "EOF"])
    }

    // =========================================================================
    // \verb / \verb* support
    // =========================================================================

    @Test func verbBasic() {
        #expect(lexTexts("\\verb|hello|") == ["\\verb|hello|", "EOF"])
    }

    @Test func verbStar() {
        #expect(lexTexts("\\verb*|hello world|") == ["\\verb*|hello world|", "EOF"])
    }

    @Test func verbWithSpecialChars() {
        #expect(lexTexts("\\verb!\\frac{a}{b}!") == ["\\verb!\\frac{a}{b}!", "EOF"])
    }

    @Test func verbInExpression() {
        #expect(
            lexTexts("x + \\verb|y| + z") == [
                "x", " ", "+", " ", "\\verb|y|", " ", "+", " ", "z", "EOF",
            ])
    }

    /// Unterminated \verb rewinds to the bare control word (KaTeX: the verb
    /// regex fails to match, and content is not swallowed as a delimiter).
    @Test func verbUnterminatedRewinds() {
        #expect(lexTexts("\\verb|ab") == ["\\verb", "|", "a", "b", "EOF"])
    }

    /// The verbatim body may not span a newline (KaTeX's verb regex cannot
    /// match across lines).
    @Test func verbNewlineBeforeCloseRewinds() {
        #expect(lexTexts("\\verb|a\nb|") == ["\\verb", "|", "a", " ", "b", "|", "EOF"])
    }

    @Test func verbStarUnterminatedRewinds() {
        #expect(lexTexts("\\verb*|a") == ["\\verb", "*", "|", "a", "EOF"])
    }

    /// Many consecutive comment lines must not overflow the stack: the lexer
    /// loops past comments instead of recursing (regression: `return lex()`
    /// crashed with SIGSEGV around ~50k comment lines).
    @Test func manyCommentLinesDoNotOverflowStack() {
        let input = String(repeating: "%c\n", count: 200_000) + "x"
        #expect(lexTexts(input) == ["x", "EOF"])
    }

    // =========================================================================
    // Real-world LaTeX expressions
    // =========================================================================

    /// Quadratic formula
    @Test func katexQuadraticFormula() {
        #expect(
            lexTexts("\\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}") == [
                "\\frac", "{", "-", "b", " ", "\\pm", "\\sqrt", "{", "b", "^", "2", "-", "4", "a",
                "c", "}", "}", "{", "2", "a", "}", "EOF",
            ])
    }

    /// Matrix environment
    @Test func katexMatrixBeginEnd() {
        #expect(
            lexTexts("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}") == [
                "\\begin", "{", "p", "m", "a", "t", "r", "i", "x", "}", " ", "a", " ", "&", " ",
                "b", " ", "\\\\", " ", "c", " ", "&", " ", "d", " ", "\\end", "{", "p", "m", "a",
                "t", "r", "i", "x", "}", "EOF",
            ])
    }
}
