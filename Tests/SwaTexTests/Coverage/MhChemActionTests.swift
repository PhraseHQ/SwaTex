import Foundation
import Testing

@testable import SwaTex

/// Direct tests of the mhchem action layer (`MhChemActions.apply`), mirroring
/// RaTeX `mhchem/actions.rs`: buffer transfers, two-argument outputs, color
/// outputs, malformed-token guards, and the pu number/output helpers.
@Suite("MhChemAction")
struct MhChemActionTests {
    private let data = MhChemData.shared

    private func spec(_ type: String, option: String? = nil) throws -> MhChemActionSpec {
        var json = #"{"type_":"\#(type)""#
        if let option {
            json += #","option":\#(option)"#
        }
        json += "}"
        return try JSONDecoder().decode(MhChemActionSpec.self, from: Data(json.utf8))
    }

    private func apply(
        _ machine: String, _ type: String, _ m: MhChemMatchToken,
        option: String? = nil, buffer: MhChemBuffer = MhChemBuffer()
    ) throws -> [MhChemValue] {
        try MhChemActions.apply(
            data, machine: machine, buffer: buffer, m: m, spec: spec(type, option: option))
    }

    private func str(_ v: MhChemValue?) -> String? {
        if case .string(let s)? = v { return s }
        return nil
    }

    private func isType(_ v: MhChemValue?, _ ty: String) -> Bool {
        if case .string(let t)? = v?["type_"] { return t == ty }
        return false
    }

    // ── buffer transfers ────────────────────────────────────────────────

    @Test func aToOMovesAmountSlot() throws {
        let buffer = MhChemBuffer()
        buffer.a = "2"
        let out = try apply("ce", "a to o", .s(""), buffer: buffer)
        #expect(out.isEmpty)
        #expect(buffer.o == "2")
        #expect(buffer.a == nil)
    }

    @Test func chargeOrBondAfterBondEmitsBond() throws {
        let buffer = MhChemBuffer()
        buffer.beginsWithBond = true
        buffer.o = "A"
        let out = try apply("ce", "charge or bond", .s("-"), buffer: buffer)
        guard let fields = out.last, case .obj = fields, case .string("bond")? = fields["type_"]
        else {
            Issue.record("expected trailing bond object, got \(String(describing: out.last))")
            return
        }
        #expect(str(fields["kind_"]) == "-")
    }

    @Test func dashAfterDigitsD() throws {
        let buffer = MhChemBuffer()
        buffer.o = "C"
        buffer.d = "2"
        let out = try apply("ce", "- after o/d", .s("-"), option: "true", buffer: buffer)
        #expect(!out.isEmpty)
    }

    // ── two-argument outputs ────────────────────────────────────────────

    @Test func fracOutputRequiresArrayToken() {
        #expect(throws: MhChemError.self) {
            _ = try apply("ce", "frac-output", .s("x"))
        }
        #expect(throws: MhChemError.self) {
            _ = try apply("ce", "frac-output", .a(["1"]))
        }
    }

    @Test func fracOutputBuildsFracCe() throws {
        let out = try apply("ce", "frac-output", .a(["1", "2"]))
        guard let fields = out.first, case .obj = fields else {
            Issue.record("expected object")
            return
        }
        #expect(str(fields["type_"]) == "frac-ce")
    }

    @Test func oversetOutputGuards() {
        #expect(throws: MhChemError.self) {
            _ = try apply("ce", "overset-output", .s("x"))
        }
        #expect(throws: MhChemError.self) {
            _ = try apply("ce", "underset-output", .a(["only"]))
        }
    }

    @Test func colorOutputGuards() {
        #expect(throws: MhChemError.self) {
            _ = try apply("ce", "color-output", .s("red"))
        }
        #expect(throws: MhChemError.self) {
            _ = try apply("ce", "color-output", .a(["red"]))
        }
    }

    @Test func pqColorOutputGuardAndSuccess() throws {
        #expect(throws: MhChemError.self) {
            _ = try apply("pq", "color-output", .s("red"))
        }
        let out = try apply("pq", "color-output", .a(["red", "2"]))
        guard let fields = out.first, case .obj = fields else {
            Issue.record("expected color object")
            return
        }
        #expect(str(fields["type_"]) == "color")
        #expect(str(fields["color1"]) == "red")
    }

    @Test func bdColorOutput() throws {
        let out = try apply("bd", "color-output", .a(["blue", "-"]))
        #expect(out.count == 1)
    }

    // ── global actions ──────────────────────────────────────────────────

    @Test func color0OutputGuardAndSuccess() throws {
        #expect(throws: MhChemError.self) {
            _ = try apply("ce", "color0-output", .s("red"))
        }
        let out = try apply("ce", "color0-output", .a(["red"]))
        guard let fields = out.first, case .obj = fields else {
            Issue.record("expected color0 object")
            return
        }
        #expect(str(fields["type_"]) == "color0")
        #expect(str(fields["color"]) == "red")
    }

    @Test func insertP1P2GuardAndSuccess() throws {
        #expect(throws: MhChemError.self) {
            _ = try apply("ce", "insert+p1+p2", .s("x"), option: #""ellipsis""#)
        }
        #expect(throws: MhChemError.self) {
            _ = try apply("ce", "insert+p1+p2", .a(["a"]), option: #""ellipsis""#)
        }
        let out = try apply("ce", "insert+p1+p2", .a(["a", "b"]), option: #""ellipsis""#)
        guard let fields = out.first, case .obj = fields else {
            Issue.record("expected object")
            return
        }
        #expect(str(fields["p1"]) == "a")
        #expect(str(fields["p2"]) == "b")
    }

    @Test func unknownActionThrowsBugA() {
        do {
            _ = try apply("ce", "not-an-action", .s("x"))
            Issue.record("expected mhchem bug A error")
        } catch {
            #expect((error as? MhChemError)?.description.contains("mhchem bug A") == true)
        }
    }

    @Test func operatorWithArrayTokenUsesFirstGroup() throws {
        // matchStr(.a) = first element
        let out = try apply("ce", "operator", .a(["+", "rest"]))
        guard let fields = out.first, case .obj = fields else {
            Issue.record("expected operator object")
            return
        }
        #expect(str(fields["kind_"]) == "+")
    }

    @Test func stateOfAggregationJoinsArrayToken() throws {
        // tokenString(.a) = joined elements
        let out = try apply("ce", "state of aggregation", .a(["a", "q"]))
        guard let fields = out.first, case .obj = fields else {
            Issue.record("expected object")
            return
        }
        #expect(str(fields["type_"]) == "state of aggregation")
    }

    @Test func oxidationOutputWrapsInBraces() throws {
        let out = try apply("ce", "oxidation-output", .s("+II"))
        #expect(str(out.first) == "{")
        #expect(str(out.last) == "}")
    }

    // ── pu helpers ──────────────────────────────────────────────────────

    @Test func puNumberPowVariants() throws {
        // non-array token → empty
        #expect(try apply("pu", "number^", .s("x")).isEmpty)
        // "+-" sign → \pm
        let pm = try apply("pu", "number^", .a(["+-", "2", "24"]))
        #expect(str(pm.first) == "\\pm ")
        #expect(str(pm.last) == "^{24}")
        // plain sign passes through
        let minus = try apply("pu", "number^", .a(["-", "2", "24"]))
        #expect(str(minus.first) == "-")
    }

    @Test func puEnumberExponentWithDecimal() throws {
        // third group containing '.' routes through the pu-9,9 machine
        let out = try apply("pu", "enumber", .a(["", "1", "2.5"]))
        #expect(!out.isEmpty)
        let plain = try apply("pu", "enumber", .a(["", "1", "25"]))
        #expect(plain.contains { str($0) == "25" })
    }

    @Test func puOutputSlashWithMultiElementDenominator() throws {
        let buffer = MhChemBuffer()
        buffer.d = "J"
        buffer.q = "mol s"
        buffer.o = "/"
        let out = try apply("pu", "output", .s(""), buffer: buffer)
        // multi-element denominator uses the spaced " / " divider
        #expect(out.contains { isType($0, " / ") })
    }

    @Test func puOutputBracedDenominator() throws {
        let buffer = MhChemBuffer()
        buffer.d = "J"
        buffer.q = "{mol}"
        buffer.o = "/"
        let out = try apply("pu", "output", .s(""), buffer: buffer)
        #expect(!out.isEmpty)
    }

    @Test func puOutputEmptyBuffer() throws {
        let out = try apply("pu", "output", .s(""))
        #expect(out.isEmpty)
    }

    // ── tex-math splitting ──────────────────────────────────────────────

    @Test func texMathMachineSplitsDollarSegments() throws {
        let values = try MhChemEngine.goMachine(data, input: "ab$c$d", machine: "tex-math")
        #expect(!values.isEmpty)
    }
}
