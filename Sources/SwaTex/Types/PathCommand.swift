/// SVG-style path commands for drawing glyph outlines, radical signs,
/// large delimiters, etc.
public enum PathCommand: Hashable, Sendable {
    case moveTo(x: Double, y: Double)
    case lineTo(x: Double, y: Double)
    case cubicTo(x1: Double, y1: Double, x2: Double, y2: Double, x: Double, y: Double)
    case quadTo(x1: Double, y1: Double, x: Double, y: Double)
    case close
}

extension PathCommand: Codable {
    // Wire format matches RaTeX's serde `#[serde(tag = "type")]` encoding:
    // {"type": "MoveTo", "x": 0, "y": 0}, {"type": "Close"}, ...
    private enum CodingKeys: String, CodingKey {
        case type, x, y, x1, y1, x2, y2
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "MoveTo":
            self = try .moveTo(
                x: c.decode(Double.self, forKey: .x), y: c.decode(Double.self, forKey: .y))
        case "LineTo":
            self = try .lineTo(
                x: c.decode(Double.self, forKey: .x), y: c.decode(Double.self, forKey: .y))
        case "CubicTo":
            self = try .cubicTo(
                x1: c.decode(Double.self, forKey: .x1), y1: c.decode(Double.self, forKey: .y1),
                x2: c.decode(Double.self, forKey: .x2), y2: c.decode(Double.self, forKey: .y2),
                x: c.decode(Double.self, forKey: .x), y: c.decode(Double.self, forKey: .y))
        case "QuadTo":
            self = try .quadTo(
                x1: c.decode(Double.self, forKey: .x1), y1: c.decode(Double.self, forKey: .y1),
                x: c.decode(Double.self, forKey: .x), y: c.decode(Double.self, forKey: .y))
        case "Close":
            self = .close
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "unknown path command \(other)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .moveTo(x, y):
            try c.encode("MoveTo", forKey: .type)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
        case let .lineTo(x, y):
            try c.encode("LineTo", forKey: .type)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
        case let .cubicTo(x1, y1, x2, y2, x, y):
            try c.encode("CubicTo", forKey: .type)
            try c.encode(x1, forKey: .x1)
            try c.encode(y1, forKey: .y1)
            try c.encode(x2, forKey: .x2)
            try c.encode(y2, forKey: .y2)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
        case let .quadTo(x1, y1, x, y):
            try c.encode("QuadTo", forKey: .type)
            try c.encode(x1, forKey: .x1)
            try c.encode(y1, forKey: .y1)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
        case .close:
            try c.encode("Close", forKey: .type)
        }
    }
}

extension PathCommand {
    /// Apply the axis-aligned affine map `x′ = x·sx + dx`, `y′ = y·sy + dy`
    /// to every control point — the only transform family the layout engine
    /// needs (unit scaling, per-axis stretch, and vertical shifts).
    func mapPoints(sx: Double = 1, sy: Double = 1, dx: Double = 0, dy: Double = 0) -> PathCommand {
        switch self {
        case let .moveTo(x, y):
            .moveTo(x: x * sx + dx, y: y * sy + dy)
        case let .lineTo(x, y):
            .lineTo(x: x * sx + dx, y: y * sy + dy)
        case let .cubicTo(x1, y1, x2, y2, x, y):
            .cubicTo(
                x1: x1 * sx + dx, y1: y1 * sy + dy,
                x2: x2 * sx + dx, y2: y2 * sy + dy,
                x: x * sx + dx, y: y * sy + dy)
        case let .quadTo(x1, y1, x, y):
            .quadTo(x1: x1 * sx + dx, y1: y1 * sy + dy, x: x * sx + dx, y: y * sy + dy)
        case .close:
            .close
        }
    }
}

extension [PathCommand] {
    /// Uniform scale about the origin (e.g. ×0.001 for KaTeX's
    /// thousandths-of-an-em glyph coordinates → em units).
    func scaled(by s: Double) -> [PathCommand] {
        map { $0.mapPoints(sx: s, sy: s) }
    }

    /// Vertical translation.
    func shiftedY(_ dy: Double) -> [PathCommand] {
        map { $0.mapPoints(dy: dy) }
    }
}
