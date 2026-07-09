/// Pattern matching (`mhchemParser.patterns`).
///
/// Port of RaTeX `mhchem/patterns.rs`.

/// A matched token: either a single string or a list of parts.
enum MhChemMatchToken: Sendable {
    case s(String)
    case a([String])
}

struct MhChemPatternHit {
    var token: MhChemMatchToken
    /// The unconsumed input. A `Substring` sharing the original `\ce`
    /// argument's storage: tokenization repeatedly re-slices the tail, and
    /// `String` here made that O(n²) copies (P-018).
    var remainder: Substring
}

enum MhChemPatterns {
    /// A begin/end matcher for `findObserveGroups`: literal string or regex.
    enum Side {
        case str(String)
        case re(MhChemRegex)
    }

    // Compiled once at static init (ICU-backed, see MhChemRegex / P-015).
    private static let reAggOpen =
        try! MhChemRegex(#"^\([a-z]{1,3}(?=[\),])"#)
    private static let reCmdBrace =
        try! MhChemRegex(#"^\\[a-zA-Z]+\{"#)
    private static let reBeforeBrace =
        try! MhChemRegex(#"^(?=\{)"#)
    private static let reNegPow = try! MhChemRegex(
        #"^(\+\-|\+\/\-|\+|\-|\\pm\s?)?([0-9]+(?:[,.][0-9]+)?|[0-9]*(?:\.[0-9]+)?)\^([+\-]?[0-9]+|\{[+\-]?[0-9]+\})"#
    )
    private static let reSci = try! MhChemRegex(
        #"^(\+\-|\+\/\-|\+|\-|\\pm\s?)?([0-9]+(?:[,.][0-9]+)?|[0-9]*(?:\.[0-9]+))?(\((?:[0-9]+(?:[,.][0-9]+)?|[0-9]*(?:\.[0-9]+))\))?(?:([eE]|\s*(\*|x|\\times|×)\s*10\^)([+\-]?[0-9]+|\{[+\-]?[0-9]+\}))?"#
    )
    private static let reSoaRemainder =
        try! MhChemRegex(#"^($|[\s,;\)\]\}])"#)
    private static let reSoaAlt =
        try! MhChemRegex(#"^(?:\((?:\\ca\s?)?\$[amothc]\$\))"#)
    private static let reAmountMain = try! MhChemRegex(
        #"^(?:(?:(?:\([+\-]?[0-9]+\/[0-9]+\)|[+\-]?(?:[0-9]+|\$[a-z]\$|[a-z])\/[0-9]+|[+\-]?[0-9]+[.,][0-9]+|[+\-]?\.[0-9]+|[+\-]?[0-9]+)(?:[a-z](?=\s*[A-Z]))?)|[+\-]?[a-z](?=\s*[A-Z])|\+(?!\s))"#
    )
    private static let reAmountDollar = try! MhChemRegex(
        #"^\$(?:\(?[+\-]?(?:[0-9]*[a-z]?[+\-])?[0-9]*[a-z](?:[+\-][0-9]*[a-z]?)?\)?|\+|-)\$$"#
    )
    private static let reFormulaParenOnly =
        try! MhChemRegex(#"^\([a-z]+\)$"#)
    private static let reFormulaMain = try! MhChemRegex(
        #"^(?:[a-z]|(?:[0-9\ \+\-\,\.\(\)]+[a-z])+[0-9\ \+\-\,\.\(\)]*|(?:[a-z][0-9\ \+\-\,\.\(\)]+)+[a-z]?)"#
    )

    /// Every static pattern source above, for the hand-matcher diff tests
    /// (key-validity: a `MhChemHandMatchers.table` key must name a pattern
    /// that actually exists — here or in the machine data).
    static let staticPatternSources: [String] = [
        reAggOpen, reCmdBrace, reBeforeBrace, reNegPow, reSci, reSoaRemainder,
        reSoaAlt, reAmountMain, reAmountDollar, reFormulaParenOnly, reFormulaMain,
    ].map(\.pattern)

    /// Scalar-wise literal prefix match. The Rust reference compares bytes;
    /// `hasPrefix` compares grapheme clusters with canonical equivalence,
    /// which would treat `"}\u{301}"` as *not* starting with `"}"` — the
    /// scalar walk matches the reference (and all needles are ASCII).
    private static func scalarPrefixEnd(
        _ input: Substring, _ at: String.Index, _ s: String
    ) -> String.Index? {
        let sc = input.unicodeScalars
        var i = at
        for c in s.unicodeScalars {
            guard i < sc.endIndex, sc[i] == c else { return nil }
            i = sc.index(after: i)
        }
        return i
    }

    /// If `beg` matches in `input` at position `at`, return the index just
    /// past the matched prefix; otherwise nil.
    private static func prefixEnd(
        _ input: Substring, _ at: String.Index, _ beg: Side
    ) -> String.Index? {
        switch beg {
        case .str(let s):
            if s.isEmpty {
                return at
            }
            return scalarPrefixEnd(input, at, s)
        case .re(let re):
            // Rust uses `find` filtered to start == 0; with a match required
            // at position 0 this is equivalent to an anchored prefix match.
            return re.match(input, from: at)?.range.upperBound
        }
    }

    /// Scan forward from `start` for `end`, skipping balanced `{...}` groups.
    /// Returns (match start, match end) indices, or nil if not found.
    /// The walk steps by unicode scalar (matching the Rust reference's
    /// per-`char` loop) — scalar stepping is a byte decode, where the
    /// previous per-`Character` walk recomputed grapheme boundaries at
    /// every position (P-018).
    private static func scanEnd(
        _ input: Substring,
        _ start: String.Index,
        _ end: Side
    ) throws(MhChemError) -> (String.Index, String.Index)? {
        let scalars = input.unicodeScalars
        var i = start
        var braces = 0
        while i < input.endIndex {
            var matchEnd: String.Index?
            switch end {
            case .str(let s):
                matchEnd = s.isEmpty ? nil : scalarPrefixEnd(input, i, s)
            case .re(let re):
                matchEnd = re.match(input, from: i)?.range.upperBound
            }
            if let e = matchEnd, braces == 0 {
                return (i, e)
            }
            let c = scalars[i]
            if c == "{" {
                braces += 1
            } else if c == "}" {
                if braces == 0 {
                    throw MhChemError.extraClose
                }
                braces -= 1
            }
            i = scalars.index(after: i)
        }
        return nil
    }

    /// KaTeX `findObserveGroups`.
    static func findObserveGroups(
        _ input: Substring,
        begExcl: String,
        begIncl: Side,
        endIncl: String,
        endExcl: Side,
        part2: (String, Side, String, Side)?,
        combine: Bool
    ) throws(MhChemError) -> MhChemPatternHit? {
        let ex: String.Index
        if begExcl.isEmpty {
            ex = input.startIndex
        } else {
            guard let n = prefixEnd(input, input.startIndex, .str(begExcl)) else {
                return nil
            }
            ex = n
        }
        let rest1 = input[ex...]
        guard let open = prefixEnd(rest1, rest1.startIndex, begIncl) else {
            return nil
        }
        let endMain: Side = !endIncl.isEmpty ? .str(endIncl) : endExcl
        guard let e = try scanEnd(rest1, open, endMain) else {
            return nil
        }
        let useIncl = !endIncl.isEmpty
        let cut = useIncl ? e.1 : e.0
        let m1 = String(rest1[..<cut])
        let after = rest1[e.1...]

        if let (b2e, b2i, e2i, e2e) = part2 {
            guard
                let h2 = try findObserveGroups(
                    after, begExcl: b2e, begIncl: b2i, endIncl: e2i, endExcl: e2e,
                    part2: nil, combine: false
                )
            else {
                return nil
            }
            guard case .s(let m2) = h2.token else {
                throw MhChemError.msg("nested Fog pair")
            }
            let tok: MhChemMatchToken = combine ? .s(m1 + m2) : .a([m1, m2])
            return MhChemPatternHit(token: tok, remainder: h2.remainder)
        }

        return MhChemPatternHit(token: .s(m1), remainder: after)
    }

    /// Match a named regex, extracting groups per KaTeX conventions:
    /// group 2 non-empty → pair [g1, g2]; else group 1 → single; else whole match.
    private static func regexMatchToken(
        _ re: MhChemRegex,
        _ input: Substring
    ) -> MhChemPatternHit? {
        guard let m = re.match(input) else {
            return nil
        }
        let remainder = input[m.range.upperBound...]
        if m.groups.count > 1, let g2r = m.groups[1], !g2r.isEmpty {
            let g1 = m.groups[0].map { String(input[$0]) } ?? ""
            return MhChemPatternHit(
                token: .a([g1, String(input[g2r])]), remainder: remainder)
        }
        if m.groups.count > 0, let g1r = m.groups[0] {
            return MhChemPatternHit(token: .s(String(input[g1r])), remainder: remainder)
        }
        return MhChemPatternHit(token: .s(String(input[m.range])), remainder: remainder)
    }

    /// Collect all capture groups (1...) as strings, empty for non-participating.
    private static func allGroups(_ m: MhChemRegex.Match, _ input: Substring) -> [String] {
        m.groups.map { r in r.map { String(input[$0]) } ?? "" }
    }

    private static func patternNegPow(_ input: Substring) -> MhChemPatternHit? {
        guard let m = reNegPow.match(input) else {
            return nil
        }
        return MhChemPatternHit(
            token: .a(allGroups(m, input)),
            remainder: input[m.range.upperBound...]
        )
    }

    private static func patternSci(_ input: Substring) -> MhChemPatternHit? {
        guard let m = reSci.match(input) else {
            return nil
        }
        if m.range.isEmpty {
            return nil
        }
        return MhChemPatternHit(
            token: .a(allGroups(m, input)),
            remainder: input[m.range.upperBound...]
        )
    }

    private static func patternStateOfAgg(_ input: Substring) throws(MhChemError)
        -> MhChemPatternHit?
    {
        if let h = try findObserveGroups(
            input, begExcl: "", begIncl: .re(reAggOpen), endIncl: ")",
            endExcl: .str(""), part2: nil, combine: false
        ) {
            if reSoaRemainder.match(h.remainder) != nil {
                return h
            }
        }
        if let m = reSoaAlt.match(input) {
            return MhChemPatternHit(
                token: .s(String(input[m.range])),
                remainder: input[m.range.upperBound...]
            )
        }
        return nil
    }

    private static func patternAmount(_ input: Substring) throws(MhChemError) -> MhChemPatternHit? {
        if let m = reAmountMain.match(input) {
            return MhChemPatternHit(
                token: .s(String(input[m.range])),
                remainder: input[m.range.upperBound...]
            )
        }
        guard
            let h = try findObserveGroups(
                input, begExcl: "", begIncl: .str("$"), endIncl: "$",
                endExcl: .str(""), part2: nil, combine: false
            )
        else {
            return nil
        }
        guard case .s(let s) = h.token else {
            return nil
        }
        if reAmountDollar.match(s) != nil {
            return MhChemPatternHit(token: .s(s), remainder: h.remainder)
        }
        return nil
    }

    private static func patternFormula(_ input: Substring) -> MhChemPatternHit? {
        if reFormulaParenOnly.match(input) != nil {
            return nil
        }
        guard let m = reFormulaMain.match(input) else {
            return nil
        }
        return MhChemPatternHit(
            token: .s(String(input[m.range])),
            remainder: input[m.range.upperBound...]
        )
    }

    /// A transition pattern resolved from its KaTeX name to a directly
    /// dispatchable form (P-016). Resolution happens once at data-load time
    /// (`MhChemData.init`), removing a ~30-case string switch and — for the
    /// machine regexes — a dictionary lookup from every match attempt in the
    /// tokenizer hot loop.
    enum Kind: @unchecked Sendable {
        // @unchecked: the `part2` tuple payload defeats Sendable synthesis,
        // but every element (String / Side) is immutable and Sendable.
        case negPow
        case sci
        case stateOfAgg
        case amount
        case formula
        case fog(
            begExcl: String, begIncl: Side, endIncl: String, endExcl: Side,
            part2: (String, Side, String, Side)?, combine: Bool)
        case regex(MhChemRegex)
        /// Unknown pattern name — throws at match time, matching the
        /// pre-resolution behavior ("mhchem bug P").
        case unknown(String)
    }

    /// Resolve a KaTeX pattern name to its dispatchable ``Kind``.
    static func resolveKind(_ patternName: String, regexes: [String: MhChemRegex]) -> Kind {
        switch patternName {
        case "(-)(9)^(-9)":
            return .negPow
        case "(-)(9.,9)(e)(99)":
            return .sci
        case "state of aggregation $":
            return .stateOfAgg
        case "amount", "amount2":
            return .amount
        case "formula$":
            return .formula
        case "^{(...)}":
            return .fog(
                begExcl: "^{", begIncl: .str(""), endIncl: "",
                endExcl: .str("}"), part2: nil, combine: false)
        case "^($...$)":
            return .fog(
                begExcl: "^", begIncl: .str("$"), endIncl: "$",
                endExcl: .str(""), part2: nil, combine: false)
        case "^\\x{}{}":
            return .fog(
                begExcl: "^", begIncl: .re(reCmdBrace), endIncl: "}",
                endExcl: .str(""),
                part2: ("", .str("{"), "}", .str("")), combine: true)
        case "^\\x{}":
            return .fog(
                begExcl: "^", begIncl: .re(reCmdBrace), endIncl: "}",
                endExcl: .str(""), part2: nil, combine: false)
        case "_{(...)}":
            return .fog(
                begExcl: "_{", begIncl: .str(""), endIncl: "",
                endExcl: .str("}"), part2: nil, combine: false)
        case "_($...$)":
            return .fog(
                begExcl: "_", begIncl: .str("$"), endIncl: "$",
                endExcl: .str(""), part2: nil, combine: false)
        case "_\\x{}{}":
            return .fog(
                begExcl: "_", begIncl: .re(reCmdBrace), endIncl: "}",
                endExcl: .str(""),
                part2: ("", .str("{"), "}", .str("")), combine: true)
        case "_\\x{}":
            return .fog(
                begExcl: "_", begIncl: .re(reCmdBrace), endIncl: "}",
                endExcl: .str(""), part2: nil, combine: false)
        case "{...}":
            return .fog(
                begExcl: "", begIncl: .str("{"), endIncl: "}",
                endExcl: .str(""), part2: nil, combine: false)
        case "{(...)}":
            return .fog(
                begExcl: "{", begIncl: .str(""), endIncl: "",
                endExcl: .str("}"), part2: nil, combine: false)
        case "$...$":
            return .fog(
                begExcl: "", begIncl: .str("$"), endIncl: "$",
                endExcl: .str(""), part2: nil, combine: false)
        case "${(...)}$":
            return .fog(
                begExcl: "${", begIncl: .str(""), endIncl: "",
                endExcl: .str("}$"), part2: nil, combine: false)
        case "$(...)$":
            return .fog(
                begExcl: "$", begIncl: .str(""), endIncl: "",
                endExcl: .str("$"), part2: nil, combine: false)
        case "\\bond{(...)}":
            return .fog(
                begExcl: "\\bond{", begIncl: .str(""), endIncl: "",
                endExcl: .str("}"), part2: nil, combine: false)
        case "[(...)]":
            return .fog(
                begExcl: "[", begIncl: .str(""), endIncl: "",
                endExcl: .str("]"), part2: nil, combine: false)
        case "\\x{}{}":
            return .fog(
                begExcl: "", begIncl: .re(reCmdBrace), endIncl: "}",
                endExcl: .str(""),
                part2: ("", .str("{"), "}", .str("")), combine: true)
        case "\\x{}":
            return .fog(
                begExcl: "", begIncl: .re(reCmdBrace), endIncl: "}",
                endExcl: .str(""), part2: nil, combine: false)
        case "\\frac{(...)}":
            return .fog(
                begExcl: "\\frac{", begIncl: .str(""), endIncl: "",
                endExcl: .str("}"),
                part2: ("{", .str(""), "", .str("}")), combine: false)
        case "\\overset{(...)}":
            return .fog(
                begExcl: "\\overset{", begIncl: .str(""), endIncl: "",
                endExcl: .str("}"),
                part2: ("{", .str(""), "", .str("}")), combine: false)
        case "\\underset{(...)}":
            return .fog(
                begExcl: "\\underset{", begIncl: .str(""), endIncl: "",
                endExcl: .str("}"),
                part2: ("{", .str(""), "", .str("}")), combine: false)
        case "\\underbrace{(...)}":
            return .fog(
                begExcl: "\\underbrace{", begIncl: .str(""), endIncl: "",
                endExcl: .str("}_"),
                part2: ("{", .str(""), "", .str("}")), combine: false)
        case "\\color{(...)}0":
            return .fog(
                begExcl: "\\color{", begIncl: .str(""), endIncl: "",
                endExcl: .str("}"), part2: nil, combine: false)
        case "\\color{(...)}{(...)}1":
            return .fog(
                begExcl: "\\color{", begIncl: .str(""), endIncl: "",
                endExcl: .str("}"),
                part2: ("{", .str(""), "", .str("}")), combine: false)
        case "\\color(...){(...)}2":
            return .fog(
                begExcl: "\\color", begIncl: .str("\\"), endIncl: "",
                endExcl: .re(reBeforeBrace),
                part2: ("{", .str(""), "", .str("}")), combine: false)
        case "\\ce{(...)}":
            return .fog(
                begExcl: "\\ce{", begIncl: .str(""), endIncl: "",
                endExcl: .str("}"), part2: nil, combine: false)
        default:
            guard let re = regexes[patternName] else {
                return .unknown(patternName)
            }
            return .regex(re)
        }
    }

    /// Match a resolved pattern against `input`.
    static func match(
        _ kind: Kind, _ input: Substring
    ) throws(MhChemError) -> MhChemPatternHit? {
        switch kind {
        case .negPow:
            return patternNegPow(input)
        case .sci:
            return patternSci(input)
        case .stateOfAgg:
            return try patternStateOfAgg(input)
        case .amount:
            return try patternAmount(input)
        case .formula:
            return patternFormula(input)
        case .fog(let begExcl, let begIncl, let endIncl, let endExcl, let part2, let combine):
            return try findObserveGroups(
                input, begExcl: begExcl, begIncl: begIncl, endIncl: endIncl,
                endExcl: endExcl, part2: part2, combine: combine)
        case .regex(let re):
            return regexMatchToken(re, input)
        case .unknown(let name):
            throw MhChemError.msg("mhchem bug P: unknown pattern (\(name))")
        }
    }

    static func matchPattern(
        _ data: MhChemData,
        _ patternName: String,
        _ input: String
    ) throws(MhChemError) -> MhChemPatternHit? {
        try match(resolveKind(patternName, regexes: data.regexes), input[...])
    }
}
