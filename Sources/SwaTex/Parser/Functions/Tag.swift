// Port of RaTeX crates/ratex-parser/src/functions/tag.rs

func registerTag(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\tag"],
        nodeType: "tag",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: true,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: true,
        handler: handleTag)
}

private func handleTag(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    try ctx.parser.consumeSpaces()
    let star: Bool
    if try ctx.parser.fetch().text == "*" {
        ctx.parser.consume()
        star = true
    } else {
        star = false
    }

    guard let arg = try ctx.parser.parseGroup(name: "\\tag", breakOnTokenText: nil) else {
        throw ParseError("\\tag requires an argument")
    }

    let inner: [ParseNode]
    if case let .ordGroup(body, _) = arg.kind {
        inner = body
    } else {
        inner = [arg]
    }

    let tag: [ParseNode]
    if star {
        tag = inner
    } else {
        var v: [ParseNode] = []
        v.reserveCapacity(inner.count + 2)
        v.append(ParseNode(.mathOrd(text: "("), mode: .math))
        v.append(contentsOf: inner)
        v.append(ParseNode(.mathOrd(text: ")"), mode: .math))
        tag = v
    }

    return ParseNode(.tag(body: [], tag: tag), mode: ctx.parser.mode)
}
