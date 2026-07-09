/// Source location of a token in the original LaTeX string (UTF-8 byte offsets).
public struct SourceLocation: Hashable, Sendable, Codable {
    /// UTF-8 byte offset of the first byte of the token.
    public var start: Int
    /// UTF-8 byte offset one past the last byte of the token.
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    /// Compute a location spanning from `start` to `end`.
    public static func range(_ start: SourceLocation, _ end: SourceLocation) -> SourceLocation {
        SourceLocation(start: start.start, end: end.end)
    }
}

/// A lexed token from a LaTeX input string.
///
/// Mirrors KaTeX's Token class: the token's identity is determined by its
/// `text` field. The parser and macro expander interpret meaning.
public struct Token: Hashable, Sendable {
    /// The text content of the token.
    /// - For control sequences: `"\frac"`, `"\alpha"`, `"\ "` (control space)
    /// - For single chars: `"a"`, `"+"`, `"{"`, `"}"`, `"^"`, `"_"`
    /// - For whitespace: `" "`
    /// - For EOF: `"EOF"`
    public var text: String
    public var loc: SourceLocation
    /// When true, the macro expander should not expand this token.
    /// Set by `\noexpand`.
    public var noexpand: Bool
    /// When true, the token should be treated as `\relax` by the parser.
    /// Used in conjunction with `noexpand` for `\noexpand` semantics.
    public var treatAsRelax: Bool

    public init(_ text: String, start: Int, end: Int) {
        self.text = text
        self.loc = SourceLocation(start: start, end: end)
        self.noexpand = false
        self.treatAsRelax = false
    }

    public static func eof(at pos: Int) -> Token {
        Token("EOF", start: pos, end: pos)
    }

    public var isEOF: Bool {
        text == "EOF"
    }

    /// Whether this token is a control sequence (starts with `\`).
    public var isCommand: Bool {
        text.hasPrefix("\\")
    }

    /// Whether this is a whitespace token.
    public var isSpace: Bool {
        text == " "
    }

    /// For a control sequence, the name without the leading `\`.
    public var commandName: String? {
        isCommand ? String(text.dropFirst()) : nil
    }

    /// Create a new token spanning from `self` to `endToken` with the given text.
    public func range(to endToken: Token, text: String) -> Token {
        var token = Token(text, start: loc.start, end: endToken.loc.end)
        token.loc = .range(loc, endToken.loc)
        return token
    }
}
