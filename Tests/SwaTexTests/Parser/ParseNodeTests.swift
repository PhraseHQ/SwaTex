import Testing

@testable import SwaTex

// Ported from the inline #[cfg(test)] tests in ratex-parser/src/parse_node.rs.
//
// The Rust tests asserted on serde JSON serialization. The Swift ParseNode has
// no Codable conformance, so the serde assertions are adapted to structural
// assertions (typeName, mode, pattern matching on .kind) while keeping the
// semantic intent of each test.

@Suite("ParseNode")
struct ParseNodeTests {
    // Rust: test_serialize_mathord — JSON had "type":"mathord", "mode":"math", "text":"x".
    @Test func serializeMathord() {
        let node = ParseNode(.mathOrd(text: "x"), mode: .math)
        #expect(node.typeName == "mathord")
        #expect(node.mode == .math)
        #expect(node.symbolText == "x")
    }

    // Rust: test_serialize_ordgroup — JSON had "type":"ordgroup".
    @Test func serializeOrdgroup() {
        let node = ParseNode(
            .ordGroup(
                body: [ParseNode(.mathOrd(text: "a"), mode: .math)],
                semisimple: nil),
            mode: .math)
        #expect(node.typeName == "ordgroup")
    }

    // Rust: test_serialize_supsub — JSON had "type":"supsub".
    @Test func serializeSupsub() {
        let node = ParseNode(
            .supSub(
                base: ParseNode(.mathOrd(text: "x"), mode: .math),
                sup: ParseNode(.textOrd(text: "2"), mode: .math),
                sub: nil),
            mode: .math)
        #expect(node.typeName == "supsub")
    }

    // Rust: test_serialize_genfrac — JSON had "type":"genfrac", "hasBarLine":true.
    @Test func serializeGenfrac() {
        let node = ParseNode(
            .genfrac(
                continued: false,
                numer: ParseNode(.mathOrd(text: "a"), mode: .math),
                denom: ParseNode(.mathOrd(text: "b"), mode: .math),
                hasBarLine: true,
                leftDelim: nil,
                rightDelim: nil,
                barSize: nil),
            mode: .math)
        #expect(node.typeName == "genfrac")
        if case let .genfrac(_, _, _, hasBarLine, _, _, _) = node.kind {
            #expect(hasBarLine == true)
        } else {
            Issue.record("Expected genfrac kind")
        }
    }

    // Rust: test_serialize_atom — JSON had "type":"atom", "family":"bin".
    @Test func serializeAtom() {
        let node = ParseNode(.atom(family: .bin, text: "+"), mode: .math)
        #expect(node.typeName == "atom")
        if case let .atom(family, _) = node.kind {
            #expect(family == .bin)
        } else {
            Issue.record("Expected atom kind")
        }
    }

    // Rust: test_roundtrip — serialize then deserialize preserved typeName and
    // symbolText. Without Codable, assert those accessors on a node carrying a
    // SourceLocation directly.
    @Test func roundtrip() {
        let node = ParseNode(
            .mathOrd(text: "x"), mode: .math, loc: SourceLocation(start: 0, end: 1))
        #expect(node.typeName == "mathord")
        #expect(node.symbolText == "x")
        #expect(node.loc == SourceLocation(start: 0, end: 1))
    }

    // Rust: test_mode_accessor.
    @Test func modeAccessor() {
        let node = ParseNode(.atom(family: .rel, text: "="), mode: .math)
        #expect(node.mode == .math)
    }

    // Rust: test_normalize_argument.
    @Test func normalizeArgument() {
        let group = ParseNode(
            .ordGroup(
                body: [ParseNode(.mathOrd(text: "x"), mode: .math)],
                semisimple: nil),
            mode: .math)
        let normalized = ParseNode.normalizeArgument(group)
        #expect(normalized.typeName == "mathord")
    }
}
