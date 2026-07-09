private struct DelimInfo {
    var mclass: String
    var size: UInt8
}

private func delimInfo(_ name: String) -> DelimInfo? {
    switch name {
    case "\\bigl": DelimInfo(mclass: "mopen", size: 1)
    case "\\Bigl": DelimInfo(mclass: "mopen", size: 2)
    case "\\biggl": DelimInfo(mclass: "mopen", size: 3)
    case "\\Biggl": DelimInfo(mclass: "mopen", size: 4)
    case "\\bigr": DelimInfo(mclass: "mclose", size: 1)
    case "\\Bigr": DelimInfo(mclass: "mclose", size: 2)
    case "\\biggr": DelimInfo(mclass: "mclose", size: 3)
    case "\\Biggr": DelimInfo(mclass: "mclose", size: 4)
    case "\\bigm": DelimInfo(mclass: "mrel", size: 1)
    case "\\Bigm": DelimInfo(mclass: "mrel", size: 2)
    case "\\biggm": DelimInfo(mclass: "mrel", size: 3)
    case "\\Biggm": DelimInfo(mclass: "mrel", size: 4)
    case "\\big": DelimInfo(mclass: "mord", size: 1)
    case "\\Big": DelimInfo(mclass: "mord", size: 2)
    case "\\bigg": DelimInfo(mclass: "mord", size: 3)
    case "\\Bigg": DelimInfo(mclass: "mord", size: 4)
    default: nil
    }
}

func registerDelimSizing(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: [
            "\\bigl", "\\Bigl", "\\biggl", "\\Biggl", "\\bigr", "\\Bigr", "\\biggr", "\\Biggr",
            "\\bigm", "\\Bigm", "\\biggm", "\\Biggm", "\\big", "\\Big", "\\bigg", "\\Bigg",
        ],
        nodeType: "delimsizing",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: [.primitive],
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleDelimsizing)
}

private func handleDelimsizing(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let delim = try checkDelimiter(args[0], funcName: ctx.funcName)
    let info = delimInfo(ctx.funcName)!

    return ParseNode(
        .delimSizing(size: info.size, mclass: info.mclass, delim: delim),
        mode: ctx.parser.mode)
}

private func checkDelimiter(
    _ node: ParseNode, funcName: String
) throws(ParseError) -> String {
    if let text = node.symbolText {
        if isValidDelimiter(text) {
            return text
        }
        throw ParseError("Invalid delimiter '\(text)' after '\(funcName)'")
    }
    throw ParseError("Invalid delimiter type '\(node.typeName)' after '\(funcName)'")
}

private func isValidDelimiter(_ text: String) -> Bool {
    switch text {
    case "(", "\\lparen",
        ")",
        "\\rparen",
        "[",
        "\\lbrack",
        "]",
        "\\rbrack",
        "\\{",
        "\\lbrace",
        "\\}",
        "\\rbrace",
        "\\lfloor",
        "\\rfloor",
        "\\lceil",
        "\\rceil",
        "<",
        ">",
        "\\langle",
        "\\rangle",
        "\\lt",
        "\\gt",
        "\\lvert",
        "\\rvert",
        "\\lVert",
        "\\rVert",
        "\\lgroup",
        "\\rgroup",
        "\\lmoustache",
        "\\rmoustache",
        "/",
        "\\backslash",
        "|",
        "\\vert",
        "\\|",
        "\\Vert",
        "\\uparrow",
        "\\Uparrow",
        "\\downarrow",
        "\\Downarrow",
        "\\updownarrow",
        "\\Updownarrow",
        ".":
        true
    default:
        false
    }
}
