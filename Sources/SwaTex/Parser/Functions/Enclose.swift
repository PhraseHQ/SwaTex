// Port of RaTeX crates/ratex-parser/src/functions/enclose.rs

func registerEnclose(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\fbox"],
        nodeType: "enclose",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: [.hbox],
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleFbox)

    defineFunction(
        &map,
        names: ["\\cancel", "\\bcancel", "\\xcancel", "\\phase"],
        nodeType: "enclose",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleCancel)

    // \sout originates as a LaTeX text-mode command but KaTeX accepts it in
    // both modes (allowedInText: true, no argType override → arg inherits
    // surrounding mode). We mirror that so `\text{\sout{abc}}` parses while
    // `\sout{x^2}` still keeps its argument in math mode.
    defineFunction(
        &map,
        names: ["\\sout"],
        nodeType: "enclose",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleCancel)

    defineFunction(
        &map,
        names: ["\\angl"],
        nodeType: "enclose",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: [.hbox],
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleAngl)
}

private func handleFbox(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    ParseNode(
        .enclose(label: "\\fbox", backgroundColor: nil, borderColor: nil, body: args[0]),
        mode: ctx.parser.mode)
}

private func handleCancel(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    ParseNode(
        .enclose(label: ctx.funcName, backgroundColor: nil, borderColor: nil, body: args[0]),
        mode: ctx.parser.mode)
}

private func handleAngl(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    ParseNode(
        .enclose(label: "\\angl", backgroundColor: nil, borderColor: nil, body: args[0]),
        mode: ctx.parser.mode)
}
