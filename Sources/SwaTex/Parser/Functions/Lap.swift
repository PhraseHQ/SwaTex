// Port of RaTeX crates/ratex-parser/src/functions/lap.rs

func registerLap(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\mathllap", "\\mathrlap", "\\mathclap"],
        nodeType: "lap",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleLap)
}

private func handleLap(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let alignment = String(ctx.funcName.dropFirst(5))

    return ParseNode(
        .lap(alignment: alignment, body: args[0]), mode: ctx.parser.mode)
}
