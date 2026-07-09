func registerColor(_ map: inout [String: FunctionSpec]) {
    // \textcolor[model]{color}{body}  (model is optional, MathJax extension)
    defineFunction(
        &map,
        names: ["\\textcolor"],
        nodeType: "color",
        numArgs: 2,
        numOptionalArgs: 1,
        argTypes: [.raw, .color, .original],
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleTextcolor)

    // \color[model]{color}  (model is optional, MathJax extension)
    defineFunction(
        &map,
        names: ["\\color"],
        nodeType: "color",
        numArgs: 1,
        numOptionalArgs: 1,
        argTypes: [.raw, .color],
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleColor)

    // \colorbox{color}{body}
    defineFunction(
        &map,
        names: ["\\colorbox"],
        nodeType: "enclose",
        numArgs: 2,
        numOptionalArgs: 0,
        argTypes: [.color, .text],
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleColorbox)

    // \fcolorbox{bordercolor}{bgcolor}{body}
    defineFunction(
        &map,
        names: ["\\fcolorbox"],
        nodeType: "enclose",
        numArgs: 3,
        numOptionalArgs: 0,
        argTypes: [.color, .color, .text],
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleFcolorbox)
}

private func handleTextcolor(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let color = encodeColor(try extractColor(args[0]), optArgs)
    let body = ParseNode.ordArgument(args[1])

    return ParseNode(.color(color: color, body: body), mode: ctx.parser.mode)
}

private func handleColor(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let color = encodeColor(try extractColor(args[0]), optArgs)
    let breakOn = ctx.breakOnTokenText
    let body = try ctx.parser.parseExpression(breakOnInfix: true, breakOnTokenText: breakOn)

    return ParseNode(.color(color: color, body: body), mode: ctx.parser.mode)
}

private func handleColorbox(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let color = try extractColor(args[0])
    let body = args[1]

    return ParseNode(
        .enclose(
            label: "\\colorbox", backgroundColor: color, borderColor: nil, body: body),
        mode: ctx.parser.mode)
}

private func handleFcolorbox(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let borderColor = try extractColor(args[0])
    let bgColor = try extractColor(args[1])
    let body = args[2]

    return ParseNode(
        .enclose(
            label: "\\fcolorbox", backgroundColor: bgColor, borderColor: borderColor,
            body: body),
        mode: ctx.parser.mode)
}

private func extractColor(_ node: ParseNode) throws(ParseError) -> String {
    if case let .colorToken(color) = node.kind {
        return color
    }
    throw ParseError("Expected color token")
}

/// When a MathJax color model opt-arg is present, encode as `[MODEL]value`.
private func encodeColor(_ value: String, _ optArgs: [ParseNode?]) -> String {
    if let first = optArgs.first, let node = first,
        case let .raw(string) = node.kind
    {
        var model = Substring(string)
        while let f = model.first, f.isWhitespace { model.removeFirst() }
        while let l = model.last, l.isWhitespace { model.removeLast() }
        if !model.isEmpty {
            return "[\(model)]\(value)"
        }
    }
    return value
}
