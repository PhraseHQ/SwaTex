import Foundation

/// KaTeX mhchem 3.3.0 (chemistry notation): `\ce` and `\pu`.
///
/// Port of RaTeX's `mhchem/mod.rs`; the implementation lives under
/// `Parser/MhChem/` (engine, patterns, actions, texify, data).
enum MhChem {
    /// Reconstruct the raw source string from macro-argument tokens
    /// (which are in stack order, i.e. reversed). Mirrors KaTeX `chemParse`:
    /// a single space is inserted wherever consecutive tokens are not
    /// adjacent in the source (token locations are UTF-8 byte offsets).
    static func argTokensToString(_ tokens: [Token]) -> String {
        guard let last = tokens.last else {
            return ""
        }
        var expectedLoc = last.loc.start
        var out = ""
        for tok in tokens.reversed() {
            if tok.loc.start > expectedLoc {
                out += " "
                expectedLoc = tok.loc.start
            }
            out += tok.text
            expectedLoc += tok.text.utf8.count
        }
        return out
    }

    /// Translate an mhchem input string into TeX, using the given state
    /// machine ("ce" or "pu"). Wraps internal mhchem errors into `ParseError`
    /// the same way RaTeX's macro expander does (`\ce: mhchem: ...`).
    static func parse(_ input: String, stateMachine: String) throws(ParseError) -> String {
        do {
            return try chemParseStr(input, mode: stateMachine)
        } catch {
            throw ParseError("\\\(stateMachine): \(error.description)")
        }
    }

    /// Parse a `\ce` / `\pu` argument to a TeX fragment.
    static func chemParseStr(_ input: String, mode: String) throws(MhChemError) -> String {
        let data = MhChemData.shared
        guard mode == "ce" || mode == "pu" else {
            throw MhChemError.msg("unknown mhchem mode (expected ce|pu): \(mode)")
        }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let ast = try MhChemEngine.goMachine(data, input: trimmed, machine: mode)
        return try MhChemTexify.go(ast, isInner: false)
    }
}
