import Testing

@testable import SwaTex

/// P-024 semantics pins: ordered-pair objects preserve construction order,
/// subscript returns the first match, and the factory keeps the
/// no-duplicate-keys invariant the replaced Dictionary enforced by
/// trapping (checked by a debug assertion, exercised by every mhchem test).
@Suite("MhChemValueSemantics")
struct MhChemValueSemanticsTests {
    @Test func subscriptReturnsFirstMatchingKey() {
        let v = MhChemValue.obj([("a", .string("1")), ("b", .string("2")), ("a", .string("3"))])
        #expect(v["a"]?.asString == "1")
        #expect(v["b"]?.asString == "2")
        #expect(v["missing"] == nil)
    }

    @Test func factoryPreservesLiteralOrder() {
        let v = MhChemValue.object(["x": .string("1"), "y": .string("2")])
        guard case .obj(let pairs) = v else {
            Issue.record("expected .obj")
            return
        }
        #expect(pairs.map(\.0) == ["x", "y"])
    }
}
