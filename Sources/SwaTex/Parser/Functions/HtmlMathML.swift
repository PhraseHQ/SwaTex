// Port of RaTeX crates/ratex-parser/src/functions/htmlmathml.rs

func registerHtmlMathML(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\html@mathml"],
        nodeType: "htmlmathml",
        numArgs: 2,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleHtmlMathML)

    defineFunction(
        &map,
        names: ["\\htmlStyle"],
        nodeType: "html",
        numArgs: 2,
        numOptionalArgs: 0,
        argTypes: [.raw, .original],
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleHtmlStyle)
}

private func handleHtmlMathML(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let html = ParseNode.ordArgument(args[0])
    let mathml = ParseNode.ordArgument(args[1])

    return ParseNode(.htmlMathML(html: html, mathml: mathml), mode: ctx.parser.mode)
}

private func handleHtmlStyle(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    guard case let .raw(style) = args[0].kind else {
        // INTENTIONALLY UNCOVERED (argType-guarantee KEEP): args[0] is
        // declared `.raw`; `parseGroupOfType(.raw)` for a required argument
        // always returns a `.raw` node.
        throw ParseError("Expected raw style for \\htmlStyle")
    }
    let body = ParseNode.ordArgument(args[1])
    var attributes: [String: String] = [:]
    attributes["style"] = style

    return ParseNode(.html(attributes: attributes, body: body), mode: ctx.parser.mode)
}
