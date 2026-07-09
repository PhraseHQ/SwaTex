/// Commands that act like macros but aren't defined as a macro, function, or symbol.
/// Used in `isDefined`.
let implicitCommands: Set<String> = ["^", "_", "\\limits", "\\nolimits"]

/// Handler type for function-based macros (e.g. \TextOrMath, \@ifstar).
/// Takes the MacroExpander and returns tokens to push onto the stack.
typealias MacroHandler = @Sendable (MacroExpander) throws(ParseError) -> [Token]

/// A macro definition: string template, token list, or function.
enum MacroDefinition: Sendable {
    /// Simple string expansion (e.g. `\def\foo{bar}` → "bar")
    case text(String)
    /// Pre-tokenized expansion with argument count
    case tokens([Token], numArgs: Int)
    /// Function-based macro (consumes tokens directly, returns expansion)
    case function(MacroHandler)
}

/// Result of expanding a macro once. Internal (not private) so the
/// direct-call branch tests can observe `getExpansion`.
struct MacroExpansion {
    var tokens: [Token]
    var numArgs: Int
}

/// A consumed macro argument. `tokens` are in *stack order* (reversed).
struct ConsumedArg {
    var tokens: [Token]
    var start: Token
    var end: Token
}

/// Scoped macro namespace supporting group nesting.
private struct MacroNamespace {
    var current: [String: MacroDefinition] = [:]
    var groupStack: [[String: MacroDefinition?]] = []

    func get(_ name: String) -> MacroDefinition? {
        current[name]
    }

    mutating func set(_ name: String, _ def: MacroDefinition) {
        if !groupStack.isEmpty {
            let last = groupStack.count - 1
            if groupStack[last][name] == nil {
                groupStack[last][name] = .some(current[name])
            }
        }
        current[name] = def
    }

    mutating func setGlobal(_ name: String, _ def: MacroDefinition) {
        current[name] = def
    }

    func has(_ name: String) -> Bool {
        current[name] != nil
    }

    mutating func beginGroup() {
        groupStack.append([:])
    }

    mutating func endGroup() {
        guard let undo = groupStack.popLast() else { return }
        for (name, oldValue) in undo {
            switch oldValue {
            case .some(let def): current[name] = def
            case .none: current[name] = nil
            }
        }
    }

    mutating func endGroups() {
        while !groupStack.isEmpty {
            endGroup()
        }
    }
}

/// Tokenize a macro expansion string into stack order (same as
/// ``MacroDefinition/text(_:)`` bodies).
func lexStringToStackTokens(_ text: String) -> [Token] {
    var bodyLexer = Lexer(text)
    var tokens: [Token] = []
    while true {
        let tok = bodyLexer.lex()
        if tok.isEOF { break }
        tokens.append(tok)
    }
    tokens.reverse()
    return tokens
}

private func dotscSpaceAfter(_ next: String) -> Bool {
    switch next {
    case ")", "]", "\\rbrack", "\\}", "\\rbrace", "\\rangle", "\\rceil",
        "\\rfloor", "\\rgroup", "\\rmoustache", "\\right", "\\bigr",
        "\\biggr", "\\Bigr", "\\Biggr", "$", ";", ".":
        true
    default:
        false
    }
}

/// The MacroExpander (or "gullet") manages macro expansion.
///
/// It sits between the Lexer (mouth) and the Parser (stomach).
/// Tokens are read from the lexer, pushed onto an internal stack,
/// and macros are expanded until only non-expandable tokens remain.
///
/// Modeled after KaTeX's MacroExpander.ts.
final class MacroExpander {
    var lexer: Lexer
    var mode: Mode
    private var stack: [Token] = []
    private var macros = MacroNamespace()
    private var expansionCount = 0
    private let maxExpand = 1000

    init(_ input: String, mode: Mode) {
        self.lexer = Lexer(input)
        self.mode = mode
        // CoW share of the prebuilt builtin table: O(1) instead of ~370
        // dictionary inserts per parse (measured in the performance log P-009).
        macros = MacroNamespace(current: Self.builtinMacroTable)
    }

    func setMacro(_ name: String, _ def: MacroDefinition) {
        macros.set(name, def)
    }

    func setMacroGlobal(_ name: String, _ def: MacroDefinition) {
        macros.setGlobal(name, def)
    }

    func setTextMacro(_ name: String, _ text: String) {
        macros.set(name, .text(text))
    }

    func getMacro(_ name: String) -> MacroDefinition? {
        macros.get(name)
    }

    /// Expand a list of tokens fully (for \edef/\xdef).
    func expandTokens(_ tokens: [Token]) throws(ParseError) -> [Token] {
        let savedStack = stack
        stack = tokens
        defer { stack = savedStack }

        var result: [Token] = []
        while !stack.isEmpty {
            let expanded = try expandOnce(expandableOnly: false)
            if !expanded, var tok = stack.popLast() {
                if tok.isEOF { break }
                // KaTeX MacroExpander.expandTokens: `\noexpand`'s protection
                // applies to THIS expansion only — clear the flags so the
                // token expands normally when the \edef'd macro is later
                // used. (KaTeX-correctness fix; RaTeX keeps the flags and
                // renders `\edef\z{\noexpand\alpha}\z` as empty.)
                if tok.treatAsRelax {
                    tok.noexpand = false
                    tok.treatAsRelax = false
                }
                result.append(tok)
            }
        }

        result.reverse()
        return result
    }

    func switchMode(_ newMode: Mode) {
        mode = newMode
    }

    func beginGroup() {
        macros.beginGroup()
    }

    func endGroup() {
        macros.endGroup()
    }

    func endGroups() {
        macros.endGroups()
    }

    /// Returns the topmost token on the stack, without expanding it.
    @discardableResult
    func future() -> Token {
        if stack.isEmpty {
            stack.append(lexer.lex())
        }
        return stack[stack.count - 1]
    }

    /// Remove and return the next unexpanded token.
    @discardableResult
    func popToken() -> Token {
        future()
        return stack.removeLast()
    }

    /// Modify the top token's text on the stack (for \global prefix handling).
    func setTopText(_ text: String) {
        future()
        stack[stack.count - 1].text = text
    }

    /// Push a token onto the stack.
    func pushToken(_ token: Token) {
        stack.append(token)
    }

    /// Push multiple tokens onto the stack.
    func pushTokens(_ tokens: [Token]) {
        stack.append(contentsOf: tokens)
    }

    /// Consume all following space tokens, without expansion.
    func consumeSpaces() {
        while future().text == " " {
            stack.removeLast()
        }
    }

    /// Expand the next token once if possible.
    /// Returns `true` if expanded, `false` if not expandable.
    private func expandOnce(expandableOnly: Bool) throws(ParseError) -> Bool {
        let topToken = popToken()
        let name = topToken.text

        if topToken.noexpand {
            pushToken(topToken)
            return false
        }

        // Single dictionary lookup per token (this is the parser's hottest
        // path; see P-010 in the performance log). A pre-probe catcode
        // fast-reject was tried and REJECTED (P-021): this lexer's default
        // catcode is 0, so the gate almost never fires (performance log, P-021).
        let def = macros.get(name)

        // Check for function-based macro first — always expandable
        if case let .function(handler) = def {
            try countExpansion(1)
            let tokens = try handler(self)
            stack.append(contentsOf: tokens)
            return true
        }

        guard let exp = getExpansion(def, name: name) else {
            if expandableOnly, name.hasPrefix("\\"), !isDefined(name) {
                throw ParseError("Undefined control sequence: \(name)", token: topToken)
            }
            pushToken(topToken)
            return false
        }

        try countExpansion(1)
        var tokens = exp.tokens
        if exp.numArgs > 0 {
            let args = try consumeArgs(exp.numArgs)
            tokens = substituteArgs(tokens, args)
        }
        stack.append(contentsOf: tokens)
        return true
    }

    private func substituteArgs(_ tokens: [Token], _ args: [[Token]]) -> [Token] {
        var tokens = tokens
        var i = tokens.count
        while i > 0 {
            i -= 1
            if tokens[i].text == "#" && i > 0 {
                let next = tokens[i - 1]
                if next.text == "#" {
                    tokens.remove(at: i)
                    i -= 1
                } else if let n = Int(next.text), n >= 1, n <= args.count {
                    tokens.remove(at: i)
                    tokens.remove(at: i - 1)
                    tokens.insert(contentsOf: args[n - 1], at: i - 1)
                    i = max(i - 1, 0)
                }
            }
        }
        return tokens
    }

    func getExpansion(_ def: MacroDefinition?, name: String) -> MacroExpansion? {
        guard let def else { return nil }

        if name.unicodeScalars.count == 1, let ch = name.unicodeScalars.first {
            let catcode = lexer.catcode(ch)
            if catcode != 0 && catcode != 13 {
                return nil
            }
        }

        switch def {
        case .text(let text):
            var numArgs = 0
            let stripped = text.replacingOccurrences(of: "##", with: "")
            while stripped.contains("#\(numArgs + 1)") {
                numArgs += 1
            }
            return MacroExpansion(
                tokens: lexStringToStackTokens(text), numArgs: numArgs)
        case .tokens(let tokens, let numArgs):
            return MacroExpansion(tokens: tokens, numArgs: numArgs)
        case .function:
            // `expandOnce` matches `.function` before calling `getExpansion`,
            // so this is only reached by direct calls (DirectUnitTests);
            // signals a function macro to the caller.
            return MacroExpansion(tokens: [], numArgs: 0)
        }
    }

    private func countExpansion(_ amount: Int) throws(ParseError) {
        expansionCount += amount
        if expansionCount > maxExpand {
            throw ParseError(
                "Too many expansions: infinite loop or need to increase maxExpand setting")
        }
    }

    /// Recursively expand the next token until a non-expandable token is found.
    func expandNextToken() throws(ParseError) -> Token {
        while true {
            let expanded = try expandOnce(expandableOnly: false)
            if !expanded {
                var token = stack.removeLast()
                if token.treatAsRelax {
                    token.text = "\\relax"
                }
                return token
            }
        }
    }

    /// Consume a single argument from the token stream.
    /// The returned tokens are in *stack order* (reversed).
    func consumeArg(delims: [String]? = nil) throws(ParseError) -> ConsumedArg {
        let isDelimited = delims.map { !$0.isEmpty } ?? false
        if !isDelimited {
            consumeSpaces()
        }

        let start = future()
        var tokens: [Token] = []
        var depth = 0
        var endTok = start

        while true {
            let tok = popToken()
            endTok = tok
            tokens.append(tok)

            if tok.text == "{" {
                depth += 1
            } else if tok.text == "}" {
                depth -= 1
                if depth == -1 {
                    throw ParseError("Extra }", token: tok)
                }
            } else if tok.isEOF {
                throw ParseError("Unexpected end of input in a macro argument", token: tok)
            }

            if depth == 0 && !isDelimited {
                break
            }

            if isDelimited, depth == 0, let last = delims?.last, tok.text == last {
                tokens.removeLast()
                break
            }
        }

        if start.text == "{", tokens.last?.text == "}" {
            tokens.removeLast()
            tokens.removeFirst()
        }

        tokens.reverse()
        return ConsumedArg(tokens: tokens, start: start, end: endTok)
    }

    /// Consume N arguments. Each argument's tokens are in stack order.
    func consumeArgs(_ numArgs: Int) throws(ParseError) -> [[Token]] {
        var args: [[Token]] = []
        args.reserveCapacity(numArgs)
        for _ in 0..<numArgs {
            args.append(try consumeArg().tokens)
        }
        return args
    }

    /// Scan a function argument (optional or mandatory).
    /// Pushes an EOF token to mark the end, then pushes the argument tokens.
    func scanArgument(isOptional: Bool) throws(ParseError) -> Token? {
        let startLoc: SourceLocation
        let arg: ConsumedArg
        if isOptional {
            consumeSpaces()
            if future().text != "[" {
                return nil
            }
            let start = popToken()
            arg = try consumeArg(delims: ["]"])
            startLoc = start.loc
        } else {
            arg = try consumeArg()
            startLoc = arg.start.loc
        }
        let endLoc = arg.end.loc

        pushToken(Token("EOF", start: endLoc.start, end: endLoc.end))
        pushTokens(arg.tokens)

        var result = Token("", start: 0, end: 0)
        result.loc = .range(startLoc, endLoc)
        return result
    }

    /// Check if a command name is currently defined.
    func isDefined(_ name: String) -> Bool {
        macros.has(name)
            || Functions.registry[name] != nil
            || isKnownSymbol(name)
            || implicitCommands.contains(name)
    }

    /// Check if a command is expandable.
    func isExpandable(_ name: String) -> Bool {
        if macros.get(name) != nil {
            return true
        }
        if let spec = Functions.registry[name] {
            return !spec.primitive
        }
        return false
    }
}

private func isKnownSymbol(_ name: String) -> Bool {
    SymbolInfo(name: name, mode: .math) != nil || SymbolInfo(name: name, mode: .text) != nil
}

private func handleNewcommand(
    _ me: MacroExpander, existsOK: Bool, nonexistsOK: Bool
) throws(ParseError) -> [Token] {
    let nameArg = try me.consumeArg()
    // nameArg.tokens is reversed (stack order); last element = first token in original
    let name = nameArg.tokens.last?.text ?? ""

    let exists = me.isDefined(name)
    if exists && !existsOK {
        throw ParseError(
            "\\newcommand{\(name)} attempting to redefine \(name); use \\renewcommand")
    }
    if !exists && !nonexistsOK {
        throw ParseError(
            "\\renewcommand{\(name)} when command \(name) does not yet exist; use \\newcommand")
    }

    me.consumeSpaces()
    var numArgs = 0
    if me.future().text == "[" {
        me.popToken()
        let nargTok = me.popToken()
        numArgs = Int(nargTok.text) ?? 0
        let close = me.popToken()
        if close.text != "]" {
            throw ParseError("Expected ] in \\newcommand")
        }
    }

    let bodyArg = try me.consumeArg()
    me.setMacro(name, .tokens(bodyArg.tokens, numArgs: numArgs))
    return []
}

// ── Built-in macros ─────────────────────────────────────────────────────────

extension MacroExpander {
    /// The builtin macro table, built once per process.
    ///
    /// Text macros are pre-tokenized: `.text` re-lexes its body on every
    /// expansion, but builtins never change, so we bake tokens + arg count
    /// at first use (P-009 in the performance log).
    static let builtinMacroTable: [String: MacroDefinition] = {
        var m = [String: MacroDefinition](minimumCapacity: 512)
        for (name, expansion) in builtinTextMacros {
            m[name] = .tokens(
                lexStringToStackTokens(expansion),
                numArgs: textMacroArgCount(expansion))
        }
        addFunctionMacros(&m)
        return m
    }()

    /// Argument count of a text-macro body: highest contiguous `#N`
    /// (`##` escapes ignored) — must match `getExpansion`'s counting.
    private static func textMacroArgCount(_ text: String) -> Int {
        var numArgs = 0
        let stripped = text.replacingOccurrences(of: "##", with: "")
        while stripped.contains("#\(numArgs + 1)") {
            numArgs += 1
        }
        return numArgs
    }

    private static func addFunctionMacros(_ m: inout [String: MacroDefinition]) {
        // \noexpand: mark the next token as non-expandable (only if expandable)
        // \expandafter⟨tok1⟩⟨tok2⟩: expand tok2 once, then put tok1 back in
        // front of the result. (KaTeX macros.ts; not implemented in RaTeX —
        // this is a beyond-parity addition, see the KaTeX support table.)
        m["\\expandafter"] = .function { me throws(ParseError) in
            let t = me.popToken()
            _ = try me.expandOnce(expandableOnly: true)
            return [t]
        }

        m["\\noexpand"] = .function { me throws(ParseError) in
            var tok = me.popToken()
            if me.isExpandable(tok.text) {
                tok.noexpand = true
                tok.treatAsRelax = true
            }
            return [tok]
        }

        // \@firstoftwo{A}{B} → A
        // NOTE: consumeArgs returns tokens in stack order (reversed).
        // We return them as-is since expandOnce does stack.append(contentsOf:).
        m["\\@firstoftwo"] = .function { me throws(ParseError) in
            let args = try me.consumeArgs(2)
            return args[0]
        }

        // \@secondoftwo{A}{B} → B
        m["\\@secondoftwo"] = .function { me throws(ParseError) in
            let args = try me.consumeArgs(2)
            return args[1]
        }

        // \@ifnextchar{C}{T}{F}: peek; if next non-space == C then T else F
        m["\\@ifnextchar"] = .function { me throws(ParseError) in
            let args = try me.consumeArgs(3)
            me.consumeSpaces()
            let next = me.future().text
            // args[0] is reversed; the "first" char in original order is the last element
            let charText = args[0].first?.text ?? ""
            return next == charText ? args[1] : args[2]
        }

        // \@ifstar{with-star}{without-star}: if next is * → consume * and use first arg
        m["\\@ifstar"] = .function { me throws(ParseError) in
            let args = try me.consumeArgs(2)
            if me.future().text == "*" {
                me.popToken()
                return args[0]
            }
            return args[1]
        }

        // \TextOrMath{text-branch}{math-branch}: choose based on mode
        m["\\TextOrMath"] = .function { me throws(ParseError) in
            let args = try me.consumeArgs(2)
            return me.mode == .text ? args[0] : args[1]
        }

        // KaTeX/amsmath: \dotsc adds a thin space before selected right
        // delimiters/punctuation, but not before a following comma.
        m["\\dotsc"] = .function { me throws(ParseError) in
            let next = me.future().text
            let text = dotscSpaceAfter(next) ? "\\ldots\\," : "\\ldots"
            return lexStringToStackTokens(text)
        }

        // \html@mathml is registered as a function in HtmlMathML.swift

        // \newcommand{\name}[nargs]{body}
        m["\\newcommand"] = .function { me throws(ParseError) in
            try handleNewcommand(me, existsOK: false, nonexistsOK: true)
        }

        // \renewcommand{\name}[nargs]{body}
        m["\\renewcommand"] = .function { me throws(ParseError) in
            try handleNewcommand(me, existsOK: true, nonexistsOK: false)
        }

        // \providecommand{\name}[nargs]{body}
        m["\\providecommand"] = .function { me throws(ParseError) in
            try handleNewcommand(me, existsOK: true, nonexistsOK: true)
        }

        // \char: parse decimal/octal/hex/backtick number → \@char{N}
        m["\\char"] = .function { me throws(ParseError) in
            var tok = me.popToken()
            var number: Int64 = 0
            let base: Int?

            func atCharTokens(_ number: Int64, loc: SourceLocation) -> [Token] {
                // Build \@char{N} tokens in reverse (stack order)
                var result = [Token("}", start: loc.start, end: loc.end)]
                for ch in String(number).reversed() {
                    result.append(Token(String(ch), start: loc.start, end: loc.end))
                }
                result.append(Token("{", start: loc.start, end: loc.end))
                result.append(Token("\\@char", start: loc.start, end: loc.end))
                return result
            }

            if tok.text == "'" {
                base = 8
                tok = me.popToken()
            } else if tok.text == "\"" {
                base = 16
                tok = me.popToken()
            } else if tok.text == "`" {
                tok = me.popToken()
                if tok.text.hasPrefix("\\") {
                    number = Int64(tok.text.unicodeScalars.dropFirst().first?.value ?? 0)
                } else {
                    number = Int64(tok.text.unicodeScalars.first?.value ?? 0)
                }
                return atCharTokens(number, loc: tok.loc)
            } else {
                base = 10
            }

            if let b = base {
                number = Int64(tok.text, radix: b) ?? 0
                while true {
                    let next = me.future().text
                    if let d = Int64(next, radix: b) {
                        me.popToken()
                        // Wrapping arithmetic: an unbounded digit run (e.g.
                        // `\char9999...`) must not trap; matches the Rust
                        // release-mode `i64` overflow behavior.
                        number = number &* Int64(b) &+ d
                    } else {
                        break
                    }
                }
            }

            return atCharTokens(number, loc: tok.loc)
        }

        // \operatorname: \@ifstar\operatornamewithlimits\operatorname@
        m["\\operatorname"] = .text("\\@ifstar\\operatornamewithlimits\\operatorname@")

        // amsopn \DeclareMathOperator{\op}{name} (+ starred limits variant).
        // Beyond KaTeX (which asks users to hand-write \operatorname) — this
        // is one of the most common commands in real math preambles.
        // Defined as: \op → \operatorname{name} (or \operatorname*{name}).
        m["\\DeclareMathOperator"] = .function { me throws(ParseError) in
            var star = false
            if me.future().text == "*" {
                me.popToken()
                star = true
            }
            let nameArg = try me.consumeArg()
            // Stack order: the defined control sequence is the last element.
            let name = nameArg.tokens.last?.text ?? ""
            guard name.hasPrefix("\\"), name.count > 1 else {
                throw ParseError(
                    "\\DeclareMathOperator: expected a control sequence, got '\(name)'",
                    token: nameArg.start)
            }
            let bodyArg = try me.consumeArg()
            // Body tokens are in stack order; build the expansion in stack
            // order too: "}" + reversed(body) + "{" + "\operatorname[*]".
            var expansion: [Token] = [Token("}", start: 0, end: 0)]
            expansion.append(contentsOf: bodyArg.tokens)
            expansion.append(Token("{", start: 0, end: 0))
            if star {
                expansion.append(Token("*", start: 0, end: 0))
            }
            expansion.append(Token("\\operatorname", start: 0, end: 0))
            // `expansion` was assembled directly in stack order above.
            // amsopn defines operators globally (\gdef-like); match that.
            me.setMacroGlobal(name, .tokens(expansion, numArgs: 0))
            return []
        }

        // \message{...} / \errmessage{...}: consume argument and discard (no-op)
        m["\\message"] = .function { me throws(ParseError) in
            _ = try me.consumeArgs(1)
            return []
        }
        m["\\errmessage"] = .function { me throws(ParseError) in
            _ = try me.consumeArgs(1)
            return []
        }

        // KaTeX HTML extensions: no-op (only render content, no HTML attributes).
        // Not standard LaTeX; for compatibility we parse and expand to second argument only.
        // \htmlStyle is registered as a real function so the renderer can honor basic CSS.
        for name in ["\\htmlClass", "\\htmlData", "\\htmlId"] {
            m[name] = .function { me throws(ParseError) in
                let args = try me.consumeArgs(2)
                // consumeArgs returns stack order, which is exactly what the
                // expansion stack expects. (KaTeX-correctness fix: RaTeX
                // reverses here, so \htmlClass{c}{xy} rendered as "yx".)
                return args[1]
            }
        }

        // \bra@ket: like \bra@set but replaces ALL | at depth 0 (for \Braket)
        m["\\bra@ket"] = .function { me throws(ParseError) in
            let args = try me.consumeArgs(4)
            let left = args[0]
            let middle = args[1]
            let middleDouble = args[2]
            let right = args[3]

            let content = try me.consumeArgs(1)[0]

            // Convert stack-order (reversed) to logical order, replace all | at
            // depth 0, then reverse back to stack order.
            let logical: [Token] = content.reversed()
            var newLogical: [Token] = []
            var depth = 0
            var i = 0
            while i < logical.count {
                let t = logical[i]
                if t.text == "{" {
                    depth += 1
                    newLogical.append(t)
                } else if t.text == "}" {
                    depth -= 1
                    newLogical.append(t)
                } else if depth == 0 && t.text == "|" {
                    // Check for || (double pipe) → middleDouble
                    if !middleDouble.isEmpty, i + 1 < logical.count, logical[i + 1].text == "|" {
                        // middleDouble is in stack/reversed order; reverse to logical order
                        newLogical.append(contentsOf: middleDouble.reversed())
                        i += 2
                        continue
                    }
                    // middle is in stack/reversed order; reverse to logical order
                    newLogical.append(contentsOf: middle.reversed())
                } else {
                    newLogical.append(t)
                }
                i += 1
            }

            // Build: right + content + left (reversed for stack)
            var toExpand: [Token] = []
            toExpand.append(contentsOf: right)
            toExpand.append(contentsOf: newLogical.reversed())
            toExpand.append(contentsOf: left)

            me.beginGroup()
            let expanded = try me.expandTokens(toExpand)
            me.endGroup()
            return expanded
        }

        // \bra@set: braket set notation helper.
        // Only replaces the FIRST | with middle tokens (one-shot), matching KaTeX.
        m["\\bra@set"] = .function { me throws(ParseError) in
            let args = try me.consumeArgs(4)
            let left = args[0]
            let middle = args[1]
            let middleDouble = args[2]
            let right = args[3]

            var content = try me.consumeArgs(1)[0]

            // Scan content and replace only the first | at depth 0.
            // Content tokens are in reversed order (stack), scan in logical order.
            var depth = 0
            for i in stride(from: content.count - 1, through: 0, by: -1) {
                let t = content[i]
                if t.text == "{" {
                    depth += 1
                } else if t.text == "}" {
                    depth -= 1
                } else if depth == 0 && t.text == "|" {
                    // Check for || (double pipe) → middleDouble
                    if !middleDouble.isEmpty, i > 0, content[i - 1].text == "|" {
                        content.remove(at: i)
                        content.remove(at: i - 1)
                        let insertAt = i >= 2 ? i - 1 : 0
                        content.insert(contentsOf: middleDouble, at: insertAt)
                        break
                    }
                    content.remove(at: i)
                    content.insert(contentsOf: middle, at: i)
                    break
                }
            }

            // Build: right + content + left (reversed for stack)
            var toExpand: [Token] = []
            toExpand.append(contentsOf: right)
            toExpand.append(contentsOf: content)
            toExpand.append(contentsOf: left)

            me.beginGroup()
            let expanded = try me.expandTokens(toExpand)
            me.endGroup()
            return expanded
        }

        // \ce / \pu: KaTeX mhchem 3.3.0 (Swift port in MhChem.swift)
        m["\\ce"] = .function { me throws(ParseError) in
            let args = try me.consumeArgs(1)
            let s = MhChem.argTokensToString(args[0])
            let tex = try MhChem.parse(s, stateMachine: "ce")
            return lexStringToStackTokens(tex)
        }
        m["\\pu"] = .function { me throws(ParseError) in
            let args = try me.consumeArgs(1)
            let s = MhChem.argTokensToString(args[0])
            let tex = try MhChem.parse(s, stateMachine: "pu")
            return lexStringToStackTokens(tex)
        }
    }
}
