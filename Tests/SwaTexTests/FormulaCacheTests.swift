import Testing

@testable import SwaTex

@Suite("FormulaCache")
struct FormulaCacheTests {
    @Test func hitReturnsIdenticalResult() throws {
        let cache = FormulaCache(capacity: 8)
        let a = try SwaTexEngine.displayList(for: #"x^2"#, cache: cache)
        let b = try SwaTexEngine.displayList(for: #"x^2"#, cache: cache)
        #expect(a.items == b.items)
        #expect(a.width == b.width)
        let stats = cache.statistics
        #expect(stats.hits == 1)
        #expect(stats.misses == 1)
    }

    @Test func distinctStylesAreDistinctEntries() throws {
        let cache = FormulaCache(capacity: 8)
        let display = try SwaTexEngine.displayList(
            for: #"\sum_n x_n"#, style: .display, cache: cache)
        let inline = try SwaTexEngine.displayList(for: #"\sum_n x_n"#, style: .text, cache: cache)
        #expect(display.totalHeight > inline.totalHeight)
        #expect(cache.statistics.misses == 2)
    }

    @Test func errorsAreCached() {
        let cache = FormulaCache(capacity: 8)
        for _ in 0..<3 {
            #expect(throws: ParseError.self) {
                try SwaTexEngine.displayList(for: #"\frac{1}"#, cache: cache)
            }
        }
        let stats = cache.statistics
        #expect(stats.misses == 1)
        #expect(stats.hits == 2)
    }

    @Test func evictionKeepsRecentEntries() throws {
        let cache = FormulaCache(capacity: 8)
        for i in 0..<20 {
            _ = try SwaTexEngine.displayList(for: "x_{\(i)}", cache: cache)
        }
        // Most recent entry must still be cached.
        let before = cache.statistics.hits
        _ = try SwaTexEngine.displayList(for: "x_{19}", cache: cache)
        #expect(cache.statistics.hits == before + 1)
    }

    @Test func removeAll() throws {
        let cache = FormulaCache(capacity: 8)
        _ = try SwaTexEngine.displayList(for: #"a+b"#, cache: cache)
        cache.removeAll()
        _ = try SwaTexEngine.displayList(for: #"a+b"#, cache: cache)
        #expect(cache.statistics.misses == 2)
    }

    @Test func concurrentAccessIsSafe() async throws {
        let cache = FormulaCache(capacity: 64)
        let formulas = (0..<32).map { "y_{\($0 % 8)}^2 + \($0 % 4)" }
        let results = await SwaTexEngine.displayLists(for: formulas, cache: cache)
        #expect(results.count == 32)
        for result in results {
            #expect(throws: Never.self) { try result.get() }
        }
    }

    @Test func batchPreservesOrderAndIsolatesErrors() async {
        let results = await SwaTexEngine.displayLists(
            for: [#"x"#, #"\frac{1}"#, #"y"#])
        #expect(results.count == 3)
        #expect((try? results[0].get()) != nil)
        #expect((try? results[1].get()) == nil)
        #expect((try? results[2].get()) != nil)
    }

    // ── Single-flight ─────────────────────────────────────────────────────

    /// Concurrent misses of the SAME key must coalesce into one computation:
    /// the first caller leads, callers arriving during the flight follow its
    /// result, and later callers hit the cache — so the engine runs exactly
    /// once no matter how the tasks interleave.
    @Test func concurrentSameKeyMissesComputeOnce() async throws {
        let cache = FormulaCache(capacity: 64)
        let formula = #"\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}"#
        let results = await SwaTexEngine.displayLists(
            for: Array(repeating: formula, count: 32), cache: cache)
        #expect(results.count == 32)
        for result in results {
            #expect(throws: Never.self) { try result.get() }
        }
        #expect(cache.computeCount == 1, "duplicates must single-flight, not recompute")
        #expect(cache.count == 1)
    }

    /// Every request increments exactly one of hits/misses exactly once,
    /// regardless of how it interleaves with a racing leader. Regression:
    /// a request that lost the leader race was counted twice (a fast-path
    /// miss AND a re-check hit), so hits+misses drifted past the number of
    /// requests under concurrency.
    @Test func racingRequestsCountOnceInStatistics() async {
        let cache = FormulaCache(capacity: 64)
        let n = 32
        let results = await SwaTexEngine.displayLists(
            for: Array(repeating: #"\frac{a}{b}"#, count: n), cache: cache)
        #expect(results.count == n)
        let stats = cache.statistics
        #expect(stats.hits + stats.misses == UInt64(n), "each request counts exactly once")
        #expect(cache.computeCount == 1)
    }

    /// A stack-degraded render is thread-dependent and must never be cached:
    /// an iterative parse admits a deep accent chain (a + 600 combining marks)
    /// that layout drops on a small stack, so the result is flagged truncated
    /// and skipped for persistence — a later big-stack caller then renders it
    /// completely instead of hitting the mutilated copy.
    @Test func stackDegradedResultIsNotCached() throws {
        let cache = FormulaCache(capacity: 8)
        let latex = "a" + String(repeating: "\u{0301}", count: 600)

        let degraded = runOnThread(stackSize: 256 << 10) {
            Result { () throws(ParseError) -> DisplayList in
                try SwaTexEngine.displayList(for: latex, cache: cache)
            }
        }
        let partial = try degraded.get()
        #expect(partial.truncated, "small-stack layout degradation must set truncated")
        #expect(cache.count == 0, "a truncated render must not be persisted")

        let full = runOnThread(stackSize: 64 << 20) {
            Result { () throws(ParseError) -> DisplayList in
                try SwaTexEngine.displayList(for: latex, cache: cache)
            }
        }
        let complete = try full.get()
        #expect(!complete.truncated, "big-stack render is complete")
        #expect(complete.items.count == 601, "all 600 marks plus the base render")
        #expect(cache.count == 1, "the complete render is cached")
    }

    /// Cached failures single-flight too (an unparseable formula fails
    /// identically every time).
    @Test func concurrentSameKeyErrorsComputeOnce() async {
        let cache = FormulaCache(capacity: 64)
        let results = await SwaTexEngine.displayLists(
            for: Array(repeating: #"\frac{1}"#, count: 16), cache: cache)
        for result in results {
            #expect((try? result.get()) == nil)
        }
        #expect(cache.computeCount == 1)
    }

    /// Distinct keys must not serialize behind one another's flights.
    @Test func distinctKeysComputeIndependently() async throws {
        let cache = FormulaCache(capacity: 64)
        let formulas = (0..<16).map { "z_{\($0)}" }
        let results = await SwaTexEngine.displayLists(for: formulas, cache: cache)
        for result in results {
            #expect(throws: Never.self) { try result.get() }
        }
        #expect(cache.computeCount == 16)
        #expect(cache.statistics.misses == 16)
    }
}
