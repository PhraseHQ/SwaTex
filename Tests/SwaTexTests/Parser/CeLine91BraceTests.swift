import Testing

@testable import SwaTex

// Ported from ratex-parser/tests/ce_line91_brace.rs:
// Debug: lexer brace balance for nested \ce in \underset (golden case 0091).

@Suite("CeLine91Brace")
struct CeLine91BraceTests {
    @Test func lexerBalancesOuterCeBraces() throws {
        let s =
            #"\ce{Hg^2+ ->[I-]  $\underset{\mathrm{red}}{\ce{HgI2}}$  ->[I-]  $\underset{\mathrm{red}}{\ce{[Hg^{II}I4]^2-}}$}"#
        var lex = Lexer(s)
        #expect(lex.lex().text == #"\ce"#)
        #expect(lex.lex().text == "{")
        var depth = 1
        while true {
            let t = lex.lex()
            if t.isEOF {
                Issue.record("EOF with depth \(depth)")
                return
            }
            switch t.text {
            case "{": depth += 1
            case "}": depth -= 1
            default: break
            }
            if depth == 0 {
                break
            }
        }
    }

    @Test func macroExpanderConsumeArgAfterCe() throws {
        let s =
            #"\ce{Hg^2+ ->[I-]  $\underset{\mathrm{red}}{\ce{HgI2}}$  ->[I-]  $\underset{\mathrm{red}}{\ce{[Hg^{II}I4]^2-}}$}"#
        let g = MacroExpander(s, mode: .math)
        #expect(g.popToken().text == #"\ce"#)
        _ = try g.consumeArg()  // consume \ce arg
    }

    @Test func chemParseOutputThenParseFullTex() throws {
        let inner =
            #"Hg^2+ ->[I-]  $\underset{\mathrm{red}}{\ce{HgI2}}$  ->[I-]  $\underset{\mathrm{red}}{\ce{[Hg^{II}I4]^2-}}$"#
        let tex = try MhChem.chemParseStr(inner, mode: "ce")  // mhchem
        _ = try parseLaTeX(tex)  // expanded ce should parse
    }
}
