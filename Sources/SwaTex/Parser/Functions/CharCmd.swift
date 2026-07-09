// Port of RaTeX crates/ratex-parser/src/functions/char_cmd.rs

func registerCharCmd(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\@char"],
        nodeType: "textord",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleAtChar)
}

private func handleAtChar(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let arg = args[0]
    let body = ParseNode.ordArgument(arg)

    var numberStr = ""
    for node in body {
        if let text = node.symbolText {
            numberStr += text
        }
    }

    guard let code = UInt32(numberStr) else {
        throw ParseError("\\@char has non-numeric argument \(numberStr)")
    }

    guard let scalar = Unicode.Scalar(code) else {
        throw ParseError("\\@char with invalid code point \(code)")
    }
    let text = String(scalar)

    // Match KaTeX `src/functions/char.ts`: `\@char` always yields `textord`, even when the
    // codepoint is also listed as `\sum` / op-token in `symbols.js`. `\char"2211` must not
    // become a large `Size1` operator (that glyph is much wider than KaTeX's textord path).
    return ParseNode(.textOrd(text: text), mode: ctx.parser.mode)
}
