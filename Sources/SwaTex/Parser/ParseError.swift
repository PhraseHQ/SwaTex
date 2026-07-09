/// Error type for the parser, modeled after KaTeX's ParseError.
public struct ParseError: Error, Sendable {
    public var message: String
    public var loc: SourceLocation?

    public init(_ message: String, token: Token? = nil) {
        self.message = message
        self.loc = token?.loc
    }

    public init(_ message: String, at loc: SourceLocation) {
        self.message = message
        self.loc = loc
    }

    public static var recursionLimitExceeded: ParseError {
        ParseError("Recursion limit exceeded")
    }
}

extension ParseError: CustomStringConvertible {
    public var description: String {
        if let loc {
            "ParseError at position \(loc.start): \(message)"
        } else {
            "ParseError: \(message)"
        }
    }
}
