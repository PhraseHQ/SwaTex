/// Port of RaTeX crates/ratex-parser/src/functions/def.rs
/// Implements \def, \gdef, \edef, \xdef, \let, \futurelet, \global, \long.

private let globalMap: [(String, String)] = [
    ("\\global", "\\global"),
    ("\\long", "\\\\globallong"),
    ("\\\\globallong", "\\\\globallong"),
    ("\\def", "\\gdef"),
    ("\\gdef", "\\gdef"),
    ("\\edef", "\\xdef"),
    ("\\xdef", "\\xdef"),
    ("\\let", "\\\\globallet"),
    ("\\futurelet", "\\\\globalfuture"),
]

private func globalVersion(_ name: String) -> String? {
    globalMap.first(where: { $0.0 == name })?.1
}

private func checkControlSequence(_ text: String) throws(ParseError) {
    switch text {
    case "\\", "{", "}", "$", "&", "#", "^", "_", "EOF":
        throw ParseError("Expected a control sequence")
    default:
        break
    }
}

func registerDef(_ map: inout [String: FunctionSpec]) {
    // Prefix commands: \global, \long
    defineFunction(
        &map,
        names: ["\\global", "\\long", "\\\\globallong"],
        nodeType: "internal",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handlePrefix)

    // \def, \gdef, \edef, \xdef
    defineFunction(
        &map,
        names: ["\\def", "\\gdef", "\\edef", "\\xdef"],
        nodeType: "internal",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: true,
        handler: handleDef)

    // \let
    defineFunction(
        &map,
        names: ["\\let", "\\\\globallet"],
        nodeType: "internal",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: true,
        handler: handleLet)

    // \futurelet
    defineFunction(
        &map,
        names: ["\\futurelet", "\\\\globalfuture"],
        nodeType: "internal",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: true,
        handler: handleFuturelet)
}

private func handlePrefix(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    try ctx.parser.consumeSpaces()
    var nextTok = try ctx.parser.fetch()
    let tokenText = nextTok.text

    if let globalVer = globalVersion(tokenText) {
        if ctx.funcName == "\\global" || ctx.funcName == "\\\\globallong" {
            nextTok.text = globalVer
            ctx.parser.gullet.pushToken(nextTok)
            ctx.parser.consume()
        }
        let result = try ctx.parser.parseFunction(breakOnTokenText: nil, name: nil)
        guard let node = result else {
            throw ParseError("Invalid token after macro prefix")
        }
        return node
    } else {
        throw ParseError("Invalid token after macro prefix")
    }
}

private func handleDef(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let nameTok = ctx.parser.gullet.popToken()
    let name = nameTok.text
    try checkControlSequence(name)

    var numArgs = 0
    var insertBrace = false

    // Parse parameter text: read tokens until `{`. Delimiter tokens between
    // parameters are recorded and enforced at use sites (KaTeX def.js):
    // delimiters[0] must follow the macro name literally, delimiters[i]
    // terminates argument #i.
    var delimiters: [[String]] = [[]]
    while ctx.parser.gullet.future().text != "{" {
        let tok = ctx.parser.gullet.popToken()
        if tok.text == "#" {
            // `#{` — the final parameter is delimited by `{`, which also
            // reappears at the end of the replacement text (TeXbook §203).
            if ctx.parser.gullet.future().text == "{" {
                insertBrace = true
                delimiters[numArgs].append("{")
                break
            }
            let numTok = ctx.parser.gullet.popToken()
            guard numTok.text.count == 1, let n = Int(numTok.text), n >= 1 else {
                throw ParseError("Invalid argument number \"\(numTok.text)\"")
            }
            if n != numArgs + 1 {
                throw ParseError("Argument number \"\(n)\" out of order")
            }
            numArgs += 1
            delimiters.append([])
        } else if tok.isEOF {
            throw ParseError("Expected a macro definition")
        } else {
            delimiters[numArgs].append(tok.text)
        }
    }

    let arg = try ctx.parser.gullet.consumeArg()
    var tokens = arg.tokens

    if insertBrace {
        // Stack order is reversed, so index 0 is the logically-last token.
        tokens.insert(Token("{", start: 0, end: 0), at: 0)
    }

    if ctx.funcName == "\\edef" || ctx.funcName == "\\xdef" {
        // `expandTokens` consumes from the stack top and returns stack-order
        // tokens (see \bra@ket, which feeds it stack-order input). `tokens`
        // is already in stack order from consumeArg, so pass it directly.
        //
        // KaTeX-correctness fix: RaTeX reverses here (def.rs:169), which
        // makes \edef expand its body BACK-TO-FRONT — invisible to
        // dimension-only golden tests (widths sum commutatively) but wrong
        // for token order and for \noexpand's "next token".
        tokens = try ctx.parser.gullet.expandTokens(tokens)
    }

    let isGlobalDef = ctx.funcName == "\\gdef" || ctx.funcName == "\\xdef"
    // Store nil for ordinary undelimited macros (the documented
    // `MacroDefinition.tokens` invariant): expansion then skips the
    // delimiter-matching path entirely.
    let def = MacroDefinition.tokens(
        tokens, numArgs: numArgs,
        delimiters: delimiters.allSatisfy(\.isEmpty) ? nil : delimiters)
    if isGlobalDef {
        ctx.parser.gullet.setMacroGlobal(name, def)
    } else {
        ctx.parser.gullet.setMacro(name, def)
    }

    return ParseNode(.internalNode, mode: ctx.parser.mode)
}

private func handleLet(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let nameTok = ctx.parser.gullet.popToken()
    let name = nameTok.text
    try checkControlSequence(name)

    ctx.parser.gullet.consumeSpaces()

    // Consume optional `=`
    var tok = ctx.parser.gullet.popToken()
    if tok.text == "=" {
        tok = ctx.parser.gullet.popToken()
        if tok.text == " " {
            tok = ctx.parser.gullet.popToken()
        }
    }

    let isGlobal = ctx.funcName == "\\\\globallet"
    letCommand(&ctx, name: name, tok: tok, global: isGlobal)

    return ParseNode(.internalNode, mode: ctx.parser.mode)
}

private func handleFuturelet(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let nameTok = ctx.parser.gullet.popToken()
    let name = nameTok.text
    try checkControlSequence(name)

    let middle = ctx.parser.gullet.popToken()
    let tok = ctx.parser.gullet.popToken()

    let isGlobal = ctx.funcName == "\\\\globalfuture"
    letCommand(&ctx, name: name, tok: tok, global: isGlobal)

    ctx.parser.gullet.pushToken(tok)
    ctx.parser.gullet.pushToken(middle)

    return ParseNode(.internalNode, mode: ctx.parser.mode)
}

private func letCommand(
    _ ctx: inout FunctionContext, name: String, tok: Token, global: Bool
) {
    var tok = tok
    let def: MacroDefinition
    if let macroDef = ctx.parser.gullet.getMacro(tok.text) {
        def = macroDef
    } else {
        tok.noexpand = true
        def = .tokens([tok], numArgs: 0, delimiters: nil)
    }

    if global {
        ctx.parser.gullet.setMacroGlobal(name, def)
    } else {
        ctx.parser.gullet.setMacro(name, def)
    }
}
