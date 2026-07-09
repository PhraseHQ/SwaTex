import Synchronization

/// Process-wide LRU cache for parsed + laid-out formulas.
///
/// Real applications (editors, chat, note apps) render the same formulas many
/// times — every SwiftUI body evaluation, every scroll-back into view, every
/// duplicate occurrence in a document. Parsing + layout costs ~70 µs; a cache
/// hit costs a dictionary lookup (~100 ns). This is the single biggest
/// performance lever for production use.
///
/// Thread-safe (`Mutex`), bounded, and keyed by the full render-relevant
/// input: (latex, style, color).
public final class FormulaCache: Sendable {
    /// Shared cache used by ``SwaTexEngine/displayList(for:style:color:cache:)``
    /// and `MathView`. Capacity 1024 ≈ a few MB for typical formulas.
    public static let shared = FormulaCache(capacity: 1024)

    private struct Key: Hashable {
        var latex: String
        var style: MathStyle
        var color: Color
    }

    private struct Entry {
        var value: Result<DisplayList, ParseError>
        var tick: UInt64
    }

    private struct Storage {
        var entries: [Key: Entry] = [:]
        var tick: UInt64 = 0
        var hits: UInt64 = 0
        var misses: UInt64 = 0
    }

    private let storage: Mutex<Storage>
    private let capacity: Int

    public init(capacity: Int = 1024) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.storage = Mutex(Storage())
    }

    /// Cache statistics (hits, misses) — useful for tuning capacity.
    public var statistics: (hits: UInt64, misses: UInt64) {
        storage.withLock { ($0.hits, $0.misses) }
    }

    /// Remove all cached formulas (e.g. on memory pressure).
    public func removeAll() {
        storage.withLock { $0.entries.removeAll(keepingCapacity: false) }
    }

    /// Look up or compute the display list for a formula.
    ///
    /// Errors are cached too: a formula that fails to parse fails identically
    /// on every attempt, so retry work is pointless.
    func displayList(
        latex: String, style: MathStyle, color: Color
    ) throws(ParseError) -> DisplayList {
        let key = Key(latex: latex, style: style, color: color)

        let cached = storage.withLock { s -> Result<DisplayList, ParseError>? in
            s.tick += 1
            if var entry = s.entries[key] {
                s.hits += 1
                entry.tick = s.tick
                s.entries[key] = entry
                return entry.value
            }
            s.misses += 1
            return nil
        }
        if let cached {
            return try cached.get()
        }

        let result = Result { () throws(ParseError) -> DisplayList in
            let nodes = try parseLaTeX(latex)
            let box = layout(nodes, options: LayoutOptions(style: style, color: color))
            return toDisplayList(box)
        }

        storage.withLock { s in
            if s.entries.count >= capacity {
                // Amortized eviction: drop the least-recently-used quarter in
                // one pass instead of tracking a linked list per access.
                let cutoff = s.entries.values.map(\.tick).sorted()[s.entries.count / 4]
                s.entries = s.entries.filter { $0.value.tick > cutoff }
            }
            s.entries[key] = Entry(value: result, tick: s.tick)
        }

        return try result.get()
    }
}

extension SwaTexEngine {
    /// Parse and lay out a LaTeX math string, memoized through `cache`.
    ///
    /// Identical inputs return the cached display list (~100 ns) instead of
    /// re-running the engine (~70 µs). Pass `nil` to bypass caching.
    public static func displayList(
        for latex: String,
        style: MathStyle = .display,
        color: Color = .black,
        cache: FormulaCache?
    ) throws(ParseError) -> DisplayList {
        guard let cache else {
            return try displayList(for: latex, style: style, color: color)
        }
        return try cache.displayList(latex: latex, style: style, color: color)
    }

    /// Lay out many formulas concurrently across all cores.
    ///
    /// The engine is pure value computation over immutable tables, so batches
    /// parallelize perfectly. Results preserve input order; each element is
    /// an independent `Result` so one bad formula doesn't fail the batch.
    public static func displayLists(
        for formulas: [String],
        style: MathStyle = .display,
        color: Color = .black,
        cache: FormulaCache? = nil
    ) async -> [Result<DisplayList, ParseError>] {
        await withTaskGroup(of: (Int, Result<DisplayList, ParseError>).self) { group in
            for (i, latex) in formulas.enumerated() {
                group.addTask {
                    let result = Result { () throws(ParseError) -> DisplayList in
                        try displayList(for: latex, style: style, color: color, cache: cache)
                    }
                    return (i, result)
                }
            }
            var results = [Result<DisplayList, ParseError>?](repeating: nil, count: formulas.count)
            for await (i, result) in group {
                results[i] = result
            }
            return results.map { $0! }
        }
    }
}
