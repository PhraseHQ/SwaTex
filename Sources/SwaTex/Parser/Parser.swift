import Foundation

/// End-of-expression tokens.
private let endOfExpression: Set<String> = ["}", "\\endgroup", "\\end", "\\right", "&"]

private let maxRecursionDepth = 512

/// The LaTeX parser. Converts a token stream into a ParseNode AST.
///
/// Follows KaTeX's Parser.ts closely:
/// - `parse()` → parse full expression
/// - `parseExpression()` → parse a list of atoms
/// - `parseAtom()` → parse one atom with optional super/subscripts
/// - `parseGroup()` → parse a group (braced or single token)
/// - `parseFunction()` → parse a function call with arguments
/// - `parseSymbol()` → parse a single symbol
public final class Parser {
    public var mode: Mode
    let gullet: MacroExpander
    var leftrightDepth = 0
    private var recursionDepth = 0
    /// Lowest stack address `parseExpression` may recurse at while keeping
    /// `minimumParseStackHeadroom` free (see StackGuard.swift). Computed
    /// once here — init runs on the thread that parses — so the hot-path
    /// check is a single address comparison.
    private let stackFloor = stackFloorAddress(headroom: minimumParseStackHeadroom)
    private var nextToken: Token?
    var equationCounter = 0

    public init(_ input: String) {
        self.mode = .math
        self.gullet = MacroExpander(input, mode: .math)
    }

    // ── Token management ────────────────────────────────────────────────

    /// Return the current lookahead token (fetching from gullet if needed).
    @discardableResult
    public func fetch() throws(ParseError) -> Token {
        if nextToken == nil {
            nextToken = try gullet.expandNextToken()
        }
        return nextToken!
    }

    /// Discard the current lookahead token.
    public func consume() {
        nextToken = nil
    }

    /// Expect the next token to have the given text, consuming it.
    public func expect(_ text: String, consume doConsume: Bool = true) throws(ParseError) {
        let tok = try fetch()
        if tok.text != text {
            throw ParseError("Expected '\(text)', got '\(tok.text)'", token: tok)
        }
        if doConsume {
            consume()
        }
    }

    /// Consume spaces in math mode.
    public func consumeSpaces() throws(ParseError) {
        while try fetch().text == " " {
            consume()
        }
    }

    /// Switch between "math" and "text" modes.
    public func switchMode(_ newMode: Mode) {
        mode = newMode
        gullet.switchMode(newMode)
    }

    // ── Main parse entry ────────────────────────────────────────────────

    /// Parse the entire input and return the AST.
    public func parse() throws(ParseError) -> [ParseNode] {
        gullet.beginGroup()

        do throws(ParseError) {
            let parse = try parseExpression(breakOnInfix: false, breakOnTokenText: nil)
            try expect("EOF")
            gullet.endGroup()
            return parse
        } catch {
            gullet.endGroups()
            throw error
        }
    }

    // ── Expression parsing ──────────────────────────────────────────────

    /// Parse an expression: a list of atoms.
    public func parseExpression(
        breakOnInfix: Bool, breakOnTokenText: String?
    ) throws(ParseError) -> [ParseNode] {
        recursionDepth += 1
        defer { recursionDepth -= 1 }
        // Two gates: the count matches the Rust reference's limit; the
        // stack-headroom probe is what actually prevents overflow on small
        // stacks (512 KB cooperative/test threads, larger debug frames) —
        // an input that passes the count guard could otherwise SIGBUS the
        // process before ever reaching level 512. See StackGuard.swift.
        if recursionDepth > maxRecursionDepth || !stackHasHeadroom(above: stackFloor) {
            throw ParseError.recursionLimitExceeded
        }
        return try parseExpressionImpl(
            breakOnInfix: breakOnInfix, breakOnTokenText: breakOnTokenText)
    }

    private func parseExpressionImpl(
        breakOnInfix: Bool, breakOnTokenText: String?
    ) throws(ParseError) -> [ParseNode] {
        var body: [ParseNode] = []

        while true {
            if mode == .math {
                try consumeSpaces()
            }

            let lex = try fetch()

            if endOfExpression.contains(lex.text) {
                break
            }
            if let breakText = breakOnTokenText, lex.text == breakText {
                break
            }
            if breakOnInfix, let spec = Functions.registry[lex.text], spec.infix {
                break
            }

            guard let atom = try parseAtom(breakOnTokenText: breakOnTokenText) else {
                break
            }
            if case .internalNode = atom.kind {
                continue
            }
            body.append(atom)
        }

        if mode == .text {
            formLigatures(&body)
        }

        return try handleInfixNodes(body)
    }

    /// Rewrite infix operators (e.g. \over → \frac).
    private func handleInfixNodes(_ body: [ParseNode]) throws(ParseError) -> [ParseNode] {
        var overIndex: Int?
        var funcName: String?

        for (i, node) in body.enumerated() {
            if case let .infix(replaceWith, _) = node.kind {
                if overIndex != nil {
                    throw ParseError("only one infix operator per group")
                }
                overIndex = i
                funcName = replaceWith
            }
        }

        guard let idx = overIndex, let fname = funcName else {
            return body
        }

        func group(_ nodes: [ParseNode]) -> ParseNode {
            if nodes.count == 1, case .ordGroup = nodes[0].kind {
                return nodes[0]
            }
            return ParseNode(.ordGroup(body: nodes, semisimple: nil), mode: mode)
        }

        let numer = group(Array(body[..<idx]))
        let denom = group(Array(body[(idx + 1)...]))

        let node: ParseNode
        if fname == "\\\\abovefrac" {
            // \above passes the infix node (with bar size) as the middle argument
            node = try callFunction(fname, args: [numer, body[idx], denom], optArgs: [])
        } else {
            node = try callFunction(fname, args: [numer, denom], optArgs: [])
        }
        return [node]
    }

    /// Form ligatures in text mode (e.g. -- → –, --- → —).
    private func formLigatures(_ group: inout [ParseNode]) {
        var i = 0
        while i + 1 < group.count {
            if case let .textOrd(a) = group[i].kind, case let .textOrd(b) = group[i + 1].kind {
                if a == "-" && b == "-" {
                    if i + 2 < group.count, case .textOrd("-") = group[i + 2].kind {
                        group[i] = ParseNode(.textOrd(text: "---"), mode: .text)
                        group.remove(at: i + 2)
                        group.remove(at: i + 1)
                        continue
                    }
                    group[i] = ParseNode(.textOrd(text: "--"), mode: .text)
                    group.remove(at: i + 1)
                    continue
                }
                if (a == "'" || a == "`") && b == a {
                    group[i] = ParseNode(.textOrd(text: a + a), mode: .text)
                    group.remove(at: i + 1)
                    continue
                }
            }
            i += 1
        }
    }

    // ── Atom parsing ────────────────────────────────────────────────────

    /// Parse a single atom with optional super/subscripts.
    public func parseAtom(breakOnTokenText: String?) throws(ParseError) -> ParseNode? {
        var base = try parseGroup(name: "atom", breakOnTokenText: breakOnTokenText)

        if let b = base, case .internalNode = b.kind {
            return base
        }

        if mode == .text {
            return base
        }

        var superscript: ParseNode?
        var subscript_: ParseNode?

        loop: while true {
            try consumeSpaces()
            let lex = try fetch()

            switch lex.text {
            case "\\limits", "\\nolimits":
                let isLimits = lex.text == "\\limits"
                consume()
                if var baseNode = base {
                    switch baseNode.kind {
                    case .op(
                        _, _, let suppressBaseShift, let parentIsSupSub,
                        let symbol, let name, let body):
                        baseNode.kind = .op(
                            limits: isLimits, alwaysHandleSupSub: isLimits,
                            suppressBaseShift: suppressBaseShift,
                            parentIsSupSub: parentIsSupSub, symbol: symbol,
                            name: name, body: body)
                        base = baseNode
                    case .operatorName(let body, _, _, let parentIsSupSub):
                        baseNode.kind = .operatorName(
                            body: body, alwaysHandleSupSub: isLimits,
                            limits: isLimits, parentIsSupSub: parentIsSupSub)
                        base = baseNode
                    default:
                        break
                    }
                }
            case "^":
                if superscript != nil {
                    throw ParseError("Double superscript", token: lex)
                }
                superscript = try handleSupSubscript(name: "superscript")
            case "_":
                if subscript_ != nil {
                    throw ParseError("Double subscript", token: lex)
                }
                subscript_ = try handleSupSubscript(name: "subscript")
            case "'":
                if superscript != nil {
                    throw ParseError("Double superscript", token: lex)
                }
                let prime = ParseNode(.textOrd(text: "\\prime"), mode: mode)
                var primes = [prime]
                consume()
                while try fetch().text == "'" {
                    primes.append(prime)
                    consume()
                }
                if try fetch().text == "^" {
                    primes.append(try handleSupSubscript(name: "superscript"))
                }
                superscript = ParseNode(.ordGroup(body: primes, semisimple: nil), mode: mode)
            default:
                guard let first = lex.text.unicodeScalars.first,
                    let (mapped, isSub) = unicodeSubSup(first)
                else {
                    break loop
                }
                if isSub && subscript_ != nil {
                    throw ParseError("Double subscript", token: lex)
                }
                if !isSub && superscript != nil {
                    throw ParseError("Double superscript", token: lex)
                }
                // Collect consecutive Unicode sup/sub chars of the same kind
                var subsupTokens = [Token(mapped, start: 0, end: 0)]
                consume()
                while true {
                    let tok = try fetch()
                    guard let ch = tok.text.unicodeScalars.first,
                        let (m, sub) = unicodeSubSup(ch), sub == isSub
                    else {
                        break
                    }
                    subsupTokens.insert(Token(m, start: 0, end: 0), at: 0)
                    consume()
                }
                let body = try subparse(subsupTokens)
                let group = ParseNode(.ordGroup(body: body, semisimple: nil), mode: .math)
                if isSub {
                    subscript_ = group
                } else {
                    superscript = group
                }
            }
        }

        if superscript != nil || subscript_ != nil {
            return ParseNode(
                .supSub(base: base, sup: superscript, sub: subscript_), mode: mode)
        }
        return base
    }

    /// Handle a subscript or superscript.
    private func handleSupSubscript(name: String) throws(ParseError) -> ParseNode {
        let symbolToken = try fetch()
        consume()
        try consumeSpaces()

        let group = try parseGroup(name: name, breakOnTokenText: nil)
        switch group {
        case let .some(g):
            if case .internalNode = g.kind {
                // Skip internal nodes, try again
                if let g2 = try parseGroup(name: name, breakOnTokenText: nil) {
                    return g2
                }
                throw ParseError("Expected group after '\(symbolToken.text)'", token: symbolToken)
            }
            return g
        case .none:
            throw ParseError("Expected group after '\(symbolToken.text)'", token: symbolToken)
        }
    }

    // ── Group parsing ───────────────────────────────────────────────────

    /// Parse a group: braced expression, function call, or single symbol.
    public func parseGroup(
        name: String, breakOnTokenText: String?
    ) throws(ParseError) -> ParseNode? {
        let firstToken = try fetch()
        let text = firstToken.text

        if text == "{" || text == "\\begingroup" {
            consume()
            let groupEnd = text == "{" ? "}" : "\\endgroup"

            gullet.beginGroup()
            let expression = try parseExpression(breakOnInfix: false, breakOnTokenText: groupEnd)
            let lastToken = try fetch()
            try expect(groupEnd)
            gullet.endGroup()

            return ParseNode(
                .ordGroup(body: expression, semisimple: text == "\\begingroup" ? true : nil),
                mode: mode,
                loc: .range(firstToken.loc, lastToken.loc))
        }

        var result = try parseFunction(breakOnTokenText: breakOnTokenText, name: name)
        if result == nil {
            result = (try? parseSymbolInner()) ?? nil
        }

        if result == nil, text.hasPrefix("\\"), !implicitCommands.contains(text) {
            throw ParseError("Undefined control sequence: \(text)", token: firstToken)
        }

        return result
    }

    // ── Function parsing ────────────────────────────────────────────────

    /// Try to parse a function call. Returns nil if not a function.
    public func parseFunction(
        breakOnTokenText: String?, name: String?
    ) throws(ParseError) -> ParseNode? {
        let token = try fetch()
        let funcName = token.text

        guard let funcData = Functions.registry[funcName] else {
            return nil
        }

        consume()

        if let n = name, n != "atom", !funcData.allowedInArgument {
            throw ParseError(
                "Got function '\(funcName)' with no arguments as \(n)", token: token)
        }

        try checkModeCompatibility(funcData, mode: mode, funcName: funcName, token: token)

        // `\hspace*{len}` — `*` is a separate token (not part of the control word);
        // consume it here. Must use gullet peek/pop only: `parser.fetch()` without
        // `consume()` advances the lexer and leaves `{` only in `nextToken`, so
        // `parseSizeGroup`'s `gullet.future()` would miss the brace.
        if funcName == "\\hspace" {
            gullet.consumeSpaces()
            if gullet.future().text == "*" {
                gullet.popToken()
            }
        }

        let (args, optArgs) = try parseArguments(funcName, funcData)

        return try callFunction(
            funcName, args: args, optArgs: optArgs,
            token: token, breakOnTokenText: breakOnTokenText)
    }

    /// Call a function handler.
    func callFunction(
        _ name: String,
        args: [ParseNode],
        optArgs: [ParseNode?],
        token: Token? = nil,
        breakOnTokenText: String? = nil
    ) throws(ParseError) -> ParseNode {
        guard let spec = Functions.registry[name] else {
            // INTENTIONALLY UNCOVERED: invariant guard. `name` is only ever a
            // key that resolved in `Functions.registry` upstream, so this
            // never fires — kept as a defensive assertion, not deleted.
            throw ParseError("No function handler for \(name)")
        }

        var ctx = FunctionContext(
            funcName: name, parser: self, token: token, breakOnTokenText: breakOnTokenText)
        return try spec.handler(&ctx, args, optArgs)
    }

    /// Parse the arguments for a function.
    func parseArguments(
        _ funcName: String, _ funcData: FunctionSpec
    ) throws(ParseError) -> (args: [ParseNode], optArgs: [ParseNode?]) {
        let totalArgs = funcData.numArgs + funcData.numOptionalArgs
        if totalArgs == 0 {
            return ([], [])
        }

        var args: [ParseNode] = []
        var optArgs: [ParseNode?] = []

        for i in 0..<totalArgs {
            let argType = funcData.argTypes.flatMap { $0.indices.contains(i) ? $0[i] : nil }
            let isOptional = i < funcData.numOptionalArgs

            let effectiveType: ArgType?
            if (funcData.primitive && argType == nil)
                || (funcData.nodeType == "sqrt" && i == 1 && !optArgs.isEmpty && optArgs[0] == nil)
            {
                effectiveType = .primitive
            } else {
                effectiveType = argType
            }

            let arg = try parseGroupOfType(
                name: "argument to '\(funcName)'", argType: effectiveType, optional: isOptional)

            if isOptional {
                optArgs.append(arg)
            } else if let a = arg {
                args.append(a)
            } else {
                throw ParseError("Null argument, please report this as a bug")
            }
        }

        return (args, optArgs)
    }

    /// Parse a group with a specific type.
    private func parseGroupOfType(
        name: String, argType: ArgType?, optional: Bool
    ) throws(ParseError) -> ParseNode? {
        switch argType {
        case .color:
            return try parseColorGroup(optional: optional)
        case .size:
            return try parseSizeGroup(optional: optional)
        case .primitive:
            if optional {
                // INTENTIONALLY UNCOVERED: no builtin declares a `.primitive`
                // optional argument (every registration uses
                // `numOptionalArgs: 0` for primitive args), so `optional` is
                // always false here. Kept as a guard against a future
                // ill-formed registration.
                throw ParseError("A primitive argument cannot be optional")
            }
            guard let group = try parseGroup(name: name, breakOnTokenText: nil) else {
                throw ParseError("Expected group as \(name)")
            }
            return group
        case .math, .text:
            return try parseArgumentGroup(
                optional: optional, mode: argType == .math ? .math : .text)
        case .hbox:
            // INTENTIONALLY UNCOVERED (this nil return): `.hbox` is only ever
            // a *required* argument, so `parseArgumentGroup` returns a value
            // or throws; the absent-optional nil path is defensive.
            guard let group = try parseArgumentGroup(optional: optional, mode: .text) else {
                return nil
            }
            return ParseNode(.styling(style: .text, body: [group]), mode: group.mode)
        case .raw:
            guard let token = try parseStringGroup(modeName: "raw", optional: optional) else {
                return nil
            }
            return ParseNode(.raw(string: token.text), mode: .text)
        case .url:
            return try parseURLGroup(optional: optional)
        case nil, .original:
            return try parseArgumentGroup(optional: optional, mode: nil)
        }
    }

    // Regex is an immutable value type; the missing Sendable conformance is a
    // known stdlib gap (swiftlang#71356), so these constants are safe to share.
    private nonisolated(unsafe) static let colorRegex =
        /^(#[a-fA-F0-9]{3,4}|#[a-fA-F0-9]{6}|#[a-fA-F0-9]{8}|[a-fA-F0-9]{6}|[a-zA-Z]+|\d+(\.\d+)?(,\d+(\.\d+)?)*)$/
    private nonisolated(unsafe) static let hex6Regex = /^[0-9a-fA-F]{6}$/

    /// Parse a color group.
    private func parseColorGroup(optional: Bool) throws(ParseError) -> ParseNode? {
        // INTENTIONALLY UNCOVERED (this nil return): color is always a
        // required argument, so an absent-optional nil is never produced.
        guard let token = try parseStringGroup(modeName: "color", optional: optional) else {
            return nil
        }
        let text = token.text.trimmingCharacters(in: .whitespaces)

        if text.wholeMatch(of: Self.colorRegex) == nil {
            throw ParseError("Invalid color: '\(text)'", token: token)
        }
        var color = text
        if color.wholeMatch(of: Self.hex6Regex) != nil {
            color = "#\(color)"
        }

        return ParseNode(.colorToken(color: color), mode: mode)
    }

    // Hand-rolled equivalents of KaTeX's size regexes:
    //   prefix: /^[-+]? *(?:$|\d+|\d+\.\d*|\.\d*) *[a-z]{0,2} *$/
    //   size:   /([-+]?) *(\d+(?:\.\d*)?|\.\d+) *([a-z]{2})/  (unanchored firstMatch)
    // `parseRegexGroup` re-runs the prefix match on every consumed character,
    // so the Swift Regex interpreter dominated parse profiles. Digits are
    // ASCII-only, matching KaTeX's JS `\d` (Swift/Rust `\d` also accepts
    // Unicode digits — the byte scanner is the KaTeX-correct behavior).
    // Second deliberate divergence, same direction: the scanners match by
    // code unit like JS, so a combining mark on a unit letter (`"1 em\u{301}"`)
    // parses where Swift Regex's grapheme-cluster `[a-z]` rejected it.
    // Both are pinned by SizeScannerDiffTests.

    /// `^[-+]? *(?:$|\d+|\d+\.\d*|\.\d*) *[a-z]{0,2} *$` over UTF-8 bytes.
    /// The `$` alternative admits an empty number only at end-of-string
    /// (e.g. `"-"` and `"- "` match, `"-em"` does not).
    static func sizePrefixMatches(_ s: String) -> Bool {
        let u = s.utf8
        var i = u.startIndex
        let end = u.endIndex
        func skipSpaces() { while i < end, u[i] == 0x20 { u.formIndex(after: &i) } }
        func skipDigits() -> Bool {
            var any = false
            while i < end, u[i] >= 0x30, u[i] <= 0x39 {
                any = true
                u.formIndex(after: &i)
            }
            return any
        }
        if i < end, u[i] == 0x2D /* - */ || u[i] == 0x2B /* + */ { u.formIndex(after: &i) }
        skipSpaces()
        if i < end, u[i] == 0x2E /* . */ {
            u.formIndex(after: &i)
            _ = skipDigits()
        } else if skipDigits() {
            if i < end, u[i] == 0x2E {
                u.formIndex(after: &i)
                _ = skipDigits()
            }
        } else {
            return i == end  // the `$` alternative: empty number ⇒ nothing may follow
        }
        skipSpaces()
        var letters = 0
        while letters < 2, i < end, u[i] >= 0x61, u[i] <= 0x7A {
            u.formIndex(after: &i)
            letters += 1
        }
        skipSpaces()
        return i == end
    }

    /// `([-+]?) *(\d+(?:\.\d*)?|\.\d+) *([a-z]{2})` — first match anywhere in
    /// `text`, returning (sign, magnitude, unit). Greedy scanning is exactly
    /// equivalent to the backtracking regex here: digits/letters/spaces are
    /// disjoint byte classes, so no backtracking path can succeed where the
    /// greedy scan fails at the same start position.
    static func sizeMatch(_ text: String) -> (sign: String, magnitude: String, unit: String)? {
        let b = Array(text.utf8)
        let n = b.count
        var start = 0
        while start < n {
            var i = start
            var sign = ""
            if b[i] == 0x2D || b[i] == 0x2B {
                sign = b[i] == 0x2D ? "-" : "+"
                i += 1
            }
            while i < n, b[i] == 0x20 { i += 1 }
            let magStart = i
            var magEnd = i
            if i < n, b[i] >= 0x30, b[i] <= 0x39 {
                while i < n, b[i] >= 0x30, b[i] <= 0x39 { i += 1 }
                if i < n, b[i] == 0x2E {
                    i += 1
                    while i < n, b[i] >= 0x30, b[i] <= 0x39 { i += 1 }
                }
                magEnd = i
            } else if i < n, b[i] == 0x2E, i + 1 < n, b[i + 1] >= 0x30, b[i + 1] <= 0x39 {
                i += 1
                while i < n, b[i] >= 0x30, b[i] <= 0x39 { i += 1 }
                magEnd = i
            } else {
                start += 1
                continue
            }
            while i < n, b[i] == 0x20 { i += 1 }
            guard i + 1 < n, b[i] >= 0x61, b[i] <= 0x7A, b[i + 1] >= 0x61, b[i + 1] <= 0x7A
            else {
                start += 1
                continue
            }
            let magnitude = String(decoding: b[magStart..<magEnd], as: UTF8.self)
            let unit = String(decoding: b[i...(i + 1)], as: UTF8.self)
            return (sign, magnitude, unit)
        }
        return nil
    }

    /// Parse a size group (e.g. "3pt", "1em").
    public func parseSizeGroup(optional: Bool) throws(ParseError) -> ParseNode? {
        var isBlank = false

        gullet.consumeSpaces()
        let res: Token?
        if !optional && gullet.future().text != "{" {
            res = try parseRegexGroup(
                prefixMatches: Self.sizePrefixMatches, modeName: "size")
        } else {
            res = try parseStringGroup(modeName: "size", optional: optional)
        }

        guard let res else { return nil }

        var text = res.text
        if !optional && text.isEmpty {
            text = "0pt"
            isBlank = true
        }

        guard let m = Self.sizeMatch(text) else {
            throw ParseError("Invalid size: '\(text)'", token: res)
        }

        let sign = m.sign
        let magnitude = m.magnitude
        let unit = m.unit

        let number = Double(sign + magnitude) ?? 0

        if !isValidUnit(unit) {
            throw ParseError("Invalid unit: '\(unit)'", token: res)
        }

        return ParseNode(
            .size(value: Measurement(number: number, unit: unit), isBlank: isBlank),
            mode: mode)
    }

    /// Parse a URL group.
    /// Temporarily disables `%` as comment character to allow `%20` etc. in URLs.
    private func parseURLGroup(optional: Bool) throws(ParseError) -> ParseNode? {
        gullet.lexer.setCatcode("%", 13)
        gullet.lexer.setCatcode("~", 12)
        defer {
            gullet.lexer.setCatcode("%", 14)
            gullet.lexer.setCatcode("~", 13)
        }
        // INTENTIONALLY UNCOVERED (this nil return): url is always a required
        // argument, so an absent-optional nil is never produced.
        guard let token = try parseStringGroup(modeName: "url", optional: optional) else {
            return nil
        }
        return ParseNode(.url(url: token.text), mode: mode)
    }

    /// Parse a string group (brace-enclosed string).
    private func parseStringGroup(
        modeName: String, optional: Bool
    ) throws(ParseError) -> Token? {
        guard let argToken = try gullet.scanArgument(isOptional: optional) else {
            return nil
        }

        var s = ""
        while true {
            let next = try fetch()
            if next.text == "EOF" { break }
            s += next.text
            consume()
        }
        consume()  // consume EOF

        var result = argToken
        result.text = s
        return result
    }

    /// Parse a group delimited by a prefix-matching predicate.
    private func parseRegexGroup(
        prefixMatches: (String) -> Bool, modeName: String
    ) throws(ParseError) -> Token {
        let firstToken = try fetch()
        var lastToken = firstToken
        var s = ""

        while true {
            let next = try fetch()
            if next.text == "EOF" { break }
            let candidate = s + next.text
            if prefixMatches(candidate) {
                lastToken = next
                s = candidate
                consume()
            } else {
                break
            }
        }

        if s.isEmpty {
            throw ParseError("Invalid \(modeName): '\(firstToken.text)'", token: firstToken)
        }

        return firstToken.range(to: lastToken, text: s)
    }

    /// Parse an argument group (with optional mode switch).
    public func parseArgumentGroup(
        optional: Bool, mode argMode: Mode?
    ) throws(ParseError) -> ParseNode? {
        guard let argToken = try gullet.scanArgument(isOptional: optional) else {
            return nil
        }

        let outerMode = mode
        if let m = argMode {
            switchMode(m)
        }

        gullet.beginGroup()
        let expression = try parseExpression(breakOnInfix: false, breakOnTokenText: "EOF")
        try expect("EOF")
        gullet.endGroup()

        let result = ParseNode(
            .ordGroup(body: expression, semisimple: nil), mode: mode, loc: argToken.loc)

        if argMode != nil {
            switchMode(outerMode)
        }

        return result
    }

    // ── Symbol parsing ──────────────────────────────────────────────────

    /// Parse a single symbol.
    func parseSymbolInner() throws(ParseError) -> ParseNode? {
        let nucleus = try fetch()
        let text = nucleus.text

        if text.hasPrefix("\\verb") {
            consume()
            var rest = text.dropFirst("\\verb".count)
            let star = rest.hasPrefix("*")
            if star {
                rest = rest.dropFirst()
            }
            if rest.count < 2 {
                throw ParseError("\\verb assertion failed", token: nucleus)
            }
            let body = String(rest.dropFirst().dropLast())
            return ParseNode(.verb(body: body, star: star), mode: .text, loc: nucleus.loc)
        }

        // ^ and _ are handled by parseAtom for sup/sub, not as symbol nodes.
        // Bare backslash (incomplete control sequence) → not a valid symbol.
        if text == "^" || text == "_" || text == "\\" {
            return nil
        }

        if let symInfo = SymbolInfo(name: text, mode: mode) {
            let loc = SourceLocation.range(nucleus.loc, nucleus.loc)
            let group = symInfo.group

            let kind: ParseNode.Kind
            if group.isAtom {
                let family: AtomFamily =
                    switch group {
                    case .bin: .bin
                    case .close: .close
                    case .inner: .inner
                    case .open: .open
                    case .punct: .punct
                    default: .rel
                    }
                kind = .atom(family: family, text: text)
            } else {
                kind =
                    switch group {
                    case .mathOrd: .mathOrd(text: text)
                    case .textOrd: .textOrd(text: text)
                    case .opToken: .opToken(text: text)
                    case .accentToken: .accentToken(text: text)
                    case .spacing: .spacing(text: text)
                    default: .mathOrd(text: text)
                    }
            }

            consume()
            return ParseNode(kind, mode: mode, loc: loc)
        }

        // Unicode accented characters → decompose into accent nodes.
        // Handles both precomposed (á U+00E1) and combining forms (a + U+0301).
        if let node = try tryParseUnicodeAccent(text, nucleus: nucleus) {
            consume()
            return node
        }

        // Non-ASCII characters without accent decomposition → treat as textord.
        // KaTeX always uses mode="text" for these, regardless of current mode.
        if let first = text.unicodeScalars.first, first.value >= 0x80 {
            let node = ParseNode(
                .textOrd(text: text), mode: .text,
                loc: .range(nucleus.loc, nucleus.loc))
            consume()
            return node
        }

        return nil
    }

    /// Try to decompose a Unicode accented character into accent nodes.
    /// Returns nil if no decomposition is available.
    /// Only decomposes Latin-script characters, matching KaTeX behavior.
    private func tryParseUnicodeAccent(
        _ text: String, nucleus: Token
    ) throws(ParseError) -> ParseNode? {
        let nfd = text.decomposedStringWithCanonicalMapping
        let chars = Array(nfd.unicodeScalars)

        if chars.count < 2 {
            return nil
        }

        // Build from the base up through each combining mark
        var splitIdx = chars.count - 1
        while splitIdx > 0 && isSupportedCombiningAccent(chars[splitIdx]) {
            splitIdx -= 1
        }

        // Verify at least one trailing char is a supported combining accent
        if splitIdx == chars.count - 1 {
            return nil
        }

        // Only decompose Latin-script base characters
        if !isLatinBaseChar(chars[0]) {
            return nil
        }

        let loc = SourceLocation.range(nucleus.loc, nucleus.loc)

        // Base: everything before the combining marks
        var baseStr = String(String.UnicodeScalarView(chars[...splitIdx]))

        // Accented i→ı and j→ȷ (dotless variants), matching KaTeX behavior
        switch baseStr {
        case "i": baseStr = "\u{0131}"  // ı
        case "j": baseStr = "\u{0237}"  // ȷ
        default: break
        }

        var node: ParseNode
        if baseStr.unicodeScalars.count == 1 {
            let ch = baseStr.unicodeScalars.first!
            if let sym = SymbolInfo(name: baseStr, mode: mode) {
                if sym.group == .textOrd {
                    node = ParseNode(.textOrd(text: baseStr), mode: mode, loc: loc)
                } else {
                    node = ParseNode(.mathOrd(text: baseStr), mode: mode, loc: loc)
                }
            } else if ch.value >= 0x80 {
                // Non-ASCII base chars always text mode (KaTeX compat)
                node = ParseNode(.textOrd(text: baseStr), mode: .text, loc: loc)
            } else {
                // INTENTIONALLY UNCOVERED: an ASCII base that is not a known
                // symbol yet carries combining marks — not produced by valid
                // LaTeX (such bytes error earlier in symbol parsing). Kept as
                // the exhaustive else.
                node = ParseNode(.mathOrd(text: baseStr), mode: mode, loc: loc)
            }
        } else {
            // INTENTIONALLY UNCOVERED: a multi-scalar base preceding combining
            // marks (e.g. a surrogate-pair glyph + mark) — not reached by the
            // corpus; defensive fallback to a Unicode accent or textOrd.
            node =
                try tryParseUnicodeAccent(baseStr, nucleus: nucleus)
                ?? ParseNode(.textOrd(text: baseStr), mode: .text, loc: loc)
        }

        // Wrap in accent nodes from innermost to outermost
        for combining in chars[(splitIdx + 1)...] {
            let label = combiningToAccentLabel(combining, mode: mode)
            node = ParseNode(
                .accent(label: label, isStretchy: false, isShifty: true, base: node),
                mode: mode, loc: loc)
        }

        return node
    }

    /// Parse a sub-expression from the given tokens.
    public func subparse(_ tokens: [Token]) throws(ParseError) -> [ParseNode] {
        let oldToken = nextToken
        nextToken = nil

        gullet.pushToken(Token("}", start: 0, end: 0))
        gullet.pushTokens(tokens)
        let parse = try parseExpression(breakOnInfix: false, breakOnTokenText: nil)
        try expect("}")

        nextToken = oldToken
        return parse
    }
}

private func isLatinBaseChar(_ ch: Unicode.Scalar) -> Bool {
    switch ch {
    case "A"..."Z", "a"..."z",
        "\u{0131}",  // ı (dotless i)
        "\u{0237}",  // ȷ (dotless j)
        "\u{00C6}",  // Æ
        "\u{00D0}",  // Ð
        "\u{00D8}",  // Ø
        "\u{00DE}",  // Þ
        "\u{00DF}",  // ß
        "\u{00E6}",  // æ
        "\u{00F0}",  // ð
        "\u{00F8}",  // ø
        "\u{00FE}":  // þ
        true
    default:
        false
    }
}

private func isSupportedCombiningAccent(_ ch: Unicode.Scalar) -> Bool {
    switch ch {
    case "\u{0300}", "\u{0301}", "\u{0302}", "\u{0303}", "\u{0304}", "\u{0306}",
        "\u{0307}", "\u{0308}", "\u{030A}", "\u{030B}", "\u{030C}", "\u{0327}":
        true
    default:
        false
    }
}

private func combiningToAccentLabel(_ ch: Unicode.Scalar, mode: Mode) -> String {
    switch mode {
    case .math:
        switch ch {
        case "\u{0300}": "\\grave"
        case "\u{0301}": "\\acute"
        case "\u{0302}": "\\hat"
        case "\u{0303}": "\\tilde"
        case "\u{0304}": "\\bar"
        case "\u{0306}": "\\breve"
        case "\u{0307}": "\\dot"
        case "\u{0308}": "\\ddot"
        case "\u{030A}": "\\mathring"
        case "\u{030B}": "\\H"
        case "\u{030C}": "\\check"
        case "\u{0327}": "\\c"
        default: "\\char\"\(String(ch.value, radix: 16, uppercase: true))"
        }
    case .text:
        switch ch {
        case "\u{0300}": "\\`"
        case "\u{0301}": "\\'"
        case "\u{0302}": "\\^"
        case "\u{0303}": "\\~"
        case "\u{0304}": "\\="
        case "\u{0306}": "\\u"
        case "\u{0307}": "\\."
        case "\u{0308}": "\\\""
        case "\u{030A}": "\\r"
        case "\u{030B}": "\\H"
        case "\u{030C}": "\\v"
        case "\u{0327}": "\\c"
        default: "\\char\"\(String(ch.value, radix: 16, uppercase: true))"
        }
    }
}

func isValidUnit(_ unit: String) -> Bool {
    switch unit {
    case "pt", "mm", "cm", "in", "bp", "pc", "dd", "cc", "nd", "nc", "sp", "px", "ex", "em", "mu":
        true
    default:
        false
    }
}

/// If the whole expression is wrapped in TeX inline/display math delimiters,
/// parse the inside only. The parser already runs in math mode; a leading `$`
/// would otherwise hit the `$` / `\(` "switch to math" handler, which is
/// disallowed in math mode (see the `math` function handlers).
private func stripOuterMathDelimiters(_ input: String) -> Substring {
    func trimmed(_ s: Substring) -> Substring {
        var s = s
        while let f = s.first, f.isWhitespace { s.removeFirst() }
        while let l = s.last, l.isWhitespace { s.removeLast() }
        return s
    }
    let s = trimmed(input[...])
    if s.count >= 4 && s.hasPrefix("$$") && s.hasSuffix("$$") {
        return trimmed(s.dropFirst(2).dropLast(2))
    }
    if s.count >= 2 && s.hasPrefix("$") && s.hasSuffix("$") {
        return trimmed(s.dropFirst().dropLast())
    }
    return s
}

/// Convenience function: parse a LaTeX string and return the AST.
public func parseLaTeX(_ input: String) throws(ParseError) -> [ParseNode] {
    try Parser(String(stripOuterMathDelimiters(input))).parse()
}
