// Port of RaTeX crates/ratex-parser/src/functions/math.rs

func registerMath(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\(", "$"],
        nodeType: "styling",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: false,
        infix: false,
        primitive: false,
        handler: handleMathSwitch)

    defineFunction(
        &map,
        names: ["\\)", "\\]"],
        nodeType: "text",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: false,
        infix: false,
        primitive: false,
        handler: handleMathClose)
}

private func handleMathSwitch(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let outerMode = ctx.parser.mode
    ctx.parser.switchMode(.math)
    let close = ctx.funcName == "\\(" ? "\\)" : "$"
    let body = try ctx.parser.parseExpression(breakOnInfix: false, breakOnTokenText: close)
    try ctx.parser.expect(close, consume: true)
    ctx.parser.switchMode(outerMode)

    return ParseNode(.styling(style: .text, body: body), mode: ctx.parser.mode)
}

private func handleMathClose(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    throw ParseError("Mismatched \(ctx.funcName)")
}
