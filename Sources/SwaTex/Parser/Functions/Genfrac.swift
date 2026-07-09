func registerGenfrac(_ map: inout [String: FunctionSpec]) {
    // \frac, \dfrac, \tfrac, \cfrac, \binom, \dbinom, \tbinom
    defineFunction(
        &map,
        names: [
            "\\cfrac",
            "\\dfrac",
            "\\frac",
            "\\tfrac",
            "\\dbinom",
            "\\binom",
            "\\tbinom",
            "\\\\atopfrac",
            "\\\\bracefrac",
            "\\\\brackfrac",
        ],
        nodeType: "genfrac",
        numArgs: 2,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: true,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleGenfrac)

    // \genfrac{left}{right}{bar-size}{style}{numer}{denom}
    defineFunction(
        &map,
        names: ["\\genfrac"],
        nodeType: "genfrac",
        numArgs: 6,
        numOptionalArgs: 0,
        argTypes: [.math, .math, .size, .text, .math, .math],
        allowedInArgument: true,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleGenfracFull)

    // Infix: \over, \choose, \atop, \brace, \brack
    defineFunction(
        &map,
        names: ["\\over", "\\choose", "\\atop", "\\brace", "\\brack"],
        nodeType: "infix",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: true,
        primitive: false,
        handler: handleInfix)

    // \above{size} — infix with bar size
    defineFunction(
        &map,
        names: ["\\above"],
        nodeType: "infix",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: [.size],
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: true,
        primitive: false,
        handler: handleAboveInfix)

    // \\abovefrac — internal 3-arg handler for \above
    defineFunction(
        &map,
        names: ["\\\\abovefrac"],
        nodeType: "genfrac",
        numArgs: 3,
        numOptionalArgs: 0,
        argTypes: [.math, .size, .math],
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleAbovefrac)
}

private func handleGenfrac(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let numer = args[0]
    let denom = args[1]
    let funcName = ctx.funcName
    let mode = ctx.parser.mode

    let hasBarLine: Bool
    let leftDelim: String?
    let rightDelim: String?
    switch funcName {
    case "\\cfrac", "\\dfrac", "\\frac", "\\tfrac":
        (hasBarLine, leftDelim, rightDelim) = (true, nil, nil)
    case "\\\\atopfrac":
        (hasBarLine, leftDelim, rightDelim) = (false, nil, nil)
    case "\\dbinom", "\\binom", "\\tbinom":
        (hasBarLine, leftDelim, rightDelim) = (false, "(", ")")
    case "\\\\bracefrac":
        (hasBarLine, leftDelim, rightDelim) = (false, "\\{", "\\}")
    case "\\\\brackfrac":
        (hasBarLine, leftDelim, rightDelim) = (false, "[", "]")
    default:
        (hasBarLine, leftDelim, rightDelim) = (true, nil, nil)
    }

    let continued = funcName == "\\cfrac"

    let frac = ParseNode(
        .genfrac(
            continued: continued, numer: numer, denom: denom,
            hasBarLine: hasBarLine, leftDelim: leftDelim, rightDelim: rightDelim,
            barSize: nil),
        mode: mode)

    // Wrap in styling if needed
    let style: StyleStr?
    if continued || funcName.hasPrefix("\\d") {
        style = .display
    } else if funcName.hasPrefix("\\t") {
        style = .text
    } else {
        style = nil
    }

    if let style {
        return ParseNode(.styling(style: style, body: [frac]), mode: mode)
    }
    return frac
}

private func handleGenfracFull(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let mode = ctx.parser.mode
    let numer = args[4]
    let denom = args[5]

    let leftDelim = extractDelim(args[0])
    let rightDelim = extractDelim(args[1])

    let hasBarLine: Bool
    let barSize: Measurement?
    if case let .size(value, isBlank) = args[2].kind {
        if isBlank {
            (hasBarLine, barSize) = (true, nil)
        } else {
            (hasBarLine, barSize) = (value.number > 0.0, value)
        }
    } else {
        (hasBarLine, barSize) = (true, nil)
    }

    let styleStrs: [StyleStr] = [.display, .text, .script, .scriptscript]
    let style: StyleStr?
    if case let .ordGroup(body, _) = args[3].kind, !body.isEmpty {
        style = extractTextordNum(body[0]).flatMap { n in
            styleStrs.indices.contains(n) ? styleStrs[n] : nil
        }
    } else {
        style = extractTextordNum(args[3]).flatMap { n in
            styleStrs.indices.contains(n) ? styleStrs[n] : nil
        }
    }

    let frac = ParseNode(
        .genfrac(
            continued: false, numer: numer, denom: denom,
            hasBarLine: hasBarLine, leftDelim: leftDelim, rightDelim: rightDelim,
            barSize: barSize),
        mode: mode)

    if let style {
        return ParseNode(.styling(style: style, body: [frac]), mode: mode)
    }
    return frac
}

private func extractDelim(_ node: ParseNode) -> String? {
    let text: String
    switch node.kind {
    case let .atom(_, t):
        text = t
    case let .ordGroup(body, _) where body.count == 1:
        if case let .atom(_, t) = body[0].kind {
            text = t
        } else {
            return nil
        }
    default:
        return nil
    }
    if text == "." || text.isEmpty {
        return nil
    }
    return text
}

private func extractTextordNum(_ node: ParseNode) -> Int? {
    if case let .textOrd(text) = node.kind {
        return Int(text)
    }
    return nil
}

private func handleAboveInfix(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let size: Measurement?
    if case let .size(value, _) = args[0].kind {
        size = value
    } else {
        size = nil
    }

    return ParseNode(
        .infix(replaceWith: "\\\\abovefrac", size: size), mode: ctx.parser.mode)
}

private func handleAbovefrac(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let mode = ctx.parser.mode
    let numer = args[0]
    let denom = args[2]

    let barSize: Measurement?
    if case let .infix(_, size) = args[1].kind {
        barSize = size
    } else {
        barSize = nil
    }

    let hasBarLine = barSize.map { $0.number > 0.0 } ?? false

    return ParseNode(
        .genfrac(
            continued: false, numer: numer, denom: denom,
            hasBarLine: hasBarLine, leftDelim: nil, rightDelim: nil,
            barSize: barSize),
        mode: mode)
}

private func handleInfix(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let replaceWith: String
    switch ctx.funcName {
    case "\\over": replaceWith = "\\frac"
    case "\\choose": replaceWith = "\\binom"
    case "\\atop": replaceWith = "\\\\atopfrac"
    case "\\brace": replaceWith = "\\\\bracefrac"
    case "\\brack": replaceWith = "\\\\brackfrac"
    default: replaceWith = "\\frac"
    }

    return ParseNode(.infix(replaceWith: replaceWith, size: nil), mode: ctx.parser.mode)
}
