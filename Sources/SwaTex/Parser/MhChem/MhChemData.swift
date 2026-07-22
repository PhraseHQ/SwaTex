/// mhchem static data: decoded `machines.json` + compiled `patterns_regex.json`.
///
/// Port of RaTeX `mhchem/data.rs` and `mhchem/json.rs`.

import Foundation

/// Internal error type for the mhchem module; mapped to `ParseError` at the
/// public `MhChem.parse` boundary. Mirrors RaTeX `MhchemError`.
enum MhChemError: Error, Sendable {
    case msg(String)
    case extraClose

    /// Matches the Rust `Display` implementation (`thiserror` messages).
    var description: String {
        switch self {
        case .msg(let s): "mhchem: \(s)"
        case .extraClose: "extra close brace or missing open brace"
        }
    }
}

/// JSON structures for `machines.json` (from `tools/generate_mhchem_data.mjs`).
struct MhChemMachineDef: Decodable, Sendable {
    var transitions: [String: [MhChemTransition]]
    var hasLocalActions: Bool

    // P-023: the engine's transition loop runs against an index-resolved
    // form of `transitions` — state names interned to Ints, `nextState`
    // strings pre-resolved per transition — so the hot loop performs no
    // string hashing and no dictionary probes. Populated by
    // `MhChemData.init` after decoding.

    /// State name → index into `stateTable`.
    var stateIndexByName: [String: Int] = [:]
    /// Transitions per state index (same arrays as `transitions`' values).
    var stateTable: [[MhChemTransition]] = []
    /// Index of the `"*"` fallback state, if the machine has one.
    var starStateIndex: Int? = nil

    enum CodingKeys: String, CodingKey {
        case transitions
        case hasLocalActions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transitions = try c.decode([String: [MhChemTransition]].self, forKey: .transitions)
        hasLocalActions = try c.decodeIfPresent(Bool.self, forKey: .hasLocalActions) ?? false
    }

    /// Build the index-resolved tables (P-016 kinds + P-023 state indices).
    mutating func resolve(regexes: [String: MhChemRegex]) {
        let names = transitions.keys.sorted()
        stateIndexByName = Dictionary(
            uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        starStateIndex = stateIndexByName["*"]
        stateTable = names.map { name in
            var trs = transitions[name]!
            for i in trs.indices {
                trs[i].kind = MhChemPatterns.resolveKind(trs[i].pattern, regexes: regexes)
                trs[i].nextStateIndex = trs[i].task.nextState.flatMap {
                    // Unknown targets keep nil; the engine then reports the
                    // same "no transitions for state" error as before, at
                    // the same point (when the state is entered).
                    stateIndexByName[$0]
                }
            }
            transitions[name] = trs
            return trs
        }
    }
}

struct MhChemTransition: Decodable, Sendable {
    var pattern: String
    var task: MhChemTask
    /// Pattern pre-resolved for dispatch (P-016); populated by
    /// `MhChemData.init` after decoding, never from JSON.
    var kind: MhChemPatterns.Kind = .unknown("unresolved")
    /// `task.nextState` pre-resolved to a state-table index (P-023);
    /// populated by `MhChemData.init`, never from JSON.
    var nextStateIndex: Int? = nil

    enum CodingKeys: String, CodingKey {
        case pattern
        case task
    }
}

struct MhChemTask: Decodable, Sendable {
    var nextState: String?
    var revisit: Bool
    var toContinue: Bool
    var actions: [MhChemActionSpec]

    enum CodingKeys: String, CodingKey {
        case nextState
        case revisit
        case toContinue
        /// JSON keeps KaTeX name `action_`.
        case actions = "action_"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nextState = try c.decodeIfPresent(String.self, forKey: .nextState)
        revisit = try c.decodeIfPresent(Bool.self, forKey: .revisit) ?? false
        toContinue = try c.decodeIfPresent(Bool.self, forKey: .toContinue) ?? false
        actions = try c.decodeIfPresent([MhChemActionSpec].self, forKey: .actions) ?? []
    }
}

struct MhChemActionSpec: Decodable, Sendable {
    var type: String
    var option: MhChemOption?

    enum CodingKeys: String, CodingKey {
        case type = "type_"
        case option
    }
}

/// The `option` value of an action, which in the JSON is a bool, an int, or
/// a string (mirrors the `serde_json::Value` option in RaTeX).
enum MhChemOption: Decodable, Sendable {
    case bool(Bool)
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else {
            self = .string(try c.decode(String.self))
        }
    }

    var asBool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var asInt: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

/// JSON-like value produced by the state machines and consumed by texify
/// (mirrors the `serde_json::Value` AST in RaTeX).
enum MhChemValue: Sendable {
    case string(String)
    case array([MhChemValue])
    /// Objects carry 1–4 fields; ordered pairs with a linear-scan
    /// subscript beat a `Dictionary` here (P-024: no bucket allocation,
    /// no key hashing — object construction is a per-token hot path).
    case obj([(String, MhChemValue)])

    /// Dictionary-literal construction sugar so build sites read like the
    /// KaTeX/RaTeX originals: `.object(["type_": .string("bond")])`.
    /// `KeyValuePairs` preserves the literal syntax without hashing.
    static func object(_ pairs: KeyValuePairs<String, MhChemValue>) -> MhChemValue {
        // The Dictionary this replaced trapped on duplicate literal keys;
        // ordered pairs would silently shadow (subscript returns the first).
        // Keep the old invariant checkable in debug builds.
        assert(
            Set(pairs.map(\.0)).count == pairs.count,
            "duplicate MhChemValue object keys: \(pairs.map(\.0))")
        return .obj(pairs.map { ($0, $1) })
    }

    var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var asArray: [MhChemValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    subscript(key: String) -> MhChemValue? {
        if case .obj(let o) = self {
            for (k, v) in o where k == key {
                return v
            }
        }
        return nil
    }
}

/// Decoded machines + compiled named regex patterns. All stored properties
/// are immutable and Sendable, so the instance is safely shared.
final class MhChemData: Sendable {
    let machines: [String: MhChemMachineDef]
    /// Named regexes from `patterns_regex.json`, compiled once (ICU-backed,
    /// see MhChemRegex / P-015).
    let regexes: [String: MhChemRegex]

    private struct PatternsFile: Decodable {
        var regex: [String: String]
    }

    init() throws {
        var decoded = try JSONDecoder().decode(
            [String: MhChemMachineDef].self,
            from: Data(MhChemDataJSON.machines.utf8)
        )
        let patterns = try JSONDecoder().decode(
            PatternsFile.self,
            from: Data(MhChemDataJSON.patterns.utf8)
        )
        var map: [String: MhChemRegex] = [:]
        map.reserveCapacity(patterns.regex.count)
        for (k, src) in patterns.regex {
            do {
                map[k] = try MhChemRegex(src)
            } catch {
                // INTENTIONALLY UNCOVERED (embedded-data KEEP): `init` only
                // ever compiles the vendored `patterns_regex.json` sources,
                // all of which compile; reachable only if the generated data
                // is corrupted.
                throw MhChemError.msg("regex compile \"\(k)\": \(error)")
            }
        }
        regexes = map

        // Resolve every transition once — pattern kinds (P-016) and state
        // indices (P-023) — so the engine's loop needs no string work.
        for (mk, var def) in decoded {
            def.resolve(regexes: map)
            decoded[mk] = def
        }
        machines = decoded
    }

    static let shared: MhChemData = {
        // Data is embedded and covered by tests, so a failure here is a
        // programming error (matches the Rust `.expect(...)`).
        do {
            return try MhChemData()
        } catch {
            // INTENTIONALLY UNCOVERED (embedded-data KEEP): reachable only if
            // the vendored JSON fails to decode or compile — a programming
            // error, matching the Rust `.expect(...)`.
            fatalError("mhchem static data must parse and compile: \(error)")
        }
    }()
}
