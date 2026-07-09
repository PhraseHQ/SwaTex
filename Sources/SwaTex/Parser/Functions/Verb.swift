// Port of RaTeX crates/ratex-parser/src/functions/verb.rs

func registerVerb(_ map: inout [String: FunctionSpec]) {
    // \verb is handled directly in Parser.parseSymbolInner
    // because it has special lexing requirements.
}
