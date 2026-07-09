// Port of RaTeX crates/ratex-parser/src/functions/arrow.rs

func registerArrow(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: [
            "\\xleftarrow",
            "\\xrightarrow",
            "\\xLeftarrow",
            "\\xRightarrow",
            "\\xleftrightarrow",
            "\\xLeftrightarrow",
            "\\xhookleftarrow",
            "\\xhookrightarrow",
            "\\xmapsto",
            "\\xrightharpoondown",
            "\\xrightharpoonup",
            "\\xleftharpoondown",
            "\\xleftharpoonup",
            "\\xrightleftharpoons",
            "\\xleftrightharpoons",
            "\\xlongequal",
            "\\xtwoheadrightarrow",
            "\\xtwoheadleftarrow",
            "\\xtofrom",
            "\\xrightleftarrows",
            "\\xrightequilibrium",
            "\\xleftequilibrium",
        ],
        nodeType: "xArrow",
        numArgs: 1,
        numOptionalArgs: 1,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleArrow)
}

private func handleArrow(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let body = args[0]
    let below = optArgs.first.flatMap { $0 }

    return ParseNode(
        .xArrow(label: ctx.funcName, body: body, below: below),
        mode: ctx.parser.mode)
}
