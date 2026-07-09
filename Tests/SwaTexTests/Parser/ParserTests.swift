import Testing

@testable import SwaTex

@Suite("Parser")
struct ParserTests {
    @Test func parseSingleChar() throws {
        let result = try parseLaTeX("x")
        #expect(result.count == 1)
        #expect(result[0].typeName == "mathord")
    }

    @Test func parseStripsOuterDollarInlineMath() throws {
        let inner = #"C_p[\ce{H2O(l)}] = \pu{75.3 J // mol K}"#
        let a = try parseLaTeX("$\(inner)$")
        let b = try parseLaTeX(inner)
        #expect(a.count == b.count)
        for (x, y) in zip(a, b) {
            #expect(x.typeName == y.typeName)
        }
    }

    @Test func parseAddition() throws {
        let result = try parseLaTeX("a+b")
        #expect(result.count == 3)
        #expect(result[0].typeName == "mathord")  // a
        #expect(result[1].typeName == "atom")  // +
        #expect(result[2].typeName == "mathord")  // b
    }

    @Test func parseSuperscript() throws {
        let result = try parseLaTeX("x^2")
        #expect(result.count == 1)
        #expect(result[0].typeName == "supsub")
    }

    @Test func parseSubscript() throws {
        let result = try parseLaTeX("a_i")
        #expect(result.count == 1)
        #expect(result[0].typeName == "supsub")
    }

    @Test func parseSupSub() throws {
        let result = try parseLaTeX("x^2_i")
        #expect(result.count == 1)
        #expect(result[0].typeName == "supsub")
        if case let .supSub(_, sup, sub) = result[0].kind {
            #expect(sup != nil)
            #expect(sub != nil)
        } else {
            Issue.record("Expected supSub")
        }
    }

    @Test func parseGroup() throws {
        let result = try parseLaTeX("{a+b}")
        #expect(result.count == 1)
        #expect(result[0].typeName == "ordgroup")
    }

    @Test func parseFrac() throws {
        let result = try parseLaTeX(#"\frac{a}{b}"#)
        #expect(result.count == 1)
        #expect(result[0].typeName == "genfrac")
    }

    @Test func parseSqrt() throws {
        let result = try parseLaTeX(#"\sqrt{x}"#)
        #expect(result.count == 1)
        #expect(result[0].typeName == "sqrt")
    }

    @Test func parseSqrtOptional() throws {
        let result = try parseLaTeX(#"\sqrt[3]{x}"#)
        #expect(result.count == 1)
        if case let .sqrt(_, index) = result[0].kind {
            #expect(index != nil)
        } else {
            Issue.record("Expected sqrt")
        }
    }

    @Test func parseNested() throws {
        let result = try parseLaTeX(#"\frac{\sqrt{a^2+b^2}}{c}"#)
        #expect(result.count == 1)
        #expect(result[0].typeName == "genfrac")
    }

    @Test func parseEmpty() throws {
        let result = try parseLaTeX("")
        #expect(result.isEmpty)
    }

    @Test func parseDoubleSuperscriptError() {
        #expect(throws: ParseError.self) {
            try parseLaTeX("x^2^3")
        }
    }

    @Test func parseUnclosedBraceError() {
        #expect(throws: ParseError.self) {
            try parseLaTeX("{x")
        }
    }
}
