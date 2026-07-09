import Foundation
import Testing

@testable import SwaTex

/// Coarse performance-regression sentinels that run in the *default* suite
/// (unlike the `SWATEX_BENCH` micro-benchmarks). Thresholds are set ~5–10×
/// above measured medians on CI-class hardware, so they catch only gross
/// algorithmic regressions (an accidental O(n²), a lost cache, a dropped
/// fast path) — never normal machine-to-machine variance. Skipped under
/// sanitizers / debug-heavy environments where absolute timing is
/// meaningless.
@Suite(
    "PerfRegression",
    .enabled(if: ProcessInfo.processInfo.environment["SWATEX_NO_PERF"] == nil),
    .serialized)
struct PerformanceRegressionTests {
    private static let corpus = [
        #"x^2 + y^2 = z^2"#, #"\frac{-b \pm \sqrt{b^2-4ac}}{2a}"#,
        #"\sum_{n=1}^{\infty} \frac{1}{n^2}"#, #"\int_0^1 x\,dx"#,
        #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#,
        #"\ce{H2SO4 + 2NaOH -> Na2SO4 + 2H2O}"#, #"e^{i\pi}+1=0"#,
        #"\lim_{x\to0}\frac{\sin x}{x}"#,
    ]

    @Test func engineThroughputHasNotRegressed() {
        // Warm static tables.
        for f in Self.corpus { _ = try? SwaTexEngine.displayList(for: f) }

        let iterations = 600
        let start = ContinuousClock.now
        for _ in 0..<iterations {
            for f in Self.corpus {
                _ = try? SwaTexEngine.displayList(for: f)
            }
        }
        let elapsed = ContinuousClock.now - start
        let perFormula = elapsed / (iterations * Self.corpus.count)
        // Median on dev hardware ≈ 20 µs/formula; CI runners are slower.
        // 500 µs is a 25× ceiling — trips only on an algorithmic regression.
        #expect(
            perFormula < .microseconds(500),
            "engine throughput regressed: \(perFormula)/formula")
    }

    @Test func formulaCacheHitStaysFast() {
        let cache = FormulaCache(capacity: 64)
        let latex = #"\frac{-b \pm \sqrt{b^2-4ac}}{2a}"#
        _ = try? cache.displayList(latex: latex, style: .display, color: .black)  // prime

        let iterations = 30_000
        let start = ContinuousClock.now
        for _ in 0..<iterations {
            _ = try? cache.displayList(latex: latex, style: .display, color: .black)
        }
        let perHit = (ContinuousClock.now - start) / iterations
        // A hit is a dictionary lookup (~100 ns dev). 20 µs = 200× ceiling;
        // trips if the cache is bypassed and the engine re-runs per call.
        #expect(perHit < .microseconds(20), "cache-hit path regressed: \(perHit)/hit")
    }

    @Test func longInputScalesLinearly() {
        // Doubling input length should roughly double time, not quadruple.
        func time(_ repeats: Int) -> Duration {
            let latex = String(repeating: #"a + b - "#, count: repeats) + "c"
            let start = ContinuousClock.now
            _ = try? SwaTexEngine.displayList(for: latex)
            return ContinuousClock.now - start
        }
        _ = time(500)  // warm
        let t1 = time(2_000)
        let t2 = time(4_000)
        // Linear ⇒ ratio ≈ 2. Allow up to 3.5× for constant-factor noise;
        // an O(n²) path would show ≈ 4× and climbing.
        let ratio = t2 / t1
        #expect(ratio < 3.5, "superlinear scaling: 2× input took \(ratio)× time")
    }
}
