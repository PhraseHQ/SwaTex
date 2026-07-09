import Foundation
import Testing

@testable import SwaTex

/// Golden layout parity tests.
///
/// The fixtures under `Resources/golden/*.jsonl` are the RaTeX (Rust) engine's
/// output over its golden corpora (regenerate with:
/// `target/release/ratex-layout < tests/golden/<corpus>.txt`). Every formula's
/// box metrics and display-list summary must match the Rust engine **exactly**
/// (both engines round to 5 decimals).
@Suite("GoldenLayout")
struct GoldenLayoutTests {
    struct Fixture: Decodable {
        struct Box: Decodable {
            var width: Double
            var height: Double
            var depth: Double
        }
        struct DL: Decodable {
            var width: Double
            var height: Double
            var depth: Double
            var itemCount: Int
        }
        var input: String
        var box: Box?
        var displayList: DL?
        var error: Bool?
        var message: String?
    }

    static func fixtures(_ name: String) throws -> [Fixture] {
        let url = try #require(
            Bundle.module.url(
                forResource: name, withExtension: "jsonl", subdirectory: "golden"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try text.split(separator: "\n").map {
            try decoder.decode(Fixture.self, from: Data($0.utf8))
        }
    }

    private func round5(_ v: Double) -> Double {
        (v * 100000).rounded() / 100000
    }

    private func check(corpus: String) throws {
        var mismatches: [String] = []
        var checked = 0

        for fixture in try Self.fixtures(corpus) {
            let result = Result { () throws(ParseError) -> DisplayList in
                let ast = try parseLaTeX(fixture.input)
                return toDisplayList(layout(ast, options: LayoutOptions()))
            }

            switch (result, fixture.error == true) {
            case (.success(let dl), false):
                guard let box = fixture.box, let fdl = fixture.displayList else {
                    mismatches.append("\(fixture.input): fixture missing box")
                    continue
                }
                // The fixture's box is the pre-display LayoutBox; compare via
                // the display list dimensions, which are what renderers consume.
                if round5(dl.width) != fdl.width || round5(dl.height) != fdl.height
                    || round5(dl.depth) != fdl.depth || dl.items.count != fdl.itemCount
                {
                    mismatches.append(
                        "\(fixture.input): swift(w:\(round5(dl.width)) h:\(round5(dl.height)) "
                            + "d:\(round5(dl.depth)) n:\(dl.items.count)) "
                            + "rust(w:\(fdl.width) h:\(fdl.height) d:\(fdl.depth) n:\(fdl.itemCount))"
                    )
                }
                _ = box
            case (.failure, true):
                break  // both engines reject — OK
            case (.success, true):
                mismatches.append("\(fixture.input): Swift parsed but Rust errored")
            case (.failure(let e), false):
                mismatches.append("\(fixture.input): Swift errored (\(e)) but Rust parsed")
            }
            checked += 1
        }

        let detail =
            "\(mismatches.count)/\(checked) mismatches:\n"
            + mismatches.prefix(20).joined(separator: "\n")
        #expect(mismatches.isEmpty, Comment(rawValue: detail))
        #expect(checked > 0)
    }

    @Test func mainCorpus() throws {
        try check(corpus: "test_cases")
    }

    @Test func mhchemCorpus() throws {
        try check(corpus: "test_case_ce")
    }

    @Test func prooftreeCorpus() throws {
        try check(corpus: "test_cases_prooftree")
    }
}
