import Foundation
import Testing

@testable import SwaTex

@Suite("DisplayList")
struct DisplayListTests {
    @Test func emptyList() {
        let dl = DisplayList()
        #expect(dl.items.isEmpty)
        #expect(abs(dl.width) < .ulpOfOne)
        #expect(abs(dl.totalHeight) < .ulpOfOne)
    }

    @Test func codableRoundtrip() throws {
        let dl = DisplayList(
            items: [
                .line(x: 0, y: 5, width: 10, thickness: 0.04, color: .black, dashed: false),
                .rect(x: 0, y: 0, width: 10, height: 10, color: Color(r: 1, g: 0, b: 0)),
                .path(
                    x: 0, y: 0,
                    commands: [.moveTo(x: 0, y: 0), .lineTo(x: 5, y: 5), .close],
                    fill: false, color: .black),
                .glyphPath(
                    x: 1, y: 2, scale: 1, font: "Main-Regular", charCode: 0x78, color: .black),
            ],
            width: 10, height: 5, depth: 5)

        let data = try JSONEncoder().encode(dl)
        let dl2 = try JSONDecoder().decode(DisplayList.self, from: data)

        #expect(dl.items == dl2.items)
        #expect(abs(dl.width - dl2.width) < .ulpOfOne)
        #expect(abs(dl.height - dl2.height) < .ulpOfOne)
        #expect(abs(dl.depth - dl2.depth) < .ulpOfOne)
    }

    @Test func totalHeight() {
        let dl = DisplayList(items: [], width: 10, height: 3, depth: 2)
        #expect(abs(dl.totalHeight - 5) < .ulpOfOne)
    }

    /// The JSON wire format must stay byte-compatible with RaTeX's serde
    /// encoding (`#[serde(tag = "type")]`, snake_case field names).
    @Test func wireFormatMatchesRaTeX() throws {
        let json = """
            {"items":[
                {"type":"GlyphPath","x":1.0,"y":2.0,"scale":1.0,"font":"Main-Regular","char_code":120,
                 "color":{"r":0.0,"g":0.0,"b":0.0,"a":1.0}},
                {"type":"Line","x":0.0,"y":5.0,"width":10.0,"thickness":0.04,
                 "color":{"r":0.0,"g":0.0,"b":0.0,"a":1.0}},
                {"type":"Rect","x":0.0,"y":0.0,"width":10.0,"height":10.0,
                 "color":{"r":1.0,"g":0.0,"b":0.0,"a":1.0}},
                {"type":"Path","x":0.0,"y":0.0,
                 "commands":[{"type":"MoveTo","x":0.0,"y":0.0},{"type":"Close"}],
                 "fill":true,"color":{"r":0.0,"g":0.0,"b":0.0,"a":1.0}}
            ],"width":10.0,"height":5.0,"depth":5.0}
            """
        let dl = try JSONDecoder().decode(DisplayList.self, from: Data(json.utf8))
        #expect(dl.items.count == 4)
        #expect(
            dl.items[0]
                == .glyphPath(
                    x: 1, y: 2, scale: 1, font: "Main-Regular", charCode: 120, color: .black))
        // `dashed` is optional in the wire format (serde default), decoding as false.
        #expect(
            dl.items[1]
                == .line(x: 0, y: 5, width: 10, thickness: 0.04, color: .black, dashed: false))
    }
}

@Suite("PathCommand")
struct PathCommandTests {
    @Test func codableRoundtrip() throws {
        let cmds: [PathCommand] = [
            .moveTo(x: 0, y: 0),
            .lineTo(x: 10, y: 0),
            .cubicTo(x1: 10, y1: 5, x2: 5, y2: 10, x: 0, y: 10),
            .quadTo(x1: 5, y1: 5, x: 0, y: 0),
            .close,
        ]
        let data = try JSONEncoder().encode(cmds)
        let cmds2 = try JSONDecoder().decode([PathCommand].self, from: data)
        #expect(cmds == cmds2)
    }
}
