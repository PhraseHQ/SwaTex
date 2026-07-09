/// ICU-backed regex for the mhchem tokenizer (P-015).
///
/// mhchem attempts many anchored patterns per input token, and the Swift
/// `Regex` interpreter dominated whole-engine profiles on `\ce` formulas
/// (~4× the cost of an average formula). Every mhchem pattern is
/// `^`-anchored, so matching reduces to "anchored match at a position in the
/// full string" — exactly what `NSRegularExpression` expresses with a search
/// range plus ICU's default anchoring bounds (`^` matches at range start,
/// `$` at range end). This also avoids the per-position `Substring` →
/// `String` copies the previous implementation needed.
///
/// Semantics note: ICU matches by code point, which is *closer* to the
/// JavaScript reference (mhchem 3.3.0, no `/u` flag) and to Rust's `regex`
/// crate than Swift `Regex`'s grapheme-cluster semantics. Byte-identical
/// output is enforced by the mhchem texify suite and the golden corpora.

import Foundation

struct MhChemRegex: @unchecked Sendable {
    // NSRegularExpression is documented as immutable and thread-safe.
    private let re: NSRegularExpression
    let pattern: String
    /// Hand-rolled fast matcher (P-019), present when `pattern`'s exact
    /// source string is in `MhChemHandMatchers.table`. If regenerated
    /// upstream data ever changes a pattern, its key stops matching and that
    /// pattern silently falls back to ICU — a hand matcher can never drift
    /// from a changed upstream pattern. Equivalence with ICU is asserted
    /// wholesale by `MhChemHandMatcherDiffTests`.
    private let hand: MhChemHandMatchers.Matcher?

    init(_ pattern: String) throws {
        re = try NSRegularExpression(pattern: pattern)
        self.pattern = pattern
        hand = MhChemHandMatchers.table[pattern]
    }

    /// ICU-only variant (differential tests compare `hand` against this).
    init(icuOnly pattern: String) throws {
        re = try NSRegularExpression(pattern: pattern)
        self.pattern = pattern
        hand = nil
    }

    struct Match {
        var range: Range<String.Index>
        /// Capture groups 1…; `nil` for non-participating groups.
        var groups: [Range<String.Index>?]
    }

    /// Match anchored at `from` within `s` (the whole pattern must start
    /// there; all mhchem patterns are additionally `^`-anchored, which under
    /// ICU's anchoring bounds means "at the start of the search range").
    /// Zero-copy: the search runs on the substring's base string with the
    /// substring's bounds as the ICU region, so `$` means "end of the
    /// substring" — the same semantics Swift Regex has on a `Substring`.
    func match(_ s: Substring, from: String.Index) -> Match? {
        if let hand {
            return hand(s, from)
        }
        let base = s.base
        let ns = NSRange(from..<s.endIndex, in: base)
        guard let m = re.firstMatch(in: base, options: [.anchored], range: ns) else {
            return nil
        }
        guard let whole = Range(m.range, in: base) else { return nil }
        var groups: [Range<String.Index>?] = []
        if m.numberOfRanges > 1 {
            groups.reserveCapacity(m.numberOfRanges - 1)
            for i in 1..<m.numberOfRanges {
                groups.append(Range(m.range(at: i), in: base))
            }
        }
        return Match(range: whole, groups: groups)
    }

    /// Anchored match at the start of `s`.
    func match(_ s: Substring) -> Match? {
        match(s, from: s.startIndex)
    }

    /// Anchored match at the start of `s`.
    func match(_ s: String) -> Match? {
        match(s[...], from: s.startIndex)
    }
}
