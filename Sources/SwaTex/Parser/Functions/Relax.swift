// Port of RaTeX crates/ratex-parser/src/functions/relax.rs

func registerRelax(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\relax"],
        nodeType: "internal",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: true,  // allowed_in_argument
        allowedInText: true,  // allowed_in_text
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleRelax)
}

private func handleRelax(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    ParseNode(.internalNode, mode: ctx.parser.mode)
}
