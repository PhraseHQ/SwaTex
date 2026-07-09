// Port of RaTeX crates/ratex-parser/src/functions/text.rs

func registerText(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: [
            "\\text",
            "\\textrm",
            "\\textsf",
            "\\texttt",
            "\\textnormal",
            "\\textbf",
            "\\textit",
            "\\textmd",
            "\\textup",
            "\\textsl",
            "\\textsc",
        ],
        nodeType: "text",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: [.text],
        allowedInArgument: true,  // allowed_in_argument
        allowedInText: true,  // allowed_in_text
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleText)
}

private func handleText(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let body = args[0]
    let bodyVec = ParseNode.ordArgument(body)

    let font: String? = ctx.funcName

    return ParseNode(.text(body: bodyVec, font: font), mode: ctx.parser.mode)
}
