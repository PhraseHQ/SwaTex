import Foundation
import Testing

@testable import SwaTex

/// P-019 safety net: every hand-rolled mhchem matcher must be
/// observationally identical to the ICU regex it replaces — same match
/// range, same capture groups (including non-participation) — across the
/// whole `\ce` golden corpus (every scalar suffix of every formula) plus
/// crafted edge inputs. Also asserts every hand-table key names a pattern
/// that actually exists, so a typo'd key cannot silently never fire.
@Suite("MhChemHandMatcherDiff")
struct MhChemHandMatcherDiffTests {
    static let edgeInputs: [String] = [
        "", " ", "  x", "\t", "\u{A0}", "\u{2028}", "\n", "\r",
        "1", "12", "1.5", "12.", ".5", ".", "1,5", "1.2.3", "-", "+", "+-",
        "+/-", "\\pm", "\\pm 0", "$\\pm$0", "$\\pm$ 0", "+IV", "-IX", "+IVx",
        "IVX", "I", "<->", "<-->", "->", "<-", "<=>>", "<<=>", "<=>", "<<3",
        "<=", "\u{2192}", "\u{27F6}", "\u{21CC}", "=", "<", ">", "#",
        "\u{2261}", "v", "v)", "(v) ", "(v)x", "^", "(^),", "^_", "_^", "_",
        "^2", "^25x", "^{2}", "^-3", "^\u{661}\u{662}", "^-", "^\\alpha  x",
        "^a", "^\\", "^_x", "_3", "_+4", "_-", "_a", "_\\beta x", "_\\",
        "'", "''", "x", "xx", "x,", "i", "i,", "ix", "a", "z", "A",
        "\\alpha", "\\alphax", "\\alpha x", "\\alpha{}", "\\alpha{x",
        "\\omega\\Pi", "\\Omicron", "\\eta3", "\\theta", "abcXYZ", "H2O",
        "?@", "\u{3B1}\u{3C9}\u{391}\u{3A9}", "\u{3A2}", "Å",
        "(aq)", "(aq),", "(aqua)", "(s,", "(l)", "(v)", "($a$)", "(\\ca $c$)",
        "(\\ca$t$)", "pH2", "pH,", "pKa", "pOH!", "iPr,", "iBux", "pC",
        "2p3", "12sp", "1s2", "sp)", "3d ", "99f", "0sp", "sp",
        "...x", "....", "...", "..", ". x", "\u{22C5} y", "\u{B7}",
        "\u{2022}  z", "*  y", "* ", " * ", " . ", "//x", " // ", "/", " / y",
        "~", "|", "{}", "{", "}", "\\{", "[", "(", ")", "]", "\\}",
        "\\hline  x", "&x", "\\\\x", "\\\\", "\\,", "\\ ", "\\;", "\\:",
        "\\ca t", "\\ca\tt", "\\cat", "\\ca", "\\x{", "\\frac{", "\\frac{}{",
        "\\bond{-}", "\\color{red}x", "$a$/2", "x/2", "1/2", "1/2x", "1/2xy",
        "(1/2)", "$x$/9$y$", "1/2$b$!", ",x", "; y", ",", ".", "C[", "M[x",
        "T[", "Cx", "K,", "Na,", "NaCl,", "Fe2,", "i,", "Abc,", "Abcd,",
        "_{(aq)}", "_{(aqua)}", "_{(g)}x", "_{aq}", "12e", "-9.,9", "-3",
        "- x", "-,", "-(aq)", "-(aqua!", "-sp)", "-s", "-d,", "-p x", "-spx",
        "\u{661}\u{662}pt", "12\u{661}", "e", "E", "2.5e4", "\u{FEFF}",
        // ICU's actual \s / line-terminator sets (VT, FF, NEL) and CRLF —
        // the review that found the isSpace/atDollar bugs (P-019 follow-up):
        "\u{0B}", "\u{0C}", "\u{85}", "\r\n", "x\u{0B}", "x\r\n", " \r\n",
        ",\u{0B}\u{0B}", "-\u{85}x", "\\alpha\u{0B}x", "\u{0B}B", "\u{0C}B",
        "v\u{0B}", "-sp\u{0C}", "+IV\u{85}", "1/2\u{0B}", "(aq)\u{0C}",
        "^\u{0B}", "*\u{0B}\u{0B}y", ".\u{85}", "<\u{0B}", "x\u{2028}",
        "x\n\r\n", "x\r\r\n", "x\u{2029}", "\u{2029}",
        // Degenerate graphemes (combining marks straddling delimiters):
        "}\u{301}", "{\u{301}a", ")\u{301}", "e\u{301}m", "2e\u{301}m",
    ]

    /// All pattern sources that actually compile in the engine.
    static func knownSources() -> Set<String> {
        var known = Set(MhChemData.shared.regexes.values.map(\.pattern))
        known.formUnion(MhChemPatterns.staticPatternSources)
        return known
    }

    @Test func everyHandKeyNamesARealPattern() {
        let known = Self.knownSources()
        for key in MhChemHandMatchers.table.keys {
            #expect(known.contains(key), "hand-matcher key never fires: \(key)")
        }
    }

    @Test func handMatchersAreICUIdentical() throws {
        // Inputs: edge strings + every scalar suffix of every \ce golden
        // formula (the corpus the tokenizer actually sees).
        var inputs = Self.edgeInputs
        let url = try #require(
            Bundle.module.url(
                forResource: "test_case_ce", withExtension: "jsonl", subdirectory: "golden"))
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        for line in lines {
            guard
                let obj = try? JSONSerialization.jsonObject(
                    with: Data(line.utf8)) as? [String: Any],
                let formula = obj["input"] as? String
            else { continue }
            var idx = formula.startIndex
            while idx < formula.endIndex {
                inputs.append(String(formula[idx...]))
                idx = formula.unicodeScalars.index(after: idx)
            }
        }

        var compared = 0
        for source in MhChemHandMatchers.table.keys.sorted() {
            let hand = try MhChemRegex(source)
            let icu = try MhChemRegex(icuOnly: source)
            for input in inputs {
                let h = hand.match(input[...])
                let i = icu.match(input[...])
                let hDesc = describe(h, in: input)
                let iDesc = describe(i, in: input)
                if hDesc != iDesc {
                    Issue.record(
                        "pattern \(source) diverges on \(String(reflecting: input)): hand=\(hDesc) icu=\(iDesc)"
                    )
                    return
                }
                compared += 1
            }
        }
        #expect(compared > 100_000)
    }

    private func describe(_ m: MhChemRegex.Match?, in s: String) -> String {
        guard let m else { return "nil" }
        let whole = String(s[m.range])
        let groups = m.groups.map { r in r.map { String(s[$0]) } ?? "<nil>" }
        return "\(whole)|\(groups.joined(separator: ","))"
    }

    /// `scanEnd` matches end delimiters scalar-wise (Rust byte semantics):
    /// a combining mark straddling a closing brace neither hides the brace
    /// (the old Character-level `hasPrefix` did) nor throws `extraClose`
    /// (the first scalar-walk version did).
    @Test func scanEndTreatsCombiningMarkBraceAsDelimiter() throws {
        let input = "{a}\u{301}b"
        let hit = try MhChemPatterns.findObserveGroups(
            input[...], begExcl: "", begIncl: .str("{"), endIncl: "}",
            endExcl: .str(""), part2: nil, combine: false)
        let got = try #require(hit)
        guard case .s(let body) = got.token else {
            Issue.record("expected string token")
            return
        }
        #expect(body == "{a}")
        #expect(got.remainder == "\u{301}b")
    }
}

/// P-029 safety net: the hand-rolled action scanners must be
/// observationally identical to the reference regex semantics they encode.
/// `replaceCelsius` is pinned against live ICU global replacement (scalar
/// semantics — the JS/Rust reference behavior; the Swift `Regex` it
/// replaced used grapheme semantics, deliberately not preserved).
/// `isAllAsciiDigits` is pinned against the Swift `Regex` it replaced over
/// every input reachable through `normalizeInput` (no line terminators).
@Suite("MhChemActionScannerDiff")
struct MhChemActionScannerDiffTests {
    private func icuReplaceCelsius(_ s: String, unitLetter: String) throws -> String {
        let re = try NSRegularExpression(
            pattern: "\u{00B0}\(unitLetter)|\\^o\(unitLetter)|\\^\\{o\\}\(unitLetter)")
        let template = NSRegularExpression.escapedTemplate(for: "{}^{\\circ}\(unitLetter)")
        return re.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    @Test func replaceCelsiusMatchesICUReplacement() throws {
        var inputs: [String] = [
            "", "C", "F", "°", "°C", "°F", "° C", "°c", "^oC", "^oF", "^oc",
            "^{o}C", "^{o}F", "^{o C", "^{oC", "^o", "^", "^{", "^{o",
            "^{o}", "x°Cy", "25 °C", "25°C und 77 °F", "^oC^oC", "°C°C",
            "°F°C", "^{o}C^oC°C", "a^ob", "a^{o}b", "°^oC", "°°C",
            "\u{00B0}\u{00B0}", "℃", "℉", "e\u{301}°C", "°C\u{301}",
            "°\u{308}C", "\n°C\n", "12^{o}Fx", "$^oC$", "^{^{o}C}", "^o^oC",
            "^{o}}C", "^^oC", "25.0^{o}C 77^oF °F",
        ]
        // Exhaustive sweep: every 5-scalar string over the needle alphabet
        // covers all overlap/adjacency shapes up to the longest needle.
        let alphabet = ["°", "^", "o", "{", "}", "C"]
        for a in alphabet {
            for b in alphabet {
                for c in alphabet {
                    for d in alphabet {
                        for e in alphabet {
                            inputs.append(a + b + c + d + e)
                        }
                    }
                }
            }
        }
        for s in inputs {
            for (unit, byte) in [("C", UInt8(ascii: "C")), ("F", UInt8(ascii: "F"))] {
                let hand = MhChemActions.replaceCelsius(s, unit: byte)
                let icu = try icuReplaceCelsius(s, unitLetter: unit)
                #expect(hand == icu, "unit \(unit), input \(s.debugDescription)")
            }
        }
    }

    @Test func isAllAsciiDigitsMatchesReplacedRegex() throws {
        let re = try Regex(#"^[0-9]+$"#)
        // No line terminators: `normalizeInput` rewrites `\n` to a space,
        // and on terminator-free inputs Swift Regex `$`, JS `$`, and Rust
        // `$` all mean end-of-string, so the scanner is exact.
        let inputs = [
            "", "0", "9", "123", "0123456789", "12a", "a12", "1 2", " 12",
            "12 ", "-1", "+1", "1.5", "١٢٣", "12٣", "①", "12\u{00A0}",
            "\u{0660}", "e4", "12e", "۹", "𝟙", "3\u{301}", "/", ":",
            String(repeating: "7", count: 300),
        ]
        for s in inputs {
            let hand = MhChemActions.isAllAsciiDigits(s)
            let regex = (try? re.firstMatch(in: s)) != nil
            #expect(hand == regex, "\(s.debugDescription)")
        }
    }
}
