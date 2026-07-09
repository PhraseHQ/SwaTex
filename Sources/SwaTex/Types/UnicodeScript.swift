/// Unicode script detection for characters supported in `\text{}` blocks.
///
/// Port of KaTeX's `unicodeScripts.ts`. Characters from these scripts can
/// appear inside `\text{}` even when no font metrics exist for them.
enum UnicodeScript: String, Hashable, Sendable, CaseIterable {
    case latin
    case cyrillic
    case armenian
    case brahmic
    case georgian
    case cjk
    case hangul

    /// Each script has one or more [start, end] (inclusive) codepoint blocks.
    private static let scriptData: [(script: UnicodeScript, blocks: [ClosedRange<UInt32>])] = [
        (.latin, [
            0x0100...0x024F,  // Latin Extended-A and Latin Extended-B
            0x0300...0x036F,  // Combining Diacritical Marks
        ]),
        (.cyrillic, [0x0400...0x04FF]),
        (.armenian, [0x0530...0x058F]),
        (.brahmic, [0x0900...0x109F]),
        (.georgian, [0x10A0...0x10FF]),
        (.cjk, [
            0x3000...0x30FF,  // CJK symbols, Hiragana, Katakana
            0x4E00...0x9FAF,  // CJK Unified Ideographs
            0xFF00...0xFF60,  // Fullwidth forms
        ]),
        (.hangul, [0xAC00...0xD7AF]),
    ]

    /// Identify the script/script family of a Unicode codepoint, if known.
    init?(codepoint: UInt32) {
        for (script, blocks) in Self.scriptData where blocks.contains(where: { $0.contains(codepoint) }) {
            self = script
            return
        }
        return nil
    }

    /// Return `true` if the codepoint falls within one of the supported scripts.
    ///
    /// Used in text mode to decide whether a character without font metrics
    /// should be rendered with fallback metrics (Latin capital M).
    static func supports(codepoint: UInt32) -> Bool {
        UnicodeScript(codepoint: codepoint) != nil
    }
}
