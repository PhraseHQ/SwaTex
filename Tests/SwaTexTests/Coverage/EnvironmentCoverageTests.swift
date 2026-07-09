import Testing

@testable import SwaTex

/// Environment error-path coverage (array/align/alignat/CD/subarray/prooftree).
/// Every message was cross-checked against the Rust reference engine
/// (`ratex-layout` emits the identical `ParseError` for the same input).
@Suite("EnvironmentCoverage")
struct EnvironmentCoverageTests {
    private func parseError(_ input: String) -> ParseError? {
        do {
            _ = try parseLaTeX(input)
            return nil
        } catch {
            return error
        }
    }

    static let errorCases: [(input: String, message: String)] = [
        (
            #"\begin{align} a \tag{x} \nonumber \end{align}"#,
            #"Cannot use both \tag and \nonumber in the same row"#
        ),
        (#"\begin{align} a \tag{x} \tag{y} \end{align}"#, #"Multiple \tag in a row"#),
        (
            #"\begin{align} a \tag{x} b \end{align}"#,
            #"\tag must appear at the end of the row after the equation body"#
        ),
        (#"\begin{align} a \nonumber \nonumber \end{align}"#, #"Multiple \nonumber in a row"#),
        (
            #"\begin{align} a \nonumber b \end{align}"#,
            #"\nonumber must appear at the end of the row"#
        ),
        (#"\begin{array}{q} a \end{array}"#, "Unknown column alignment: q"),
        (#"\begin{array}\alpha a \end{array}"#, #"Unknown column alignment: \alpha"#),
        (#"\begin{matrix*}[x] a \end{matrix*}"#, "Expected l or c or r"),
        (#"\begin{matrix*}[l a \end{matrix*}"#, "Expected ]"),
        (
            #"\begin{alignat}{1} a & b & c & d \end{alignat}"#,
            "Too many math in a row: expected 1, but got 2"
        ),
        (#"\begin{CD} A @x B \end{CD}"#, "Unknown CD directive: @x"),
        (#"\begin{CD} A @\end{CD}"#, "Unexpected end of CD row after @"),
        (#"\begin{subarray}{cc} a \end{subarray}"#, "{subarray} can contain only one column"),
        (#"\begin{subarray}{c} a & b \end{subarray}"#, "{subarray} can contain only one column"),
        (#"\begin{subarray}x a \end{subarray}"#, "Unknown column alignment: x"),
        (
            #"\begin{prooftree} \AxiomC{A} \AxiomC{B} \end{prooftree}"#,
            "prooftree ended with 2 proof stack item(s), expected 1"
        ),
        (
            #"\begin{prooftree} \AxiomC{A} \QuaternaryInfC{B} \end{prooftree}"#,
            #"\QuaternaryInfC needs 4 premise(s), but only 1 available"#
        ),
        (
            #"\begin{prooftree} x \end{prooftree}"#,
            "x valid only as a supported bussproofs command within prooftree"
        ),
        (#"\begin{array}{c} a & b \end{array}"#, "Too many tab characters: &"),
        (#"\begin{matrix} a \end{pmatrix}"#, #"Mismatch: \begin{matrix} matched by \end{pmatrix}"#),
        (#"\begin{noSuchEnv} x \end{noSuchEnv}"#, "No such environment: noSuchEnv"),
    ]

    @Test(arguments: 0..<errorCases.count)
    func environmentErrors(_ i: Int) {
        let (input, message) = Self.errorCases[i]
        let e = parseError(input)
        #expect(e?.message == message, Comment(rawValue: "input: \(input)"))
    }

    @Test func gatherAllowsSecondColumnTab() throws {
        // KaTeX-compat: gather tolerates & (parses as extra column)
        let nodes = try parseLaTeX(#"\begin{gather} a & b \end{gather}"#)
        #expect(nodes.count == 1)
        #expect(nodes[0].typeName == "array")
    }

    @Test func crWithStarAndSizeInMatrix() throws {
        let nodes = try parseLaTeX(#"\begin{matrix} a \\* b \\[2em] c \end{matrix}"#)
        #expect(nodes.count == 1)
        guard case let .array(info) = nodes[0].kind else {
            Issue.record("expected array")
            return
        }
        #expect(info.body.count == 3)
        // The \\[2em] row gap is recorded on the second row
        #expect(info.rowGaps.count >= 2)
        #expect(info.rowGaps[1] != nil)
    }

    @Test func emptyTagStaysExplicit() throws {
        // \tag{} keeps an explicit (empty-bodied) tag: it renders bare
        // parentheses, narrower than \tag{7} (matches the Rust engine).
        let nodes = try parseLaTeX(#"\begin{align} a &= b \tag{} \end{align}"#)
        guard case let .array(info) = nodes[0].kind else {
            Issue.record("expected array")
            return
        }
        guard case .explicit? = info.tags?.first else {
            Issue.record("expected explicit tag for \\tag{}")
            return
        }
    }

    @Test func explicitTagRecorded() throws {
        let nodes = try parseLaTeX(#"\begin{align} a &= b \tag{7} \end{align}"#)
        guard case let .array(info) = nodes[0].kind else {
            Issue.record("expected array")
            return
        }
        if case .explicit(let body)? = info.tags?.first {
            #expect(!body.isEmpty)
        } else {
            Issue.record("expected explicit tag")
        }
    }

    @Test func trailingCrDropsEmptyRow() throws {
        let nodes = try parseLaTeX(#"\begin{matrix} a \\ \end{matrix}"#)
        guard case let .array(info) = nodes[0].kind else {
            Issue.record("expected array")
            return
        }
        #expect(info.body.count == 1)
    }

    @Test func arrayWithSeparators() throws {
        let nodes = try parseLaTeX(#"\begin{array}{l|c:r} a & b & c \end{array}"#)
        guard case let .array(info) = nodes[0].kind else {
            Issue.record("expected array")
            return
        }
        let seps = info.cols?.filter { $0.alignType == .separator } ?? []
        #expect(seps.count == 2)
    }

    @Test func arrayAtExpressionsRejected() {
        // LaTeX @{...} column expressions are not supported (KaTeX-compat;
        // the Rust engine rejects them identically).
        let e = parseError(#"\begin{array}{@{}l@{\quad}r@{}} a & b \end{array}"#)
        #expect(e?.message == "Unknown column alignment: @")
    }
}
