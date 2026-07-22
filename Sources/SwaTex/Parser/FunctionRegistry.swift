/// Context passed to function handlers.
struct FunctionContext {
    var funcName: String
    var parser: Parser
    var token: Token?
    var breakOnTokenText: String?
}

/// Handler function signature.
typealias FunctionHandler =
    @Sendable (
        _ ctx: inout FunctionContext,
        _ args: [ParseNode],
        _ optArgs: [ParseNode?]
    ) throws(ParseError) -> ParseNode

/// Argument types for function parameters.
enum ArgType: Hashable, Sendable {
    case color
    case size
    case url
    case math
    case text
    case hbox
    case raw
    case primitive
    case original
}

/// Specification for a registered function.
struct FunctionSpec: Sendable {
    var nodeType: String
    var numArgs: Int
    var numOptionalArgs: Int
    var argTypes: [ArgType]?
    var allowedInArgument: Bool
    var allowedInText: Bool
    var allowedInMath: Bool
    var infix: Bool
    var primitive: Bool
    var handler: FunctionHandler
}

/// The global function registry: command name → spec.
///
/// Built once, lazily and thread-safely (`static let` is the Swift
/// equivalent of Rust's `LazyLock`).
enum Functions {
    /// First-byte filter over `registry` keys: `parseFunction` runs for
    /// every atom, and most tokens can be rejected without hashing
    /// (performance log P-026).
    static let registryFirstBytes = FirstByteSet(keys: registry.keys)

    static let registry: [String: FunctionSpec] = {
        var map: [String: FunctionSpec] = [:]
        registerGenfrac(&map)
        registerSqrt(&map)
        registerOp(&map)
        registerAccent(&map)
        registerFont(&map)
        registerColor(&map)
        registerSizing(&map)
        registerDelimSizing(&map)
        registerLeftRight(&map)
        registerSpacing(&map)
        registerStyling(&map)
        registerOverline(&map)
        registerKern(&map)
        registerPhantom(&map)
        registerText(&map)
        registerCr(&map)
        registerRelax(&map)
        registerVerb(&map)
        registerSymbolsCmd(&map)
        registerEnvironment(&map)
        registerMclass(&map)
        registerOperatorName(&map)
        registerHorizBrace(&map)
        registerArrow(&map)
        registerEnclose(&map)
        registerRule(&map)
        registerHref(&map)
        registerHBox(&map)
        registerLap(&map)
        registerRaiseBox(&map)
        registerVCenter(&map)
        registerPmb(&map)
        registerMathChoice(&map)
        registerDef(&map)
        registerHtmlMathML(&map)
        registerCharCmd(&map)
        registerMath(&map)
        registerTag(&map)
        registerNoNumber(&map)
        registerBussproofs(&map)
        return map
    }()
}

/// Helper to define a function with common defaults.
func defineFunction(
    _ map: inout [String: FunctionSpec],
    names: [String],
    nodeType: String,
    numArgs: Int,
    handler: @escaping FunctionHandler
) {
    defineFunction(
        &map, names: names, nodeType: nodeType, numArgs: numArgs,
        numOptionalArgs: 0, argTypes: nil, allowedInArgument: false,
        allowedInText: false, allowedInMath: true, infix: false,
        primitive: false, handler: handler)
}

func defineFunction(
    _ map: inout [String: FunctionSpec],
    names: [String],
    nodeType: String,
    numArgs: Int,
    numOptionalArgs: Int,
    argTypes: [ArgType]?,
    allowedInArgument: Bool,
    allowedInText: Bool,
    allowedInMath: Bool,
    infix: Bool,
    primitive: Bool,
    handler: @escaping FunctionHandler
) {
    let spec = FunctionSpec(
        nodeType: nodeType, numArgs: numArgs, numOptionalArgs: numOptionalArgs,
        argTypes: argTypes, allowedInArgument: allowedInArgument,
        allowedInText: allowedInText, allowedInMath: allowedInMath,
        infix: infix, primitive: primitive, handler: handler)
    for name in names {
        map[name] = spec
    }
}

/// Check if a mode is compatible with a function spec.
func checkModeCompatibility(
    _ spec: FunctionSpec, mode: Mode, funcName: String, token: Token?
) throws(ParseError) {
    if mode == .text && !spec.allowedInText {
        throw ParseError("Can't use function '\(funcName)' in text mode", token: token)
    }
    if mode == .math && !spec.allowedInMath {
        throw ParseError("Can't use function '\(funcName)' in math mode", token: token)
    }
}
