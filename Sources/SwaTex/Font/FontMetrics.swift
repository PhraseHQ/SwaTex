/// Per-character font metrics, all values in em units.
public struct CharMetrics: Hashable, Sendable {
    public var depth: Double
    public var height: Double
    public var italic: Double
    public var skew: Double
    public var width: Double

    public init(depth: Double, height: Double, italic: Double, skew: Double, width: Double) {
        self.depth = depth
        self.height = height
        self.italic = italic
        self.skew = skew
        self.width = width
    }
}

/// TeX math constants used by the layout engine, all in em units.
///
/// Values from Computer Modern / Latin Modern via KaTeX's `fontMetrics.ts`.
/// KaTeX provides three sets of values indexed by size:
///   [0] = textstyle (size >= 5, i.e. >= 9pt)
///   [1] = scriptstyle (size 3-4, i.e. 7-8pt)
///   [2] = scriptscriptstyle (size 1-2, i.e. 5-6pt)
public struct MathConstants: Sendable {
    public var slant: Double
    public var space: Double
    public var stretch: Double
    public var shrink: Double
    public var xHeight: Double
    public var quad: Double
    public var extraSpace: Double
    public var num1: Double
    public var num2: Double
    public var num3: Double
    public var denom1: Double
    public var denom2: Double
    public var sup1: Double
    public var sup2: Double
    public var sup3: Double
    public var sub1: Double
    public var sub2: Double
    public var supDrop: Double
    public var subDrop: Double
    public var delim1: Double
    public var delim2: Double
    public var axisHeight: Double
    public var defaultRuleThickness: Double
    public var bigOpSpacing1: Double
    public var bigOpSpacing2: Double
    public var bigOpSpacing3: Double
    public var bigOpSpacing4: Double
    public var bigOpSpacing5: Double
    public var sqrtRuleThickness: Double
    public var ptPerEm: Double
    public var doubleRuleSep: Double
    public var arrayRuleWidth: Double
    public var fboxsep: Double
    public var fboxrule: Double

    /// mu is 1/18 of a quad (em).
    public var cssEmPerMu: Double {
        quad / 18.0
    }
}

extension MathConstants {
    /// Get math constants for a given size index (0=text, 1=script, 2=scriptscript).
    public static func forSize(_ sizeIndex: Int) -> MathConstants {
        bySize[min(sizeIndex, 2)]
    }

    /// Three sets of TeX math constants, indexed by size (0=text, 1=script, 2=scriptscript).
    /// Exact values from KaTeX's `fontMetrics.ts` sigmasAndXis table.
    public static let bySize: [MathConstants] = [
        // [0] textstyle (size index >= 5, >= 9pt) — from cmsy10
        MathConstants(
            slant: 0.250, space: 0.0, stretch: 0.0, shrink: 0.0,
            xHeight: 0.431, quad: 1.0, extraSpace: 0.0,
            num1: 0.677, num2: 0.394, num3: 0.444,
            denom1: 0.686, denom2: 0.345,
            sup1: 0.413, sup2: 0.363, sup3: 0.289,
            sub1: 0.150, sub2: 0.247,
            supDrop: 0.386, subDrop: 0.050,
            delim1: 2.390, delim2: 1.010,
            axisHeight: 0.250, defaultRuleThickness: 0.04,
            bigOpSpacing1: 0.111, bigOpSpacing2: 0.166, bigOpSpacing3: 0.2,
            bigOpSpacing4: 0.6, bigOpSpacing5: 0.1,
            sqrtRuleThickness: 0.04, ptPerEm: 10.0, doubleRuleSep: 0.2,
            arrayRuleWidth: 0.04, fboxsep: 0.3, fboxrule: 0.04),
        // [1] scriptstyle (size index 3-4, 7-8pt) — from cmsy7
        MathConstants(
            slant: 0.250, space: 0.0, stretch: 0.0, shrink: 0.0,
            xHeight: 0.431, quad: 1.171, extraSpace: 0.0,
            num1: 0.732, num2: 0.384, num3: 0.471,
            denom1: 0.752, denom2: 0.344,
            sup1: 0.503, sup2: 0.431, sup3: 0.286,
            sub1: 0.143, sub2: 0.286,
            supDrop: 0.353, subDrop: 0.071,
            delim1: 1.700, delim2: 1.157,
            axisHeight: 0.250, defaultRuleThickness: 0.049,
            bigOpSpacing1: 0.111, bigOpSpacing2: 0.166, bigOpSpacing3: 0.2,
            bigOpSpacing4: 0.611, bigOpSpacing5: 0.143,
            sqrtRuleThickness: 0.04, ptPerEm: 10.0, doubleRuleSep: 0.2,
            arrayRuleWidth: 0.04, fboxsep: 0.3, fboxrule: 0.04),
        // [2] scriptscriptstyle (size index 1-2, 5-6pt) — from cmsy5
        MathConstants(
            slant: 0.250, space: 0.0, stretch: 0.0, shrink: 0.0,
            xHeight: 0.431, quad: 1.472, extraSpace: 0.0,
            num1: 0.925, num2: 0.387, num3: 0.504,
            denom1: 1.025, denom2: 0.532,
            sup1: 0.504, sup2: 0.404, sup3: 0.294,
            sub1: 0.200, sub2: 0.400,
            supDrop: 0.494, subDrop: 0.100,
            delim1: 1.980, delim2: 1.420,
            axisHeight: 0.250, defaultRuleThickness: 0.049,
            bigOpSpacing1: 0.111, bigOpSpacing2: 0.166, bigOpSpacing3: 0.2,
            bigOpSpacing4: 0.611, bigOpSpacing5: 0.143,
            sqrtRuleThickness: 0.04, ptPerEm: 10.0, doubleRuleSep: 0.2,
            arrayRuleWidth: 0.04, fboxsep: 0.3, fboxrule: 0.04),
    ]
}

extension FontId {
    fileprivate var metricsTable: [MetricsEntry] {
        switch self {
        case .amsRegular: MetricsData.amsRegular
        case .caligraphicRegular: MetricsData.caligraphicRegular
        case .frakturRegular: MetricsData.frakturRegular
        case .frakturBold: MetricsData.frakturBold
        case .mainBold: MetricsData.mainBold
        case .mainBoldItalic: MetricsData.mainBoldItalic
        case .mainItalic: MetricsData.mainItalic
        case .mainRegular: MetricsData.mainRegular
        case .mathBoldItalic: MetricsData.mathBoldItalic
        case .mathItalic: MetricsData.mathItalic
        case .sansSerifBold: MetricsData.sansSerifBold
        case .sansSerifItalic: MetricsData.sansSerifItalic
        case .sansSerifRegular: MetricsData.sansSerifRegular
        case .scriptRegular: MetricsData.scriptRegular
        case .size1Regular: MetricsData.size1Regular
        case .size2Regular: MetricsData.size2Regular
        case .size3Regular: MetricsData.size3Regular
        case .size4Regular: MetricsData.size4Regular
        case .typewriterRegular: MetricsData.typewriterRegular
        case .cjkRegular, .cjkFallback, .emojiFallback: []
        }
    }

    /// Look up character metrics for a character code in this font.
    ///
    /// Single flat-dictionary probe on a 64-bit key — no string hashing, no
    /// per-call array retain, no binary-search bounds checks. Glyph metrics
    /// are the layout engine's hottest lookup (P-010 in the performance log).
    public func metrics(forChar charCode: UInt32) -> CharMetrics? {
        FontId.metricsByFontChar[metricsKey(charCode)]
    }

    @inline(__always)
    fileprivate func metricsKey(_ charCode: UInt32) -> UInt64 {
        UInt64(ordinal) << 32 | UInt64(charCode)
    }

    /// Stable numeric index for the metrics key (independent of allCases order).
    fileprivate var ordinal: UInt64 {
        switch self {
        case .amsRegular: 0
        case .caligraphicRegular: 1
        case .frakturRegular: 2
        case .frakturBold: 3
        case .mainBold: 4
        case .mainBoldItalic: 5
        case .mainItalic: 6
        case .mainRegular: 7
        case .mathBoldItalic: 8
        case .mathItalic: 9
        case .sansSerifBold: 10
        case .sansSerifItalic: 11
        case .sansSerifRegular: 12
        case .scriptRegular: 13
        case .size1Regular: 14
        case .size2Regular: 15
        case .size3Regular: 16
        case .size4Regular: 17
        case .typewriterRegular: 18
        case .cjkRegular: 19
        case .cjkFallback: 20
        case .emojiFallback: 21
        }
    }

    /// All font metric tables flattened into one dictionary keyed by
    /// `(font ordinal << 32) | charCode`. ~2100 entries, built once.
    fileprivate static let metricsByFontChar: [UInt64: CharMetrics] = {
        var map = [UInt64: CharMetrics](minimumCapacity: 4096)
        for font in FontId.allCases {
            for entry in font.metricsTable {
                map[font.metricsKey(entry.code)] = CharMetrics(
                    depth: entry.depth, height: entry.height, italic: entry.italic,
                    skew: entry.skew, width: entry.width)
            }
        }
        return map
    }()
}

/// Map characters without direct metrics to similar Latin characters.
/// Covers Latin-1 extended and Cyrillic, matching KaTeX's `extraCharacterMap`.
private func extraCharacterFallback(_ ch: UInt32) -> UInt32? {
    guard let scalar = Unicode.Scalar(ch) else { return nil }
    let mapped: Unicode.Scalar
    switch scalar {
    case "Å": mapped = "A"
    case "Ð": mapped = "D"
    case "Þ": mapped = "o"
    case "å": mapped = "a"
    case "ð": mapped = "d"
    case "þ": mapped = "o"
    case "А": mapped = "A"
    case "Б": mapped = "B"
    case "В": mapped = "B"
    case "Г": mapped = "F"
    case "Д": mapped = "A"
    case "Е": mapped = "E"
    case "Ж": mapped = "K"
    case "З": mapped = "3"
    case "И": mapped = "N"
    case "Й": mapped = "N"
    case "К": mapped = "K"
    case "Л": mapped = "N"
    case "М": mapped = "M"
    case "Н": mapped = "H"
    case "О": mapped = "O"
    case "П": mapped = "N"
    case "Р": mapped = "P"
    case "С": mapped = "C"
    case "Т": mapped = "T"
    case "У": mapped = "y"
    case "Ф": mapped = "O"
    case "Х": mapped = "X"
    case "Ц": mapped = "U"
    case "Ч": mapped = "h"
    case "Ш": mapped = "W"
    case "Щ": mapped = "W"
    case "Ъ": mapped = "B"
    case "Ы": mapped = "X"
    case "Ь": mapped = "B"
    case "Э": mapped = "3"
    case "Ю": mapped = "X"
    case "Я": mapped = "R"
    case "а": mapped = "a"
    case "б": mapped = "b"
    case "в": mapped = "a"
    case "г": mapped = "r"
    case "д": mapped = "y"
    case "е": mapped = "e"
    case "ж": mapped = "m"
    case "з": mapped = "e"
    case "и": mapped = "n"
    case "й": mapped = "n"
    case "к": mapped = "n"
    case "л": mapped = "n"
    case "м": mapped = "m"
    case "н": mapped = "n"
    case "о": mapped = "o"
    case "п": mapped = "n"
    case "р": mapped = "p"
    case "с": mapped = "c"
    case "т": mapped = "o"
    case "у": mapped = "y"
    case "ф": mapped = "b"
    case "х": mapped = "x"
    case "ц": mapped = "n"
    case "ч": mapped = "n"
    case "ш": mapped = "w"
    case "щ": mapped = "w"
    case "ъ": mapped = "a"
    case "ы": mapped = "m"
    case "ь": mapped = "a"
    case "э": mapped = "e"
    case "ю": mapped = "m"
    case "я": mapped = "r"
    default: return nil
    }
    return mapped.value
}

extension FontId {
    /// Look up character metrics with fallback for Latin-1/Cyrillic characters.
    ///
    /// First tries direct lookup, then falls back to `extraCharacterMap` approximation.
    public func metricsWithFallback(forChar charCode: UInt32) -> CharMetrics? {
        metrics(forChar: charCode)
            ?? extraCharacterFallback(charCode).flatMap { metrics(forChar: $0) }
    }

    /// Look up character metrics with full KaTeX-compatible fallback chain.
    ///
    /// 1. Direct metric lookup
    /// 2. `extraCharacterMap` approximation (Latin-1 / Cyrillic)
    /// 3. In text mode only: if the codepoint belongs to a supported Unicode script
    ///    (CJK, Brahmic, etc.), fall back to the metrics of Latin capital 'M'.
    ///    This matches KaTeX's behavior for Asian/complex scripts in `\text{}`.
    public func metrics(forChar charCode: UInt32, isTextMode: Bool) -> CharMetrics? {
        metricsWithFallback(forChar: charCode)
            ?? (isTextMode && UnicodeScript.supports(codepoint: charCode)
                ? metrics(forChar: 77)  // 'M'
                : nil)
    }
}
