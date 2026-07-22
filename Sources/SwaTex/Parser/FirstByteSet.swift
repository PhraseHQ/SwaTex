/// A 128-bit membership filter over the *first UTF-8 byte* of a set of
/// dictionary keys, used to skip String hashing on the parser's hottest
/// lookups (performance log P-026).
///
/// Most tokens are single ASCII characters ("x", "2", "+") that are neither
/// macros nor functions, yet every one of them paid a full `Hasher` pass
/// against those tables. The filter answers "could this name possibly be a
/// key?" from its first byte alone: false → skip the dictionary; true →
/// fall through to the real lookup. False positives are harmless; the
/// filter never produces false negatives because inserts only accumulate
/// (a name removed from the table leaves its bit set — conservative).
struct FirstByteSet: Sendable {
    private var lo: UInt64 = 0
    private var hi: UInt64 = 0
    /// Any key whose first byte is ≥ 0x80 sets this catch-all instead.
    private var hasNonASCII = false

    init() {}

    init(keys: some Sequence<String>) {
        for key in keys {
            insert(firstByteOf: key)
        }
    }

    mutating func insert(firstByteOf name: String) {
        guard let b = name.utf8.first else { return }
        if b < 64 {
            lo |= 1 &<< UInt64(b)
        } else if b < 128 {
            hi |= 1 &<< UInt64(b - 64)
        } else {
            hasNonASCII = true
        }
    }

    /// `false` means no key in the set starts with `name`'s first byte
    /// (or `name` is empty), so a dictionary lookup cannot succeed.
    @inline(__always)
    func mayContain(_ name: String) -> Bool {
        guard let b = name.utf8.first else { return false }
        if b < 64 { return lo & (1 &<< UInt64(b)) != 0 }
        if b < 128 { return hi & (1 &<< UInt64(b - 64)) != 0 }
        return hasNonASCII
    }
}
