/// A symbol's mode in TeX.
public enum Mode: Hashable, Sendable {
    case math
    case text
}

/// The font family for a symbol.
public enum SymbolFont: Hashable, Sendable {
    case main
    case ams
}

/// The group/atom type of a symbol, determining spacing behavior.
public enum Group: String, Hashable, Sendable {
    case bin
    case close
    case inner
    case open
    case punct
    case rel
    case accentToken = "accent-token"
    case mathOrd = "mathord"
    case opToken = "op-token"
    case spacing
    case textOrd = "textord"

    public var isAtom: Bool {
        switch self {
        case .bin, .close, .inner, .open, .punct, .rel: true
        default: false
        }
    }
}

/// Information about a resolved symbol.
public struct SymbolInfo: Sendable {
    public var name: String
    public var mode: Mode
    public var font: SymbolFont
    public var group: Group
    public var codepoint: Unicode.Scalar?
}

/// Lazily built lookup indices over the generated symbol table.
/// `static let` gives thread-safe once-only initialization (the Swift
/// equivalent of Rust's `OnceLock`).
private enum SymbolMaps {
    // Flat per-mode dictionaries: symbol resolution runs for every parsed
    // token, so a nested `[UInt8: [String: Int]]` would pay two hash lookups
    // plus an extra retain per call (P-010 in the performance log).

    /// name → index into SymbolsData.symbols, per mode.
    static let mathByName: [String: Int] = buildByName(mode: 0)
    static let textByName: [String: Int] = buildByName(mode: 1)

    /// codepoint → index into SymbolsData.symbols, per mode.
    static let mathByCodepoint: [Unicode.Scalar: Int] = buildByCodepoint(mode: 0)
    static let textByCodepoint: [Unicode.Scalar: Int] = buildByCodepoint(mode: 1)

    private static func buildByName(mode: UInt8) -> [String: Int] {
        var map = [String: Int](minimumCapacity: SymbolsData.symbols.count)
        for (i, entry) in SymbolsData.symbols.enumerated()
        where entry.mode == mode && map[entry.name] == nil {
            map[entry.name] = i
        }
        return map
    }

    private static func buildByCodepoint(mode: UInt8) -> [Unicode.Scalar: Int] {
        var map = [Unicode.Scalar: Int](minimumCapacity: SymbolsData.symbols.count)
        for (i, entry) in SymbolsData.symbols.enumerated()
        where entry.mode == mode {
            if let cp = entry.codepoint, map[cp] == nil {
                map[cp] = i
            }
        }
        return map
    }

    /// `Group` parsed once per table row (P-021): `Group(rawValue:)` is a
    /// string switch, and symbol resolution runs it for every parsed token.
    static let groups: [Group] = SymbolsData.symbols.map {
        Group(rawValue: $0.group) ?? .mathOrd
    }
}

extension SymbolInfo {
    fileprivate init(entryAt idx: Int, mode: Mode) {
        let entry = SymbolsData.symbols[idx]
        self.init(
            name: entry.name,
            mode: mode,
            font: entry.font == 0 ? .main : .ams,
            group: SymbolMaps.groups[idx],
            codepoint: entry.codepoint)
    }

    /// Look up a symbol by name in a given mode. O(1) via dictionary.
    ///
    /// When `name` is a single Unicode character, this also tries codepoint lookup,
    /// matching KaTeX's `acceptUnicodeChar` behavior where both `name` and `replace`
    /// are valid keys (e.g. both `\alpha` and `α` resolve to the same symbol).
    public init?(name: String, mode: Mode) {
        // Direct name lookup (command name like "\alpha")
        let byName = mode == .math ? SymbolMaps.mathByName : SymbolMaps.textByName
        if let idx = byName[name] {
            self.init(entryAt: idx, mode: mode)
            return
        }
        // KaTeX acceptUnicodeChar: replace string is also a key. Single-char name → try by codepoint.
        let scalars = name.unicodeScalars
        if let first = scalars.first, scalars.count == 1 {
            self.init(codepoint: first, mode: mode)
            return
        }
        return nil
    }

    /// Look up a symbol by its Unicode codepoint in a given mode. O(1) via dictionary.
    public init?(codepoint: Unicode.Scalar, mode: Mode) {
        let byCodepoint = mode == .math ? SymbolMaps.mathByCodepoint : SymbolMaps.textByCodepoint
        guard let idx = byCodepoint[codepoint] else {
            return nil
        }
        self.init(entryAt: idx, mode: mode)
    }
}
