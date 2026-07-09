// Port of RaTeX crates/ratex-parser/src/functions/horiz_brace.rs

func registerHorizBrace(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: [
            "\\overbrace",
            "\\underbrace",
            "\\overbracket",
            "\\underbracket",
        ],
        nodeType: "horizBrace",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleHorizBrace)
}

private func handleHorizBrace(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let base = args[0]
    let isOver = ctx.funcName.hasPrefix("\\over")

    return ParseNode(
        .horizBrace(label: ctx.funcName, isOver: isOver, base: base),
        mode: ctx.parser.mode)
}
