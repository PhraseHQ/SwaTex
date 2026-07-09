// Port of RaTeX crates/ratex-parser/src/functions/operatorname.rs

func registerOperatorName(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\operatorname@", "\\operatornamewithlimits"],
        nodeType: "operatorname",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleOperatorName)
}

private func handleOperatorName(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let body = ParseNode.ordArgument(args[0])

    let alwaysHandleSupSub = ctx.funcName == "\\operatornamewithlimits"

    return ParseNode(
        .operatorName(
            body: body, alwaysHandleSupSub: alwaysHandleSupSub,
            limits: false, parentIsSupSub: false),
        mode: ctx.parser.mode)
}
