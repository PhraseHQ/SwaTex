/// An RGBA color with components in the range 0...1.
///
/// The textual representation (``description``) matches CSS: `#rrggbb` for
/// opaque colors, `rgba(r, g, b, a)` otherwise. This is the exact format the
/// SVG backend emits, so it must stay byte-compatible with RaTeX/KaTeX output.
public struct Color: Hashable, Sendable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    public static let black = Color(r: 0, g: 0, b: 0, a: 1)
    public static let white = Color(r: 1, g: 1, b: 1, a: 1)

    public init(r: Float, g: Float, b: Float, a: Float = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Parse a hex color string like `#ff0000`, `#f00`, `#ff000080`, or `#f008`.
    public init?(hex: String) {
        let hex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let bytes = Array(hex.utf8)
        guard bytes.allSatisfy(Self.isHexDigit) else { return nil }

        func nibble(_ i: Int) -> Float {
            Float(Self.hexValue(bytes[i]) * 17) / 255
        }
        func byte(_ i: Int) -> Float {
            Float(Self.hexValue(bytes[i]) << 4 | Self.hexValue(bytes[i + 1])) / 255
        }

        switch bytes.count {
        case 3: self.init(r: nibble(0), g: nibble(1), b: nibble(2))
        case 4: self.init(r: nibble(0), g: nibble(1), b: nibble(2), a: nibble(3))
        case 6: self.init(r: byte(0), g: byte(2), b: byte(4))
        case 8: self.init(r: byte(0), g: byte(2), b: byte(4), a: byte(6))
        default: return nil
        }
    }

    /// Parse a color from a MathJax color model + value string.
    /// The model is case-sensitive per the MathJax spec:
    ///   `RGB`  → integers 0-255  e.g. "178,34,34"
    ///   `rgb`  → floats 0-1      e.g. "0.7,0.13,0.13"
    ///   `HTML` → hex RRGGBB      e.g. "B22222"
    ///   `gray` → float 0-1       e.g. "0.5"
    ///   `cmyk` → floats 0-1      e.g. "0,0.8,0.8,0"
    public init?(model: String, value: String) {
        func trimmed(_ s: Substring) -> Substring {
            var s = s
            while let f = s.first, f == " " || f == "\t" { s.removeFirst() }
            while let l = s.last, l == " " || l == "\t" { s.removeLast() }
            return s
        }
        func csv(_ expected: Int) -> [Float]? {
            let parts = value.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == expected else { return nil }
            var out: [Float] = []
            out.reserveCapacity(expected)
            for part in parts {
                guard let f = Float(trimmed(part)) else { return nil }
                out.append(f)
            }
            return out
        }

        switch model {
        case "RGB":
            guard let p = csv(3) else { return nil }
            self.init(r: p[0] / 255, g: p[1] / 255, b: p[2] / 255)
        case "rgb":
            guard let p = csv(3) else { return nil }
            self.init(r: p[0], g: p[1], b: p[2])
        case "HTML":
            self.init(hex: value)
        case "gray":
            guard let g = Float(trimmed(value[...])) else { return nil }
            self.init(r: g, g: g, b: g)
        case "cmyk":
            guard let p = csv(4) else { return nil }
            let (c, m, y, k) = (p[0], p[1], p[2], p[3])
            self.init(r: (1 - c) * (1 - k), g: (1 - m) * (1 - k), b: (1 - y) * (1 - k))
        default:
            return nil
        }
    }

    /// Parse a named CSS color (the subset used by KaTeX).
    public init?(name: String) {
        switch name.lowercased() {
        case "red": self.init(r: 1, g: 0, b: 0)
        // CSS `green` is #008000; `lime` is #00ff00 (HTML 4 / CSS1 standard colors).
        case "green": self.init(r: 0, g: 0.502, b: 0)
        case "lime": self.init(r: 0, g: 1, b: 0)
        case "blue": self.init(r: 0, g: 0, b: 1)
        case "maroon": self.init(r: 0.502, g: 0, b: 0)
        case "navy": self.init(r: 0, g: 0, b: 0.502)
        case "olive": self.init(r: 0.502, g: 0.502, b: 0)
        case "silver": self.init(r: 0.753, g: 0.753, b: 0.753)
        case "white": self = .white
        case "black": self = .black
        case "orange": self.init(r: 1, g: 0.647, b: 0)
        case "yellow": self.init(r: 1, g: 1, b: 0)
        case "purple": self.init(r: 0.502, g: 0, b: 0.502)
        // CSS: `aqua` ≡ `cyan` (#00ffff); common in `\colorbox`/xcolor examples.
        case "aqua", "cyan": self.init(r: 0, g: 1, b: 1)
        // CSS: `fuchsia` ≡ `magenta`
        case "fuchsia", "magenta": self.init(r: 1, g: 0, b: 1)
        case "gray", "grey": self.init(r: 0.502, g: 0.502, b: 0.502)
        case "brown": self.init(r: 0.647, g: 0.165, b: 0.165)
        case "pink": self.init(r: 1, g: 0.753, b: 0.796)
        case "teal": self.init(r: 0, g: 0.502, b: 0.502)
        case "transparent": self.init(r: 0, g: 0, b: 0, a: 0)
        default: return nil
        }
    }

    /// Parse any supported color string: hex, named, or `[MODEL]value`
    /// (MathJax model syntax).
    public static func parse(_ s: String) -> Color? {
        if s.hasPrefix("["), let bracketEnd = s.firstIndex(of: "]") {
            let model = String(s[s.index(after: s.startIndex)..<bracketEnd])
            let value = String(s[s.index(after: bracketEnd)...])
            return Color(model: model, value: value)
        }
        return Color(hex: s) ?? Color(name: s)
    }

    private static func isHexDigit(_ b: UInt8) -> Bool {
        (0x30...0x39).contains(b) || (0x41...0x46).contains(b) || (0x61...0x66).contains(b)
    }

    private static func hexValue(_ b: UInt8) -> Int {
        switch b {
        case 0x30...0x39: Int(b - 0x30)
        case 0x41...0x46: Int(b - 0x41 + 10)
        default: Int(b - 0x61 + 10)
        }
    }
}

extension Color: CustomStringConvertible {
    public var description: String {
        // Truncate toward zero after scaling, matching Rust's `as u8` and
        // KaTeX's own component formatting.
        func byte(_ v: Float) -> Int {
            Int(max(0, min(255, (v * 255).rounded(.towardZero))))
        }
        func hex2(_ v: Int) -> String {
            let digits = "0123456789abcdef"
            let hi = digits[digits.index(digits.startIndex, offsetBy: v >> 4)]
            let lo = digits[digits.index(digits.startIndex, offsetBy: v & 0xf)]
            return "\(hi)\(lo)"
        }
        if abs(a - 1) < Float.ulpOfOne {
            return "#\(hex2(byte(r)))\(hex2(byte(g)))\(hex2(byte(b)))"
        } else {
            // Two-decimal alpha, matching Rust's `{:.2}` formatting.
            let centi = Int((Double(a) * 100).rounded())
            let alpha = "\(centi / 100).\(centi % 100 < 10 ? "0" : "")\(centi % 100)"
            return "rgba(\(byte(r)), \(byte(g)), \(byte(b)), \(alpha))"
        }
    }
}

extension Color: Codable {
    // Plain {r, g, b, a} keys — wire-compatible with RaTeX's serde output.
}
