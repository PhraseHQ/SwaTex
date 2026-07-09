#if canImport(AppKit) && !canImport(UIKit)
    import AppKit
    import Foundation
    import Testing

    @testable import SwaTex
    @testable import SwaTexRender

    /// Block-editor scroll simulation: many math cells configured, measured,
    /// and drawn — the workload a Notion-style editor puts on SwaTexView.
    @Suite("ScrollBench", .enabled(if: ProcessInfo.processInfo.environment["SWATEX_BENCH"] != nil))
    @MainActor
    struct ScrollStressBench {
        @Test func editorScrollSimulation() throws {
            // A document: 200 blocks cycling through 25 distinct formulas
            // (documents repeat notation constantly — the cache's case).
            let distinct = [
                #"x^2 + y^2 = z^2"#, #"\frac{a}{b}"#, #"\sqrt{2\pi}"#,
                #"\sum_{n=1}^{\infty} \frac{1}{n^2}"#, #"e^{i\pi}+1=0"#,
                #"\int_0^1 x\,dx"#, #"\alpha\beta\gamma"#, #"\vec{v}\cdot\vec{w}"#,
                #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#, #"\lim_{x\to0}\frac{\sin x}{x}"#,
                #"a_1 + a_2 + \cdots + a_n"#, #"\binom{n}{k}"#, #"\hat{H}\psi = E\psi"#,
                #"P(A \mid B)"#, #"\nabla \times \vec{F}"#, #"\mathbb{R}^n"#,
                #"\log_2 n"#, #"\theta \approx \sin\theta"#, #"f'(x) = 2x"#,
                #"\left(\frac{1}{2}\right)^n"#, #"\ce{H2O}"#, #"x \in A \cup B"#,
                #"\overline{AB}"#, #"90^\circ"#, #"\pi r^2"#,
            ]
            let blocks = (0..<200).map { distinct[$0 % distinct.count] }
            FormulaCache.shared.removeAll()

            // Views are pre-created: editors recycle cells, and NSView
            // instantiation (~60 µs) is platform cost, not SwaTex cost.
            let views = blocks.map { _ in SwaTexView(frame: .zero) }

            // Phase 1: cell configuration (set properties, query intrinsic
            // size + baseline — what an editor layout pass does), cold cache.
            var t0 = ContinuousClock.now
            for (v, latex) in zip(views, blocks) {
                v.fontSize = 18
                v.mathStyle = .text
                v.latex = latex
                _ = v.intrinsicContentSize
                _ = v.baselineFromTop
            }
            let configure = ContinuousClock.now - t0

            // Phase 2: first full draw pass (scroll through everything).
            t0 = ContinuousClock.now
            for v in views {
                v.frame = CGRect(origin: .zero, size: v.intrinsicContentSize)
                guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                v.cacheDisplay(in: v.bounds, to: rep)
            }
            let firstDraw = ContinuousClock.now - t0

            // Phase 3: cell reuse — reconfigure existing views (scroll back).
            t0 = ContinuousClock.now
            for (i, v) in views.enumerated() {
                v.latex = blocks[(i + 7) % blocks.count]
                _ = v.intrinsicContentSize
            }
            let reuse = ContinuousClock.now - t0

            print(
                "BENCH scroll200 configure=\(configure) (\(configure / 200)/cell) "
                    + "firstDraw=\(firstDraw) (\(firstDraw / 200)/cell) "
                    + "reuse=\(reuse) (\(reuse / 200)/cell)")
            // 60 fps budget = 16.6ms; an entire 200-block document must
            // configure well inside one frame.
            #expect(configure < .milliseconds(16))
            #expect(reuse < .milliseconds(8))
        }
    }
#endif
