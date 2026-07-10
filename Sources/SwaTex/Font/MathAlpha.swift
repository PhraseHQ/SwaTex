// Mathematical Alphanumeric Symbols (U+1D400–U+1D7FF) — KaTeX `symbols.ts` wide tables.

extension FontId {
    /// Letter ranges of the math alphanumeric block, hoisted so the per-glyph
    /// hot path (every non-ASCII scalar goes through `mathAlphanumeric`)
    /// doesn't rebuild the tables on each call.
    private static let letterBases: [(base: UInt32, font: FontId)] = [
        (0x1D400, .mainBold),  // bold
        (0x1D434, .mathItalic),  // italic
        (0x1D468, .mathBoldItalic),  // bold italic
        (0x1D504, .frakturRegular),  // Fraktur
        (0x1D56C, .frakturBold),  // bold Fraktur
        (0x1D5A0, .sansSerifRegular),
        (0x1D5D4, .sansSerifBold),
        (0x1D608, .sansSerifItalic),
        (0x1D670, .typewriterRegular),
    ]

    private static let digitBases: [(base: UInt32, font: FontId)] = [
        (0x1D7CE, .mainBold),
        (0x1D7E2, .sansSerifRegular),
        (0x1D7EC, .sansSerifBold),
        (0x1D7F6, .typewriterRegular),
    ]

    /// Maps a Unicode mathematical alphanumeric codepoint to the ``FontId`` and ASCII
    /// metric codepoint used by bundled KaTeX font metrics (`fontMetricsData`) and
    /// **`.ttf` cmaps** (glyphs live at ASCII letter/digit slots, not at the Unicode scalar).
    static func mathAlphanumeric(_ cp: UInt32) -> (font: FontId, metric: UInt32)? {
        // All math alphanumeric symbols are U+1D400–U+1D7FF (way above ASCII).
        // Early exit for ASCII saves 9+ range checks per glyph in the hot path.
        if cp <= 0x7F {
            return nil
        }
        for (base, fid) in letterBases where cp >= base && cp < base + 52 {
            let i = cp - base
            let metric = i < 26 ? 0x41 + i : 0x61 + (i - 26)
            return (fid, metric)
        }
        if (0x1D538..<0x1D538 + 26).contains(cp) {
            return (.amsRegular, 0x41 + (cp - 0x1D538))
        }
        if (0x1D49C..<0x1D49C + 26).contains(cp) {
            return (.scriptRegular, 0x41 + (cp - 0x1D49C))
        }
        if cp == 0x1D55C {
            return (.amsRegular, UInt32(UInt8(ascii: "k")))
        }
        for (base, fid) in digitBases where cp >= base && cp < base + 10 {
            return (fid, 0x30 + (cp - base))
        }
        return nil
    }

    /// Character for glyph cmap lookup in KaTeX `.ttf` files.
    ///
    /// The display list keeps the real Unicode scalar in `charCode` (for web canvas /
    /// SVG `<text>`). Outlines in shipped KaTeX fonts are keyed by ASCII letters and
    /// digits for these ranges.
    public func ttfGlyphScalar(forDisplayCharCode cp: UInt32) -> Unicode.Scalar {
        if let (mappedFont, metric) = FontId.mathAlphanumeric(cp), mappedFont == self {
            return Unicode.Scalar(metric) ?? "\u{fffd}"
        }
        return Unicode.Scalar(cp) ?? "\u{fffd}"
    }
}
