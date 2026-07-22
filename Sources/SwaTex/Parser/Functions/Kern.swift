func registerKern(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\kern", "\\mkern", "\\hskip", "\\mskip"],
        nodeType: "kern",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: [.size],
        allowedInArgument: true,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleKern)
}

private func handleKern(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let dimension: Measurement
    if case let .size(value, _) = args[0].kind {
        dimension = value
    } else {
        // INTENTIONALLY UNCOVERED (argType-guarantee KEEP): args[0] is
        // declared `.size`, and `parseSizeGroup` for a required argument
        // always returns a `.size` node or throws.
        dimension = Measurement(number: 0.0, unit: "em")
    }

    return ParseNode(.kern(dimension: dimension), mode: ctx.parser.mode)
}
