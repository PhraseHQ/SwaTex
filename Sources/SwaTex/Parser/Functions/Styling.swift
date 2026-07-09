func registerStyling(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: [
            "\\displaystyle",
            "\\textstyle",
            "\\scriptstyle",
            "\\scriptscriptstyle",
        ],
        nodeType: "styling",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: true,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleStyling)
}

private func handleStyling(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let breakOn = ctx.breakOnTokenText
    let body = try ctx.parser.parseExpression(breakOnInfix: true, breakOnTokenText: breakOn)

    let style: StyleStr =
        switch ctx.funcName {
        case "\\displaystyle": .display
        case "\\textstyle": .text
        case "\\scriptstyle": .script
        case "\\scriptscriptstyle": .scriptscript
        default: .text
        }

    return ParseNode(.styling(style: style, body: body), mode: ctx.parser.mode)
}
