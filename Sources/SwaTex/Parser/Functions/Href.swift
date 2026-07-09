// Port of RaTeX crates/ratex-parser/src/functions/href.rs

func registerHref(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\href"],
        nodeType: "href",
        numArgs: 2,
        numOptionalArgs: 0,
        argTypes: [.url, .original],
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleHref)

    defineFunction(
        &map,
        names: ["\\url"],
        nodeType: "href",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: [.url],
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleUrl)
}

private func handleHref(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let urlArg = args[0]
    let bodyArg = args[1]

    guard case let .url(href) = urlArg.kind else {
        throw ParseError("Expected URL")
    }

    return ParseNode(
        .href(href: href, body: ParseNode.ordArgument(bodyArg)),
        mode: ctx.parser.mode)
}

private func handleUrl(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let urlArg = args[0]

    guard case let .url(url) = urlArg.kind else {
        throw ParseError("Expected URL")
    }

    let chars: [ParseNode] = url.unicodeScalars.map { c in
        ParseNode(.textOrd(text: String(c)), mode: .text)
    }

    let textNode = ParseNode(
        .text(body: chars, font: "\\texttt"), mode: ctx.parser.mode)

    return ParseNode(
        .href(href: url, body: [textNode]), mode: ctx.parser.mode)
}
