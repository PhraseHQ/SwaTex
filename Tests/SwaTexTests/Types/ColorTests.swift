import Foundation
import Testing

@testable import SwaTex

@Suite("Color")
struct ColorTests {
    @Test func defaultIsBlack() {
        #expect(Color.black == Color(r: 0, g: 0, b: 0, a: 1))
    }

    @Test func fromHex6() throws {
        let c = try #require(Color(hex: "#ff0000"))
        #expect(abs(c.r - 1) < 0.01)
        #expect(abs(c.g) < 0.01)
        #expect(abs(c.b) < 0.01)
        #expect(abs(c.a - 1) < 0.01)
    }

    @Test func fromHex3() throws {
        let c = try #require(Color(hex: "#f00"))
        #expect(abs(c.r - 1) < 0.01)
        #expect(abs(c.g) < 0.01)
        #expect(abs(c.b) < 0.01)
    }

    @Test func fromHex4() throws {
        let c = try #require(Color(hex: "#f008"))
        #expect(abs(c.r - 1) < 0.01)
        #expect(abs(c.g) < 0.01)
        #expect(abs(c.b) < 0.01)
        #expect(abs(c.a - 136.0 / 255.0) < 0.01)
    }

    @Test func fromHexNoHash() throws {
        let c = try #require(Color(hex: "00ff00"))
        #expect(abs(c.r) < 0.01)
        #expect(abs(c.g - 1) < 0.01)
        #expect(abs(c.b) < 0.01)
    }

    @Test func fromHex8() throws {
        let c = try #require(Color(hex: "#ff000010"))
        #expect(abs(c.r - 1) < 0.01)
        #expect(abs(c.g) < 0.01)
        #expect(abs(c.b) < 0.01)
        #expect(abs(c.a - 16.0 / 255.0) < 0.01)
    }

    @Test func parseNonASCIIColorReturnsNil() {
        #expect(Color.parse("😀") == nil)
        #expect(Color(hex: "ééé") == nil)
    }

    @Test func fromName() {
        #expect(Color(name: "red") != nil)
        #expect(Color(name: "Blue") != nil)
        #expect(Color(name: "aqua") == Color(name: "cyan"))
        #expect(Color(name: "transparent") == Color(r: 0, g: 0, b: 0, a: 0))
        #expect(Color(name: "lime") != nil)
        #expect(Color(name: "maroon") != nil)
        #expect(Color(name: "navy") != nil)
        #expect(Color(name: "olive") != nil)
        #expect(Color(name: "silver") != nil)
        #expect(Color(name: "nonexistent") == nil)
    }

    @Test func displayRGB() {
        #expect(Color(r: 1, g: 0, b: 0).description == "#ff0000")
    }

    @Test func displayRGBA() {
        #expect(Color(r: 1, g: 0, b: 0, a: 0.5).description == "rgba(255, 0, 0, 0.50)")
    }

    @Test func codableRoundtrip() throws {
        let c = Color(r: 0.5, g: 0.25, b: 0.75)
        let data = try JSONEncoder().encode(c)
        let c2 = try JSONDecoder().decode(Color.self, from: data)
        #expect(abs(c.r - c2.r) < .ulpOfOne)
        #expect(abs(c.g - c2.g) < .ulpOfOne)
        #expect(abs(c.b - c2.b) < .ulpOfOne)
    }

    @Test func parseHex() throws {
        let c = try #require(Color.parse("#0000ff"))
        #expect(abs(c.r) < 0.01)
        #expect(abs(c.g) < 0.01)
        #expect(abs(c.b - 1) < 0.01)
    }

    @Test func parseName() throws {
        let c = try #require(Color.parse("red"))
        #expect(abs(c.r - 1) < 0.01)
    }

    @Test func fromModelRGB() throws {
        let c = try #require(Color(model: "RGB", value: "178,34,34"))
        #expect(abs(c.r - 178.0 / 255.0) < 0.01)
        #expect(abs(c.g - 34.0 / 255.0) < 0.01)
        #expect(abs(c.b - 34.0 / 255.0) < 0.01)
    }

    @Test func fromModelRGBLower() throws {
        let c = try #require(Color(model: "rgb", value: "0.7,0.13,0.13"))
        #expect(abs(c.r - 0.7) < 0.01)
        #expect(abs(c.g - 0.13) < 0.01)
    }

    @Test func fromModelHTML() throws {
        let c = try #require(Color(model: "HTML", value: "B22222"))
        #expect(abs(c.r - 178.0 / 255.0) < 0.01)
    }

    @Test func fromModelGray() throws {
        let c = try #require(Color(model: "gray", value: "0.5"))
        #expect(abs(c.r - 0.5) < 0.01)
        #expect(abs(c.g - 0.5) < 0.01)
        #expect(abs(c.b - 0.5) < 0.01)
    }

    @Test func fromModelCMYK() throws {
        // cmyk 0,0.8,0.8,0 → r=1, g=0.2, b=0.2
        let c = try #require(Color(model: "cmyk", value: "0,0.8,0.8,0"))
        #expect(abs(c.r - 1) < 0.01)
        #expect(abs(c.g - 0.2) < 0.01)
        #expect(abs(c.b - 0.2) < 0.01)
    }

    @Test func parseModelEncoded() throws {
        let c = try #require(Color.parse("[RGB]178,34,34"))
        #expect(abs(c.r - 178.0 / 255.0) < 0.01)
    }
}
