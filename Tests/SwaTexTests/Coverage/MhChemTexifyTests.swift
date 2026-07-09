import Testing

@testable import SwaTex

/// Direct tests of `MhChemTexify.go` over hand-built mhchem AST values —
/// the expected strings mirror KaTeX mhchem 3.3 / RaTeX `texify.rs`.
@Suite("MhChemTexifyDirect")
struct MhChemTexifyTests {
    private func node(_ fields: KeyValuePairs<String, MhChemValue>) -> MhChemValue {
        .object(fields)
    }

    private func texify(_ v: MhChemValue, isInner: Bool = true) throws -> String {
        try MhChemTexify.go([v], isInner: isInner)
    }

    @Test func missingTypeThrows() {
        #expect(throws: MhChemError.self) {
            _ = try texify(node(["p1": .string("x")]))
        }
    }

    @Test func unknownTypeThrows() {
        do {
            _ = try texify(node(["type_": .string("not-a-type")]))
            Issue.record("expected unknown-type error")
        } catch {
            #expect((error as? MhChemError)?.description.contains("unknown type") == true)
        }
    }

    @Test func textWithScriptsBecomesMathrm() throws {
        // text containing ^ or _ switches to \mathrm with ~ and \text{-}
        let got = try texify(node(["type_": .string("text"), "p1": .string("a^b c-d")]))
        #expect(got == #"\mathrm{a^b~c\text{-}d}"#)
    }

    @Test func plainTextStaysText() throws {
        let got = try texify(node(["type_": .string("text"), "p1": .string("ab")]))
        #expect(got == #"\text{ab}"#)
    }

    @Test func color0EmitsBareColor() throws {
        let got = try texify(node(["type_": .string("color0"), "color": .string("red")]))
        #expect(got == #"\color{red}"#)
    }

    @Test func unknownOperatorThrows() {
        do {
            _ = try texify(node(["type_": .string("operator"), "kind_": .string("??")]))
            Issue.record("expected unknown-operator error")
        } catch {
            #expect((error as? MhChemError)?.description.contains("Unknown operator") == true)
        }
    }

    @Test func firstLevelEscapeAppendsSpace() throws {
        let got = try texify(node(["type_": .string("1st-level escape"), "p1": .string("x")]))
        #expect(got == "x ")
    }

    @Test func firstLevelEscapeSuppressesOuterBraces() throws {
        // cee flag: outer {} suppressed even when isInner == false
        let got = try texify(
            node(["type_": .string("1st-level escape"), "p1": .string("x")]), isInner: false)
        #expect(got == "x ")
    }

    @Test func spaceType() throws {
        #expect(try texify(node(["type_": .string("space")])) == " ")
    }

    @Test func upAndDownArrowOperators() throws {
        #expect(try texify(node(["type_": .string("^")])) == "\\uparrow ")
        #expect(try texify(node(["type_": .string("v")])) == "\\downarrow ")
    }

    @Test func spacedSlash() throws {
        #expect(try texify(node(["type_": .string(" / ")])) == #"\,/\,"#)
    }

    @Test func unknownArrowThrows() {
        do {
            _ = try texify(
                node([
                    "type_": .string("arrow"), "r": .string("-->>"),
                    "rd": .array([]), "rq": .array([]),
                ]))
            Issue.record("expected unknown-arrow error")
        } catch {
            #expect((error as? MhChemError)?.description.contains("unknown arrow") == true)
        }
    }

    @Test func arrowVariantsTranslate() throws {
        let pairs: [(String, String)] = [
            ("->", "\\xrightarrow{}"),
            ("<-", "\\xleftarrow{}"),
            ("<->", "\\xleftrightarrow{}"),
            ("<-->", "\\xrightleftarrows{}"),
            ("<=>", "\\xrightleftharpoons{}"),
            ("<=>>", "\\xrightequilibrium{}"),
            ("<<=>", "\\xleftequilibrium{}"),
            ("\u{2192}", "\\xrightarrow{}"),
            ("\u{21cc}", "\\xrightleftharpoons{}"),
        ]
        for (r, expected) in pairs {
            let got = try texify(
                node([
                    "type_": .string("arrow"), "r": .string(r),
                    "rd": .array([]), "rq": .array([]),
                ]))
            #expect(got == expected, Comment(rawValue: "arrow \(r)"))
        }
    }

    @Test func angleBracketBonds() throws {
        #expect(
            try texify(node(["type_": .string("bond"), "kind_": .string("<")])) == "{<}")
        #expect(
            try texify(node(["type_": .string("bond"), "kind_": .string(">")])) == "{>}")
    }

    @Test func unknownBondThrows() {
        #expect(throws: MhChemError.self) {
            _ = try texify(node(["type_": .string("bond"), "kind_": .string("?!")]))
        }
    }
}
