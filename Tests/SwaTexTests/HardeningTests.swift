import Foundation
import Testing

@testable import SwaTex

/// Release-hardening battery: hostile inputs must fail fast with a
/// `ParseError` — never hang, trap, or exhaust memory — and boundary
/// inputs must behave. Complements the golden corpus (correctness) and
/// the differential suites (fast-path equivalence).
@Suite("Hardening")
struct HardeningTests {

    // ── Stress: hostile inputs fail fast ─────────────────────────────────

    @Test(arguments: [
        #"\begin{alignat}{999999999}a\end{alignat}"#,  // hung before the cap
        #"\begin{alignat}{257}a\end{alignat}"#,
        #"\begin{alignedat}{999999999}a\end{alignedat}"#,
    ])
    func hugeAlignatFailsFast(_ latex: String) {
        let start = ContinuousClock.now
        #expect(throws: ParseError.self) {
            _ = try SwaTexEngine.displayList(for: latex)
        }
        #expect(ContinuousClock.now - start < .seconds(1), "must fail fast, not hang")
    }

    @Test func alignatAtTheCapStillWorks() throws {
        let list = try SwaTexEngine.displayList(for: #"\begin{alignat}{256}a\end{alignat}"#)
        #expect(list.items.count > 0)
    }

    @Test func macroExpansionBombIsBounded() {
        // Exponential expansion must hit maxExpand, quickly.
        let bomb =
            #"\def\a{xx}\def\b{\a\a}\def\c{\b\b}\def\d{\c\c}"#
            + #"\def\e{\d\d}\def\f{\e\e}\def\g{\f\f}\def\h{\g\g}"#
            + #"\def\i{\h\h}\def\j{\i\i}\def\k{\j\j}\def\l{\k\k}\l\l\l\l"#
        let start = ContinuousClock.now
        #expect(throws: ParseError.self) {
            _ = try SwaTexEngine.displayList(for: bomb)
        }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func hundredKilobyteInputCompletes() throws {
        // Long-but-legitimate input: linear behavior, no quadratic blowup.
        let latex = String(repeating: #"x + y - "#, count: 12_000) + "z"
        let start = ContinuousClock.now
        let list = try SwaTexEngine.displayList(for: latex)
        #expect(list.items.count > 10_000)
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    // ── Fuzz smoke: random input never crashes ───────────────────────────

    /// Deterministic LCG so failures reproduce from the seed in the name.
    private struct LCG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    @Test func randomInputsNeverCrash() {
        // Alphabet biased toward TeX syntax to reach deep code paths.
        let alphabet = Array(
            #"\{}$&#^_%~ abcdefgxyz01259.,;:+-*/()[]|'<>=!"# + "\u{0B}\u{85}αΩ①"
                + #"\frac\sqrt\begin\end\left\right\ce\pu\def\text\color\rule"#)
        var rng = LCG(state: 0x5137_2026)
        for _ in 0..<2_000 {
            let len = Int(rng.next() % 60) + 1
            var s = ""
            for _ in 0..<len {
                s.append(alphabet[Int(rng.next() % UInt64(alphabet.count))])
            }
            // Must parse or throw ParseError — never trap or hang.
            _ = try? SwaTexEngine.displayList(for: s)
        }
    }

    // ── Boundary inputs ──────────────────────────────────────────────────

    @Test(arguments: [
        "", " ", "\n", "\t", "{}", "%comment only", "\u{FEFF}",
        "\\", "$", "^", "_", "&", "\u{0}",
        #"\kern99999999999999em x"#,  // absurd-but-parseable dimension
        #"\rule{0pt}{0pt}"#,
        #"\text{}"#, #"\frac{}{}"#, #"\sqrt{}"#,
    ])
    func boundaryInputsParseOrError(_ latex: String) {
        // Either outcome is fine; crashing or hanging is not.
        if let list = try? SwaTexEngine.displayList(for: latex) {
            #expect(list.width.isFinite && list.height.isFinite && list.depth.isFinite)
        }
    }

    @Test func outputGeometryIsAlwaysFinite() throws {
        // NaN/inf leaking into the display list would poison renderers.
        for latex in [#"\frac{1}{0}"#, #"x^{x^{x^{x}}}"#, #"\hspace{0pt}"#] {
            let list = try SwaTexEngine.displayList(for: latex)
            #expect(list.width.isFinite && list.totalHeight.isFinite)
            for item in list.items {
                if case let .glyphPath(x, y, scale, _, _, _) = item {
                    #expect(x.isFinite && y.isFinite && scale.isFinite)
                }
            }
        }
    }

    // ── Concurrency stress ───────────────────────────────────────────────

    @Test func concurrentMixedWorkloadIsStable() async {
        // Caches (FormulaCache, SVG memo, font tables) under contention:
        // 8 tasks × shared + unique formulas, incl. failures.
        await withTaskGroup(of: Int.self) { group in
            for t in 0..<8 {
                group.addTask {
                    var ok = 0
                    for i in 0..<200 {
                        let latex =
                            i % 3 == 0
                            ? #"\frac{a}{b}"#  // shared hit → cache contention
                            : i % 7 == 0
                                ? #"\undefinedshared"#  // shared cached failure (all tasks)
                                : "x_{\(t)}^{\(i)}"  // unique miss
                        if (try? SwaTexEngine.displayList(for: latex, cache: .shared))
                            != nil
                        {
                            ok += 1
                        }
                    }
                    return ok
                }
            }
            var total = 0
            for await ok in group { total += ok }
            #expect(total > 1_000)
        }
    }
}

/// Memory-bound invariants of the shared caches under adversarial load.
@Suite("CacheBounds")
struct CacheBoundsTests {
    @Test func distinctFloodStaysWithinCapacity() throws {
        let cache = FormulaCache(capacity: 128)
        // 10k distinct formulas through a 128-slot cache: must never exceed
        // capacity (amortized-eviction correctness = no unbounded growth).
        for i in 0..<10_000 {
            _ = try? cache.displayList(latex: "x_{\(i)}", style: .display, color: .black)
            #expect(cache.count <= 128)
        }
        #expect(cache.count <= 128)
    }

    @Test func errorsAreCachedAndBounded() throws {
        let cache = FormulaCache(capacity: 64)
        for i in 0..<5_000 {
            _ = try? cache.displayList(latex: "\\undef\(i)", style: .display, color: .black)
            #expect(cache.count <= 64)
        }
    }
}

/// Edge-of-core paths that legitimate-but-unusual input reaches: lexer
/// boundary cases, verb delimiters, char forms. (Parser invariant guards
/// like "No function handler for X" are unreachable by construction — a
/// registered function always has a handler — and are kept as assertions.)
@Suite("CoreEdgeCases")
struct CoreEdgeCasesTests {
    @Test(arguments: [
        "\\verb", "\\verb*",  // bare verb at EOF (lexer EOF branches)
        "\\verb!a+b!", "\\verb*|x y|", "\\verb#z#",
        "\\char65", "\\char\"41", "\\char'101",  // decimal/hex/octal char
        "\\text{a}\\text{b}",  // adjacent text runs
        "{\\bf x}\\rm y",  // font declaration scoping
        "\\begingroup x\\endgroup",
        "a % comment\nb",  // comment mid-expression
        "\\ x",  // control space
    ])
    func lexerAndCharEdgePaths(_ latex: String) {
        // Must parse or throw ParseError; never trap.
        _ = try? SwaTexEngine.displayList(for: latex)
    }

    @Test func catcodeMutationPath() throws {
        // \verb with % as delimiter exercises setCatcode append path.
        _ = try? SwaTexEngine.displayList(for: "\\verb%a%")
        // A fresh custom active char via \def on ~ (catcode 13):
        _ = try SwaTexEngine.displayList(for: "\\def~{x}~")
    }
}
