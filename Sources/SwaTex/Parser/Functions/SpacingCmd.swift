func registerSpacing(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: [
            "\\quad",
            "\\qquad",
            "\\enspace",
            "\\thinspace",
            "\\medspace",
            "\\thickspace",
            "\\negthinspace",
            "\\negmedspace",
            "\\negthickspace",
            "\\nobreakspace",
        ],
        nodeType: "spacing",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: true,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleSpacing)

    defineFunction(
        &map,
        names: ["\\hspace"],
        nodeType: "kern",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: [.size],
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleHspace)

    // \hfill — produces a kern that fills available space
    defineFunction(
        &map,
        names: ["\\hfill"],
        nodeType: "spacing",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleSpacing)
}

private func handleSpacing(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    ParseNode(.spacing(text: ctx.funcName), mode: ctx.parser.mode)
}

private func handleHspace(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let dimension: Measurement
    if case let .size(value, _) = args[0].kind {
        dimension = value
    } else {
        dimension = Measurement(number: 0.0, unit: "em")
    }

    return ParseNode(.kern(dimension: dimension), mode: ctx.parser.mode)
}
