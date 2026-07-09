// Port of RaTeX crates/ratex-parser/src/functions/phantom.rs

func registerPhantom(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\phantom"],
        nodeType: "phantom",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: true,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handlePhantom)

    defineFunction(
        &map,
        names: ["\\vphantom"],
        nodeType: "vphantom",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: true,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleVPhantom)

    // \hphantom is defined as a macro: \smash{\phantom{#1}}
    // (registered in macro_expander builtins)

    defineFunction(
        &map,
        names: ["\\smash"],
        nodeType: "smash",
        numArgs: 1,
        numOptionalArgs: 1,
        argTypes: nil,
        allowedInArgument: true,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleSmash)
}

private func handlePhantom(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let body = ParseNode.ordArgument(args[0])
    return ParseNode(.phantom(body: body), mode: ctx.parser.mode)
}

private func handleVPhantom(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    ParseNode(.vphantom(body: args[0]), mode: ctx.parser.mode)
}

private func handleSmash(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    var smashHeight = false
    var smashDepth = false

    if let first = optArgs.first, let opt = first, case let .ordGroup(body, _) = opt.kind {
        loop: for node in body {
            let text = node.symbolText ?? ""
            switch text {
            case "t":
                smashHeight = true
            case "b":
                smashDepth = true
            default:
                smashHeight = false
                smashDepth = false
                break loop
            }
        }
    } else {
        smashHeight = true
        smashDepth = true
    }

    return ParseNode(
        .smash(body: args[0], smashHeight: smashHeight, smashDepth: smashDepth),
        mode: ctx.parser.mode)
}
