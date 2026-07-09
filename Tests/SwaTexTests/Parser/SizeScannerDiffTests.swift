import Testing

@testable import SwaTex

/// P-014 safety net (the size-group analogue of `MhChemHandMatcherDiffTests`):
/// the hand-rolled byte scanners must agree with the Swift `Regex`es they
/// replaced on all ASCII inputs — including every incremental prefix
/// `parseRegexGroup` generates while consuming a size token. The one
/// *deliberate* divergence (ASCII-only digits, matching KaTeX's JS `\d`
/// where Swift/Rust `\d` also accept Unicode digits) is asserted explicitly.
@Suite("SizeScannerDiff")
struct SizeScannerDiffTests {
    // The originals replaced by P-014.
    nonisolated(unsafe) static let prefixRegex =
        /^[-+]? *(?:$|\d+|\d+\.\d*|\.\d*) *[a-z]{0,2} *$/
    nonisolated(unsafe) static let sizeRegex =
        /([-+]?) *(\d+(?:\.\d*)?|\.\d+) *([a-z]{2})/

    static let seeds: [String] = [
        "", " ", "  ", "-", "+", "- ", "-1", "-1.", "-1.5", "-1.5e", "-1.5em",
        "-1.5em ", "2em", " -1.5pt ", "0pt", ".5em", "5.", "5.em", "..",
        "2.5.3", "em", "-em", "- em", "2em3", "2EM", "abc", "x2em", "1.em",
        "1..em", "12e", "12 em", "1,5em", "--2em", "+ .5 pt", "1.2.3em",
        "2e m", "2 e m", "2  em  ", "-.em", "-.", ".", "+.", "+.5", "mu",
        "-3mu", "150 fil", "1fill", "9 ex", "0", "00", "007pt", "2pt2",
        "pt2", " pt", "-  12  pt  ", "+2sp", "2bp", "\t2em", "2\tem",
    ]

    /// All inputs: seeds plus every prefix of every seed (what
    /// `parseRegexGroup` actually feeds the prefix matcher).
    static var inputs: [String] {
        var set = Set<String>()
        for s in seeds {
            var end = s.startIndex
            while end <= s.endIndex {
                set.insert(String(s[..<end]))
                if end == s.endIndex { break }
                end = s.index(after: end)
            }
        }
        return Array(set)
    }

    @Test func prefixScannerMatchesOriginalRegex() {
        for input in Self.inputs {
            let hand = Parser.sizePrefixMatches(input)
            let regex = input.wholeMatch(of: Self.prefixRegex) != nil
            #expect(hand == regex, "prefix diverges on \(String(reflecting: input))")
        }
    }

    @Test func sizeMatchAgreesWithOriginalRegex() {
        for input in Self.inputs {
            let hand = Parser.sizeMatch(input)
            let m = input.firstMatch(of: Self.sizeRegex)
            if let m {
                let expected = (String(m.output.1), String(m.output.2), String(m.output.3))
                #expect(hand != nil, "sizeMatch missed \(String(reflecting: input))")
                if let hand {
                    #expect(
                        hand.sign == expected.0 && hand.magnitude == expected.1
                            && hand.unit == expected.2,
                        "groups diverge on \(String(reflecting: input)): hand=\(hand) regex=\(expected)"
                    )
                }
            } else {
                #expect(hand == nil, "sizeMatch over-matched \(String(reflecting: input))")
            }
        }
    }

    @Test func combiningMarkUnitsMatchByCodeUnitByDesign() {
        // The scanners match code-unit style like KaTeX's JS regex: a
        // combining mark on the unit's last letter does not hide the unit
        // (Swift Regex's grapheme-cluster [a-z] rejected it).
        let input = "1 em\u{301}"
        #expect(input.firstMatch(of: Self.sizeRegex) == nil)  // old behavior
        let m = Parser.sizeMatch(input)
        #expect(m?.magnitude == "1" && m?.unit == "em")  // KaTeX-correct
    }

    @Test func unicodeDigitsAreRejectedByDesign() {
        // KaTeX's JS `\d` is ASCII-only; Swift Regex `\d` is not. The byte
        // scanner follows KaTeX (see P-014 in the performance log).
        #expect("٣em".wholeMatch(of: Self.prefixRegex) != nil)  // Swift Regex: accepts
        #expect(!Parser.sizePrefixMatches("٣em"))  // scanner: KaTeX-correct reject
        #expect(Parser.sizeMatch("٣em") == nil)
        // And the whole pipeline rejects it as an invalid size:
        #expect(throws: ParseError.self) { try parseLaTeX(#"\kern٣em x"#) }
    }
}
