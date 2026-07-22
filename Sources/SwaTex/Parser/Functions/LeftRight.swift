func registerLeftRight(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\left"],
        nodeType: "leftright",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: true,
        handler: handleLeft)

    defineFunction(
        &map,
        names: ["\\right"],
        nodeType: "leftright-right",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: true,
        handler: handleRight)

    defineFunction(
        &map,
        names: ["\\middle"],
        nodeType: "middle",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: true,
        handler: handleMiddle)
}

private func handleLeft(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let delim = try getDelimText(args[0])

    ctx.parser.leftrightDepth += 1
    let body = try ctx.parser.parseExpression(breakOnInfix: false, breakOnTokenText: nil)
    ctx.parser.leftrightDepth -= 1

    // Expect \right, but don't consume it yet
    try ctx.parser.expect("\\right", consume: false)
    // Parse \right as a function, which returns a leftright-right node
    let rightNode = try ctx.parser.parseFunction(breakOnTokenText: nil, name: nil)

    guard let rightNode, case let .leftRightRight(right, rightColor) = rightNode.kind else {
        // INTENTIONALLY UNCOVERED (defensive guard KEEP): the preceding
        // `expect("\\right")` guarantees the next token is the registered
        // \right function, whose handler always returns a `.leftRightRight`
        // node; `parseFunction` cannot return nil for it.
        throw ParseError("Expected \\right after \\left")
    }

    return ParseNode(
        .leftRight(body: body, left: delim, right: right, rightColor: rightColor),
        mode: ctx.parser.mode)
}

private func handleRight(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let delim = try getDelimText(args[0])

    return ParseNode(.leftRightRight(delim: delim, color: nil), mode: ctx.parser.mode)
}

private func handleMiddle(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let delim = try getDelimText(args[0])

    if ctx.parser.leftrightDepth <= 0 {
        throw ParseError("\\middle must be within \\left and \\right")
    }

    return ParseNode(.middle(delim: delim), mode: ctx.parser.mode)
}

private func getDelimText(_ node: ParseNode) throws(ParseError) -> String {
    if let text = node.symbolText {
        return text
    }
    throw ParseError("Invalid delimiter type '\(node.typeName)'")
}
