import Testing

@testable import SwaTex

/// P-026 safety net: the first-byte filters must never produce a false
/// negative (a name that IS a key but gets rejected before the dictionary
/// lookup), and the `SymbolInfo` ASCII fast table must agree with the
/// dictionary path it bypasses for every single-ASCII-character name.
@Suite("FirstByteSet")
struct FirstByteSetTests {
    @Test func emptySetRejectsEverything() {
        let set = FirstByteSet()
        #expect(!set.mayContain("a"))
        #expect(!set.mayContain("\\alpha"))
        #expect(!set.mayContain("α"))
        #expect(!set.mayContain(""))
    }

    @Test func insertedFirstBytesAreFound() {
        var set = FirstByteSet()
        set.insert(firstByteOf: "\\alpha")  // "\" = 0x5C (hi word)
        set.insert(firstByteOf: "-")  // 0x2D (lo word)
        #expect(set.mayContain("\\anything"))
        #expect(set.mayContain("--"))
        #expect(!set.mayContain("a"))
        #expect(!set.mayContain("α"))
        #expect(!set.mayContain(""))
    }

    @Test func nonASCIIFirstByteIsACatchAll() {
        var set = FirstByteSet()
        #expect(!set.mayContain("≠"))
        set.insert(firstByteOf: "≠")
        // Conservative: ANY non-ASCII first byte matches once one is inserted.
        #expect(set.mayContain("≠"))
        #expect(set.mayContain("α"))
        #expect(!set.mayContain("a"))
    }

    @Test func insertingEmptyNameIsANoOp() {
        var set = FirstByteSet()
        set.insert(firstByteOf: "")
        #expect(!set.mayContain(""))
        #expect(!set.mayContain("a"))
    }

    /// No false negatives against the real tables the filters guard.
    @Test func filtersCoverAllRealKeys() {
        for name in Functions.registry.keys {
            #expect(Functions.registryFirstBytes.mayContain(name), "\(name)")
        }
        for name in MacroExpander.builtinMacroTable.keys {
            #expect(MacroExpander.builtinMacroFirstBytes.mayContain(name), "\(name)")
        }
    }

    /// The 128-entry ASCII symbol table must agree with the dictionary path
    /// it bypasses — name lookup first, then codepoint, exactly as
    /// `SymbolInfo.init(name:mode:)` resolves — for every single-ASCII-
    /// character string, in both modes.
    @Test func symbolASCIITableMatchesDictionaryPath() {
        for c in UInt8(0)..<128 {
            let scalar = Unicode.Scalar(c)
            let name = String(scalar)
            for mode in [Mode.math, Mode.text] {
                let byName = mode == .math ? SymbolMaps.mathByName : SymbolMaps.textByName
                let byCodepoint =
                    mode == .math ? SymbolMaps.mathByCodepoint : SymbolMaps.textByCodepoint
                let expectedIdx = byName[name] ?? byCodepoint[scalar]
                let table = mode == .math ? SymbolMaps.mathASCII : SymbolMaps.textASCII
                let fastIdx = table[Int(c)] < 0 ? nil : table[Int(c)]
                #expect(fastIdx == expectedIdx, "U+\(String(c, radix: 16)) \(mode)")
                // And the public initializer's observable result matches.
                let info = SymbolInfo(name: name, mode: mode)
                #expect((info != nil) == (expectedIdx != nil), "U+\(String(c, radix: 16)) \(mode)")
            }
        }
    }

    /// End-to-end: macros whose names are NOT backslash commands still
    /// expand through the filtered `get` — ligatures ("--"), quotes ("`"),
    /// and non-ASCII names ("≠" is a builtin macro for \ne).
    @Test func filteredMacroLookupStillExpands() throws {
        let dash = try Parser("\\text{a--b}").parse()
        #expect(!dash.isEmpty)
        let ne = try Parser("a ≠ b").parse()
        #expect(!ne.isEmpty)
    }

    /// A macro defined mid-parse (new first byte) must be found afterwards.
    @Test func userDefinedMacroSetsItsFirstByte() throws {
        let nodes = try Parser("\\def\\zz{q}\\zz").parse()
        #expect(!nodes.isEmpty)
    }
}
