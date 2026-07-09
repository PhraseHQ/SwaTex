// Symbol layout: glyph selection, metrics fallback, font resolution.
// Port of crates/ratex-layout/src/engine.rs (lines 656–885).

/// Advance width for glyphs missing from bundled KaTeX fonts (e.g. CJK in `\text{…}`).
///
/// The placeholder width must match what system font fallback draws at ~1em: using 0.5em
/// collapses the advance and Core Text / platform rasterizers still paint a full-width
/// ideograph, so neighbors overlap and the row looks "too large" / clipped.
func missingGlyphWidthEm(_ ch: Unicode.Scalar) -> Double {
    switch ch.value {
    // Hiragana / Katakana
    case 0x3040...0x30FF, 0x31F0...0x31FF: 1.0
    // CJK Unified + extension / compatibility ideographs
    case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: 1.0
    // Hangul syllables
    case 0xAC00...0xD7AF: 1.0
    // Fullwidth ASCII, punctuation, currency
    case 0xFF01...0xFF60, 0xFFE0...0xFFEE: 1.0
    // Emoji / pictographs in supplementary planes (e.g. U+1F60A 😊) and related blocks:
    // system fallback draws ~one em, same rationale as CJK above (issue #49).
    case 0x1F000...0x1FAFF: 1.0
    // Dingbats (many BMP emoji / ornaments lack bundled TeX metrics)
    case 0x2700...0x27BF: 1.0
    // Miscellaneous Symbols (★ ☆ ☎ ☑ ☒ etc.)
    case 0x2600...0x26FF: 1.0
    // Miscellaneous Symbols and Arrows (⭐ ⬛ ⬜ etc.)
    case 0x2B00...0x2BFF: 1.0
    default: 0.5
    }
}

private func missingGlyphHeightEm(_ ch: Unicode.Scalar, _ m: MathConstants) -> Double {
    if (0x1F000...0x1FAFF).contains(ch.value) {
        // Supplementary-plane emoji: `missingGlyphWidthEm` uses ~1em width for raster
        // parity (#49), but a 0.92·quad tall box inflates `\sqrt` minDelimHeight past KaTeX's
        // threshold so we pick Size1 surd (1em advance) instead of the small surd (0.833em),
        // visibly widening the gap before the radicand (golden 0955).
        max(m.quad * 0.74, m.xHeight)
    } else {
        max(m.quad * 0.92, m.xHeight)
    }
}

private func missingGlyphMetricsFallback(
    _ ch: Unicode.Scalar, _ options: LayoutOptions
) -> (width: Double, height: Double, depth: Double) {
    let m = MathConstants.forSize(options.style.sizeIndex)
    let w = missingGlyphWidthEm(ch)
    if w >= 0.99 {
        return (w, missingGlyphHeightEm(ch, m), 0)
    }
    return (w, m.xHeight, 0)
}

/// KaTeX `SymbolNode.toNode`: math symbols use `margin-right: italic`
/// (advance = width + italic).
@inline(__always)
private func mathGlyphAdvanceEm(_ m: CharMetrics, _ mode: Mode) -> Double {
    mode == .math ? m.width + m.italic : m.width
}

func layoutSymbol(_ text: String, _ mode: Mode, _ options: LayoutOptions) -> LayoutBox {
    let ch = resolveSymbolChar(text, mode)

    if text == "\\shortmid" {
        return makeShortmidBox(options)
    }
    if text == "\\textunderscore" {
        return makeTextunderscoreBox(options)
    }

    // Synthetic symbols not present in any KaTeX font; built from SVG paths.
    switch ch.value {
    case 0x2258, 0xE258: return makeCorrespondsSymbol(options)
    case 0x225E, 0xE25E: return makeMeasuredBySymbol(options)
    case 0x22B7: return layoutImageofOrigof(imageof: true, options)  // \imageof  •—○
    case 0x22B6: return layoutImageofOrigof(imageof: false, options)  // \origof   ○—•
    default: break
    }

    let charCode = ch.value

    if let (fontId, metricCp) = FontId.mathAlphanumeric(charCode) {
        let (width, height, depth): (Double, Double, Double)
        if let m = fontId.metrics(forChar: metricCp) {
            (width, height, depth) = (mathGlyphAdvanceEm(m, mode), m.height, m.depth)
        } else {
            (width, height, depth) = missingGlyphMetricsFallback(ch, options)
        }
        return LayoutBox(
            width: width, height: height, depth: depth,
            content: .glyph(fontId: fontId, charCode: charCode),
            color: options.color)
    }

    var fontId = selectFont(text, ch, mode, options)
    var metrics = fontId.metrics(forChar: charCode)

    if metrics == nil, mode == .math, fontId != .mathItalic,
        let m = FontId.mathItalic.metrics(forChar: charCode)
    {
        fontId = .mathItalic
        metrics = m
    }

    // KaTeX `Main-Regular` has no metrics/cmap for some codepoints (e.g. U+2211) that only
    // exist in `Size1`/`Size2`. `\@char` yields `textord`, so we still rasterize via the
    // normal lookup chain (unicode fallback when Main has no glyph). Using
    // `missingGlyphMetricsFallback` (0.5em wide) then clips the real fallback outline in
    // PNG/SVG — borrow Size-font TeX metrics for the box only, without switching `fontId`.
    let (width, height, depth): (Double, Double, Double)
    if let m = metrics {
        (width, height, depth) = (mathGlyphAdvanceEm(m, mode), m.height, m.depth)
    } else if mode == .math {
        let sizeFont: FontId = options.style.isDisplay ? .size2Regular : .size1Regular
        if let m = sizeFont.metrics(forChar: charCode)
            ?? FontId.size1Regular.metrics(forChar: charCode)
        {
            (width, height, depth) = (mathGlyphAdvanceEm(m, mode), m.height, m.depth)
        } else {
            (width, height, depth) = missingGlyphMetricsFallback(ch, options)
        }
    } else {
        (width, height, depth) = missingGlyphMetricsFallback(ch, options)
    }

    // If the glyph has no KaTeX metrics and is a wide fallback character (CJK, emoji, etc.),
    // switch fontId to CjkRegular so renderers can load it from a system Unicode font.
    if metrics == nil, missingGlyphWidthEm(ch) >= 0.99 {
        fontId = .cjkRegular
    }

    return LayoutBox(
        width: width, height: height, depth: depth,
        content: .glyph(fontId: fontId, charCode: charCode),
        color: options.color)
}

/// Resolve a symbol name to its actual character.
func resolveSymbolChar(_ text: String, _ mode: Mode) -> Unicode.Scalar {
    if let raw = text.unicodeScalars.first, (0x1D400...0x1D7FF).contains(raw.value) {
        return raw
    }

    if let info = SymbolInfo(name: text, mode: mode), let cp = info.codepoint {
        return cp
    }

    return text.unicodeScalars.first ?? "?"
}

/// Select the font for a math symbol.
/// Uses the symbol table's font field for AMS symbols, and character properties
/// to choose between MathItalic (for letters and Greek) and MainRegular.
func selectFont(
    _ text: String, _ resolvedChar: Unicode.Scalar, _ mode: Mode, _ options: LayoutOptions
) -> FontId {
    if let info = SymbolInfo(name: text, mode: mode), info.font == .ams {
        return .amsRegular
    }

    switch mode {
    case .math:
        let isASCIILetter =
            (0x41...0x5A).contains(resolvedChar.value) || (0x61...0x7A).contains(resolvedChar.value)
        return isASCIILetter || isMathItalicGreek(resolvedChar) ? .mathItalic : .mainRegular
    case .text:
        return .mainRegular
    }
}

/// Lowercase Greek letters and variant forms use Math-Italic in math mode.
/// Uppercase Greek (U+0391–U+03A9) stays upright in Main-Regular per TeX convention.
func isMathItalicGreek(_ ch: Unicode.Scalar) -> Bool {
    switch ch.value {
    case 0x03B1...0x03C9, 0x03D1, 0x03D5, 0x03D6, 0x03F1, 0x03F5: true
    default: false
    }
}

func isArrowAccent(_ label: String) -> Bool {
    switch label {
    case "\\overrightarrow", "\\overleftarrow", "\\Overrightarrow",
        "\\overleftrightarrow", "\\underrightarrow", "\\underleftarrow",
        "\\underleftrightarrow", "\\overleftharpoon", "\\overrightharpoon",
        "\\overlinesegment", "\\underlinesegment":
        true
    default:
        false
    }
}
