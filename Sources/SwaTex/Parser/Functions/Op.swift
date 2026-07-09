func registerOp(_ map: inout [String: FunctionSpec]) {
    // Limits, symbols (big operators) — includes single-char Unicode equivalents
    defineFunction(
        &map,
        names: [
            "\\coprod",
            "\\bigvee",
            "\\bigwedge",
            "\\biguplus",
            "\\bigcap",
            "\\bigcup",
            "\\intop",
            "\\prod",
            "\\sum",
            "\\bigotimes",
            "\\bigoplus",
            "\\bigodot",
            "\\bigsqcup",
            "\\smallint",
            "\u{220F}",
            "\u{2210}",
            "\u{2211}",
            "\u{22C0}",
            "\u{22C1}",
            "\u{22C2}",
            "\u{22C3}",
            "\u{2A00}",
            "\u{2A01}",
            "\u{2A02}",
            "\u{2A04}",
            "\u{2A06}",
        ],
        nodeType: "op",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleOpSymbolLimits)

    // No limits, not symbols (trig/log functions)
    defineFunction(
        &map,
        names: [
            "\\arcsin", "\\arccos", "\\arctan", "\\arctg", "\\arcctg", "\\arg", "\\ch", "\\cos",
            "\\cosec", "\\cosh", "\\cot", "\\cotg", "\\coth", "\\csc", "\\ctg", "\\cth", "\\deg",
            "\\dim", "\\exp", "\\hom", "\\ker", "\\lg", "\\ln", "\\log", "\\sec", "\\sin",
            "\\sinh", "\\sh", "\\tan", "\\tanh", "\\tg", "\\th",
        ],
        nodeType: "op",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleOpTextNolimits)

    // Limits, not symbols (det, gcd, lim, etc.)
    defineFunction(
        &map,
        names: [
            "\\det", "\\gcd", "\\inf", "\\lim", "\\max", "\\min", "\\Pr", "\\sup",
        ],
        nodeType: "op",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleOpTextLimits)

    // No limits, symbols (integrals) — including single-char Unicode equivalents.
    defineFunction(
        &map,
        names: [
            "\\int", "\\iint", "\\iiint", "\\oint", "\\oiint", "\\oiiint", "\u{222B}", "\u{222C}",
            "\u{222D}", "\u{222E}", "\u{222F}", "\u{2230}",
        ],
        nodeType: "op",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: true,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleOpSymbolNolimits)

    // \mathop
    defineFunction(
        &map,
        names: ["\\mathop"],
        nodeType: "op",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: true,
        handler: handleMathop)
}

private func singleCharBigOp(_ c: String) -> String? {
    switch c {
    case "\u{220F}": "\\prod"
    case "\u{2210}": "\\coprod"
    case "\u{2211}": "\\sum"
    case "\u{22C0}": "\\bigwedge"
    case "\u{22C1}": "\\bigvee"
    case "\u{22C2}": "\\bigcap"
    case "\u{22C3}": "\\bigcup"
    case "\u{2A00}": "\\bigodot"
    case "\u{2A01}": "\\bigoplus"
    case "\u{2A02}": "\\bigotimes"
    case "\u{2A04}": "\\biguplus"
    case "\u{2A06}": "\\bigsqcup"
    default: nil
    }
}

private func singleCharIntegral(_ c: String) -> String? {
    switch c {
    case "\u{222B}": "\\int"
    case "\u{222C}": "\\iint"
    case "\u{222D}": "\\iiint"
    case "\u{222E}": "\\oint"
    case "\u{222F}": "\\oiint"
    case "\u{2230}": "\\oiiint"
    default: nil
    }
}

private func handleOpSymbolLimits(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let name = singleCharBigOp(ctx.funcName) ?? ctx.funcName
    return ParseNode(
        .op(
            limits: true, alwaysHandleSupSub: nil, suppressBaseShift: nil,
            parentIsSupSub: false, symbol: true, name: name, body: nil),
        mode: ctx.parser.mode)
}

private func handleOpTextNolimits(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    ParseNode(
        .op(
            limits: false, alwaysHandleSupSub: nil, suppressBaseShift: nil,
            parentIsSupSub: false, symbol: false, name: ctx.funcName, body: nil),
        mode: ctx.parser.mode)
}

private func handleOpTextLimits(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    ParseNode(
        .op(
            limits: true, alwaysHandleSupSub: nil, suppressBaseShift: nil,
            parentIsSupSub: false, symbol: false, name: ctx.funcName, body: nil),
        mode: ctx.parser.mode)
}

private func handleOpSymbolNolimits(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let name = singleCharIntegral(ctx.funcName) ?? ctx.funcName
    return ParseNode(
        .op(
            limits: false, alwaysHandleSupSub: nil, suppressBaseShift: nil,
            parentIsSupSub: false, symbol: true, name: name, body: nil),
        mode: ctx.parser.mode)
}

private func handleMathop(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let body = ParseNode.ordArgument(args[0])
    return ParseNode(
        .op(
            limits: false, alwaysHandleSupSub: nil, suppressBaseShift: nil,
            parentIsSupSub: false, symbol: false, name: nil, body: body),
        mode: ctx.parser.mode)
}
