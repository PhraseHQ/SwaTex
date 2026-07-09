func registerFont(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: [
            "\\mathrm",
            "\\mathit",
            "\\mathbf",
            "\\mathnormal",
            "\\mathsfit",
            "\\mathbb",
            "\\mathcal",
            "\\mathfrak",
            "\\mathscr",
            "\\mathsf",
            "\\mathtt",
            "\\Bbb",
            "\\bold",
            "\\frak",
        ],
        nodeType: "font",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: true,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleFont)

    // \boldsymbol and \bm produce mclass nodes
    defineFunction(
        &map,
        names: ["\\boldsymbol", "\\bm"],
        nodeType: "mclass",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleBoldsymbol)

    // \emph — emphasis (italic in text mode)
    defineFunction(
        &map,
        names: ["\\emph"],
        nodeType: "text",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: [.text],
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleEmph)

    // Old-style font switching commands: \rm, \sf, \tt, \bf, \it, \cal
    defineFunction(
        &map,
        names: ["\\rm", "\\sf", "\\tt", "\\bf", "\\it", "\\cal"],
        nodeType: "font",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleOldFont)
}

private func handleFont(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let body = ParseNode.normalizeArgument(args[0])

    let fontAliases: [(String, String)] = [
        ("\\Bbb", "\\mathbb"),
        ("\\bold", "\\mathbf"),
        ("\\frak", "\\mathfrak"),
        ("\\bm", "\\boldsymbol"),
    ]

    var funcName = ctx.funcName
    for (alias, target) in fontAliases {
        if funcName == alias {
            funcName = target
            break
        }
    }

    let fontName = funcName.hasPrefix("\\") ? String(funcName.dropFirst()) : funcName

    return ParseNode(.font(font: fontName, body: body), mode: ctx.parser.mode)
}

private func handleOldFont(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let fontName = "math" + ctx.funcName.dropFirst()
    let breakOn = ctx.breakOnTokenText
    let body = try ctx.parser.parseExpression(breakOnInfix: true, breakOnTokenText: breakOn)

    return ParseNode(
        .font(
            font: fontName,
            body: ParseNode(.ordGroup(body: body, semisimple: nil), mode: ctx.parser.mode)),
        mode: ctx.parser.mode)
}

private func handleBoldsymbol(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let body = args[0]

    return ParseNode(
        .mclass(
            mclass: "mord",
            body: [ParseNode(.font(font: "boldsymbol", body: body), mode: ctx.parser.mode)],
            isCharacterBox: false),
        mode: ctx.parser.mode)
}

private func handleEmph(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let bodyVec = ParseNode.ordArgument(args[0])
    return ParseNode(.text(body: bodyVec, font: "\\emph"), mode: ctx.parser.mode)
}
