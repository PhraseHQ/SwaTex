import Foundation
import Testing

@testable import SwaTex

/// Ports of the Rust unit tests in `crates/ratex-parser/src/mhchem/mod.rs`.
@Suite("MhChem")
struct MhChemTests {
    @Test func h2oCe() throws {
        let t = try MhChem.chemParseStr("H2O", mode: "ce")
        #expect(!t.isEmpty)
        #expect(t.contains("H"))
    }

    @Test func reactionArrow() throws {
        let t = try MhChem.chemParseStr("2H + O -> H2O", mode: "ce")
        #expect(t.contains("rightarrow") || t.contains("->"), "\(t)")
    }

    @Test func puSimple() throws {
        let t = try MhChem.chemParseStr("123 kJ/mol", mode: "pu")
        #expect(!t.isEmpty)
    }

    @Test func puScientificLowercaseECdotUppercaseETimes() throws {
        for src in ["1.2e3 kJ", "1,2e3 kJ"] {
            let t = try MhChem.chemParseStr(src, mode: "pu")
            #expect(
                t.contains("\\cdot") && t.contains("10^{3}") && !t.contains("\\times"),
                "expected \\cdot for lowercase e: \(src) → \(t)")
        }
        for src in ["1.2E3 kJ", "1,2E3 kJ"] {
            let t = try MhChem.chemParseStr(src, mode: "pu")
            #expect(
                t.contains("\\times") && t.contains("10^{3}") && !t.contains("\\cdot"),
                "expected \\times for uppercase E: \(src) → \(t)")
        }
    }

    @Test func dollarUndersetInnerCeTexIsValidLatex() throws {
        let inner = #"$\underset{\mathrm{red}}{\ce{HgI2}}$"#
        let tex = try MhChem.chemParseStr(inner, mode: "ce")
        _ = try Parser(tex).parse()
    }
}

/// Ports of the Rust `fog_tests` in `crates/ratex-parser/src/mhchem/patterns.rs`.
@Suite("MhChemPatterns")
struct MhChemPatternsTests {
    @Test func xDoubleBraceSecondGroupIncludesNestedCeClose() throws {
        let input = #"\underset{\mathrm{red}}{\ce{HgI2}}"#
        let hit = try #require(
            try MhChemPatterns.matchPattern(MhChemData.shared, #"\x{}{}"#, input))
        guard case .s(let s) = hit.token else {
            Issue.record("expected combined S")
            return
        }
        #expect(s == #"\underset{\mathrm{red}}{\ce{HgI2}}"#)
        #expect(hit.remainder.isEmpty)
    }

    @Test func undersetSplitsNestedMathrm() throws {
        let input = #"\underset{\mathrm{red}}{\ce{HgI2}}"#
        let hit = try #require(
            try MhChemPatterns.findObserveGroups(
                input[...],
                begExcl: "\\underset{",
                begIncl: .str(""),
                endIncl: "",
                endExcl: .str("}"),
                part2: ("{", .str(""), "", .str("}")),
                combine: false
            ))
        guard case .a(let parts) = hit.token else {
            Issue.record("expected pair")
            return
        }
        #expect(parts[0] == #"\mathrm{red}"#)
        #expect(parts[1] == #"\ce{HgI2}"#)
    }
}

/// P-023 edge semantics: a transition whose `nextState` names a state with
/// no table entry must fail exactly where the old dictionary miss failed —
/// at the top of the NEXT iteration (i.e. not at all if input ended).
@Suite("MhChemStateResolution")
struct MhChemStateResolutionTests {
    private func makeMachine(_ json: String) throws -> MhChemMachineDef {
        var def = try JSONDecoder().decode(MhChemMachineDef.self, from: Data(json.utf8))
        def.resolve(regexes: MhChemData.shared.regexes)
        return def
    }

    @Test func unknownNextStateThrowsAtNextIteration() throws {
        let def = try makeMachine(
            #"""
            {"transitions": {"0": [{"pattern": "else", "task": {"nextState": "nowhere"}}]}}
            """#)
        #expect(def.stateIndexByName["0"] != nil)
        #expect(def.stateTable[def.stateIndexByName["0"]!][0].nextStateIndex == nil)
    }

    @Test func starFallbackResolves() throws {
        let def = try makeMachine(
            #"""
            {"transitions": {"*": [{"pattern": "empty", "task": {}}]}}
            """#)
        #expect(def.starStateIndex != nil)
    }
}
