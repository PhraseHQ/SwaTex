import Testing

@testable import SwaTex

/// Parser branch coverage: error paths, double-script detection, URL/color/size
/// argument groups, unicode accent decomposition, and text-mode ligatures.
@Suite("ParserCoverage")
struct ParserCoverageTests {
    private func parseError(_ input: String) -> ParseError? {
        do {
            _ = try parseLaTeX(input)
            return nil
        } catch {
            return error
        }
    }

    // ── Error paths ─────────────────────────────────────────────────────

    @Test func doubleInfixError() {
        let e = parseError(#"{a \over b \over c}"#)
        #expect(e?.message == "only one infix operator per group")
    }

    @Test func doubleSuperscriptError() {
        #expect(parseError("x^a^b")?.message == "Double superscript")
    }

    @Test func doubleSubscriptError() {
        #expect(parseError("x_a_b")?.message == "Double subscript")
    }

    @Test func primeAfterSuperscriptError() {
        // x^a' — prime sees an existing superscript
        #expect(parseError("x^a'")?.message == "Double superscript")
    }

    @Test func unicodeSubAfterSubscriptError() {
        // x_a₂ — unicode subscript char with explicit subscript already set
        #expect(parseError("x_a\u{2082}")?.message == "Double subscript")
    }

    @Test func unicodeSupAfterSuperscriptError() {
        #expect(parseError("x^a\u{00B2}")?.message == "Double superscript")
    }

    @Test func missingGroupAfterSuperscript() {
        let e = parseError("x^")
        #expect(e?.message.contains("Expected group after") == true)
    }

    @Test func functionAsArgumentError() {
        let e = parseError(#"\sqrt\over"#)
        #expect(e?.message.contains("no arguments") == true || e != nil)
    }

    @Test func invalidColorError() {
        let e = parseError(#"\textcolor{not a color!}{x}"#)
        #expect(e?.message.contains("Invalid color") == true)
    }

    @Test func bareHex6ColorGetsHashPrefix() throws {
        // 6-hex-digit color without '#' is normalized to #RRGGBB
        let nodes = try parseLaTeX(#"\textcolor{ff0000}{x}"#)
        try #require(nodes.count == 1)
        guard case let .color(color, _) = nodes[0].kind else {
            Issue.record("expected color node")
            return
        }
        #expect(color == "#ff0000")
    }

    @Test func invalidSizeError() {
        let e = parseError(#"\rule{bad}{1pt}"#)
        #expect(e?.message.contains("Invalid size") == true)
    }

    @Test func invalidUnitError() {
        let e = parseError(#"\rule{1foo}{1pt}"#)
        #expect(e?.message.contains("Invalid unit") == true)
    }

    @Test func invalidSizeRegexGroupError() {
        // \above takes a size without braces; non-size input fails the regex group
        let e = parseError(#"{a \above xx b}"#)
        #expect(e?.message.contains("Invalid size") == true)
    }

    @Test func unexpectedCloseBraceError() {
        #expect(parseError("x}")?.message.contains("Expected 'EOF', got '}'") == true)
    }

    @Test func extraCloseBraceInMacroArgError() {
        // consumeArg sees a } at depth 0 → "Extra }"
        let e = parseError(#"\@firstoftwo{a}}x"#)
        #expect(e?.message.contains("Extra }") == true)
    }

    // ── URL groups ──────────────────────────────────────────────────────

    @Test func hrefProducesHrefNode() throws {
        let nodes = try parseLaTeX(#"\href{https://example.com/%20a~b}{x}"#)
        try #require(nodes.count == 1)
        guard case let .href(href, body) = nodes[0].kind else {
            Issue.record("expected href node")
            return
        }
        #expect(href == "https://example.com/%20a~b")
        #expect(!body.isEmpty)
    }

    @Test func urlProducesHrefWithTextttBody() throws {
        let nodes = try parseLaTeX(#"\url{http://a.b/~c%20d}"#)
        try #require(nodes.count == 1)
        guard case let .href(url, body) = nodes[0].kind else {
            Issue.record("expected href node, got \(nodes[0].typeName)")
            return
        }
        #expect(url == "http://a.b/~c%20d")
        try #require(body.count == 1)
        guard case let .text(chars, font) = body[0].kind else {
            Issue.record("expected text body")
            return
        }
        #expect(font == "\\texttt")
        #expect(chars.count == url.count)
    }

    // ── \hspace* ────────────────────────────────────────────────────────

    @Test func hspaceStarParsesAsKern() throws {
        let nodes = try parseLaTeX(#"a\hspace*{2em}b"#)
        #expect(nodes.contains { $0.typeName == "kern" })
    }

    // ── Text-mode ligatures ─────────────────────────────────────────────

    @Test func textEnDashLigature() throws {
        let nodes = try parseLaTeX(#"\text{a--b}"#)
        guard case let .text(body, _) = nodes[0].kind else {
            Issue.record("expected text node")
            return
        }
        #expect(body.contains { $0.symbolText == "--" })
    }

    @Test func textEmDashLigature() throws {
        let nodes = try parseLaTeX(#"\text{a---b}"#)
        guard case let .text(body, _) = nodes[0].kind else {
            Issue.record("expected text node")
            return
        }
        #expect(body.contains { $0.symbolText == "---" })
    }

    @Test func textQuoteLigatures() throws {
        let nodes = try parseLaTeX(#"\text{``x''}"#)
        guard case let .text(body, _) = nodes[0].kind else {
            Issue.record("expected text node")
            return
        }
        #expect(body.contains { $0.symbolText == "``" })
        #expect(body.contains { $0.symbolText == "''" })
    }

    // ── Unicode accent decomposition ────────────────────────────────────

    @Test func precomposedAccentDecomposes() throws {
        let nodes = try parseLaTeX("é")
        try #require(nodes.count == 1)
        guard case let .accent(label, _, _, base) = nodes[0].kind else {
            Issue.record("expected accent node, got \(nodes[0].typeName)")
            return
        }
        #expect(label == "\\acute")
        #expect(base.symbolText == "e")
    }

    @Test func combiningAccentDecomposes() throws {
        // x + combining acute (U+0301)
        let nodes = try parseLaTeX("x\u{0301}")
        try #require(nodes.count == 1)
        guard case let .accent(label, _, _, base) = nodes[0].kind else {
            Issue.record("expected accent node, got \(nodes[0].typeName)")
            return
        }
        #expect(label == "\\acute")
        #expect(base.symbolText == "x")
    }

    @Test func accentedIUsesDotlessBase() throws {
        let nodes = try parseLaTeX("í")
        try #require(nodes.count == 1)
        guard case let .accent(_, _, _, base) = nodes[0].kind else {
            Issue.record("expected accent node, got \(nodes[0].typeName)")
            return
        }
        #expect(base.symbolText == "\u{0131}")  // dotless ı
    }

    @Test func accentedJUsesDotlessBase() throws {
        let nodes = try parseLaTeX("j\u{0301}")
        try #require(nodes.count == 1)
        guard case let .accent(_, _, _, base) = nodes[0].kind else {
            Issue.record("expected accent node, got \(nodes[0].typeName)")
            return
        }
        #expect(base.symbolText == "\u{0237}")  // dotless ȷ
    }

    @Test func textModeAccentLabels() throws {
        // In text mode, combining marks map to text accent commands (\\' etc.)
        let nodes = try parseLaTeX(#"\text{é ù ĉ ñ ō ă ż ä å ő ǔ ç}"#)
        guard case let .text(body, _) = nodes[0].kind else {
            Issue.record("expected text node")
            return
        }
        let labels = body.compactMap { node -> String? in
            if case let .accent(label, _, _, _) = node.kind { return label }
            return nil
        }
        #expect(labels.contains("\\'"))
        #expect(labels.contains("\\`"))
        #expect(labels.contains("\\^"))
        #expect(labels.contains("\\~"))
        #expect(labels.contains("\\="))
        #expect(labels.contains("\\u"))
        #expect(labels.contains("\\."))
        #expect(labels.contains("\\\""))
        #expect(labels.contains("\\r"))
        #expect(labels.contains("\\H"))
        #expect(labels.contains("\\v"))
        #expect(labels.contains("\\c"))
    }

    @Test func mathModeAccentLabels() throws {
        let inputs: [(String, String)] = [
            ("x\u{0300}", "\\grave"),
            ("x\u{0301}", "\\acute"),
            ("x\u{0302}", "\\hat"),
            ("x\u{0303}", "\\tilde"),
            ("x\u{0304}", "\\bar"),
            ("x\u{0306}", "\\breve"),
            ("x\u{0307}", "\\dot"),
            ("x\u{0308}", "\\ddot"),
            ("x\u{030A}", "\\mathring"),
            ("x\u{030B}", "\\H"),
            ("x\u{030C}", "\\check"),
            ("x\u{0327}", "\\c"),
        ]
        for (input, expectedLabel) in inputs {
            let nodes = try parseLaTeX(input)
            guard case let .accent(label, _, _, _) = nodes[0].kind else {
                Issue.record("expected accent for \(input)")
                continue
            }
            #expect(label == expectedLabel, Comment(rawValue: "input: \(input)"))
        }
    }

    @Test func multipleCombiningMarksNest() throws {
        // a + tilde + acute → accent(acute, accent(tilde, a))
        let nodes = try parseLaTeX("a\u{0303}\u{0301}")
        try #require(nodes.count == 1)
        guard case let .accent(outer, _, _, inner) = nodes[0].kind,
            case let .accent(innerLabel, _, _, base) = inner.kind
        else {
            Issue.record("expected nested accents")
            return
        }
        #expect(outer == "\\acute")
        #expect(innerLabel == "\\tilde")
        #expect(base.symbolText == "a")
    }

    @Test func nonLatinBaseWithCombiningMark() throws {
        // Cyrillic base + combining mark: no decomposition, falls through to textord
        let nodes = try parseLaTeX("б\u{0301}")
        #expect(!nodes.isEmpty)
        #expect(nodes[0].typeName == "textord")
    }

    // ── ParseError type ─────────────────────────────────────────────────

    @Test func parseErrorDescriptions() {
        let plain = ParseError("boom")
        #expect(plain.description == "ParseError: boom")
        let located = ParseError("bang", at: SourceLocation(start: 3, end: 5))
        #expect(located.description.contains("position 3"))
        #expect(ParseError.recursionLimitExceeded.message == "Recursion limit exceeded")
    }
}
