import Testing

@testable import SwaTex

/// Exhaustive coverage of the Unicode superscript/subscript character map
/// (KaTeX `unicodeSupOrSub`): every mapped character must translate to the
/// right base character and sub/sup side, and parsing `x<char>` must produce
/// a `supsub` node.
@Suite("UnicodeSupSubCoverage")
struct UnicodeSupSubCoverageTests {
    /// (character, mapped text, isSubscript) — mirrors KaTeX's table.
    static let mappings: [(Unicode.Scalar, String, Bool)] = [
        // Subscript digits
        ("\u{2080}", "0", true), ("\u{2081}", "1", true), ("\u{2082}", "2", true),
        ("\u{2083}", "3", true), ("\u{2084}", "4", true), ("\u{2085}", "5", true),
        ("\u{2086}", "6", true), ("\u{2087}", "7", true), ("\u{2088}", "8", true),
        ("\u{2089}", "9", true),
        // Subscript operators
        ("\u{208A}", "+", true), ("\u{208B}", "\u{2212}", true), ("\u{208C}", "=", true),
        ("\u{208D}", "(", true), ("\u{208E}", ")", true),
        // Subscript letters
        ("\u{2090}", "a", true), ("\u{2091}", "e", true), ("\u{2092}", "o", true),
        ("\u{2093}", "x", true), ("\u{2095}", "h", true), ("\u{2096}", "k", true),
        ("\u{2097}", "l", true), ("\u{2098}", "m", true), ("\u{2099}", "n", true),
        ("\u{209A}", "p", true), ("\u{209B}", "s", true), ("\u{209C}", "t", true),
        ("\u{1D62}", "i", true), ("\u{1D63}", "r", true), ("\u{1D64}", "u", true),
        ("\u{1D65}", "v", true), ("\u{2C7C}", "j", true),
        // Subscript Greek
        ("\u{1D66}", "\u{03B2}", true), ("\u{1D67}", "\u{03B3}", true),
        ("\u{1D68}", "\u{03C1}", true), ("\u{1D69}", "\u{03C6}", true),
        ("\u{1D6A}", "\u{03C7}", true),
        // Superscript digits
        ("\u{2070}", "0", false), ("\u{00B9}", "1", false), ("\u{00B2}", "2", false),
        ("\u{00B3}", "3", false), ("\u{2074}", "4", false), ("\u{2075}", "5", false),
        ("\u{2076}", "6", false), ("\u{2077}", "7", false), ("\u{2078}", "8", false),
        ("\u{2079}", "9", false),
        // Superscript operators
        ("\u{207A}", "+", false), ("\u{207B}", "\u{2212}", false), ("\u{207C}", "=", false),
        ("\u{207D}", "(", false), ("\u{207E}", ")", false),
        // Superscript lowercase letters
        ("\u{2071}", "i", false), ("\u{207F}", "n", false), ("\u{1D43}", "a", false),
        ("\u{1D47}", "b", false), ("\u{1D48}", "d", false), ("\u{1D49}", "e", false),
        ("\u{1D4D}", "g", false), ("\u{02B0}", "h", false), ("\u{02B2}", "j", false),
        ("\u{1D4F}", "k", false), ("\u{02E1}", "l", false), ("\u{1D50}", "m", false),
        ("\u{1D52}", "o", false), ("\u{1D56}", "p", false), ("\u{02B3}", "r", false),
        ("\u{02E2}", "s", false), ("\u{1D57}", "t", false), ("\u{1D58}", "u", false),
        ("\u{1D5B}", "v", false), ("\u{02B7}", "w", false), ("\u{02E3}", "x", false),
        ("\u{02B8}", "y", false),
        // Superscript uppercase letters
        ("\u{1D2C}", "A", false), ("\u{1D2E}", "B", false), ("\u{1D30}", "D", false),
        ("\u{1D31}", "E", false), ("\u{1D33}", "G", false), ("\u{1D34}", "H", false),
        ("\u{1D35}", "I", false), ("\u{1D36}", "J", false), ("\u{1D37}", "K", false),
        ("\u{1D38}", "L", false), ("\u{1D39}", "M", false), ("\u{1D3A}", "N", false),
        ("\u{1D3C}", "O", false), ("\u{1D3E}", "P", false), ("\u{1D3F}", "R", false),
        ("\u{1D40}", "T", false), ("\u{1D41}", "U", false), ("\u{1D42}", "W", false),
        // Superscript Greek
        ("\u{1D5D}", "\u{03B2}", false), ("\u{1D5E}", "\u{03B3}", false),
        ("\u{1D5F}", "\u{03B4}", false), ("\u{1D60}", "\u{03C6}", false),
        ("\u{1D61}", "\u{03C7}", false), ("\u{1DBF}", "\u{03B8}", false),
    ]

    @Test(arguments: 0..<mappings.count)
    func mapping(_ i: Int) {
        let (ch, mapped, isSub) = Self.mappings[i]
        let result = unicodeSubSup(ch)
        #expect(result?.mapped == mapped)
        #expect(result?.isSub == isSub)
    }

    @Test func unmappedCharacters() {
        #expect(unicodeSubSup("x") == nil)
        #expect(unicodeSubSup("\u{2094}") == nil)  // ₔ schwa — not in KaTeX's table
        #expect(unicodeSubSup("\u{1D2D}") == nil)  // ᴭ — not in KaTeX's table
    }

    /// Every mapped character after a base must parse to a supsub node whose
    /// sub/sup side matches the table.
    @Test(arguments: 0..<mappings.count)
    func parsesAsSupSub(_ i: Int) throws {
        let (ch, _, isSub) = Self.mappings[i]
        let nodes = try parseLaTeX("x\(Character(ch))")
        try #require(nodes.count == 1)
        guard case let .supSub(base, sup, sub) = nodes[0].kind else {
            Issue.record("expected supsub for x\(Character(ch)), got \(nodes[0].typeName)")
            return
        }
        #expect(base?.symbolText == "x")
        #expect((sub != nil) == isSub)
        #expect((sup != nil) == !isSub)
    }
}
