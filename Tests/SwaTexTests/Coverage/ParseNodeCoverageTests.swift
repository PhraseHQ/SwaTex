import Testing

@testable import SwaTex

/// Exhaustive `ParseNode.Kind` coverage: every case must report the exact
/// KaTeX `type` string via `typeName`, and `isSymbolNode`/`symbolText` must
/// agree with the symbol-node subset.
@Suite("ParseNodeCoverage")
struct ParseNodeCoverageTests {
    private static let x = ParseNode(.mathOrd(text: "x"), mode: .math)
    private static let em = Measurement(number: 1.0, unit: "em")

    /// (node, expected typeName, expected symbolText or nil)
    static let cases: [(ParseNode.Kind, String, String?)] = [
        (.atom(family: .bin, text: "+"), "atom", "+"),
        (.mathOrd(text: "x"), "mathord", "x"),
        (.textOrd(text: "t"), "textord", "t"),
        (.opToken(text: "\\sum"), "op-token", "\\sum"),
        (.accentToken(text: "\\hat"), "accent-token", "\\hat"),
        (.spacing(text: "\\quad"), "spacing", "\\quad"),
        (.ordGroup(body: [x], semisimple: nil), "ordgroup", nil),
        (.supSub(base: x, sup: x, sub: nil), "supsub", nil),
        (
            .genfrac(
                continued: false, numer: x, denom: x, hasBarLine: true,
                leftDelim: nil, rightDelim: nil, barSize: nil),
            "genfrac", nil
        ),
        (.sqrt(body: x, index: nil), "sqrt", nil),
        (.accent(label: "\\hat", isStretchy: false, isShifty: true, base: x), "accent", nil),
        (
            .accentUnder(label: "\\utilde", isStretchy: true, isShifty: false, base: x),
            "accentUnder", nil
        ),
        (
            .op(
                limits: true, alwaysHandleSupSub: nil, suppressBaseShift: nil,
                parentIsSupSub: false, symbol: true, name: "\\sum", body: nil),
            "op", nil
        ),
        (
            .operatorName(
                body: [x], alwaysHandleSupSub: false, limits: false, parentIsSupSub: false),
            "operatorname", nil
        ),
        (.font(font: "mathrm", body: x), "font", nil),
        (.text(body: [x], font: nil), "text", nil),
        (.color(color: "red", body: [x]), "color", nil),
        (.colorToken(color: "red"), "color-token", nil),
        (.size(value: em, isBlank: false), "size", nil),
        (.styling(style: .display, body: [x]), "styling", nil),
        (.sizing(size: 3, body: [x]), "sizing", nil),
        (.delimSizing(size: 1, mclass: "mopen", delim: "("), "delimsizing", nil),
        (.leftRight(body: [x], left: "(", right: ")", rightColor: nil), "leftright", nil),
        (.leftRightRight(delim: ")", color: nil), "leftright-right", nil),
        (.middle(delim: "|"), "middle", nil),
        (.overline(body: x), "overline", nil),
        (.underline(body: x), "underline", nil),
        (.rule(shift: nil, width: em, height: em), "rule", nil),
        (.kern(dimension: em), "kern", nil),
        (.phantom(body: [x]), "phantom", nil),
        (.vphantom(body: x), "vphantom", nil),
        (.smash(body: x, smashHeight: true, smashDepth: false), "smash", nil),
        (.mclass(mclass: "mbin", body: [x], isCharacterBox: false), "mclass", nil),
        (
            .array(ParseNode.ArrayInfo(body: [[x]], rowGaps: [nil], hLinesBeforeRow: [[], []])),
            "array", nil
        ),
        (.environment(name: "matrix", nameGroup: x), "environment", nil),
        (.cr(newLine: true, size: nil), "cr", nil),
        (.infix(replaceWith: "\\frac", size: nil), "infix", nil),
        (.internalNode, "internal", nil),
        (.verb(body: "v", star: false), "verb", nil),
        (.href(href: "https://example.com/", body: [x]), "href", nil),
        (.url(url: "https://example.com/"), "url", nil),
        (.raw(string: "raw"), "raw", nil),
        (.hbox(body: [x]), "hbox", nil),
        (.horizBrace(label: "\\overbrace", isOver: true, base: x), "horizBrace", nil),
        (
            .enclose(label: "\\cancel", backgroundColor: nil, borderColor: nil, body: x),
            "enclose", nil
        ),
        (.lap(alignment: "rlap", body: x), "lap", nil),
        (
            .mathChoice(display: [x], text: [x], script: [x], scriptscript: [x]),
            "mathchoice", nil
        ),
        (.raiseBox(dy: em, body: x), "raisebox", nil),
        (.vcenter(body: x), "vcenter", nil),
        (.xArrow(label: "\\xrightarrow", body: x, below: nil), "xArrow", nil),
        (.pmb(mclass: "mord", body: [x]), "pmb", nil),
        (.tag(body: [x], tag: [x]), "tag", nil),
        (.noNumber, "nonumber", nil),
        (.html(attributes: ["class": "c"], body: [x]), "html", nil),
        (.htmlMathML(html: [x], mathml: [x]), "htmlmathml", nil),
        (
            .includeGraphics(alt: "a", width: em, height: em, totalheight: em, src: "s"),
            "includegraphics", nil
        ),
        (.cdLabel(side: "left", label: x), "cdlabel", nil),
        (.cdLabelParent(fragment: x), "cdlabelparent", nil),
        (.cdArrow(direction: "right", labelAbove: nil, labelBelow: nil), "cdArrow", nil),
        (
            .proofTree(
                tree: ProofBranch(conclusion: [x], premises: [], lineStyle: .solid)),
            "proofTree", nil
        ),
    ]

    @Test(arguments: 0..<cases.count)
    func typeNameAndSymbolText(_ i: Int) {
        let (kind, expectedType, expectedSymbol) = Self.cases[i]
        let node = ParseNode(kind, mode: .math)
        #expect(node.typeName == expectedType)
        #expect(node.symbolText == expectedSymbol)
        #expect(node.isSymbolNode == (expectedSymbol != nil))
    }

    @Test func normalizeArgument() {
        let single = ParseNode(.ordGroup(body: [Self.x], semisimple: nil), mode: .math)
        #expect(ParseNode.normalizeArgument(single).typeName == "mathord")
        let double = ParseNode(.ordGroup(body: [Self.x, Self.x], semisimple: nil), mode: .math)
        #expect(ParseNode.normalizeArgument(double).typeName == "ordgroup")
        #expect(ParseNode.normalizeArgument(Self.x).typeName == "mathord")
    }

    @Test func ordArgument() {
        let group = ParseNode(.ordGroup(body: [Self.x, Self.x], semisimple: nil), mode: .math)
        #expect(ParseNode.ordArgument(group).count == 2)
        #expect(ParseNode.ordArgument(Self.x).count == 1)
    }
}
