#if canImport(AppKit) && !canImport(UIKit)
    import AppKit
    import CoreGraphics
    import Testing

    @testable import SwaTex
    @testable import SwaTexRender

    /// NSView-side tests (the UIView variant shares all logic; it is
    /// compile-verified by the iOS CI build).
    @Suite("SwaTexView", .serialized)
    @MainActor
    struct SwaTexViewTests {
        @Test func intrinsicSizeAndBaseline() throws {
            let view = SwaTexView(frame: .zero)
            view.fontSize = 40
            view.latex = #"\frac{a}{b}"#

            let size = view.intrinsicContentSize
            #expect(size.width > 10)
            #expect(size.height > 20)
            // Fraction: baseline sits between numerator and denominator.
            #expect(view.baselineFromTop > 0)
            #expect(view.baselineFromBottom > 0)
            #expect(abs(view.baselineFromTop + view.baselineFromBottom - size.height) < 0.001)
        }

        @Test func inlineStyleIsShorter() {
            let view = SwaTexView(frame: .zero)
            view.fontSize = 40
            view.latex = #"\sum_{n=1}^{\infty} \frac{1}{n^2}"#
            let displayHeight = view.intrinsicContentSize.height
            view.mathStyle = .text
            #expect(view.intrinsicContentSize.height < displayHeight)
        }

        @Test func errorCallbackFires() {
            let view = SwaTexView(frame: .zero)
            var received: ParseError?
            view.onError = { received = $0 }
            view.latex = #"\frac{1}"#
            // Layout is lazy: the error surfaces on the first metrics query.
            #expect(view.intrinsicContentSize == CGSize(width: 1, height: 1))
            #expect(received != nil)
        }

        @Test func layoutCallbackReportsMetrics() throws {
            let view = SwaTexView(frame: .zero)
            var metrics: RenderMetrics?
            view.onLayout = { metrics = $0 }
            view.fontSize = 40
            view.latex = #"x^2"#
            _ = view.intrinsicContentSize  // lazy layout runs here
            let m = try #require(metrics)
            #expect(m.baseline > 0)
        }

        @Test func drawsInkIntoContext() throws {
            let view = SwaTexView(frame: .zero)
            view.fontSize = 40
            view.latex = #"x^2 + y^2"#
            let size = view.intrinsicContentSize
            view.frame = CGRect(origin: .zero, size: size)

            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            var ink = 0
            for x in stride(from: 0, to: Int(size.width), by: 2) {
                for y in stride(from: 0, to: Int(size.height), by: 2) {
                    if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.1 {
                        ink += 1
                    }
                }
            }
            #expect(ink > 20, "expected rendered ink, found \(ink) samples")
        }
    }
#endif
