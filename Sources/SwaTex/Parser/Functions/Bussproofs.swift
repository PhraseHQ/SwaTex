/// Port of RaTeX crates/ratex-parser/src/functions/bussproofs.rs

func registerBussproofs(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\fCenter"],
        nodeType: "internal",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: true,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleFCenter)
}

private func handleFCenter(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    // bussproofs defaults \fCenter to \Rightarrow (U+21D2 ⇒), separating the
    // left and right sides of a sequent (e.g. A \fCenter B → "A ⇒ B").
    ParseNode(.atom(family: .rel, text: "\\Rightarrow"), mode: ctx.parser.mode)
}
