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
/// input: (latex, style, color). Concurrent misses of the same key are
/// single-flighted: one caller computes, the rest wait for its result —
/// so a batch containing duplicates does each unique formula once.
public final class FormulaCache: Sendable {
    /// Shared cache used by ``SwaTexEngine/displayList(for:style:color:cache:)``
    /// and `MathView`. Capacity 1024 ≈ a few MB for typical formulas.
    public static let shared = FormulaCache(capacity: 1024)

    // Key/Flight/Storage/storage/lead are internal (not private) so
    // FunctionCoverageTests can drive the lead-vs-lead race re-check
    // deterministically; production callers use only `displayList`.
    struct Key: Hashable {
        var latex: String
        var style: MathStyle
        var color: Color
    }

    struct Entry {
        var value: Result<DisplayList, ParseError>
        var tick: UInt64
    }

    /// One in-flight computation. The leader acquires `gate` *before*
    /// publishing the flight and holds it while computing; followers block
    /// on `gate` and read the finished result. By construction the slot is
    /// always filled by the time a follower can acquire the lock.
    final class Flight: Sendable {
        let gate = Mutex<Result<DisplayList, ParseError>?>(nil)
    }

    struct Storage {
        var entries: [Key: Entry] = [:]
        var flights: [Key: Flight] = [:]
        var tick: UInt64 = 0
        var hits: UInt64 = 0
        var misses: UInt64 = 0
        var computes: UInt64 = 0
    }

    let storage: Mutex<Storage>
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

    /// Number of actual engine computations performed (misses that led,
    /// i.e. excluding single-flight followers). Test/diagnostics seam.
    var computeCount: UInt64 {
        storage.withLock { $0.computes }
    }

    /// Current number of cached entries. Bounded by `capacity` (amortized —
    /// eviction drops the least-recently-used quarter when the cap is hit).
    public var count: Int {
        storage.withLock { $0.entries.count }
    }

    /// Remove all cached formulas (e.g. on memory pressure).
    public func removeAll() {
        storage.withLock { $0.entries.removeAll(keepingCapacity: false) }
    }

    /// Outcome of one locked entry/flight lookup (nil = true miss).
    private enum Lookup {
        case value(Result<DisplayList, ParseError>)
        case follow(Flight)
    }

    /// Shared lookup used by the fast path and the leader's re-check: touch
    /// the entry's LRU tick on a hit, or surface an in-flight computation.
    /// Counter accounting stays with the callers — the fast path counts every
    /// request exactly once; the re-check counts nothing (its request was
    /// already counted as a miss).
    private static func lookup(_ s: inout Storage, _ key: Key) -> Lookup? {
        if var entry = s.entries[key] {
            entry.tick = s.tick
            s.entries[key] = entry
            return .value(entry.value)
        }
        if let flight = s.flights[key] {
            return .follow(flight)
        }
        return nil
    }

    /// Look up or compute the display list for a formula.
    ///
    /// Errors are cached too: a formula that fails to parse fails identically
    /// on every attempt, so retry work is pointless.
    func displayList(
        latex: String, style: MathStyle, color: Color
    ) throws(ParseError) -> DisplayList {
        let key = Key(latex: latex, style: style, color: color)

        let fast = storage.withLock { s -> Lookup? in
            s.tick += 1
            let found = Self.lookup(&s, key)
            if case .value = found {
                s.hits += 1
            } else {
                s.misses += 1
            }
            return found
        }
        switch fast {
        case .value(let result):
            return try result.get()
        case .follow(let flight):
            return try followResult(of: flight).get()
        case nil:
            return try lead(key).get()
        }
    }

    /// Wait for another caller's in-flight computation.
    private func followResult(of flight: Flight) -> Result<DisplayList, ParseError> {
        // Blocks until the leader — which acquired the gate before the
        // flight became discoverable and fills the slot before releasing —
        // is done. The slot is therefore always non-nil here; trapping on
        // a broken invariant beats silently recomputing without publishing.
        flight.gate.withLock { $0! }
    }

    /// Take leadership for `key`: compute once, publish to the cache, and
    /// wake any followers blocked on the flight's gate.
    ///
    /// The leader computes while holding the gate, so followers block for
    /// the full computation. For a synchronous API that is the floor: any
    /// correct wait strategy blocks the calling thread, and pre-single-flight
    /// behavior pinned the same threads doing N redundant computes instead
    /// of one. `Mutex` additionally donates blocked callers' QoS to the
    /// leader; a non-blocking follower path would require an async surface.
    func lead(_ key: Key) -> Result<DisplayList, ParseError> {
        let flight = Flight()
        return flight.gate.withLock { slot in
            // Re-check under our own gate: another leader may have raced us
            // between the fast path and here. Lock order is gate → storage;
            // followers only ever take storage and a gate separately, so
            // there is no cycle.
            let race = storage.withLock { s -> Lookup? in
                if let found = Self.lookup(&s, key) {
                    return found
                }
                s.flights[key] = flight
                return nil
            }
            switch race {
            case .value(let result):
                return result
            case .follow(let other):
                // Our gate was never published, so holding it while waiting
                // on the racing leader's gate cannot form a wait cycle.
                return followResult(of: other)
            case nil:
                break
            }

            let result = Self.compute(key)

            storage.withLock { s in
                s.computes += 1
                // A stack-degraded partial render is thread-dependent: a later
                // caller on a bigger stack would render it fully. Never persist
                // it — followers of THIS flight still receive it, but the cache
                // won't serve the mutilated list to unrelated callers.
                let isTruncated: Bool
                if case .success(let dl) = result {
                    isTruncated = dl.truncated
                } else {
                    isTruncated = false
                }
                if !isTruncated {
                    if s.entries.count >= capacity {
                        // Amortized eviction: drop the least-recently-used quarter
                        // in one pass instead of tracking a linked list per access.
                        let cutoff = s.entries.values.map(\.tick).sorted()[s.entries.count / 4]
                        s.entries = s.entries.filter { $0.value.tick > cutoff }
                    }
                    s.entries[key] = Entry(value: result, tick: s.tick)
                }
                s.flights[key] = nil
            }
            // Fill the slot before releasing the gate so every follower
            // observes the result.
            slot = result
            return result
        }
    }

    private static func compute(_ key: Key) -> Result<DisplayList, ParseError> {
        Result { () throws(ParseError) -> DisplayList in
            let nodes = try parseLaTeX(key.latex)
            let box = layout(
                nodes, options: LayoutOptions(style: key.style, color: key.color))
            // `truncated` covers BOTH degradation stages: layout-stage drops
            // travel in the box tree as `.degraded` markers and emission
            // converts them (plus its own drops) into the flag.
            return toDisplayList(box)
        }
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
