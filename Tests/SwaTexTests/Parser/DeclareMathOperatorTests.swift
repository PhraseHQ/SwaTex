import Testing

@testable import SwaTex

/// `\DeclareMathOperator` (amsopn) — beyond-KaTeX addition.
@Suite("DeclareMathOperator")
struct DeclareMathOperatorTests {
    @Test func definesOperator() throws {
        let result = try parseLaTeX(#"\DeclareMathOperator{\lcm}{lcm}\lcm(a,b)"#)
        #expect(result.first?.typeName == "operatorname")
        if case let .operatorName(body, _, _, _) = result[0].kind {
            let texts = body.compactMap(\.symbolText)
            #expect(texts == ["l", "c", "m"])
        } else {
            Issue.record("expected operatorname node, got \(result.first?.typeName ?? "nil")")
        }
    }

    @Test func starredVariantTakesLimits() throws {
        // \DeclareMathOperator*{\argmin2}{argmin} → limits in display style.
        let starred = try parseLaTeX(#"\DeclareMathOperator*{\am}{am}\am_{x}"#)
        #expect(starred.count == 1)
        // The supsub base must be an operatorname with alwaysHandleSupSub.
        if case let .supSub(base, _, _) = starred[0].kind,
            case let .operatorName(_, alwaysHandleSupSub, _, _) = base?.kind
        {
            #expect(alwaysHandleSupSub)
        } else {
            Issue.record("expected supsub(operatorname) structure")
        }
    }

    @Test func operatorIsGlobal() throws {
        // amsopn semantics: definitions escape groups.
        let result = try parseLaTeX(#"{\DeclareMathOperator{\foo}{foo}}\foo"#)
        #expect(result.last?.typeName == "operatorname")
    }

    @Test func rendersLikeHandwrittenOperatorname() throws {
        let declared = try SwaTexEngine.displayList(
            for: #"\DeclareMathOperator{\lcm}{lcm}\lcm(a,b)"#)
        let manual = try SwaTexEngine.displayList(for: #"\operatorname{lcm}(a,b)"#)
        #expect(declared.width == manual.width)
        #expect(declared.items.count == manual.items.count)
    }

    @Test func nonControlSequenceNameThrows() {
        #expect(throws: ParseError.self) {
            try parseLaTeX(#"\DeclareMathOperator{x}{foo}"#)
        }
    }
}
