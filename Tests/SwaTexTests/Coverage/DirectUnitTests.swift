import Testing

@testable import SwaTex

/// Direct unit tests of internal functions — exercising branches that the
/// full parse→layout→display pipeline does not reach through top-level
/// LaTeX input, but that are legitimate to unit-test by calling the
/// component directly. This is standard branch testing, not white-box
/// coupling: each test drives a documented public/internal entry point.
@Suite("DirectUnit")
struct DirectUnitTests {

    // Engine layout switch — `.cdArrow` node laid out standalone (in the
    // pipeline `layoutCD` intercepts it, but `layout()` must handle it).
    @Test func layoutCdArrowNodeDirectly() {
        let node = ParseNode(
            .cdArrow(direction: "right", labelAbove: nil, labelBelow: nil), mode: .math)
        let box = layout([node], options: LayoutOptions())
        #expect(box.width.isFinite)
    }

    @Test(arguments: ["right", "left", "horiz_eq", "vert_eq", "none"])
    func layoutCdArrowAllDirections(_ direction: String) {
        let node = ParseNode(
            .cdArrow(direction: direction, labelAbove: nil, labelBelow: nil), mode: .math)
        let box = layout([node], options: LayoutOptions())
        #expect(box.width.isFinite && box.height.isFinite)
    }

    // Engine `.text` node with `font: nil` — pipeline producers always set a
    // font, but `layout()` must handle the nil-font case (→ layoutText).
    @Test func layoutTextNodeNilFontDirectly() {
        let inner = ParseNode(.mathOrd(text: "x"), mode: .text)
        let node = ParseNode(.text(body: [inner], font: nil), mode: .text)
        let box = layout([node], options: LayoutOptions())
        #expect(box.width >= 0)
    }

    // Lexer.setCatcode append branch — the append path fires for a character
    // not already in the default catcode table.
    @Test func lexerSetCatcodeAppendsNovelCharacter() {
        var lexer = Lexer("§x")
        // '§' is not in the default catcode table → append branch.
        lexer.setCatcode("§", 13)  // make it active
        #expect(lexer.catcode("§") == 13)
        // A second novel char also appends.
        lexer.setCatcode("¶", 12)
        #expect(lexer.catcode("¶") == 12)
        // Updating an existing entry takes the update branch, not append.
        lexer.setCatcode("§", 11)
        #expect(lexer.catcode("§") == 11)
    }

    // ToDisplay path scaling + bounds with quadratic Bézier commands — no
    // bundled geometry emits quads, but `toDisplayList` must scale and bound
    // them if a path contains them.
    @Test func toDisplayListHandlesQuadCurves() {
        let commands: [PathCommand] = [
            .moveTo(x: 0, y: 0),
            .quadTo(x1: 0.5, y1: 1.0, x: 1.0, y: 0),
            .close,
        ]
        let box = LayoutBox(
            width: 1, height: 1, depth: 0,
            content: .svgPath(commands: commands, fill: true))
        let list = toDisplayList(box)
        #expect(list.width.isFinite)
        // The scaled path must preserve the quad command.
        var sawQuad = false
        for item in list.items {
            if case let .path(_, _, cmds, _, _) = item {
                for c in cmds {
                    if case .quadTo = c { sawQuad = true }
                }
            }
        }
        #expect(sawQuad, "quad command should survive scaling")
    }

    // Color(model:value:) — every model branch plus the unknown-model default.
    @Test func colorModelInitBranches() {
        #expect(Color(model: "RGB", value: "255,0,0") == Color(r: 1, g: 0, b: 0))
        #expect(Color(model: "rgb", value: "1,0,0") == Color(r: 1, g: 0, b: 0))
        #expect(Color(model: "gray", value: "0.5")?.r == 0.5)
        #expect(Color(model: "HTML", value: "00FF00") != nil)
        #expect(Color(model: "cmyk", value: "0,0,0,0") == Color(r: 1, g: 1, b: 1))
        // Unknown model → default branch → nil.
        #expect(Color(model: "nosuchmodel", value: "1,2,3") == nil)
        // Malformed component counts → csv guard → nil.
        #expect(Color(model: "RGB", value: "1,2") == nil)
        #expect(Color(model: "cmyk", value: "notanumber,0,0,0") == nil)
    }
}

extension DirectUnitTests {
    // Absent-optional-argument nil returns for hbox/color/url arg types.
    // No builtin declares these as optional, so the pipeline never takes
    // the nil branch — driven directly here with `optional: true` on input
    // whose optional `[...]` argument is absent.
    @Test func absentOptionalArgumentReturnsNil() throws {
        // Empty / non-bracket input → the optional argument is absent.
        let hboxNil = try Parser("").parseGroupOfType(
            name: "\\hbox", argType: .hbox, optional: true)
        #expect(hboxNil == nil)

        let colorNil = try Parser("x").parseColorGroup(optional: true)
        #expect(colorNil == nil)

        let urlNil = try Parser("x").parseURLGroup(optional: true)
        #expect(urlNil == nil)
    }
}

extension DirectUnitTests {
    // Parser invariant guards, driven directly (the pipeline never triggers
    // them: names always resolve, primitive args are never optional).
    @Test func functionRegistryMissThrows() {
        #expect(throws: ParseError.self) {
            _ = try Parser("x").callFunction(
                "\\definitelyNotARegisteredFunction", args: [], optArgs: [])
        }
    }

    @Test func primitiveOptionalArgumentThrows() {
        #expect(throws: ParseError.self) {
            _ = try Parser("x").parseGroupOfType(
                name: "\\somecmd", argType: .primitive, optional: true)
        }
    }

    // tryParseUnicodeAccent multi-scalar-base branch: a two-scalar base
    // ("ab") before the combining mark takes the else that recurses /
    // falls back to textOrd.
    @Test func unicodeAccentMultiScalarBase() throws {
        let tok = Token("a", start: 0, end: 1)
        let node = try Parser("").tryParseUnicodeAccent("ab\u{0301}", nucleus: tok)
        #expect(node != nil)
    }

    // getExpansion `.function` case (expandOnce intercepts `.function`
    // before this is reached in the pipeline).
    @Test func getExpansionFunctionSignal() {
        let def = MacroDefinition.function { _ in [] }
        let exp = Parser("").gullet.getExpansion(def, name: "\\fn")
        #expect(exp != nil)
        #expect(exp?.tokens.isEmpty == true)
    }

    // Lexer mid-stream decode-failure guard: a truncated UTF-8 lead byte
    // after a valid token yields an EOF token (never crashes).
    @Test func lexerHandlesMalformedUTF8() {
        // 0xC3 is a 2-byte-sequence lead; without its continuation byte the
        // scalar decode fails mid-stream.
        var lexer = Lexer(bytes: [UInt8(ascii: "x"), 0xC3])
        _ = lexer.lex()  // 'x'
        let tok = lexer.lex()  // decode failure → EOF
        #expect(tok.isEOF)
    }
}
