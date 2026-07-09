private let nonStretchy: Set<String> = [
    "\\acute",
    "\\grave",
    "\\ddot",
    "\\tilde",
    "\\bar",
    "\\breve",
    "\\check",
    "\\hat",
    "\\vec",
    "\\dot",
    "\\mathring",
]

func registerAccent(_ map: inout [String: FunctionSpec]) {
    // Math-mode accents
    defineFunction(
        &map,
        names: [
            "\\acute",
            "\\grave",
            "\\ddot",
            "\\tilde",
            "\\bar",
            "\\breve",
            "\\check",
            "\\hat",
            "\\vec",
            "\\dot",
            "\\mathring",
            "\\widecheck",
            "\\widehat",
            "\\widetilde",
            "\\overrightarrow",
            "\\overleftarrow",
            "\\Overrightarrow",
            "\\overleftrightarrow",
            "\\overgroup",
            "\\overlinesegment",
            "\\overleftharpoon",
            "\\overrightharpoon",
        ],
        nodeType: "accent",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleAccent)

    // Text-mode accents
    defineFunction(
        &map,
        names: [
            "\\'",
            "\\`",
            "\\^",
            "\\~",
            "\\=",
            "\\u",
            "\\.",
            "\\\"",
            "\\c",
            "\\r",
            "\\H",
            "\\v",
            "\\textcircled",
        ],
        nodeType: "accent",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: [.primitive],
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleTextAccent)

    // Under-accents
    defineFunction(
        &map,
        names: [
            "\\underleftarrow",
            "\\underrightarrow",
            "\\underleftrightarrow",
            "\\undergroup",
            "\\underlinesegment",
            "\\utilde",
        ],
        nodeType: "accentUnder",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleAccentUnder)
}

private func handleAccent(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let base = ParseNode.normalizeArgument(args[0])
    let funcName = ctx.funcName
    let isStretchy = !nonStretchy.contains(funcName)
    let isShifty =
        !isStretchy
        || funcName == "\\widehat"
        || funcName == "\\widetilde"
        || funcName == "\\widecheck"

    return ParseNode(
        .accent(label: funcName, isStretchy: isStretchy, isShifty: isShifty, base: base),
        mode: ctx.parser.mode)
}

private func handleTextAccent(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let base = args[0]
    // Text accents always produce text-mode nodes, even in math mode
    let mode = Mode.text

    return ParseNode(
        .accent(label: ctx.funcName, isStretchy: false, isShifty: true, base: base),
        mode: mode)
}

private func handleAccentUnder(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let base = args[0]

    return ParseNode(
        .accentUnder(label: ctx.funcName, isStretchy: true, isShifty: false, base: base),
        mode: ctx.parser.mode)
}
