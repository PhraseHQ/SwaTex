#if canImport(AppKit) && !canImport(UIKit)
    import AppKit
    import SwiftUI
    import Testing

    @testable import SwaTex
    @testable import SwaTexRender

    /// RaTeX view-parity features: Auto Layout baseline anchors, dynamic
    /// (dark-mode-adaptive) colors, and the SwiftUI ascent LayoutValueKey.
    /// Tests exercise the real machinery — constraint solving, appearance
    /// switching in a window, and SwiftUI Layout hosting — not just
    /// property plumbing.
    @Suite("ViewParity", .serialized)
    @MainActor
    struct ViewParityTests {
        private func makeWindow(size: NSSize = NSSize(width: 500, height: 300)) -> NSWindow {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView!.wantsLayer = true
            return window
        }

        private func spin(_ seconds: TimeInterval = 0.05) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }

        /// Poll the run loop until `condition` holds — CI runners commit
        /// display cycles slowly, so a fixed spin flakes.
        @discardableResult
        private func waitUntil(
            timeout: TimeInterval = 5, _ condition: () -> Bool
        ) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() { return true }
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            return condition()
        }

        // MARK: Baseline anchors

        @Test func baselineOffsetsMatchMathBaseline() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"\frac{a}{b}"#  // depth below baseline, ascent above
            view.fontSize = 24

            let expected = view.baselineFromTop
            #expect(expected > 0)
            #expect(view.firstBaselineOffsetFromTop == expected)
            #expect(
                view.lastBaselineOffsetFromBottom
                    == view.intrinsicContentSize.height - expected)
        }

        @Test func baselineFallsBackForUnrenderableContent() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"\undefinedmacro"#
            // Must not trap; falls back to NSView's default behavior.
            _ = view.firstBaselineOffsetFromTop
            _ = view.lastBaselineOffsetFromBottom
        }

        /// End-to-end: AppKit's constraint solver must place a label's
        /// first baseline on the formula's math baseline.
        @Test func firstBaselineConstraintAlignsWithLabel() {
            let formula = SwaTexView(frame: .zero)
            formula.latex = #"\frac{a}{b}"#
            formula.fontSize = 24
            formula.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(labelWithString: "text")
            label.translatesAutoresizingMaskIntoConstraints = false

            let window = makeWindow()
            let host = window.contentView!
            host.addSubview(formula)
            host.addSubview(label)
            NSLayoutConstraint.activate([
                formula.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
                formula.topAnchor.constraint(equalTo: host.topAnchor, constant: 40),
                label.leadingAnchor.constraint(equalTo: formula.trailingAnchor, constant: 8),
                label.firstBaselineAnchor.constraint(equalTo: formula.firstBaselineAnchor),
            ])
            host.layoutSubtreeIfNeeded()

            let formulaBaselineY = formula.frame.minY + formula.firstBaselineOffsetFromTop
            let labelBaselineY = label.frame.minY + label.firstBaselineOffsetFromTop
            // AppKit rounds baseline offsets to device pixels during constraint
            // solving; allow one point.
            #expect(abs(formulaBaselineY - labelBaselineY) < 1.0)
            // And the formula's baseline really is its math baseline.
            #expect(formula.firstBaselineOffsetFromTop == formula.baselineFromTop)
        }

        // MARK: Dynamic color (dark mode)

        private static let adaptive = NSColor(
            name: nil,
            dynamicProvider: { appearance in
                appearance.name == .darkAqua ? .green : .red
            })

        @Test func dynamicColorResolvesPerAppearance() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"x"#
            view.color = Self.adaptive

            let window = makeWindow()
            window.appearance = NSAppearance(named: .aqua)
            window.contentView!.addSubview(view)
            _ = view.intrinsicContentSize
            #expect(view.effectiveMathColor.r > 0.9 && view.effectiveMathColor.g < 0.1)

            window.appearance = NSAppearance(named: .darkAqua)
            spin(0.2)
            _ = view.intrinsicContentSize
            #expect(
                waitUntil { view.effectiveMathColor.g > 0.9 && view.effectiveMathColor.r < 0.1 },
                "dark appearance should resolve to green")
        }

        @Test func appearanceChangeRerasterizesExactlyOnce() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"x^2"#
            view.fontSize = 18
            view.color = Self.adaptive
            view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)

            let window = makeWindow()
            window.appearance = NSAppearance(named: .aqua)
            window.contentView!.addSubview(view)
            window.orderBack(nil)
            waitUntil { view.rasterizationCount >= 1 }
            let baseline = view.rasterizationCount
            #expect(baseline == 1)

            window.appearance = NSAppearance(named: .darkAqua)
            #expect(
                waitUntil { view.rasterizationCount == baseline + 1 },
                "dark mode must re-render once")

            // Same appearance again: no color change, no re-rasterization.
            window.appearance = NSAppearance(named: .darkAqua)
            spin(0.2)
            #expect(view.rasterizationCount == baseline + 1)
            window.orderOut(nil)
        }

        @Test func staticColorIgnoresAppearanceChanges() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"x^2"#
            view.mathColor = .black  // no dynamic color set
            view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)

            let window = makeWindow()
            window.appearance = NSAppearance(named: .aqua)
            window.contentView!.addSubview(view)
            window.orderBack(nil)
            waitUntil { view.rasterizationCount >= 1 }
            let baseline = view.rasterizationCount

            window.appearance = NSAppearance(named: .darkAqua)
            spin(0.2)
            #expect(view.rasterizationCount == baseline, "static color must not re-render")
            window.orderOut(nil)
        }

        @Test func dynamicColorPrecedenceAndReset() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"x"#
            view.mathColor = SwaTex.Color(r: 0, g: 0, b: 1, a: 1)
            view.color = .red
            _ = view.intrinsicContentSize
            #expect(view.effectiveMathColor.r > 0.9, "platform color must win over mathColor")

            view.color = nil
            _ = view.intrinsicContentSize
            #expect(view.effectiveMathColor.b > 0.9, "nil platform color falls back to mathColor")
        }

        // MARK: SwiftUI ascent key

        /// A probe Layout that records each subview's ``MathViewAscentKey``.
        private struct AscentProbeLayout: Layout {
            let record: (CGFloat) -> Void

            func sizeThatFits(
                proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
            ) -> CGSize {
                for subview in subviews {
                    record(subview[MathViewAscentKey.self])
                }
                return subviews.first?.sizeThatFits(proposal) ?? .zero
            }

            func placeSubviews(
                in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                cache: inout ()
            ) {
                for subview in subviews {
                    subview.place(at: bounds.origin, proposal: proposal)
                }
            }
        }

        @MainActor
        private final class AscentBox {
            var values: [CGFloat] = []
        }

        @Test func mathViewPublishesAscentForCustomLayouts() throws {
            let box = AscentBox()
            let latex = #"\frac{a}{b}"#
            let fontSize: CGFloat = 24

            let probe = AscentProbeLayout(record: { box.values.append($0) })
            let root = probe {
                MathView(latex).font(size: fontSize)
            }
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 120)
            let window = makeWindow()
            window.contentView!.addSubview(hosting)
            hosting.layoutSubtreeIfNeeded()
            spin()

            let list = try SwaTexEngine.displayList(for: latex)
            let expected = DisplayListRenderer.metrics(
                for: list, options: RenderOptions(fontSize: fontSize, padding: 0)
            ).baseline
            #expect(expected > 0)
            #expect(
                box.values.contains { abs($0 - expected) < 0.01 },
                "Layout saw ascents \(box.values), expected \(expected)")
        }

        /// End-to-end pixel check: a SwiftUI dynamic color reaches the
        /// rendered output (red channel dominates the drawn glyphs).
        @Test func swiftUIDynamicColorReachesPixels() throws {
            let hosting = NSHostingView(
                rootView: MathView(#"x"#).font(size: 40).mathColor(SwiftUI.Color.red))
            hosting.frame = NSRect(x: 0, y: 0, width: 60, height: 60)
            let window = makeWindow()
            window.contentView!.addSubview(hosting)
            window.orderBack(nil)
            hosting.layoutSubtreeIfNeeded()
            spin(0.1)

            let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            var sawRed = false
            var opaque = 0
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh {
                    if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 {
                        opaque += 1
                        // Antialiasing blends edges toward the backdrop;
                        // require clear red dominance rather than purity.
                        if c.redComponent > 0.7, c.redComponent > c.greenComponent * 2,
                            c.redComponent > c.blueComponent * 2
                        {
                            sawRed = true
                        }
                    }
                }
            }
            window.orderOut(nil)
            #expect(sawRed, "expected red-dominant glyph pixels (opaque pixels: \(opaque))")
        }

        /// Source-compat pin (final review finding): shared implicit member
        /// names keep selecting the 0.1.0 `SwaTex.Color` overload; SwiftUI-
        /// only members select the dynamic overload. Compilation IS the test.
        @Test func mathColorOverloadsDisambiguate() {
            _ = MathView("x").mathColor(.black)  // SwaTex.Color, as in 0.1.0
            _ = MathView("x").mathColor(.primary)  // SwiftUI-only member
            _ = MathView("x").mathColor(SwiftUI.Color.red)
            _ = MathView("x").mathColor(SwaTex.Color(r: 0, g: 1, b: 0, a: 1))
        }

        /// Final-review NIT fixes, pinned: unresolvable dynamic colors fall
        /// back to `mathColor` (was: opaque black on UIKit, mathColor on
        /// AppKit), and the error-branch baseline matches the platform
        /// default (same as AppKit's `super` fallback).
        @Test func unresolvableDynamicColorFallsBackToMathColor() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"x"#
            view.mathColor = SwaTex.Color(r: 0, g: 0, b: 1, a: 1)
            let image = NSImage(size: NSSize(width: 2, height: 2))
            image.lockFocus()
            NSColor.orange.setFill()
            NSRect(x: 0, y: 0, width: 2, height: 2).fill()
            image.unlockFocus()
            view.color = NSColor(patternImage: image)  // no sRGB representation
            _ = view.intrinsicContentSize
            #expect(view.effectiveMathColor.b > 0.9, "pattern color must fall back to mathColor")
        }

        @Test func errorBaselineMatchesPlatformDefault() {
            let frame = NSRect(x: 0, y: 0, width: 40, height: 20)
            let view = SwaTexView(frame: frame)
            view.latex = #"\undefinedmacro"#
            let plain = NSView(frame: frame)
            #expect(view.firstBaselineOffsetFromTop == plain.firstBaselineOffsetFromTop)
            #expect(view.lastBaselineOffsetFromBottom == plain.lastBaselineOffsetFromBottom)
        }

        @Test func cgColorConversionFailableSemantics() {
            let srgbRed = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
            let converted = SwaTex.Color(cgColor: srgbRed)
            #expect(converted == SwaTex.Color(r: 1, g: 0, b: 0, a: 1))
        }
    }
#endif
