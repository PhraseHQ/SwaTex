// Port of RaTeX crates/ratex-parser/src/functions/pmb.rs

func registerPmb(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\pmb"],
        nodeType: "pmb",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handlePmb)
}

private func binrelClass(_ arg: ParseNode) -> String {
    let atom: ParseNode
    if case let .ordGroup(body, _) = arg.kind {
        atom = body.isEmpty ? arg : body[0]
    } else {
        atom = arg
    }
    if case let .atom(family, _) = atom.kind {
        switch family {
        case .bin: return "mbin"
        case .rel: return "mrel"
        default: break
        }
    }
    return "mord"
}

private func handlePmb(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let body = args[0]

    return ParseNode(
        .pmb(mclass: binrelClass(body), body: ParseNode.ordArgument(body)),
        mode: ctx.parser.mode)
}
