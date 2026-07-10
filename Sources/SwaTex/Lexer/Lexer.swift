/// Lexer for LaTeX math input.
///
/// Follows KaTeX's lexing strategy:
/// - Control words: `\` followed by one or more ASCII letters or `@`
/// - Control symbols: `\` followed by a single non-letter character
/// - Control space: `\` followed by whitespace
/// - Verb: `\verb*<delim>...<delim>` or `\verb<delim>...<delim>`
/// - Comments: `%` through end of line (skipped)
/// - Whitespace: collapsed to a single space token
/// - Regular characters: character + any trailing combining diacritical marks
///
/// Operates on UTF-8 bytes; all positions are UTF-8 byte offsets.
public struct Lexer: Sendable {
    private let bytes: [UInt8]
    /// Current position in the input (UTF-8 byte offset).
    public private(set) var pos: Int
    /// Category codes. Currently only comment (14) and active (13) are used.
    /// `%` defaults to catcode 14 (comment), `~` to catcode 13 (active).
    /// The MacroExpander may change catcodes (e.g. `\makeatletter` sets `@` to 13).
    private var catcodes: [(char: Unicode.Scalar, code: UInt8)]

    public init(_ input: String) {
        self.init(bytes: Array(input.utf8))
    }

    /// Internal seam for tests: build a lexer over raw bytes, which may be
    /// malformed UTF-8 (the public `String` initializer cannot produce
    /// that). Used to exercise the mid-stream decode-failure guard.
    init(bytes: [UInt8]) {
        self.bytes = bytes
        self.pos = 0
        self.catcodes = [("%", 14), ("~", 13)]
    }

    /// Set the category code for a character.
    /// Used by MacroExpander for commands like `\makeatletter`.
    public mutating func setCatcode(_ ch: Unicode.Scalar, _ code: UInt8) {
        if let i = catcodes.firstIndex(where: { $0.char == ch }) {
            catcodes[i].code = code
        } else {
            // A character not already in the default table (covered by
            // DirectUnitTests via a novel active char).
            catcodes.append((ch, code))
        }
    }

    /// Get the catcode for a character (public for MacroExpander).
    public func catcode(_ ch: Unicode.Scalar) -> UInt8 {
        catcodes.first(where: { $0.char == ch })?.code ?? 0
    }

    private var atEnd: Bool {
        pos >= bytes.count
    }

    private func peekByte() -> UInt8? {
        pos < bytes.count ? bytes[pos] : nil
    }

    /// Decode the Unicode scalar at `offset` without advancing.
    /// Returns the scalar and its UTF-8 byte length.
    private func scalar(at offset: Int) -> (Unicode.Scalar, Int)? {
        guard offset < bytes.count else { return nil }
        let b0 = bytes[offset]
        if b0 < 0x80 {
            return (Unicode.Scalar(b0), 1)
        }
        let len: Int =
            b0 >= 0xF0 ? 4 : b0 >= 0xE0 ? 3 : 2
        guard offset + len <= bytes.count else { return nil }
        var value: UInt32 = UInt32(b0 & (0xFF >> UInt8(len + 1)))
        for i in 1..<len {
            value = value << 6 | UInt32(bytes[offset + i] & 0x3F)
        }
        guard let scalar = Unicode.Scalar(value) else { return nil }
        return (scalar, len)
    }

    private func currentScalar() -> (Unicode.Scalar, Int)? {
        scalar(at: pos)
    }

    @discardableResult
    private mutating func advanceScalar() -> Unicode.Scalar? {
        guard let (s, len) = scalar(at: pos) else { return nil }
        pos += len
        return s
    }

    private func text(from start: Int) -> String {
        String(decoding: bytes[start..<pos], as: UTF8.self)
    }

    private static func isWhitespace(_ b: UInt8) -> Bool {
        b == UInt8(ascii: " ") || b == UInt8(ascii: "\t")
            || b == UInt8(ascii: "\r") || b == UInt8(ascii: "\n")
    }

    /// KaTeX includes `@` in control word characters (`\\[a-zA-Z@]+`).
    private static func isControlWordChar(_ b: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(b)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(b)
            || b == UInt8(ascii: "@")
    }

    private static func isCombiningDiacritical(_ s: Unicode.Scalar) -> Bool {
        (0x0300...0x036F).contains(s.value)
    }

    private mutating func skipWhitespace() {
        while pos < bytes.count, Self.isWhitespace(bytes[pos]) {
            pos += 1
        }
    }

    /// Lex `\verb*<d>...<d>` or `\verb<d>...<d>` after `\verb` has been consumed.
    ///
    /// Mirrors KaTeX: the verbatim body may not contain a newline, and an
    /// unterminated `\verb` does not swallow its content. In both failure
    /// cases the lexer rewinds and returns the bare `\verb` control word,
    /// which the parser rejects with "\verb ended by end of line instead of
    /// matching delimiter" (matching KaTeX's `\verb` fallback macro).
    private mutating func lexVerb(start: Int) -> Token {
        let wordEnd = pos
        // Check for \verb* variant
        if peekByte() == UInt8(ascii: "*") {
            pos += 1
        }
        // The next character is the delimiter
        if let (delim, delimLen) = currentScalar(), delim != "\n" {
            pos += delimLen
            // Scan until the matching delimiter, stopping at end of line
            // (KaTeX's verb regex cannot match across newlines).
            while let (ch, chLen) = currentScalar(), ch != "\n" {
                pos += chLen
                if ch == delim {
                    return Token(text(from: start), start: start, end: pos)
                }
            }
        }
        // Unterminated \verb — rewind so the content re-lexes normally and
        // surface just the control word for the parser to reject.
        pos = wordEnd
        return Token(text(from: start), start: start, end: pos)
    }

    /// Lex a single token from the current position.
    public mutating func lex() -> Token {
        // Loop instead of recursing past comments: Swift does not guarantee
        // tail-call elimination for mutating methods, so `return lex()` after
        // a comment overflows the stack on inputs with many comment lines —
        // below the parser's StackGuard, which cannot catch it.
        while !atEnd {
            let start = pos
            guard let (ch, chLen) = currentScalar() else {
                // Mid-stream decode failure — only reachable with malformed
                // UTF-8 bytes (the `init(bytes:)` seam; the `String` initializer
                // cannot produce them). Covered by DirectUnitTests.
                return .eof(at: pos)
            }

            // Whitespace → single space token
            if let b = peekByte(), Self.isWhitespace(b) {
                skipWhitespace()
                return Token(" ", start: start, end: pos)
            }

            // Comment character (catcode 14, default `%`)
            if catcode(ch) == 14 {
                pos += chLen
                // Skip to end of line, then loop for the next real token
                while !atEnd {
                    if peekByte() == UInt8(ascii: "\n") {
                        pos += 1
                        break
                    }
                    pos += 1
                }
                continue
            }

            // Backslash → control sequence
            if ch == "\\" {
                pos += 1  // consume the backslash
                if atEnd {
                    return Token("\\", start: start, end: pos)
                }

                let nextByte = bytes[pos]

                if Self.isWhitespace(nextByte) {
                    // Control space: \<whitespace> → "\ " token, then skip trailing whitespace
                    pos += 1
                    skipWhitespace()
                    return Token("\\ ", start: start, end: pos)
                }

                if Self.isControlWordChar(nextByte) {
                    // Control word: \<letters or @>
                    while pos < bytes.count, Self.isControlWordChar(bytes[pos]) {
                        pos += 1
                    }
                    let text = text(from: start)

                    // Handle \verb and \verb* — verbatim content delimited by next char
                    if text == "\\verb" {
                        return lexVerb(start: start)
                    }

                    let end = pos
                    // Skip trailing whitespace after control word (KaTeX behavior)
                    skipWhitespace()
                    return Token(text, start: start, end: end)
                }

                // Control symbol: \<single non-letter char>
                advanceScalar()
                return Token(text(from: start), start: start, end: pos)
            }

            // Active character (catcode 13, default `~`) → single-char token
            if catcode(ch) == 13 {
                pos += chLen
                return Token(String(ch), start: start, end: pos)
            }

            // Regular character (including {, }, ^, _, &, etc.)
            // Consume trailing combining diacritical marks (U+0300–U+036F) to form
            // a single token, matching KaTeX's regex behavior.
            pos += chLen
            while let (next, nextLen) = currentScalar(), Self.isCombiningDiacritical(next) {
                pos += nextLen
            }
            return Token(text(from: start), start: start, end: pos)
        }
        return .eof(at: pos)
    }

    /// Lex all remaining tokens until EOF (inclusive).
    public mutating func lexAll() -> [Token] {
        var tokens: [Token] = []
        while true {
            let tok = lex()
            tokens.append(tok)
            if tok.isEOF { break }
        }
        return tokens
    }
}

extension Lexer: Sequence, IteratorProtocol {
    public mutating func next() -> Token? {
        let tok = lex()
        return tok.isEOF ? nil : tok
    }
}
