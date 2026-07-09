// Port of RaTeX crates/ratex-parser/src/functions/mathchoice.rs

func registerMathChoice(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\mathchoice"],
        nodeType: "mathchoice",
        numArgs: 4,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: true,
        handler: handleMathChoice)
}

private func handleMathChoice(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let display = ParseNode.ordArgument(args[0])
    let text = ParseNode.ordArgument(args[1])
    let script = ParseNode.ordArgument(args[2])
    let scriptscript = ParseNode.ordArgument(args[3])

    return ParseNode(
        .mathChoice(
            display: display, text: text, script: script, scriptscript: scriptscript),
        mode: ctx.parser.mode)
}
