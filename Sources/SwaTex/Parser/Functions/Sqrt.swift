func registerSqrt(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\sqrt"],
        nodeType: "sqrt",
        numArgs: 1,
        numOptionalArgs: 1,  // one optional arg [n]
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleSqrt)
}

private func handleSqrt(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let index = optArgs.first.flatMap { $0 }
    let body = args[0]

    return ParseNode(.sqrt(body: body, index: index), mode: ctx.parser.mode)
}
