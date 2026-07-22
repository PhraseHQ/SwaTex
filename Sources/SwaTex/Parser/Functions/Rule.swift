// Port of RaTeX crates/ratex-parser/src/functions/rule.rs

func registerRule(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\rule"],
        nodeType: "rule",
        numArgs: 2,
        numOptionalArgs: 1,
        argTypes: [.size, .size, .size],
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleRule)
}

private func handleRule(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let shift: Measurement?
    if let first = optArgs.first, let opt = first, case let .size(value, _) = opt.kind {
        shift = value
    } else {
        shift = nil
    }

    guard case let .size(width, _) = args[0].kind else {
        // INTENTIONALLY UNCOVERED (argType-guarantee KEEP): both required
        // arguments are declared `.size`, and `parseSizeGroup` for a
        // required argument always returns a `.size` node or throws.
        throw ParseError("Expected size for \\rule width")
    }
    guard case let .size(height, _) = args[1].kind else {
        // INTENTIONALLY UNCOVERED (argType-guarantee KEEP): see the width
        // guard above.
        throw ParseError("Expected size for \\rule height")
    }

    return ParseNode(
        .rule(shift: shift, width: width, height: height), mode: ctx.parser.mode)
}
