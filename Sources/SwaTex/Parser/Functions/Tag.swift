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

    // KaTeX expands `\tag{X}` to `\text{({X})}` and `\tag*{X}` to `\text{X}`
    // (macros.js `\tag@paren` / `\tag@literal`, consumed by array.js's
    // `parser.subparse([new Token("\\df@tag")])`), so the argument is parsed in
    // text mode and the parentheses are text-mode characters — a tag renders
    // upright, not in math italic.
    // The mode switch mirrors the `$…$` handler: `parseArgumentGroup` cannot
    // serve here because it rescans the argument through
    // `gullet.scanArgument`, which expects to run during declared-argument
    // parsing, not from inside a handler that has already consumed the `*`.
    let parser = ctx.parser
    let outerMode = parser.mode
    parser.switchMode(.text)
    defer { parser.switchMode(outerMode) }

    guard let arg = try parser.parseGroup(name: "\\tag", breakOnTokenText: nil) else {
        throw ParseError("\\tag requires an argument")
    }

    let body: [ParseNode]
    if star {
        body = ParseNode.ordArgument(arg)
    } else {
        body = [
            ParseNode(.textOrd(text: "("), mode: .text),
            arg,
            ParseNode(.textOrd(text: ")"), mode: .text),
        ]
    }

    let tag = [ParseNode(.text(body: body, font: "\\text"), mode: .text)]
    return ParseNode(.tag(body: [], tag: tag), mode: outerMode)
}
