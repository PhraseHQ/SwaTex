// Port of RaTeX crates/ratex-parser/src/functions/nonumber.rs

func registerNoNumber(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\nonumber", "\\notag"],
        nodeType: "nonumber",
        numArgs: 0,
        handler: handleNoNumber)
}

private func handleNoNumber(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    ParseNode(.noNumber, mode: ctx.parser.mode)
}
