// Port of RaTeX crates/ratex-parser/src/functions/mclass.rs

func registerMclass(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: [
            "\\mathord",
            "\\mathbin",
            "\\mathrel",
            "\\mathopen",
            "\\mathclose",
            "\\mathpunct",
            "\\mathinner",
        ],
        nodeType: "mclass",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: true,
        handler: handleMclass)

    defineFunction(
        &map,
        names: ["\\stackrel", "\\overset", "\\underset"],
        nodeType: "mclass",
        numArgs: 2,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleStackrel)

    // \@binrel{x}{body} — infer mbin/mrel/mord from x, wrap body
    defineFunction(
        &map,
        names: ["\\@binrel"],
        nodeType: "mclass",
        numArgs: 2,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleBinrel)
}

private func handleMclass(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let mclass = "m" + ctx.funcName.dropFirst(5)
    let body = ParseNode.ordArgument(args[0])
    let isCharBox = body.count == 1 && body[0].isSymbolNode

    return ParseNode(
        .mclass(mclass: mclass, body: body, isCharacterBox: isCharBox),
        mode: ctx.parser.mode)
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

private func handleBinrel(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let atom = args[0]
    let body = args[1]
    let mclass = binrelClass(atom)

    return ParseNode(
        .mclass(mclass: mclass, body: ParseNode.ordArgument(body), isCharacterBox: false),
        mode: ctx.parser.mode)
}

private func handleStackrel(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let shiftedArg = args[0]
    let baseArg = args[1]

    let mclass = ctx.funcName == "\\stackrel" ? "mrel" : binrelClass(baseArg)

    let opNode = ParseNode(
        .op(
            limits: true,
            alwaysHandleSupSub: true,
            suppressBaseShift: ctx.funcName != "\\stackrel",
            parentIsSupSub: false,
            symbol: false,
            name: nil,
            body: ParseNode.ordArgument(baseArg)),
        mode: ctx.parser.mode)

    let sup: ParseNode?
    let sub: ParseNode?
    if ctx.funcName == "\\underset" {
        sup = nil
        sub = shiftedArg
    } else {
        sup = shiftedArg
        sub = nil
    }

    let supsub = ParseNode(
        .supSub(base: opNode, sup: sup, sub: sub), mode: ctx.parser.mode)

    return ParseNode(
        .mclass(mclass: mclass, body: [supsub], isCharacterBox: false),
        mode: ctx.parser.mode)
}
