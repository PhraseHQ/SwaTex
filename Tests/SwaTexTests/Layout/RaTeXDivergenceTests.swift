import Foundation
import Testing

@testable import SwaTex

/// `golden/ratex_divergences.json` is the machine-readable form of the
/// EXCEPTIONS comments on the golden suites: the corpus inputs whose fixtures
/// hold SwaTex's KaTeX-correct values rather than the RaTeX reference's.
/// `scripts/diff_layout.py` reads it to tell an expected divergence from a
/// regression; these tests keep it in step with the corpora, so a divergence
/// cannot appear, vanish or be renamed without the manifest saying so.
@Suite("RaTeXDivergence")
struct RaTeXDivergenceTests {
    struct Manifest: Decodable {
        struct Group: Decodable {
            var reason: String
            var pinnedBy: String
            var inputs: [String]
        }
        var comment: String
        var divergences: [Group]
    }

    /// How many corpus inputs each reason covers. Changing a divergence means
    /// changing this table too — which is the point: it cannot happen quietly.
    static let expectedCounts = [
        "align-family column and relation spacing": 38,
        "an unterminated \\verb is a parse error": 2,
        "\\limits after an ordinary atom is a parse error": 1,
        "\\vcenter centers ink on the math axis, changing display-list depth": 2,
        "a \\tag renders in text mode, as KaTeX expands it": 5,
        "a subscript takes the base's italic correction only from a symbol base": 2,
    ]

    static let corpora = ["test_cases", "test_cases_coverage"]

    static func manifest() throws -> Manifest {
        let url = try #require(
            Bundle.module.url(
                forResource: "ratex_divergences", withExtension: "json", subdirectory: "golden"))
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    }

    @Test func everyReasonCoversThePinnedNumberOfInputs() throws {
        let groups = try Self.manifest().divergences
        // Summing duplicates rather than trapping on them keeps a manifest
        // that repeats a reason a test failure, not a crash.
        let counts = Dictionary(
            groups.map { ($0.reason, $0.inputs.count) }, uniquingKeysWith: +)
        #expect(counts.count == groups.count, "a reason is listed twice")
        #expect(counts == Self.expectedCounts)
        for group in groups {
            #expect(!group.pinnedBy.isEmpty, "\(group.reason) names no pinning test")
        }
    }

    @Test func noInputIsListedTwice() throws {
        let inputs = try Self.manifest().divergences.flatMap(\.inputs)
        #expect(Set(inputs).count == inputs.count)
    }

    /// A listed input that no corpus contains would silently stop protecting
    /// anything, and would make `diff_layout.py` excuse a formula that is not
    /// even tested.
    @Test func everyListedInputIsInACorpus() throws {
        var corpusInputs: Set<String> = []
        for corpus in Self.corpora {
            corpusInputs.formUnion(
                try GoldenLayoutTests.fixtures(corpus).map(\.input))
        }
        for input in try Self.manifest().divergences.flatMap(\.inputs) {
            #expect(corpusInputs.contains(input), "not in any corpus: \(input)")
        }
    }
}
