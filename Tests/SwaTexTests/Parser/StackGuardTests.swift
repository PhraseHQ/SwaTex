import Testing

@testable import SwaTex

/// The recursion guard must hold on EVERY thread: Swift Concurrency
/// cooperative threads have 512 KB stacks, where deep-but-guard-passing
/// input used to overflow the stack and SIGBUS the process (found while
/// raising coverage; the parse stage crashed at ~350 levels in release,
/// under the 512-level count guard). The stack-headroom probe turns that
/// into the same `ParseError.recursionLimitExceeded` the count guard
/// throws.
@Suite("StackGuard")
struct StackGuardTests {
    private static func deep(_ n: Int) -> String {
        String(repeating: "{", count: n) + "x" + String(repeating: "}", count: n)
    }

    @Test(arguments: [400, 500, 1000, 3000])
    func deepNestingThrowsOnCooperativeThread(_ n: Int) async {
        // Task.detached runs on a 512 KB cooperative thread — the exact
        // environment that used to crash.
        let result = await Task.detached { () -> Bool in
            do {
                _ = try SwaTexEngine.displayList(for: Self.deep(n))
                return false  // must not succeed at these depths on 512 KB
            } catch {
                return true
            }
        }.value
        #expect(result, "depth \(n) must throw, not crash or succeed")
    }

    @Test func deepNestingThrowsRecursionErrorOnTestThread() {
        #expect(throws: ParseError.self) {
            _ = try SwaTexEngine.displayList(for: Self.deep(3000))
        }
    }

    @Test func moderateNestingStillParses() throws {
        // Legitimate nesting keeps working (well inside every guard).
        let list = try SwaTexEngine.displayList(for: Self.deep(30))
        #expect(list.items.count > 0)
    }

    @Test func batchIsolatesDeepFormulaFailures() async {
        // The parallel batch API runs on cooperative threads; one hostile
        // formula must fail alone, not take down the batch (or process).
        let formulas = [#"x^2"#, Self.deep(800), #"\frac{a}{b}"#]
        let results = await SwaTexEngine.displayLists(for: formulas)
        #expect((try? results[0].get()) != nil)
        #expect((try? results[1].get()) == nil)
        #expect((try? results[2].get()) != nil)
    }
}
