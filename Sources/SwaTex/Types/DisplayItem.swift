/// The final output of the layout engine: a flat list of drawing commands
/// with absolute coordinates, ready for platform renderers.
public struct DisplayList: Sendable, Codable {
    public var items: [DisplayItem]
    public var width: Double
    public var height: Double
    public var depth: Double

    public init(items: [DisplayItem] = [], width: Double = 0, height: Double = 0, depth: Double = 0) {
        self.items = items
        self.width = width
        self.height = height
        self.depth = depth
    }

    public var totalHeight: Double {
        height + depth
    }
}

/// A single drawing instruction with absolute position.
public enum DisplayItem: Hashable, Sendable {
    /// Draw a glyph outline at the given position.
    case glyphPath(x: Double, y: Double, scale: Double, font: String, charCode: UInt32, color: Color)
    /// Draw a horizontal line (fraction bars, overlines, etc.).
    /// `dashed` renders a dashed line (for `\hdashline`).
    case line(x: Double, y: Double, width: Double, thickness: Double, color: Color, dashed: Bool)
    /// Draw a filled rectangle (`\colorbox` backgrounds).
    case rect(x: Double, y: Double, width: Double, height: Double, color: Color)
    /// Draw an arbitrary SVG-style path (radical signs, large delimiters).
    case path(x: Double, y: Double, commands: [PathCommand], fill: Bool, color: Color)
}

extension DisplayItem: Codable {
    // Wire format matches RaTeX's serde `#[serde(tag = "type")]` encoding, so
    // display lists serialize identically across the Rust and Swift engines.
    private enum CodingKeys: String, CodingKey {
        case type, x, y, scale, font, charCode = "char_code", color
        case width, thickness, dashed, height, commands, fill
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let x = try c.decode(Double.self, forKey: .x)
        let y = try c.decode(Double.self, forKey: .y)
        let color = try c.decode(Color.self, forKey: .color)
        switch try c.decode(String.self, forKey: .type) {
        case "GlyphPath":
            self = try .glyphPath(
                x: x, y: y,
                scale: c.decode(Double.self, forKey: .scale),
                font: c.decode(String.self, forKey: .font),
                charCode: c.decode(UInt32.self, forKey: .charCode),
                color: color)
        case "Line":
            self = try .line(
                x: x, y: y,
                width: c.decode(Double.self, forKey: .width),
                thickness: c.decode(Double.self, forKey: .thickness),
                color: color,
                dashed: c.decodeIfPresent(Bool.self, forKey: .dashed) ?? false)
        case "Rect":
            self = try .rect(
                x: x, y: y,
                width: c.decode(Double.self, forKey: .width),
                height: c.decode(Double.self, forKey: .height),
                color: color)
        case "Path":
            self = try .path(
                x: x, y: y,
                commands: c.decode([PathCommand].self, forKey: .commands),
                fill: c.decode(Bool.self, forKey: .fill),
                color: color)
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "unknown display item \(other)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .glyphPath(x, y, scale, font, charCode, color):
            try c.encode("GlyphPath", forKey: .type)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
            try c.encode(scale, forKey: .scale)
            try c.encode(font, forKey: .font)
            try c.encode(charCode, forKey: .charCode)
            try c.encode(color, forKey: .color)
        case let .line(x, y, width, thickness, color, dashed):
            try c.encode("Line", forKey: .type)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
            try c.encode(width, forKey: .width)
            try c.encode(thickness, forKey: .thickness)
            try c.encode(color, forKey: .color)
            try c.encode(dashed, forKey: .dashed)
        case let .rect(x, y, width, height, color):
            try c.encode("Rect", forKey: .type)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
            try c.encode(width, forKey: .width)
            try c.encode(height, forKey: .height)
            try c.encode(color, forKey: .color)
        case let .path(x, y, commands, fill, color):
            try c.encode("Path", forKey: .type)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
            try c.encode(commands, forKey: .commands)
            try c.encode(fill, forKey: .fill)
            try c.encode(color, forKey: .color)
        }
    }
}
