import Testing

@testable import SwaTex

/// Direct unit tests of mhchem internals: state-machine dispatch errors,
/// pattern-matcher edge cases, input normalization, and error descriptions.
@Suite("MhChemInternal")
struct MhChemInternalTests {
    private let data = MhChemData.shared

    // ── goMachine dispatch ──────────────────────────────────────────────

    @Test func unknownMachineThrows() {
        #expect(throws: MhChemError.self) {
            _ = try MhChemEngine.goMachine(data, input: "x", machine: "bogus-machine")
        }
    }

    @Test func unknownModeThrows() {
        #expect(throws: MhChemError.self) {
            _ = try MhChem.chemParseStr("H2O", mode: "nope")
        }
    }

    // ── Input normalization (unicode minus/dash/ellipsis, newlines) ─────

    @Test func unicodeMinusNormalizes() throws {
        // U+2212 MINUS SIGN normalizes to '-' → same output as ASCII input
        let a = try MhChem.chemParseStr("A \u{2212} B", mode: "ce")
        let b = try MhChem.chemParseStr("A - B", mode: "ce")
        #expect(a == b)
    }

    @Test func enDashAndEmDashNormalize() throws {
        let ascii = try MhChem.chemParseStr("A-B", mode: "ce")
        #expect(try MhChem.chemParseStr("A\u{2013}B", mode: "ce") == ascii)
        #expect(try MhChem.chemParseStr("A\u{2014}B", mode: "ce") == ascii)
        #expect(try MhChem.chemParseStr("A\u{2010}B", mode: "ce") == ascii)
    }

    @Test func ellipsisNormalizes() throws {
        let a = try MhChem.chemParseStr("A \u{2026} B", mode: "ce")
        let b = try MhChem.chemParseStr("A ... B", mode: "ce")
        #expect(a == b)
    }

    @Test func newlineNormalizesToSpace() throws {
        let a = try MhChem.chemParseStr("A +\nB", mode: "ce")
        let b = try MhChem.chemParseStr("A + B", mode: "ce")
        #expect(a == b)
    }

    // ── Error paths ─────────────────────────────────────────────────────

    @Test func extraCloseBraceThrows() {
        // Unbalanced brace inside an arrow argument (verified against Rust)
        do {
            _ = try MhChem.chemParseStr("A ->[a}] B", mode: "ce")
            Issue.record("expected extraClose error")
        } catch {
            #expect(error.description == "extra close brace or missing open brace")
        }
    }

    @Test func extraCloseBraceInMathThrows() {
        #expect(throws: MhChemError.self) {
            _ = try MhChem.chemParseStr("$x} $", mode: "ce")
        }
    }

    @Test func errorDescriptions() {
        #expect(MhChemError.msg("boom").description == "mhchem: boom")
        #expect(
            MhChemError.extraClose.description
                == "extra close brace or missing open brace")
    }

    @Test func unknownPatternThrows() {
        do {
            _ = try MhChemPatterns.matchPattern(data, "no-such-pattern!", "abc")
            Issue.record("expected mhchem bug P error")
        } catch {
            #expect(error.description.contains("mhchem bug P"))
        }
    }

    // ── matchPattern behaviors ──────────────────────────────────────────

    @Test func numberPowPatternProducesArrayToken() throws {
        // "(-)(9)^(-9)" (pu number^power) yields an array token
        let hit = try MhChemPatterns.matchPattern(data, "(-)(9)^(-9)", "-2^24")
        let got = try #require(hit)
        guard case .a(let parts) = got.token else {
            Issue.record("expected array token, got \(got.token)")
            return
        }
        #expect(parts.count >= 2)
    }

    @Test func noMatchReturnsNil() throws {
        let hit = try MhChemPatterns.matchPattern(data, "digits", "abc")
        #expect(hit == nil)
    }

    @Test func orbitalPatternMatches() throws {
        let hit = try MhChemPatterns.matchPattern(data, "orbital", "2p3")
        #expect(hit != nil)
    }

    @Test func oxidationPatternMatches() throws {
        let hit = try MhChemPatterns.matchPattern(data, "oxidation$", "+IV")
        #expect(hit != nil)
        let miss = try MhChemPatterns.matchPattern(data, "oxidation$", "IV+")
        #expect(miss == nil)
    }

    // ── goMachine direct output shapes ──────────────────────────────────

    @Test func aMachineParsesAmount() throws {
        let values = try MhChemEngine.goMachine(data, input: "1/2", machine: "a")
        #expect(!values.isEmpty)
    }

    @Test func oMachineParsesText() throws {
        let values = try MhChemEngine.goMachine(data, input: "aq", machine: "o")
        #expect(!values.isEmpty)
    }
}
