func registerOverline(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\overline"],
        nodeType: "overline",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleOverline)

    defineFunction(
        &map,
        names: ["\\underline"],
        nodeType: "underline",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleUnderline)
}

private func handleOverline(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    ParseNode(.overline(body: args[0]), mode: ctx.parser.mode)
}

private func handleUnderline(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    ParseNode(.underline(body: args[0]), mode: ctx.parser.mode)
}
