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
}
