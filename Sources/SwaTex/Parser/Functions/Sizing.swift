private let sizeFuncs: [String] = [
    "\\tiny",
    "\\sixptsize",
    "\\scriptsize",
    "\\footnotesize",
    "\\small",
    "\\normalsize",
    "\\large",
    "\\Large",
    "\\LARGE",
    "\\huge",
    "\\Huge",
]

func registerSizing(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: sizeFuncs,
        nodeType: "sizing",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleSizing)
}

private func handleSizing(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let breakOn = ctx.breakOnTokenText
    let body = try ctx.parser.parseExpression(breakOnInfix: false, breakOnTokenText: breakOn)

    let size = UInt8(sizeFuncs.firstIndex(of: ctx.funcName).map { $0 + 1 } ?? 6)

    return ParseNode(.sizing(size: size, body: body), mode: ctx.parser.mode)
}
