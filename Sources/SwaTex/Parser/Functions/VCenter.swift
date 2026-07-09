// Port of RaTeX crates/ratex-parser/src/functions/vcenter.rs

func registerVCenter(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\vcenter"],
        nodeType: "vcenter",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: [.original],
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleVCenter)
}

private func handleVCenter(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    ParseNode(.vcenter(body: args[0]), mode: ctx.parser.mode)
}
