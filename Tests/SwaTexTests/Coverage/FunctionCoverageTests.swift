import Foundation
import Testing

@testable import SwaTex

/// Coverage-driven tests for function handlers, the formula cache, the SVG
/// renderer, and the mhchem module. Wherever possible the gaps are reached
/// through real LaTeX inputs via the public pipeline; direct component calls
/// are used only where an input cannot reach the branch.
@Suite("Function handler coverage")
struct FunctionCoverageTests {
    /// Parse `latex` and return the thrown error's description, or nil on
    /// success.
    private func parseFailure(_ latex: String) -> String? {
        do {
            _ = try SwaTexEngine.displayList(for: latex)
            return nil
        } catch {
            return "\(error)"
        }
    }

    private func parses(_ latex: String) -> Bool {
        parseFailure(latex) == nil
    }

    // ── Functions/ handlers ─────────────────────────────────────────────

    @Test func delimSizingRejectsInvalidSymbolDelimiter() {
        let msg = parseFailure(#"\bigl a"#)
        #expect(msg?.contains("Invalid delimiter 'a' after '\\bigl'") == true)
    }

    @Test func mathCloseTokensOutsideMathAreMismatched() {
        #expect(parseFailure(#"\text{\)}"#)?.contains("Mismatched \\)") == true)
        #expect(parseFailure(#"\text{\]}"#)?.contains("Mismatched \\]") == true)
    }

    @Test func defRejectsNonNumericParameter() {
        let msg = parseFailure(#"\def\f#a{x}"#)
        #expect(msg?.contains("Invalid argument number \"a\"") == true)
    }

    @Test func defRejectsEOFInParameterText() {
        let msg = parseFailure(#"\def\f x"#)
        #expect(msg?.contains("Expected a macro definition") == true)
    }

    @Test func globalPrefixRejectsShadowedDefiner() {
        // `\gdef` is shadowed by an empty macro, so after `\global` rewrites
        // `\def` → `\gdef`, parseFunction expands it away and finds no
        // function to parse.
        let msg = parseFailure(#"\def\gdef{}\global\def\a{1}"#)
        #expect(msg?.contains("Invalid token after macro prefix") == true)
    }

    @Test func letConsumesSpaceAfterEquals() {
        // `\let\a= b` — the optional `=` may be followed by one space token.
        #expect(parses(#"\let\a= b \a"#))
        #expect(parses(#"\long\long\def\b{2}\b"#))
    }

    @Test func environmentNameVariants() {
        // Atom characters are legal in environment names.
        #expect(parseFailure(#"\begin{a+}x\end{a+}"#)?.contains("No such environment: a+") == true)
        // Non-symbol nodes in the name group are rejected.
        let msg = parseFailure(#"\begin{a\hspace{1em}}x"#)
        #expect(msg?.contains("Invalid environment name character") == true)
        // `\ldots` in text mode is an *atom* (inner family) — atoms are
        // legal name characters.
        #expect(parseFailure(#"\begin{a\ldots}x"#)?.contains("No such environment") == true)
    }

    @Test func tagRequiresAnArgument() {
        #expect(parseFailure(#"x\tag"#)?.contains("\\tag requires an argument") == true)
        // A braceless single-token argument is accepted as-is.
        #expect(parses(#"x\tag5"#))
    }

    @Test func crParsesOptionalSize() {
        #expect(parses(#"\begin{matrix}a\\[1ex]b\end{matrix}"#))
        // Top-level `\\` goes through the cr handler, including its
        // optional [size].
        #expect(parses(#"a\\[1em]b"#))
    }

    @Test func genfracArgumentShapes() {
        // Braceless delimiters and style digit.
        #expect(parses(#"\genfrac(){0pt}1{a}{b}"#))
        // Empty delimiter groups and empty style group.
        #expect(parses(#"\genfrac{}{}{0pt}{}{a}{b}"#))
        // A braceless punct atom as delimiter.
        #expect(parses(#"\genfrac\ldotp\ldotp{0pt}{1}{a}{b}"#))
    }

    @Test func binrelClassifiesBareArguments() {
        #expect(parses(#"\@binrel+{x}"#))
        #expect(parses(#"\@binrel{+}{x}"#))
        #expect(parses(#"\pmb ="#))
        #expect(parses(#"\pmb{}"#))
    }

    // ── mhchem: real inputs ─────────────────────────────────────────────

    @Test func mhchemSubscriptCommandForms() {
        // `_\x` hand matcher (`^_(\\[a-zA-Z]+)\s*`), with and without
        // trailing space.
        #expect(parses(#"\ce{H_\alpha}"#))
        #expect(parses(#"\ce{A_\beta B}"#))
    }

    @Test func mhchemUnclosedDollarGroup() {
        // `$a` never closes: findObserveGroups scans to the end of input and
        // gives up; the mhchem output then fails to re-parse as LaTeX.
        #expect(parseFailure(#"\ce{$a}"#) != nil)
    }

    @Test func mhchemEngineRejectsUnmatchableCharacter() {
        // "\r" in `ce`: the zero-width `empty` pattern (ICU `$` before one
        // final line terminator) matches without consuming, looping until
        // the engine's watchdog fires.
        do {
            _ = try MhChemEngine.goMachine(MhChemData.shared, input: "\r", machine: "ce")
            Issue.record("expected mhchem bug U (watchdog)")
        } catch {
            #expect("\(error.description)".contains("mhchem bug U"))
        }
        // "\r\r" in `9,9` (state 0 has only empty/,/else): `empty` needs a
        // *single* final terminator, `else` (ICU `.`) rejects terminators —
        // no transition matches at all.
        do {
            _ = try MhChemEngine.goMachine(MhChemData.shared, input: "\r\r", machine: "9,9")
            Issue.record("expected mhchem bug U (no matching transition)")
        } catch {
            #expect("\(error.description)".contains("mhchem bug U"))
        }
    }

    /// Data invariants backing the INTENTIONALLY UNCOVERED markers in
    /// MhChemEngine: every vendored machine has a "*" fallback state, so
    /// `stateIndex ?? starStateIndex` never fails.
    @Test func mhchemMachineDataInvariants() {
        let machines = MhChemData.shared.machines
        #expect(!machines.isEmpty)
        for (name, mdef) in machines {
            #expect(mdef.starStateIndex != nil, "machine \(name) lacks a '*' state")
        }
    }

    // ── mhchem: direct component calls ──────────────────────────────────

    @Test func mhchemPatternDirectGaps() throws {
        let data = MhChemData.shared

        // Unclosed `$...$`: scanEnd exhausts the input without finding `$`.
        #expect(try MhChemPatterns.matchPattern(data, "$...$", "$abc") == nil)

        // `\color(...){(...)}2` uses a regex *end* side (lookahead before
        // `{`), driving the `.re` arm of scanEnd.
        let colorHit = try MhChemPatterns.matchPattern(
            data, "\\color(...){(...)}2", "\\color\\blue{AB}")
        #expect(colorHit != nil)
        if case .a(let parts)? = colorHit?.token {
            #expect(parts == ["\\blue", "AB"])
        } else {
            Issue.record("expected pair token from \\color(...){(...)}2")
        }

        // The all-optional scientific-number pattern matches the empty
        // string on unrelated input and must report "no match".
        #expect(try MhChemPatterns.matchPattern(data, "(-)(9.,9)(e)(99)", "x") == nil)

        // `formula$` explicitly rejects a parenthesized-lowercase-only match.
        #expect(try MhChemPatterns.matchPattern(data, "formula$", "(aq)") == nil)
    }

    @Test func mhchemRegexTwoGroupToken() throws {
        // No vendored pattern has two capture groups; the KaTeX group
        // convention (group 2 non-empty → pair) is exercised directly.
        let re = try MhChemRegex("^(a+)(b+)")
        let kind = MhChemPatterns.resolveKind("two-groups", regexes: ["two-groups": re])
        let hit = try MhChemPatterns.match(kind, "aabX"[...])
        if case .a(let parts)? = hit?.token {
            #expect(parts == ["aa", "b"])
        } else {
            Issue.record("expected pair token from two-group regex")
        }
        #expect(hit.map { String($0.remainder) } == "X")
    }

    @Test func mhchemActionTokenShapeFallbacks() throws {
        let data = MhChemData.shared
        // `enumber` with a plain-string token (engine always sends a pair).
        let enumber = try MhChemActions.apply(
            data, machine: "pu", buffer: MhChemBuffer(), m: .s("x"),
            spec: MhChemActionSpec(type: "enumber", option: nil))
        #expect(enumber.isEmpty)
        // `1/2` whose token does not re-match the fraction regex.
        let half = try MhChemActions.apply(
            data, machine: "ce", buffer: MhChemBuffer(), m: .s("junk"),
            spec: MhChemActionSpec(type: "1/2", option: nil))
        #expect(half.isEmpty)
    }

    @Test func mhchemOptionAccessorMismatches() {
        #expect(MhChemOption.int(1).asBool == nil)
        #expect(MhChemOption.bool(true).asInt == nil)
        #expect(MhChemOption.int(1).asString == nil)
    }

    @Test func mhchemValueAccessorMismatches() {
        #expect(MhChemValue.array([]).asString == nil)
        #expect(MhChemValue.string("x").asArray == nil)
    }

    // ── DisplayItem wire format ─────────────────────────────────────────

    @Test func displayItemRejectsUnknownType() throws {
        let item = DisplayItem.rect(x: 0, y: 0, width: 1, height: 1, color: .black)
        let json = String(decoding: try JSONEncoder().encode([item]), as: UTF8.self)
        let bogus = json.replacingOccurrences(of: "Rect", with: "Bogus")
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode([DisplayItem].self, from: Data(bogus.utf8))
        }
    }

    // ── SVG renderer ────────────────────────────────────────────────────

    @Test func svgExpandExponentPointInsideDigits() {
        #expect(svgExpandExponent("1.25e1") == "12.5")
        #expect(svgExpandExponent("-1.25e1") == "-12.5")
    }

    @Test func svgStrokedPathWithNoCommandsEmitsNothing() {
        let list = DisplayList(
            items: [.path(x: 0, y: 0, commands: [], fill: false, color: .black)],
            width: 1, height: 1, depth: 0)
        let svg = renderToSVG(list, SVGOptions())
        #expect(!svg.contains("stroke-linecap"))
    }

    // ── FormulaCache: lead() re-check races ─────────────────────────────

    @Test func formulaCacheLeadRecheckFindsCachedEntry() throws {
        let cache = FormulaCache(capacity: 8)
        let expected = try cache.displayList(latex: "x", style: .display, color: .black)
        // A second leader for the same key re-checks under its own gate and
        // finds the freshly-published entry (the lead-vs-lead race window).
        let key = FormulaCache.Key(latex: "x", style: .display, color: .black)
        let raced = try cache.lead(key).get()
        #expect(raced.width == expected.width)
        #expect(cache.computeCount == 1)
    }

    @Test func formulaCacheLeadRecheckFollowsRacingLeader() throws {
        let cache = FormulaCache(capacity: 8)
        let expected = try SwaTexEngine.displayList(for: "y")
        let key = FormulaCache.Key(latex: "y", style: .display, color: .black)
        let other = FormulaCache.Flight()
        // Simulate a racing leader that published its flight and filled the
        // result before our lead()'s re-check runs.
        other.gate.withLock { slot in
            cache.storage.withLock { $0.flights[key] = other }
            slot = .success(expected)
        }
        let followed = try cache.lead(key).get()
        #expect(followed.width == expected.width)
        // The follower must not have computed anything itself.
        #expect(cache.computeCount == 0)
    }

    @Test func formulaCacheFastPathFollowsPublishedFlight() throws {
        let cache = FormulaCache(capacity: 8)
        let expected = try SwaTexEngine.displayList(for: "z")
        let key = FormulaCache.Key(latex: "z", style: .display, color: .black)
        let other = FormulaCache.Flight()
        // A leader has already published its flight and filled the result:
        // the public API's FAST lookup must take the `.follow` arm (not
        // lead a second computation).
        other.gate.withLock { slot in
            cache.storage.withLock { $0.flights[key] = other }
            slot = .success(expected)
        }
        let followed = try cache.displayList(latex: "z", style: .display, color: .black)
        #expect(followed.width == expected.width)
        #expect(cache.computeCount == 0)
    }
}
