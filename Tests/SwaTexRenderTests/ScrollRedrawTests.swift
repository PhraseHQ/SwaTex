#if canImport(AppKit) && !canImport(UIKit)
    import AppKit
    import QuartzCore
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
            spin()
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
            spin()
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
            spin()
            let baseline = view.rasterizationCount
            #expect(baseline == 1)
            #expect(view.layer?.contents != nil)

            // A forced full redisplay must hand back the cached bitmap.
            view.needsDisplay = true
            spin()
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
            spin()
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

        /// The bitmap handed to the layer must composite upright: compare
        /// the layer tree's actual render against the reference image via
        /// alpha centroids (an upside-down formula flips the centroid).
        @Test func updateLayerContentsCompositeUpright() throws {
            let view = SwaTexView(frame: .zero)
            view.latex = #"x^2"#  // superscript → distinctly top-heavy
            view.fontSize = 24
            view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)

            let window = makeWindow(size: view.frame.size)
            window.contentView!.addSubview(view)
            window.orderBack(nil)
            spin()
            #expect(view.layer?.contents != nil)

            let scale = view.layer!.contentsScale
            let pw = max(Int(view.frame.width * scale), 1)
            let ph = max(Int(view.frame.height * scale), 1)
            let ctx = try #require(
                CGContext(
                    data: nil, width: pw, height: ph, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.scaleBy(x: scale, y: scale)
            view.layer!.render(in: ctx)
            let composited = try #require(ctx.makeImage())

            let list = try SwaTexEngine.displayList(for: #"x^2"#, style: .display)
            let reference = try #require(
                ImageRenderer.image(
                    for: list, options: RenderOptions(fontSize: 24, padding: 0),
                    displayScale: scale))

            let got = try #require(alphaCentroidY(composited))
            let want = try #require(alphaCentroidY(reference))
            #expect(
                abs(got - want) < 0.05,
                "centroid \(got) vs reference \(want) — orientation/placement mismatch")
            window.orderOut(nil)
        }

        @Test func contentChangeRerasterizesExactlyOnce() {
            let view = SwaTexView(frame: .zero)
            view.latex = #"x^2"#
            view.fontSize = 18
            view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)

            let window = makeWindow()
            window.contentView!.addSubview(view)
            window.orderBack(nil)
            spin()
            let baseline = view.rasterizationCount

            // Configure several properties in a row — one rasterization.
            view.latex = #"y^3"#
            view.fontSize = 22
            view.mathStyle = .text
            spin()
            #expect(view.rasterizationCount == baseline + 1)

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
