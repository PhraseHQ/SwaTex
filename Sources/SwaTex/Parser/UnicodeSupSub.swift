/// Unicode superscript/subscript character mappings.
/// Mirrors KaTeX's unicodeSupOrSub module.
/// Returns `(mappedText, isSubscript)` if the character is a Unicode
/// superscript or subscript; `nil` otherwise.
func unicodeSubSup(_ c: Unicode.Scalar) -> (mapped: String, isSub: Bool)? {
    let isSub =
        (0x2080...0x209C).contains(c.value)
        || (0x1D62...0x1D6A).contains(c.value)
        || c.value == 0x2C7C
    let mapped: String
    switch c {
    // ── Subscript digits ──
    case "\u{2080}": mapped = "0"
    case "\u{2081}": mapped = "1"
    case "\u{2082}": mapped = "2"
    case "\u{2083}": mapped = "3"
    case "\u{2084}": mapped = "4"
    case "\u{2085}": mapped = "5"
    case "\u{2086}": mapped = "6"
    case "\u{2087}": mapped = "7"
    case "\u{2088}": mapped = "8"
    case "\u{2089}": mapped = "9"
    // ── Subscript operators ──
    case "\u{208A}": mapped = "+"
    case "\u{208B}": mapped = "\u{2212}"  // minus sign
    case "\u{208C}": mapped = "="
    case "\u{208D}": mapped = "("
    case "\u{208E}": mapped = ")"
    // ── Subscript letters ──
    case "\u{2090}": mapped = "a"
    case "\u{2091}": mapped = "e"
    case "\u{2092}": mapped = "o"
    case "\u{2093}": mapped = "x"
    case "\u{2095}": mapped = "h"
    case "\u{2096}": mapped = "k"
    case "\u{2097}": mapped = "l"
    case "\u{2098}": mapped = "m"
    case "\u{2099}": mapped = "n"
    case "\u{209A}": mapped = "p"
    case "\u{209B}": mapped = "s"
    case "\u{209C}": mapped = "t"
    case "\u{1D62}": mapped = "i"
    case "\u{1D63}": mapped = "r"
    case "\u{1D64}": mapped = "u"
    case "\u{1D65}": mapped = "v"
    case "\u{2C7C}": mapped = "j"
    // ── Subscript Greek ──
    case "\u{1D66}": mapped = "\u{03B2}"  // β
    case "\u{1D67}": mapped = "\u{03B3}"  // γ
    case "\u{1D68}": mapped = "\u{03C1}"  // ρ
    case "\u{1D69}": mapped = "\u{03C6}"  // φ
    case "\u{1D6A}": mapped = "\u{03C7}"  // χ

    // ── Superscript digits ──
    case "\u{2070}": mapped = "0"
    case "\u{00B9}": mapped = "1"
    case "\u{00B2}": mapped = "2"
    case "\u{00B3}": mapped = "3"
    case "\u{2074}": mapped = "4"
    case "\u{2075}": mapped = "5"
    case "\u{2076}": mapped = "6"
    case "\u{2077}": mapped = "7"
    case "\u{2078}": mapped = "8"
    case "\u{2079}": mapped = "9"
    // ── Superscript operators ──
    case "\u{207A}": mapped = "+"
    case "\u{207B}": mapped = "\u{2212}"  // minus sign
    case "\u{207C}": mapped = "="
    case "\u{207D}": mapped = "("
    case "\u{207E}": mapped = ")"
    // ── Superscript letters (lowercase) ──
    case "\u{2071}": mapped = "i"
    case "\u{207F}": mapped = "n"
    case "\u{1D43}": mapped = "a"
    case "\u{1D47}": mapped = "b"
    case "\u{1D48}": mapped = "d"
    case "\u{1D49}": mapped = "e"
    case "\u{1D4D}": mapped = "g"
    case "\u{02B0}": mapped = "h"
    case "\u{02B2}": mapped = "j"
    case "\u{1D4F}": mapped = "k"
    case "\u{02E1}": mapped = "l"
    case "\u{1D50}": mapped = "m"
    case "\u{1D52}": mapped = "o"
    case "\u{1D56}": mapped = "p"
    case "\u{02B3}": mapped = "r"
    case "\u{02E2}": mapped = "s"
    case "\u{1D57}": mapped = "t"
    case "\u{1D58}": mapped = "u"
    case "\u{1D5B}": mapped = "v"
    case "\u{02B7}": mapped = "w"
    case "\u{02E3}": mapped = "x"
    case "\u{02B8}": mapped = "y"
    // ── Superscript letters (uppercase) ──
    case "\u{1D2C}": mapped = "A"
    case "\u{1D2E}": mapped = "B"
    case "\u{1D30}": mapped = "D"
    case "\u{1D31}": mapped = "E"
    case "\u{1D33}": mapped = "G"
    case "\u{1D34}": mapped = "H"
    case "\u{1D35}": mapped = "I"
    case "\u{1D36}": mapped = "J"
    case "\u{1D37}": mapped = "K"
    case "\u{1D38}": mapped = "L"
    case "\u{1D39}": mapped = "M"
    case "\u{1D3A}": mapped = "N"
    case "\u{1D3C}": mapped = "O"
    case "\u{1D3E}": mapped = "P"
    case "\u{1D3F}": mapped = "R"
    case "\u{1D40}": mapped = "T"
    case "\u{1D41}": mapped = "U"
    case "\u{1D42}": mapped = "W"
    // ── Superscript Greek ──
    case "\u{1D5D}": mapped = "\u{03B2}"  // β
    case "\u{1D5E}": mapped = "\u{03B3}"  // γ
    case "\u{1D5F}": mapped = "\u{03B4}"  // δ
    case "\u{1D60}": mapped = "\u{03C6}"  // φ
    case "\u{1D61}": mapped = "\u{03C7}"  // χ
    case "\u{1DBF}": mapped = "\u{03B8}"  // θ
    default: return nil
    }
    return (mapped, isSub)
}
