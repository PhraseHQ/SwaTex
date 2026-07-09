// Port of RaTeX crates/ratex-parser/src/functions/raisebox.rs

func registerRaiseBox(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\raisebox"],
        nodeType: "raisebox",
        numArgs: 2,
        numOptionalArgs: 0,
        argTypes: [.size, .hbox],
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleRaiseBox)
}

private func handleRaiseBox(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    guard case let .size(dy, _) = args[0].kind else {
        throw ParseError("Expected size for \\raisebox")
    }
    let body = args[1]

    return ParseNode(.raiseBox(dy: dy, body: body), mode: ctx.parser.mode)
}
