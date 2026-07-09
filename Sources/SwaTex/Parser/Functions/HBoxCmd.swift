// Port of RaTeX crates/ratex-parser/src/functions/hbox.rs

func registerHBox(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\hbox"],
        nodeType: "hbox",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: [.text],
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: true,
        handler: handleHBox)
}

private func handleHBox(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    ParseNode(.hbox(body: ParseNode.ordArgument(args[0])), mode: ctx.parser.mode)
}
