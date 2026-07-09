/// Font families used in KaTeX math rendering.
///
/// Each case corresponds to a specific OpenType font with pre-extracted metrics.
/// The raw value is the KaTeX font name as it appears in display lists
/// (e.g. `"Main-Regular"` → `KaTeX_Main-Regular.ttf`).
public enum FontId: String, Hashable, Sendable, CaseIterable {
    case amsRegular = "AMS-Regular"
    case caligraphicRegular = "Caligraphic-Regular"
    case frakturRegular = "Fraktur-Regular"
    /// Bold Fraktur — glyphs from `KaTeX_Fraktur-Bold.ttf`; advances from bold `hmtx`.
    case frakturBold = "Fraktur-Bold"
    case mainBold = "Main-Bold"
    case mainBoldItalic = "Main-BoldItalic"
    case mainItalic = "Main-Italic"
    case mainRegular = "Main-Regular"
    case mathBoldItalic = "Math-BoldItalic"
    case mathItalic = "Math-Italic"
    case sansSerifBold = "SansSerif-Bold"
    case sansSerifItalic = "SansSerif-Italic"
    case sansSerifRegular = "SansSerif-Regular"
    case scriptRegular = "Script-Regular"
    case size1Regular = "Size1-Regular"
    case size2Regular = "Size2-Regular"
    case size3Regular = "Size3-Regular"
    case size4Regular = "Size4-Regular"
    case typewriterRegular = "Typewriter-Regular"
    case cjkRegular = "CJK-Regular"
    /// System font fallback for characters not present in the primary CJK font
    /// (e.g. emoji when the configured Unicode font is CJK-only).
    case cjkFallback = "CJK-Fallback"
    /// Color / outline emoji face (e.g. Apple Color Emoji) when `cjkFallback`
    /// still has no glyph.
    case emojiFallback = "Emoji-Fallback"
}

extension FontId: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}
