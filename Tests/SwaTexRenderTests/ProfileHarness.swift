#if canImport(AppKit) && !canImport(UIKit)
    import AppKit
    import Foundation
    import Testing

    @testable import SwaTex
    @testable import SwaTexRender

    /// Temporary profiling harness (SWATEX_PROFILE=1): long-running loops of
    /// the two block-editor interactive paths, for `sample` attribution.
    @Suite(
        "ProfileHarness", .enabled(if: ProcessInfo.processInfo.environment["SWATEX_PROFILE"] != nil)
    )
    @MainActor
    struct ProfileHarness {
        static let formulas = [
            #"x^2 + y^2 = z^2"#, #"\frac{a}{b}"#, #"\sqrt{2\pi}"#,
            #"\sum_{n=1}^{\infty} \frac{1}{n^2}"#, #"e^{i\pi}+1=0"#,
            #"\int_0^1 x\,dx"#, #"\vec{v}\cdot\vec{w}"#,
            #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#,
            #"\lim_{x\to0}\frac{\sin x}{x}"#, #"\left(\frac{1}{2}\right)^n"#,
            #"\hat{H}\psi = E\psi"#, #"\nabla \times \vec{F}"#, #"\mathbb{R}^n"#,
        ]

        /// Live-typing path: every keystroke = new latex string (cache miss)
        /// → parse + layout + measure + draw.
        @Test func typingPath() throws {
            let view = SwaTexView(frame: .zero)
            view.fontSize = 18
            view.mathStyle = .text

            var parseLayout = Duration.zero
            var drawTime = Duration.zero
            var strokes = 0

            for _ in 0..<400 {
                for f in Self.formulas {
                    // Simulate typing: grow the formula one UTF-8 rune chunk
                    // at a time (prefixes are often invalid — that's real
                    // typing; errors must be cheap too).
                    var prefix = ""
                    for ch in f {
                        prefix.append(ch)
                        FormulaCache.shared.removeAll()
                        var t0 = ContinuousClock.now
                        view.latex = prefix
                        _ = view.intrinsicContentSize
                        parseLayout += ContinuousClock.now - t0

                        t0 = ContinuousClock.now
                        view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)
                        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                            view.cacheDisplay(in: view.bounds, to: rep)
                        }
                        drawTime += ContinuousClock.now - t0
                        strokes += 1
                    }
                }
            }
            print(
                "PROFILE typing strokes=\(strokes) parse+layout=\(parseLayout / strokes)/stroke "
                    + "draw=\(drawTime / strokes)/stroke")
        }

        /// Steady-scroll path: warm cache, reconfigure + draw only.
        @Test func scrollPath() throws {
            let views = (0..<50).map { _ in SwaTexView(frame: .zero) }
            FormulaCache.shared.removeAll()
            var configure = Duration.zero
            var drawTime = Duration.zero
            var frames = 0
            for round in 0..<3000 {
                for (i, v) in views.enumerated() {
                    let t0 = ContinuousClock.now
                    v.fontSize = 18
                    v.mathStyle = .text
                    v.latex = Self.formulas[(i + round) % Self.formulas.count]
                    _ = v.intrinsicContentSize
                    configure += ContinuousClock.now - t0
                }
                for v in views {
                    let t0 = ContinuousClock.now
                    v.frame = CGRect(origin: .zero, size: v.intrinsicContentSize)
                    if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                        v.cacheDisplay(in: v.bounds, to: rep)
                    }
                    drawTime += ContinuousClock.now - t0
                    frames += 1
                }
            }
            print(
                "PROFILE scroll cells=\(frames) configure=\(configure / frames)/cell "
                    + "draw=\(drawTime / frames)/cell")
        }
    }
#endif
