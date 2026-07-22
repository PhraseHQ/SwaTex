/// Port of RaTeX crates/ratex-parser/src/functions/environment.rs
/// Handles \begin/\end (dispatching to the environments registry) and
/// \hline/\hdashline (valid only within array environments).

func registerEnvironment(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\begin", "\\end"],
        nodeType: "environment",
        numArgs: 1,
        numOptionalArgs: 0,
        argTypes: [.text],
        allowedInArgument: true,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleBeginEnd)

    defineFunction(
        &map,
        names: ["\\hline", "\\hdashline"],
        nodeType: "text",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: false,
        allowedInText: true,
        allowedInMath: true,
        infix: false,
        primitive: false,
        handler: handleHline)
}

private func extractEnvName(_ nameGroup: ParseNode) throws(ParseError) -> String {
    switch nameGroup.kind {
    case let .ordGroup(body, _):
        var envName = ""
        for node in body {
            switch node.kind {
            case let .textOrd(text), let .mathOrd(text):
                envName += text
            case let .atom(_, text):
                envName += text
            default:
                throw ParseError(
                    "Invalid environment name character: \"\(node.typeName)\"")
            }
        }
        return envName
    default:
        // INTENTIONALLY UNCOVERED (argType-guarantee KEEP): the name argument
        // is declared `.text`, and `parseArgumentGroup` always wraps a
        // required argument in an `.ordGroup` node.
        throw ParseError("Invalid environment name")
    }
}

private func handleBeginEnd(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    let nameGroup = args[0]
    let envName = try extractEnvName(nameGroup)

    if ctx.funcName == "\\begin" {
        // Allow all registered environments to parse; display vs inline is a layout concern.
        // (KaTeX rejects align/equation in inline $...$; we parse them and let layout decide.)
        guard let env = Environments.registry[envName] else {
            throw ParseError("No such environment: \(envName)")
        }

        // Parse environment arguments if any
        var envArgs: [ParseNode] = []
        for _ in 0..<env.numArgs {
            let arg = try ctx.parser.parseArgumentGroup(optional: false, mode: nil)
            guard let a = arg else {
                // INTENTIONALLY UNCOVERED (defensive guard KEEP):
                // `parseArgumentGroup(optional: false)` never returns nil —
                // `scanArgument(isOptional: false)` throws on missing input
                // instead of returning nil.
                throw ParseError("Expected argument to \\begin{\(envName)}")
            }
            envArgs.append(a)
        }

        var envCtx = EnvContext(
            mode: ctx.parser.mode,
            envName: envName,
            parser: ctx.parser)

        let result = try env.handler(&envCtx, envArgs, [])

        // Expect \end
        try ctx.parser.expect("\\end", consume: false)

        // Parse \end{name} as a function call
        let endNode = try ctx.parser.parseFunction(breakOnTokenText: nil, name: nil)
        guard let endNode, case let .environment(endName, _) = endNode.kind else {
            // INTENTIONALLY UNCOVERED (defensive guard KEEP): the preceding
            // `expect("\\end")` guarantees the next token is the registered
            // \end function, whose handler always returns an `.environment`
            // node or throws; `parseFunction` cannot return nil for it.
            throw ParseError("Expected \\end after environment body")
        }

        if endName != envName {
            throw ParseError("Mismatch: \\begin{\(envName)} matched by \\end{\(endName)}")
        }

        return result
    } else {
        // \end handler
        return ParseNode(
            .environment(name: envName, nameGroup: nameGroup), mode: ctx.parser.mode)
    }
}

private func handleHline(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    throw ParseError("\(ctx.funcName) valid only within array environment")
}
