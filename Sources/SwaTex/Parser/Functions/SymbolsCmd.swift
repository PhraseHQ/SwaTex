// Port of RaTeX crates/ratex-parser/src/functions/symbols_cmd.rs

func registerSymbolsCmd(_ map: inout [String: FunctionSpec]) {
    // Symbol commands like \alpha, \beta, \infty, etc. are NOT registered as functions.
    // They are handled by Parser.parseSymbolInner via the font symbol table lookup.
    // This matches KaTeX's behavior where symbols.js defines these characters
    // and Parser.parseSymbol() resolves them.
}
