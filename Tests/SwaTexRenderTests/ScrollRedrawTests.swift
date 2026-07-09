#if canImport(AppKit) && !canImport(UIKit)
    import AppKit
    import QuartzCore
    import SwiftUI
    import Testing

    @testable import SwaTex
    @testable import SwaTexRender

    /// P-022: `SwaTexView` renders through `updateLayer` — the view owns a
    /// rasterized bitmap and any system-initiated redisplay (scrolling back
    /// in from AppKit's purged offscreen region, window moves, forced
    /// `needsDisplay`) hands that bitmap to the layer in O(1). Glyph
    /// rasterization (`rasterizationCount`) happens only when content
    /// actually changes. Tests spin the main run loop so real display
    /// cycles execute.
    @Suite("ScrollRedraw", .serialized)
    @MainActor
    struct ScrollRedrawTests {
        private func makeWindow(size: NSSize = NSSize(width: 400, height: 300)) -> NSWindow {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView!.wantsLayer = true
            return window
        }

        private func spin(_ seconds: TimeInterval = 0.05) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }

        /// Poll the run loop until `condition` holds (CI runners commit
        /// CoreAnimation transactions much more slowly than a live
        /// session — a fixed 50 ms spin flaked on GitHub Actions).
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

        @Test func viewUsesUpdateLayerWithExplicitRedrawPolicy() {
            let view = SwaTexView(frame: .zero)
            #expect(view.wantsLayer)
            #expect(view.wantsUpdateLayer)
            #expect(view.layerContentsRedrawPolicy == .onSetNeedsDisplay)
            #expect(view.layerContentsPlacement == .topLeft)
            // A compressed host must clip, not overdraw neighbors; and the
            // bitmap being bounds-independent means growth reveals without
            // re-rasterizing.
            #expect(view.clipsToBounds)
        }

        @Test func compressedViewClipsAndGrowthRevealsWithoutRerasterizing() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"\sum_{n=1}^{\infty} \frac{1}{n^2}"#
            view.fontSize = 18
            let intrinsic = view.intrinsicContentSize
            // Host compresses the view below its intrinsic size.
            view.frame = CGRect(x: 0, y: 0, width: intrinsic.width / 2, height: intrinsic.height)

            let window = makeWindow()
            window.contentView!.addSubview(view)
            window.orderBack(nil)
            waitUntil { view.rasterizationCount >= 1 }
            let baseline = view.rasterizationCount
            #expect(baseline == 1)

            // Growing back to full size reveals the complete bitmap —
            // no re-rasterization needed (contents are bounds-independent).
            view.setFrameSize(NSSize(width: intrinsic.width, height: intrinsic.height))
            spin()
            #expect(view.rasterizationCount == baseline)
            window.orderOut(nil)
        }

        @Test func scrollingNeverRerasterizes() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"\sum_{n=1}^{\infty} \frac{1}{n^2}"#
            view.fontSize = 18
            view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)

            let document = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 4000))
            document.addSubview(view)
            view.frame.origin = CGPoint(x: 0, y: 1800)

            let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
            scroll.wantsLayer = true
            scroll.documentView = document

            let window = makeWindow()
            window.contentView!.addSubview(scroll)
            window.orderBack(nil)
            #expect(
                waitUntil { view.rasterizationCount >= 1 },
                "initial display never rasterized (CI display cycle)")
            #expect(view.rasterizationCount == 1, "initial display should rasterize once")

            // Scroll the formula in and out of the viewport repeatedly.
            // AppKit may re-request layer contents (updateLayer) as the view
            // re-enters its prepared region — but each is a cached-bitmap
            // handoff, never a re-rasterization.
            for y in stride(from: 0, through: 3600, by: 240) {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(y)))
                scroll.reflectScrolledClipView(scroll.contentView)
                spin(0.01)
            }
            spin()
            #expect(
                view.rasterizationCount == 1,
                "scrolling re-rasterized the formula \(view.rasterizationCount - 1) time(s)")
            window.orderOut(nil)
        }

        @Test func forcedRedisplayReusesCachedBitmap() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"x^2"#
            view.fontSize = 18
            view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)

            let window = makeWindow()
            window.contentView!.addSubview(view)
            window.orderBack(nil)
            #expect(
                waitUntil { view.rasterizationCount >= 1 },
                "initial display never rasterized (CI display cycle)")
            let baseline = view.rasterizationCount
            #expect(baseline == 1)
            #expect(view.layer?.contents != nil)

            // A forced full redisplay must hand back the cached bitmap.
            view.needsDisplay = true
            spin(0.2)
            #expect(view.rasterizationCount == baseline)
            window.orderOut(nil)
        }

        @Test func boundsChangeDoesNotRerasterize() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"x^2"#
            view.fontSize = 18
            view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)

            let window = makeWindow()
            window.contentView!.addSubview(view)
            window.orderBack(nil)
            waitUntil { view.rasterizationCount >= 1 }
            let baseline = view.rasterizationCount

            view.setFrameSize(NSSize(width: 300, height: 80))
            spin()
            #expect(view.rasterizationCount == baseline, "resize re-rasterized the formula")
            window.orderOut(nil)
        }

        /// Row of the alpha-weighted centroid, in *rendered* row order
        /// (row 0 = first memory row), normalized to 0…1.
        private func alphaCentroidY(_ image: CGImage) -> Double? {
            let w = image.width, h = image.height
            guard
                let ctx = CGContext(
                    data: nil, width: w, height: h, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let data = ctx.data else { return nil }
            let buf = data.assumingMemoryBound(to: UInt8.self)
            var total = 0.0, weighted = 0.0
            for row in 0..<h {
                var rowAlpha = 0.0
                for col in 0..<w {
                    rowAlpha += Double(buf[row * ctx.bytesPerRow + col * 4 + 3])
                }
                total += rowAlpha
                weighted += rowAlpha * Double(row)
            }
            guard total > 0 else { return nil }
            return weighted / total / Double(h)
        }

        /// Orientation ground truth (regression for the macOS upside-down
        /// bug): read back through SUPERVIEW compositing (`cacheDisplay` on
        /// the container), which matches on-screen output. Never assert
        /// orientation via `view.layer.render(in:)` — entered at the
        /// content layer it applies `contentsAreFlipped()` itself and shows
        /// the opposite of what the screen shows.
        private func compositedCentroid(
            of view: NSView, in windowAppearance: NSAppearance.Name = .aqua
        ) throws -> Double {
            let container = NSView(frame: view.frame)
            container.wantsLayer = true
            container.addSubview(view)
            let window = makeWindow(size: view.frame.size)
            window.appearance = NSAppearance(named: windowAppearance)
            window.contentView = container
            window.orderBack(nil)
            spin()
            let rep = try #require(
                container.bitmapImageRepForCachingDisplay(in: container.bounds))
            container.cacheDisplay(in: container.bounds, to: rep)
            window.orderOut(nil)
            let image = try #require(rep.cgImage)
            return try #require(alphaCentroidY(image))
        }

        private func referenceCentroid(
            _ latex: String, fontSize: CGFloat, scale: CGFloat = 2
        ) throws -> Double {
            let list = try SwaTexEngine.displayList(for: latex)
            let ref = try #require(
                ImageRenderer.image(
                    for: list, options: RenderOptions(fontSize: fontSize, padding: 0),
                    displayScale: scale))
            return try #require(alphaCentroidY(ref))
        }

        /// AppKit SwaTexView hosted directly: composites upright.
        @Test func appKitViewCompositesUpright() throws {
            let latex = #"x^2"#  // vertically asymmetric
            let view = SwaTexView(frame: .zero)
            view.latex = latex
            view.fontSize = 32
            view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)

            let got = try compositedCentroid(of: view)
            let want = try referenceCentroid(latex, fontSize: 32)
            #expect(
                abs(got - want) < 0.05,
                "AppKit compositing centroid \(got) vs reference \(want) — flipped or misplaced"
            )
        }

        /// SwaTexView inside SwiftUI via NSViewRepresentable (the hosting
        /// arrangement a SwiftUI macOS app uses): composites upright.
        private struct RepresentedMath: NSViewRepresentable {
            let latex: String
            let fontSize: CGFloat
            func makeNSView(context _: Context) -> SwaTexView {
                let v = SwaTexView(frame: .zero)
                v.latex = latex
                v.fontSize = fontSize
                return v
            }
            func updateNSView(_: SwaTexView, context _: Context) {}
        }

        @Test func representableInSwiftUICompositesUpright() throws {
            let latex = #"x^2"#
            let size = SwaTexView(frame: .zero)
            size.latex = latex
            size.fontSize = 32
            let intrinsic = size.intrinsicContentSize

            let hosting = NSHostingView(
                rootView: RepresentedMath(latex: latex, fontSize: 32)
                    .frame(width: intrinsic.width, height: intrinsic.height))
            hosting.frame = NSRect(origin: .zero, size: intrinsic)

            let got = try compositedCentroid(of: hosting)
            let want = try referenceCentroid(latex, fontSize: 32)
            #expect(
                abs(got - want) < 0.05,
                "NSViewRepresentable centroid \(got) vs reference \(want) — flipped in SwiftUI hosting"
            )
        }

        /// Pure SwiftUI MathView (Canvas): composites upright.
        @Test func mathViewInSwiftUICompositesUpright() throws {
            let latex = #"x^2"#
            let list = try SwaTexEngine.displayList(for: latex)
            let m = DisplayListRenderer.metrics(
                for: list, options: RenderOptions(fontSize: 32, padding: 0))

            let hosting = NSHostingView(rootView: MathView(latex).font(size: 32))
            hosting.frame = NSRect(x: 0, y: 0, width: m.width, height: m.height)

            let got = try compositedCentroid(of: hosting)
            let want = try referenceCentroid(latex, fontSize: 32)
            #expect(
                abs(got - want) < 0.05,
                "MathView centroid \(got) vs reference \(want) — Canvas orientation broken"
            )
        }

        @Test func contentChangeRerasterizesExactlyOnce() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"x^2"#
            view.fontSize = 18
            view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)

            let window = makeWindow()
            window.contentView!.addSubview(view)
            window.orderBack(nil)
            waitUntil { view.rasterizationCount >= 1 }
            let baseline = view.rasterizationCount

            // Configure several properties in a row — one rasterization.
            view.latex = #"y^3"#
            view.fontSize = 22
            view.mathStyle = .text
            #expect(
                waitUntil { view.rasterizationCount == baseline + 1 },
                "content change should rasterize exactly once")

            // No-op sets must not re-rasterize (equality short-circuit).
            view.latex = #"y^3"#
            view.fontSize = 22
            spin()
            #expect(view.rasterizationCount == baseline + 1)
            window.orderOut(nil)
        }

        /// `cacheDisplay`/printing route: the offscreen snapshot path also
        /// counts as a rasterization and produces non-empty pixels.
        @Test func cacheDisplayProducesPixels() throws {
            let view = SwaTexView(frame: .zero)
            view.latex = #"x+y"#
            view.fontSize = 18
            view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)
            let before = view.rasterizationCount
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            #expect(view.rasterizationCount > before)
            let img = try #require(rep.cgImage)
            #expect(img.width > 1 && img.height > 1)
        }

        /// A backing-properties change (screen migration) requests a
        /// redisplay; the scale-keyed cache re-renders at the new scale.
        @Test func backingPropertiesChangeRequestsRedisplay() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"x"#
            _ = view.intrinsicContentSize
            view.needsDisplay = false
            view.viewDidChangeBackingProperties()
            #expect(view.needsDisplay || (view.layer.map { $0.needsDisplay() } ?? false))
        }

        /// `init?(coder:)` — the Interface Builder path — must configure the
        /// view identically to the programmatic initializer.
        @Test func coderInitConfiguresView() throws {
            let original = SwaTexView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: original, requiringSecureCoding: false)
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            let decoded = try #require(
                unarchiver.decodeObject(of: SwaTexView.self, forKey: NSKeyedArchiveRootObjectKey))
            #expect(decoded.wantsLayer)
            #expect(decoded.wantsUpdateLayer)
            #expect(decoded.layerContentsRedrawPolicy == .onSetNeedsDisplay)
            decoded.latex = #"x^2"#
            #expect(decoded.intrinsicContentSize.width > 1)
        }

        /// The printing/PDF path goes through `draw(_:)` (not updateLayer)
        /// and must produce non-empty vector output.
        @Test func pdfExportDrawsThroughDrawRect() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"\frac{a}{b}"#
            view.fontSize = 24
            view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)
            let before = view.rasterizationCount
            let pdf = view.dataWithPDF(inside: view.bounds)
            #expect(pdf.count > 500, "expected non-trivial PDF output")
            #expect(view.rasterizationCount > before, "draw(_:) should have run")
        }
    }
#endif
