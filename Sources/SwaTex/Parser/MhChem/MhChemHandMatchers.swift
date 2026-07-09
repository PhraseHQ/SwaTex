/// Hand-rolled scalar scanners for the hottest mhchem patterns (P-019).
///
/// Pattern-frequency instrumentation over the `\ce` golden corpus showed
/// ~90 % of tokenizer match attempts hit ~30 simple anchored regexes; ICU's
/// per-call UText setup dominated the remaining `\ce` profile after P-015.
///
/// **Safety model.** The table is keyed by the *exact regex source string*.
/// `MhChemRegex.init` consults it; a pattern whose upstream-generated source
/// ever changes stops matching its key and falls back to ICU automatically.
/// Each matcher replicates its regex's ICU semantics exactly — ordered
/// alternation, greedy quantifiers (backtracking analyzed per pattern),
/// `\s` = `\p{White_Space}` (ICU's *actual* set, wider than its documented
/// one), `\d` = `\p{Nd}`, `.` excluding ICU's line terminators, `$` with
/// the before-final-terminator rule, code-point (scalar) stepping.
/// Equivalence against ICU is asserted over corpus suffixes and edge
/// inputs (including VT/FF/NEL/CRLF and combining marks) by
/// `MhChemHandMatcherDiffTests`.
enum MhChemHandMatchers {
    typealias Matcher = @Sendable (Substring, String.Index) -> MhChemRegex.Match?

    // ── Scalar predicates (ICU class definitions) ───────────────────────

    /// ICU `\s`. ICU's docs say `[\t\n\f\r\p{Z}]`, but its actual set is
    /// `\p{White_Space}` — which additionally contains U+000B (VT) and
    /// U+0085 (NEL). Verified empirically against NSRegularExpression by
    /// the diff tests (`",\u{0B}\u{0B}"`, `"-\u{85}x"`, …).
    static func isSpace(_ c: Unicode.Scalar) -> Bool {
        switch c {
        case " ", "\t", "\n", "\u{0B}", "\u{0C}", "\r", "\u{85}":
            return true
        default:
            if c.value < 0x80 { return false }
            switch c.properties.generalCategory {
            case .spaceSeparator, .lineSeparator, .paragraphSeparator:
                return true
            default:
                return false
            }
        }
    }

    /// ICU `\d`: `\p{Nd}`.
    private static func isDigitNd(_ c: Unicode.Scalar) -> Bool {
        if c.value < 0x80 { return c >= "0" && c <= "9" }
        return c.properties.generalCategory == .decimalNumber
    }

    private static func isASCIIDigit(_ c: Unicode.Scalar) -> Bool {
        c >= "0" && c <= "9"
    }

    private static func isLowerAZ(_ c: Unicode.Scalar) -> Bool {
        c >= "a" && c <= "z"
    }

    private static func isUpperAZ(_ c: Unicode.Scalar) -> Bool {
        c >= "A" && c <= "Z"
    }

    private static func isLetterAZ(_ c: Unicode.Scalar) -> Bool {
        isLowerAZ(c) || isUpperAZ(c)
    }

    /// ICU default `.`: any code point except line terminators — ICU's
    /// terminator set is U+000A…U+000D (LF, VT, FF, CR), NEL, LS, PS.
    private static func isDotMatchable(_ c: Unicode.Scalar) -> Bool {
        switch c {
        case "\n", "\u{0B}", "\u{0C}", "\r", "\u{85}", "\u{2028}", "\u{2029}":
            return false
        default:
            return true
        }
    }

    // ── Scanner ──────────────────────────────────────────────────────────

    /// Minimal scalar cursor over a substring; indices are base-string
    /// indices, so ranges are directly usable as `MhChemRegex.Match` output.
    private struct S {
        let sc: Substring.UnicodeScalarView
        let start: String.Index
        let end: String.Index
        var i: String.Index

        init(_ s: Substring, _ from: String.Index) {
            sc = s.unicodeScalars
            start = from
            end = s.endIndex
            i = from
        }

        var atEnd: Bool { i >= end }

        /// ICU non-multiline `$`: end of region, **or** the remaining text
        /// is exactly one final line terminator (LF, VT, FF, CR, CRLF, NEL,
        /// LS, PS) — but never *between* the CR and LF of a CRLF pair.
        /// Java/ICU semantics, verified against NSRegularExpression by the
        /// diff tests (`"x\u{0B}"`, `"\r\n"`, …).
        var atDollar: Bool {
            if i >= end { return true }
            // ICU refuses `$` in the middle of a CRLF sequence (it does not
            // look back past the region start).
            if sc[i] == "\n", i > start, sc[sc.index(before: i)] == "\r" {
                return false
            }
            var j = sc.index(after: i)
            switch sc[i] {
            case "\n", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}":
                return j >= end
            case "\r":
                if j < end, sc[j] == "\n" { j = sc.index(after: j) }
                return j >= end
            default:
                return false
            }
        }

        func peek() -> Unicode.Scalar? { i < end ? sc[i] : nil }

        /// Scalar at `offset` scalars past the cursor (lookahead helper).
        func peek(_ offset: Int) -> Unicode.Scalar? {
            var j = i
            for _ in 0..<offset {
                guard j < end else { return nil }
                j = sc.index(after: j)
            }
            return j < end ? sc[j] : nil
        }

        mutating func advance() { i = sc.index(after: i) }

        mutating func consume(_ c: Unicode.Scalar) -> Bool {
            if i < end, sc[i] == c {
                advance()
                return true
            }
            return false
        }

        /// Consume an ASCII literal scalar-by-scalar.
        mutating func consume(_ lit: String) -> Bool {
            var j = i
            for c in lit.unicodeScalars {
                guard j < end, sc[j] == c else { return false }
                j = sc.index(after: j)
            }
            i = j
            return true
        }

        /// Consume scalars while `pred` holds; returns the count.
        @discardableResult
        mutating func skip(while pred: (Unicode.Scalar) -> Bool) -> Int {
            var n = 0
            while i < end, pred(sc[i]) {
                advance()
                n += 1
            }
            return n
        }

        func match(from f: String.Index? = nil, groups: [Range<String.Index>?] = []) -> MhChemRegex.Match {
            MhChemRegex.Match(range: (f ?? start)..<i, groups: groups)
        }
    }

    // ── The table ────────────────────────────────────────────────────────

    static let table: [String: Matcher] = [
        // "empty"
        #"^$"#: { s, from in
            S(s, from).atDollar
                ? MhChemRegex.Match(range: from..<from, groups: []) : nil
        },
        // "else", "else2"
        #"^."#: { s, from in
            var m = S(s, from)
            guard let c = m.peek(), isDotMatchable(c) else { return nil }
            m.advance()
            return m.match()
        },
        // "space"
        #"^\s"#: { s, from in
            var m = S(s, from)
            guard let c = m.peek(), isSpace(c) else { return nil }
            m.advance()
            return m.match()
        },
        // "space$"
        #"^\s$"#: { s, from in
            var m = S(s, from)
            guard let c = m.peek(), isSpace(c) else { return nil }
            m.advance()
            return m.atDollar ? m.match() : nil
        },
        // "space A"
        #"^\s(?=[A-Z\\$])"#: { s, from in
            var m = S(s, from)
            guard let c = m.peek(), isSpace(c) else { return nil }
            m.advance()
            guard let n = m.peek(), isUpperAZ(n) || n == "\\" || n == "$" else { return nil }
            return m.match()
        },
        // "a-z"
        #"^[a-z]"#: { s, from in
            var m = S(s, from)
            guard let c = m.peek(), isLowerAZ(c) else { return nil }
            m.advance()
            return m.match()
        },
        // "x"
        #"^x"#: { s, from in
            var m = S(s, from)
            return m.consume("x" as Unicode.Scalar) ? m.match() : nil
        },
        // "x$"
        #"^x$"#: { s, from in
            var m = S(s, from)
            return m.consume("x" as Unicode.Scalar) && m.atDollar ? m.match() : nil
        },
        // "i$"
        #"^i$"#: { s, from in
            var m = S(s, from)
            return m.consume("i" as Unicode.Scalar) && m.atDollar ? m.match() : nil
        },
        // "letters" — (scalar class | \greekname (\s+|{}|(?![a-zA-Z])))+
        #"^(?:[a-zA-Z\u03B1-\u03C9\u0391-\u03A9?@]|(?:\\(?:alpha|beta|gamma|delta|epsilon|zeta|eta|theta|iota|kappa|lambda|mu|nu|xi|omicron|pi|rho|sigma|tau|upsilon|phi|chi|psi|omega|Gamma|Delta|Theta|Lambda|Xi|Pi|Sigma|Upsilon|Phi|Psi|Omega)(?:\s+|\{\}|(?![a-zA-Z]))))+"#: { s, from in
            var m = S(s, from)
            var any = false
            loop: while let c = m.peek() {
                if isLetterAZ(c) || (c.value >= 0x3B1 && c.value <= 0x3C9)
                    || (c.value >= 0x391 && c.value <= 0x3A9) || c == "?" || c == "@" {
                    m.advance()
                    any = true
                    continue
                }
                if c == "\\" {
                    var g = m
                    g.advance()
                    guard greekTail(&g) else { break loop }
                    m = g
                    any = true
                    continue
                }
                break
            }
            return any ? m.match() : nil
        },
        // "\greek" — single \greekname (\s+|{}|(?![a-zA-Z]))
        #"^\\(?:alpha|beta|gamma|delta|epsilon|zeta|eta|theta|iota|kappa|lambda|mu|nu|xi|omicron|pi|rho|sigma|tau|upsilon|phi|chi|psi|omega|Gamma|Delta|Theta|Lambda|Xi|Pi|Sigma|Upsilon|Phi|Psi|Omega)(?:\s+|\{\}|(?![a-zA-Z]))"#: { s, from in
            var m = S(s, from)
            guard m.consume("\\" as Unicode.Scalar), greekTail(&m) else { return nil }
            return m.match()
        },
        // "digits"
        #"^[0-9]+"#: { s, from in
            var m = S(s, from)
            return m.skip(while: isASCIIDigit) > 0 ? m.match() : nil
        },
        // "roman numeral"
        #"^[IVX]+"#: { s, from in
            var m = S(s, from)
            return m.skip(while: { $0 == "I" || $0 == "V" || $0 == "X" }) > 0 ? m.match() : nil
        },
        // "-9.,9" — sign? (digits+([,.]digits+)? | digits*(.digits+))
        // With ≥1 leading digit the first alternative always wins; otherwise
        // the second reduces to `.digits+` (digits* must be empty).
        #"^[+\-]?(?:[0-9]+(?:[,.][0-9]+)?|[0-9]*(?:\.[0-9]+))"#: { s, from in
            var m = S(s, from)
            if let c = m.peek(), c == "+" || c == "-" { m.advance() }
            if m.skip(while: isASCIIDigit) > 0 {
                var f = m
                if let c = f.peek(), c == "," || c == "." {
                    f.advance()
                    if f.skip(while: isASCIIDigit) > 0 { m = f }
                }
                return m.match()
            }
            guard m.consume("." as Unicode.Scalar), m.skip(while: isASCIIDigit) > 0 else {
                return nil
            }
            return m.match()
        },
        // "-9.,9 no missing 0"
        #"^[+\-]?[0-9]+(?:[.,][0-9]+)?"#: { s, from in
            var m = S(s, from)
            if let c = m.peek(), c == "+" || c == "-" { m.advance() }
            guard m.skip(while: isASCIIDigit) > 0 else { return nil }
            var f = m
            if let c = f.peek(), c == "." || c == "," {
                f.advance()
                if f.skip(while: isASCIIDigit) > 0 { m = f }
            }
            return m.match()
        },
        // "{[("
        #"^(?:\\\{|\[|\()"#: { s, from in
            var m = S(s, from)
            if m.consume(#"\{"#) || m.consume("[" as Unicode.Scalar)
                || m.consume("(" as Unicode.Scalar) {
                return m.match()
            }
            return nil
        },
        // ")]}"
        #"^(?:\)|\]|\\\})"#: { s, from in
            var m = S(s, from)
            if m.consume(")" as Unicode.Scalar) || m.consume("]" as Unicode.Scalar)
                || m.consume(#"\}"#) {
                return m.match()
            }
            return nil
        },
        // ","
        #"^[,;]"#: { s, from in
            var m = S(s, from)
            guard let c = m.peek(), c == "," || c == ";" else { return nil }
            m.advance()
            return m.match()
        },
        // ", "
        #"^[,;]\s*"#: { s, from in
            var m = S(s, from)
            guard let c = m.peek(), c == "," || c == ";" else { return nil }
            m.advance()
            m.skip(while: isSpace)
            return m.match()
        },
        // "."
        #"^[.]"#: { s, from in
            var m = S(s, from)
            return m.consume("." as Unicode.Scalar) ? m.match() : nil
        },
        // ". " — group 1 = the dot scalar
        #"^([.\u22C5\u00B7\u2022])\s*"#: { s, from in
            var m = S(s, from)
            guard let c = m.peek(),
                c == "." || c == "\u{22C5}" || c == "\u{B7}" || c == "\u{2022}"
            else { return nil }
            m.advance()
            let g1 = from..<m.i
            m.skip(while: isSpace)
            return m.match(groups: [g1])
        },
        // "..."
        #"^\.\.\.(?=$|[^.])"#: { s, from in
            var m = S(s, from)
            guard m.consume("...") else { return nil }
            if let n = m.peek(), n == "." { return nil }
            return m.match()
        },
        // "* " — group 1 = "*"
        #"^([*])\s*"#: { s, from in
            var m = S(s, from)
            guard m.consume("*" as Unicode.Scalar) else { return nil }
            let g1 = from..<m.i
            m.skip(while: isSpace)
            return m.match(groups: [g1])
        },
        // "*"
        #"^\s*[*.]\s*"#: { s, from in
            var m = S(s, from)
            m.skip(while: isSpace)
            guard let c = m.peek(), c == "*" || c == "." else { return nil }
            m.advance()
            m.skip(while: isSpace)
            return m.match()
        },
        // "/" — group 1 = "/"
        #"^\s*(\/)\s*"#: { s, from in
            var m = S(s, from)
            m.skip(while: isSpace)
            let gs = m.i
            guard m.consume("/" as Unicode.Scalar) else { return nil }
            let g1 = gs..<m.i
            m.skip(while: isSpace)
            return m.match(groups: [g1])
        },
        // "//" — group 1 = "//"
        #"^\s*(\/\/)\s*"#: { s, from in
            var m = S(s, from)
            m.skip(while: isSpace)
            let gs = m.i
            guard m.consume("//") else { return nil }
            let g1 = gs..<m.i
            m.skip(while: isSpace)
            return m.match(groups: [g1])
        },
        // "'"
        #"^'"#: { s, from in
            var m = S(s, from)
            return m.consume("'" as Unicode.Scalar) ? m.match() : nil
        },
        // "^a" — group 1 = digits+ | one scalar not \ or _
        #"^\^([0-9]+|[^\\_])"#: { s, from in
            var m = S(s, from)
            guard m.consume("^" as Unicode.Scalar) else { return nil }
            let gs = m.i
            if m.skip(while: isASCIIDigit) > 0 {
                return m.match(groups: [gs..<m.i])
            }
            guard let c = m.peek(), c != "\\", c != "_" else { return nil }
            m.advance()
            return m.match(groups: [gs..<m.i])
        },
        // "^\x" — group 1 = \letters+
        #"^\^(\\[a-zA-Z]+)\s*"#: { s, from in
            var m = S(s, from)
            guard m.consume("^" as Unicode.Scalar) else { return nil }
            let gs = m.i
            guard m.consume("\\" as Unicode.Scalar), m.skip(while: isLetterAZ) > 0 else {
                return nil
            }
            let g1 = gs..<m.i
            m.skip(while: isSpace)
            return m.match(groups: [g1])
        },
        // "^(-1)" — group 1 = -?\d+  (\d = \p{Nd}, matching ICU)
        #"^\^(-?\d+)"#: { s, from in
            var m = S(s, from)
            guard m.consume("^" as Unicode.Scalar) else { return nil }
            let gs = m.i
            _ = m.consume("-" as Unicode.Scalar)
            guard m.skip(while: isDigitNd) > 0 else { return nil }
            return m.match(groups: [gs..<m.i])
        },
        // "_9" — group 1 = sign?digits+ | one scalar not backslash
        #"^_([+\-]?[0-9]+|[^\\])"#: { s, from in
            var m = S(s, from)
            guard m.consume("_" as Unicode.Scalar) else { return nil }
            let gs = m.i
            var a = m
            if let c = a.peek(), c == "+" || c == "-" { a.advance() }
            if a.skip(while: isASCIIDigit) > 0 {
                return a.match(from: from, groups: [gs..<a.i])
            }
            guard let c = m.peek(), c != "\\" else { return nil }
            m.advance()
            return m.match(groups: [gs..<m.i])
        },
        // "_\x" — group 1 = \letters+
        #"^_(\\[a-zA-Z]+)\s*"#: { s, from in
            var m = S(s, from)
            guard m.consume("_" as Unicode.Scalar) else { return nil }
            let gs = m.i
            guard m.consume("\\" as Unicode.Scalar), m.skip(while: isLetterAZ) > 0 else {
                return nil
            }
            let g1 = gs..<m.i
            m.skip(while: isSpace)
            return m.match(groups: [g1])
        },
        // "^_" — ^(?=_) | _(?=^) | [\^_]$
        #"^(?:\^(?=_)|\_(?=\^)|[\^_]$)"#: { s, from in
            var m = S(s, from)
            guard let c = m.peek(), c == "^" || c == "_" else { return nil }
            let want: Unicode.Scalar = c == "^" ? "_" : "^"
            m.advance()
            if let n = m.peek(), n == want { return m.match() }
            return m.atDollar ? m.match() : nil
        },
        // "{}"
        #"^\{\}"#: { s, from in
            var m = S(s, from)
            return m.consume("{}") ? m.match() : nil
        },
        // "=<>"
        #"^[=<>]"#: { s, from in
            var m = S(s, from)
            guard let c = m.peek(), c == "=" || c == "<" || c == ">" else { return nil }
            m.advance()
            return m.match()
        },
        // "#"
        ##"^[#\u2261]"##: { s, from in
            var m = S(s, from)
            guard let c = m.peek(), c == "#" || c == "\u{2261}" else { return nil }
            m.advance()
            return m.match()
        },
        // "+"
        #"^\+"#: { s, from in
            var m = S(s, from)
            return m.consume("+" as Unicode.Scalar) ? m.match() : nil
        },
        // "-"
        #"^-"#: { s, from in
            var m = S(s, from)
            return m.consume("-" as Unicode.Scalar) ? m.match() : nil
        },
        // "-$" — '-' with lookahead (class | end | \([a-z]+\))
        #"^-(?=[\s_},;\]/]|$|\([a-z]+\))"#: { s, from in
            var m = S(s, from)
            guard m.consume("-" as Unicode.Scalar) else { return nil }
            guard let n = m.peek() else { return m.match() }  // $
            if isSpace(n) || n == "_" || n == "}" || n == "," || n == ";" || n == "]"
                || n == "/" || m.atDollar {
                return m.match()
            }
            var l = m
            if l.consume("(" as Unicode.Scalar), l.skip(while: isLowerAZ) > 0,
                l.consume(")" as Unicode.Scalar) {
                return m.match()
            }
            return nil
        },
        // "-9"
        #"^-(?=[0-9])"#: { s, from in
            var m = S(s, from)
            guard m.consume("-" as Unicode.Scalar), let n = m.peek(), isASCIIDigit(n) else {
                return nil
            }
            return m.match()
        },
        // "- orbital overlap" — '-' lookahead (([spd]|sp)($|class))
        #"^-(?=(?:[spd]|sp)(?:$|[\s,;\)\]\}]))"#: { s, from in
            var m = S(s, from)
            guard m.consume("-" as Unicode.Scalar) else { return nil }
            func endOrClass(_ m: S) -> Bool {
                guard let c = m.peek() else { return true }
                return m.atDollar || isSpace(c) || c == "," || c == ";" || c == ")" || c == "]"
                    || c == "}"
            }
            guard let c1 = m.peek() else { return nil }
            // ordered: single [spd] first, then "sp"
            if c1 == "s" || c1 == "p" || c1 == "d" {
                var a = m
                a.advance()
                if endOrClass(a) { return m.match() }
            }
            if c1 == "s", m.peek(1) == "p" {
                var a = m
                a.advance()
                a.advance()
                if endOrClass(a) { return m.match() }
            }
            return nil
        },
        // "pm-operator"
        #"^(?:\\pm|\$\\pm\$|\+-|\+\/-)"#: { s, from in
            var m = S(s, from)
            if m.consume(#"\pm"#) || m.consume(#"$\pm$"#) || m.consume("+-")
                || m.consume("+/-") {
                return m.match()
            }
            return nil
        },
        // "operator" — + | ([-=<>]|<<|>>|\approx|$\approx$)(?=\s|$|-?[0-9])
        #"^(?:\+|(?:[\-=<>]|<<|>>|\\approx|\$\\approx\$)(?=\s|$|-?[0-9]))"#: { s, from in
            var m = S(s, from)
            if m.consume("+" as Unicode.Scalar) { return m.match() }
            func look(_ m: S) -> Bool {
                guard let c = m.peek() else { return true }
                if isSpace(c) || m.atDollar { return true }
                if c == "-" { return m.peek(1).map(isASCIIDigit) ?? false }
                return isASCIIDigit(c)
            }
            // ordered alternatives, each followed by the lookahead
            if let c = m.peek(), c == "-" || c == "=" || c == "<" || c == ">" {
                var a = m
                a.advance()
                if look(a) { return a.match(from: from) }
            }
            for lit in ["<<", ">>", #"\approx"#, #"$\approx$"#] {
                var a = m
                if a.consume(lit), look(a) { return a.match(from: from) }
            }
            return nil
        },
        // "arrowUpDown"
        #"^(?:v|\(v\)|\^|\(\^\))(?=$|[\s,;\)\]\}])"#: { s, from in
            func look(_ m: S) -> Bool {
                guard let c = m.peek() else { return true }
                return m.atDollar || isSpace(c) || c == "," || c == ";" || c == ")" || c == "]"
                    || c == "}"
            }
            for lit in ["v", "(v)", "^", "(^)"] {
                var a = S(s, from)
                if a.consume(lit), look(a) { return a.match() }
            }
            return nil
        },
        // "->"
        #"^(?:<->|<-->|->|<-|<=>>|<<=>|<=>|[\u2192\u27F6\u21CC])"#: { s, from in
            for lit in ["<->", "<-->", "->", "<-", "<=>>", "<<=>", "<=>"] {
                var a = S(s, from)
                if a.consume(lit) { return a.match() }
            }
            var m = S(s, from)
            if let c = m.peek(), c == "\u{2192}" || c == "\u{27F6}" || c == "\u{21CC}" {
                m.advance()
                return m.match()
            }
            return nil
        },
        // "CMT"
        #"^[CMT](?=\[)"#: { s, from in
            var m = S(s, from)
            guard let c = m.peek(), c == "C" || c == "M" || c == "T" else { return nil }
            m.advance()
            guard m.peek() == "[" else { return nil }
            return m.match()
        },
        // "1st-level escape" — group 1 = & | \\ | \hline
        #"^(&|\\\\|\\hline)\s*"#: { s, from in
            var m = S(s, from)
            let gs = m.i
            if m.consume("&" as Unicode.Scalar) || m.consume(#"\\"#) || m.consume(#"\hline"#) {
                let g1 = gs..<m.i
                m.skip(while: isSpace)
                return m.match(groups: [g1])
            }
            return nil
        },
        // "\," — backslash then one of , space ; :
        #"^(?:\\[,\ ;:])"#: { s, from in
            var m = S(s, from)
            guard m.consume("\\" as Unicode.Scalar), let c = m.peek(),
                c == "," || c == " " || c == ";" || c == ":"
            else { return nil }
            m.advance()
            return m.match()
        },
        // "\ca"
        #"^\\ca(?:\s+|(?![a-zA-Z]))"#: { s, from in
            var m = S(s, from)
            guard m.consume(#"\ca"#) else { return nil }
            if m.skip(while: isSpace) > 0 { return m.match() }
            if let n = m.peek(), isLetterAZ(n) { return nil }
            return m.match()
        },
        // "\x" — \letters+\s* | \[_&{}%]
        #"^(?:\\[a-zA-Z]+\s*|\\[_&{}%])"#: { s, from in
            var m = S(s, from)
            guard m.consume("\\" as Unicode.Scalar), let c = m.peek() else { return nil }
            if isLetterAZ(c) {
                m.skip(while: isLetterAZ)
                m.skip(while: isSpace)
                return m.match()
            }
            if c == "_" || c == "&" || c == "{" || c == "}" || c == "%" {
                m.advance()
                return m.match()
            }
            return nil
        },
        // "orbital" — ordered: [0-9]{1,2}[spdfgh] | [0-9]{0,2}sp, then (?=$|[^a-zA-Z])
        #"^(?:[0-9]{1,2}[spdfgh]|[0-9]{0,2}sp)(?=$|[^a-zA-Z])"#: { s, from in
            func look(_ m: S) -> Bool {
                guard let c = m.peek() else { return true }
                return !isLetterAZ(c)
            }
            func isOrb(_ c: Unicode.Scalar) -> Bool {
                c == "s" || c == "p" || c == "d" || c == "f" || c == "g" || c == "h"
            }
            // alternative 1, digits greedy 2 → 1
            for nd in [2, 1] {
                var a = S(s, from)
                var ok = true
                for _ in 0..<nd {
                    if let c = a.peek(), isASCIIDigit(c) { a.advance() } else { ok = false; break }
                }
                guard ok, let c = a.peek(), isOrb(c) else { continue }
                a.advance()
                if look(a) { return a.match() }
            }
            // alternative 2, digits greedy 2 → 0
            for nd in [2, 1, 0] {
                var a = S(s, from)
                var ok = true
                for _ in 0..<nd {
                    if let c = a.peek(), isASCIIDigit(c) { a.advance() } else { ok = false; break }
                }
                guard ok, a.consume("sp"), look(a) else { continue }
                return a.match()
            }
            return nil
        },
        // "others"
        #"^[\/~|]"#: { s, from in
            var m = S(s, from)
            guard let c = m.peek(), c == "/" || c == "~" || c == "|" else { return nil }
            m.advance()
            return m.match()
        },
        // "oxidation$"
        #"^(?:[+-][IVX]+|\\pm\s*0|\$\\pm\$\s*0)$"#: { s, from in
            func roman(_ c: Unicode.Scalar) -> Bool { c == "I" || c == "V" || c == "X" }
            var a = S(s, from)
            if let c = a.peek(), c == "+" || c == "-" {
                a.advance()
                if a.skip(while: roman) > 0, a.atDollar { return a.match() }
            }
            for lit in [#"\pm"#, #"$\pm$"#] {
                var b = S(s, from)
                if b.consume(lit) {
                    b.skip(while: isSpace)
                    if b.consume("0" as Unicode.Scalar), b.atDollar { return b.match() }
                }
            }
            return nil
        },
        // "d-oxidation$"
        #"^(?:[+-]?\s?[IVX]+|\\pm\s*0|\$\\pm\$\s*0)$"#: { s, from in
            func roman(_ c: Unicode.Scalar) -> Bool { c == "I" || c == "V" || c == "X" }
            // alternative 1 with optional sign and optional single \s —
            // greedy options first, then dropped (ordered like the engine).
            var signOpts: [Bool] = []
            if let c = S(s, from).peek(), c == "+" || c == "-" {
                signOpts = [true, false]
            } else {
                signOpts = [false]
            }
            for takeSign in signOpts {
                var a = S(s, from)
                if takeSign { a.advance() }
                var spaceOpts: [Bool] = []
                if let c = a.peek(), isSpace(c) { spaceOpts = [true, false] } else { spaceOpts = [false] }
                for takeSpace in spaceOpts {
                    var b = a
                    if takeSpace { b.advance() }
                    if b.skip(while: roman) > 0, b.atDollar { return b.match() }
                }
            }
            for lit in [#"\pm"#, #"$\pm$"#] {
                var b = S(s, from)
                if b.consume(lit) {
                    b.skip(while: isSpace)
                    if b.consume("0" as Unicode.Scalar), b.atDollar { return b.match() }
                }
            }
            return nil
        },
        // "1/2$"
        #"^[+\-]?(?:[0-9]+|\$[a-z]\$|[a-z])\/[0-9]+(?:\$[a-z]\$|[a-z])?$"#: { s, from in
            var m = S(s, from)
            if let c = m.peek(), c == "+" || c == "-" { m.advance() }
            // numerator: digits+ | $x$ | x   (ordered; first match wins — the
            // alternatives start with disjoint scalars)
            if m.skip(while: isASCIIDigit) > 0 {
            } else if m.peek() == "$" {
                var a = m
                a.advance()
                guard let c = a.peek(), isLowerAZ(c) else { return nil }
                a.advance()
                guard a.consume("$" as Unicode.Scalar) else { return nil }
                m = a
            } else if let c = m.peek(), isLowerAZ(c) {
                m.advance()
            } else {
                return nil
            }
            guard m.consume("/" as Unicode.Scalar), m.skip(while: isASCIIDigit) > 0 else {
                return nil
            }
            // optional trailing $x$ | x, then required end (regex would
            // backtrack to dropping the optional, but a leftover char is a
            // letter/$ start or not — either way "not at end" fails both)
            if m.peek() == "$" {
                var a = m
                a.advance()
                if let c = a.peek(), isLowerAZ(c) {
                    a.advance()
                    if a.consume("$" as Unicode.Scalar), a.atDollar { return a.match(from: from) }
                }
                return nil
            }
            if let c = m.peek(), isLowerAZ(c) {
                var a = m
                a.advance()
                return a.atDollar ? a.match(from: from) : nil
            }
            return m.atDollar ? m.match() : nil
        },
        // "(KV letters),"
        #"^(?:[A-Z][a-z]{0,2}|i)(?=,)"#: { s, from in
            var m = S(s, from)
            if let c = m.peek(), isUpperAZ(c) {
                m.advance()
                var low = 0
                while low < 2, let n = m.peek(), isLowerAZ(n) {
                    m.advance()
                    low += 1
                }
                // greedy {0,2} then backtrack against (?=,)
                while true {
                    if m.peek() == "," { return m.match() }
                    guard low > 0 else { break }
                    // step back one lowercase letter
                    var a = S(s, from)
                    a.advance()
                    for _ in 0..<(low - 1) { a.advance() }
                    m = a
                    low -= 1
                }
                return nil
            }
            if m.peek() == "i" {
                m.advance()
                return m.peek() == "," ? m.match() : nil
            }
            return nil
        },
        // "uprightEntities"
        #"^(?:pH|pOH|pC|pK|iPr|iBu)(?=$|[^a-zA-Z])"#: { s, from in
            for lit in ["pH", "pOH", "pC", "pK", "iPr", "iBu"] {
                var a = S(s, from)
                if a.consume(lit) {
                    if let n = a.peek(), isLetterAZ(n) { continue }
                    return a.match()
                }
            }
            return nil
        },
        // "_{(state of aggregation)}$" — group 1 = (letters{1,3})
        #"^_\{(\([a-z]{1,3}\))\}"#: { s, from in
            var m = S(s, from)
            guard m.consume("_{") else { return nil }
            let gs = m.i
            guard m.consume("(" as Unicode.Scalar) else { return nil }
            let n = m.skip(while: isLowerAZ)
            guard n >= 1, n <= 3, m.consume(")" as Unicode.Scalar) else { return nil }
            let g1 = gs..<m.i
            guard m.consume("}" as Unicode.Scalar) else { return nil }
            return m.match(groups: [g1])
        },
        // static: reCmdBrace
        #"^\\[a-zA-Z]+\{"#: { s, from in
            var m = S(s, from)
            guard m.consume("\\" as Unicode.Scalar), m.skip(while: isLetterAZ) > 0,
                m.consume("{" as Unicode.Scalar)
            else { return nil }
            return m.match()
        },
        // static: reBeforeBrace (zero-width)
        #"^(?=\{)"#: { s, from in
            let m = S(s, from)
            return m.peek() == "{" ? MhChemRegex.Match(range: from..<from, groups: []) : nil
        },
        // static: reAggOpen — \( [a-z]{1,3} (?=[\),])
        #"^\([a-z]{1,3}(?=[\),])"#: { s, from in
            var m = S(s, from)
            guard m.consume("(" as Unicode.Scalar) else { return nil }
            let n = m.skip(while: isLowerAZ)
            guard n >= 1, n <= 3, let c = m.peek(), c == ")" || c == "," else { return nil }
            return m.match()
        },
        // static: reSoaRemainder — group 1 = "" at end, or one scalar of class
        #"^($|[\s,;\)\]\}])"#: { s, from in
            var m = S(s, from)
            if m.atDollar {
                // `$` is the first alternative: empty group 1
                return MhChemRegex.Match(range: from..<from, groups: [from..<from])
            }
            guard let c = m.peek() else { return nil }
            if isSpace(c) || c == "," || c == ";" || c == ")" || c == "]" || c == "}" {
                m.advance()
                return m.match(groups: [from..<m.i])
            }
            return nil
        },
        // static: reSoaAlt — \( (\ca\s?)? \$[amothc]\$ \)
        #"^(?:\((?:\\ca\s?)?\$[amothc]\$\))"#: { s, from in
            var m = S(s, from)
            guard m.consume("(" as Unicode.Scalar) else { return nil }
            if m.consume(#"\ca"#) {
                if let c = m.peek(), isSpace(c) { m.advance() }
            }
            guard m.consume("$" as Unicode.Scalar), let c = m.peek(),
                c == "a" || c == "m" || c == "o" || c == "t" || c == "h" || c == "c"
            else { return nil }
            m.advance()
            guard m.consume("$" as Unicode.Scalar), m.consume(")" as Unicode.Scalar) else {
                return nil
            }
            return m.match()
        },
        // static: reFormulaParenOnly
        #"^\([a-z]+\)$"#: { s, from in
            var m = S(s, from)
            guard m.consume("(" as Unicode.Scalar), m.skip(while: isLowerAZ) > 0,
                m.consume(")" as Unicode.Scalar), m.atDollar
            else { return nil }
            return m.match()
        },
    ]

    /// Greek-command tail shared by "letters" and "\greek": consumes
    /// `(?:alpha|…|Omega)(?:\s+|\{\}|(?![a-zA-Z]))` after the backslash.
    /// No name is a prefix of another, and every name must be followed by a
    /// non-letter (all three follow-alternatives require it), so "read the
    /// whole letter run and test set membership" is exactly equivalent to the
    /// regex's ordered-alternation-with-backtracking.
    private static let greekNames: Set<String> = [
        "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta",
        "iota", "kappa", "lambda", "mu", "nu", "xi", "omicron", "pi", "rho",
        "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega",
        "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Upsilon",
        "Phi", "Psi", "Omega",
    ]

    private static func greekTail(_ m: inout S) -> Bool {
        let nameStart = m.i
        guard m.skip(while: isLetterAZ) > 0 else { return false }
        guard greekNames.contains(String(m.sc[nameStart..<m.i])) else { return false }
        if m.skip(while: isSpace) > 0 { return true }
        if m.peek() == "{", m.peek(1) == "}" {
            m.advance()
            m.advance()
            return true
        }
        // (?![a-zA-Z]) — the letter run already ended, so this always holds.
        return true
    }
}
