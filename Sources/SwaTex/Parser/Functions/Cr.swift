// Port of RaTeX crates/ratex-parser/src/functions/cr.rs

func registerCr(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\\\", "\\newline"],
        nodeType: "cr",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleCr)
}

private func handleCr(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    // Only parse optional [size] if next token is directly "[" (no space)
    let sizeNode: ParseNode?
    if ctx.parser.gullet.future().text == "[" {
        sizeNode = try ctx.parser.parseSizeGroup(optional: true)
    } else {
        sizeNode = nil
    }

    let size: Measurement?
    if let node = sizeNode, case let .size(value, _) = node.kind {
        size = value
    } else {
        size = nil
    }

    let newLine = true

    return ParseNode(.cr(newLine: newLine, size: size), mode: ctx.parser.mode)
}
