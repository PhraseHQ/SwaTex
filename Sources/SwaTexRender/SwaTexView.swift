import SwaTex

#if canImport(UIKit) && !os(watchOS)
    import UIKit
    public typealias SwaTexPlatformView = UIView
    public typealias SwaTexPlatformColor = UIColor
#elseif canImport(AppKit)
    import AppKit
    public typealias SwaTexPlatformView = NSView
    public typealias SwaTexPlatformColor = NSColor
#endif

#if (canImport(UIKit) && !os(watchOS)) || canImport(AppKit)

    extension SwaTex.Color {
        /// A `SwaTex.Color` from a resolved `CGColor`, converting to sRGB.
        /// `nil` when the color has no sRGB representation (pattern colors,
        /// …) — the view then falls back to `mathColor`, identically on
        /// both platforms.
        init?(cgColor: CGColor) {
            guard
                let srgb = cgColor.converted(
                    to: CGColorSpace(name: CGColorSpace.sRGB)!,
                    intent: .defaultIntent, options: nil),
                let c = srgb.components, c.count >= 4
            else {
                return nil
            }
            self.init(r: Float(c[0]), g: Float(c[1]), b: Float(c[2]), a: Float(c[3]))
        }
    }

    /// A UIKit/AppKit view that renders LaTeX math natively — no WebView.
    ///
    /// This is the math view of [Phrase](https://phrase.so)'s native block
    /// editor. Designed for block editors and text-heavy UIs:
    /// - parse + layout are memoized through ``FormulaCache/shared`` (~100 ns
    ///   per repeated formula), so `draw(_:)` is a pure vector CoreGraphics
    ///   pass (~tens of µs) with no bitmap round-trip;
    /// - `intrinsicContentSize` participates in Auto Layout;
    /// - ``baselineFromTop`` / ``baselineFromBottom`` expose the typographic
    ///   baseline so inline formulas align with surrounding text runs.
    ///
    /// ```swift
    /// let view = SwaTexView()
    /// view.latex = #"\frac{a}{b}"#
    /// view.fontSize = 18
    /// view.mathStyle = .text  // inline
    /// ```
    public final class SwaTexView: SwaTexPlatformView {
        // MARK: Content

        /// The LaTeX source. Setting it invalidates layout (computed lazily
        /// on the next `intrinsicContentSize` / metrics query / draw).
        public var latex: String = "" {
            didSet { if latex != oldValue { invalidateContent() } }
        }

        /// Font size in points (1 em = `fontSize` points).
        public var fontSize: CGFloat = 24 {
            didSet { if fontSize != oldValue { invalidateContent() } }
        }

        /// `.display` (default) or `.text` for inline style.
        public var mathStyle: MathStyle = .display {
            didSet { if mathStyle != oldValue { invalidateContent() } }
        }

        /// Formula color as a static RGBA value.
        /// For dark-mode-adaptive colors use ``color`` instead.
        public var mathColor: SwaTex.Color = .black {
            didSet { if mathColor != oldValue { invalidateContent() } }
        }

        /// Dynamic formula color (e.g. `.label` / `.labelColor`). When set,
        /// it takes precedence over ``mathColor``, resolves against the
        /// view's current traits/appearance, and the view re-renders
        /// automatically when the effective appearance changes (dark mode).
        public var color: SwaTexPlatformColor? {
            didSet { if color != oldValue { invalidateContent() } }
        }

        /// The color the last layout actually used (``color`` resolved
        /// against the current appearance, or ``mathColor``). Internal —
        /// used by the dynamic-color tests.
        internal private(set) var effectiveMathColor: SwaTex.Color = .black

        /// Padding around the formula in points.
        public var padding: CGFloat = 0 {
            didSet { if padding != oldValue { invalidateContent() } }
        }

        /// Called when the LaTeX fails to parse. Layout is lazy, so this
        /// fires on the first metrics query or draw after the change.
        public var onError: ((ParseError) -> Void)?

        /// Called after re-layout with the rendered metrics (in points).
        /// Layout is lazy — see ``onError``.
        public var onLayout: ((RenderMetrics) -> Void)?

        // MARK: Metrics (block-editor alignment)

        /// Distance from the view's top edge to the math baseline, in points.
        public var baselineFromTop: CGFloat {
            layoutIfNeeded_()
            return cachedBaseline
        }

        /// Distance from the bottom of the formula's intrinsic content up to
        /// the math baseline. Note: measured against `intrinsicContentSize`,
        /// not `bounds` — if Auto Layout stretches the view beyond its
        /// intrinsic size, the formula stays anchored top-left and this
        /// value does not track the extra space below it.
        public var baselineFromBottom: CGFloat {
            intrinsicContentSize.height - baselineFromTop
        }

        // MARK: State

        /// Number of times the formula was actually rasterized (glyphs →
        /// pixels). The invariant P-022 guarantees: system-initiated
        /// redisplays (scrolling a view back in from AppKit's purged
        /// offscreen region, window moves, …) hand the cached bitmap back
        /// to the layer without touching this. Internal — used by the
        /// redraw-discipline tests and handy when debugging an editor
        /// integration ("is my hierarchy re-rasterizing math on scroll?").
        internal private(set) var rasterizationCount = 0

        /// Lazy relayout: property setters only mark dirty, so configuring
        /// several properties in a row (the normal cell-configure pattern in
        /// editors and lists) costs exactly one parse+layout — and even that
        /// is usually a FormulaCache hit.
        private var needsContentLayout = true
        private var displayList: DisplayList?
        private var contentSize = CGSize(width: 1, height: 1)
        private var cachedBaseline: CGFloat = 0

        #if canImport(UIKit) && !os(watchOS)
            /// Invisible zero-height marker whose top edge sits on the math
            /// baseline. UIKit resolves `firstBaselineAnchor` /
            /// `lastBaselineAnchor` from `forFirstBaselineLayout`'s frame,
            /// so returning this marker lets `label.firstBaselineAnchor`
            /// constraints align text with the formula.
            private let baselineMarker = UIView()
        #endif

        private var renderOptions: RenderOptions {
            RenderOptions(fontSize: fontSize, padding: padding, backgroundColor: nil)
        }

        public override var intrinsicContentSize: CGSize {
            layoutIfNeeded_()
            return contentSize
        }

        // MARK: Init

        public override init(frame: CGRect) {
            super.init(frame: frame)
            configure()
        }

        public required init?(coder: NSCoder) {
            super.init(coder: coder)
            configure()
        }

        private func configure() {
            // The layer backing store IS the render cache (P-022): draw(_:)
            // runs only when invalidateContent() explicitly asks for it.
            // Scrolling composites the cached contents — zero redraws — and
            // a bounds change neither redraws (content is independent of
            // bounds) nor stretches (contents anchored top-left, matching
            // the drawing origin).
            #if canImport(UIKit) && !os(watchOS)
                isOpaque = false
                backgroundColor = .clear
                // NOT .redraw (would re-rasterize on every bounds change)
                // and NOT the .scaleToFill default (would stretch the
                // cached contents on resize).
                contentMode = .topLeft
                // A host that sizes the view below its intrinsic size must
                // clip, not overdraw the neighbors.
                clipsToBounds = true
                baselineMarker.isHidden = true
                baselineMarker.isUserInteractionEnabled = false
                addSubview(baselineMarker)
                // Re-resolve `color` when any trait affecting color
                // appearance changes (dark mode, contrast, …).
                registerForTraitChanges(UITraitCollection.systemTraitsAffectingColorAppearance) {
                    (self: SwaTexView, _: UITraitCollection) in
                    self.appearanceDidChange()
                }
            #else
                // A non-layer-backed NSView is asked to draw every newly
                // exposed region while scrolling; layer-backed it draws
                // once per invalidation.
                wantsLayer = true
                layerContentsRedrawPolicy = .onSetNeedsDisplay
                layerContentsPlacement = .topLeft
                // The updateLayer bitmap always contains the full formula
                // (bounds-independent); the layer mask handles both a host
                // that compresses the view (clip, not overdraw neighbors)
                // and one that later grows it (reveal, no redraw needed).
                clipsToBounds = true
            #endif
        }

        #if canImport(AppKit) && !canImport(UIKit)
            // Match the display list's top-left/y-down coordinate space.
            public override var isFlipped: Bool { true }

            // MARK: Auto Layout baseline (AppKit)

            /// Expose the math baseline to Auto Layout so
            /// `firstBaselineAnchor` / `lastBaselineAnchor` constraints
            /// align to it instead of the view's edges. Falls back to the
            /// superclass values while there is no rendered formula.
            public override var firstBaselineOffsetFromTop: CGFloat {
                layoutIfNeeded_()
                return cachedBaseline > 0 ? cachedBaseline : super.firstBaselineOffsetFromTop
            }

            public override var lastBaselineOffsetFromBottom: CGFloat {
                layoutIfNeeded_()
                return cachedBaseline > 0
                    ? contentSize.height - cachedBaseline
                    : super.lastBaselineOffsetFromBottom
            }
        #endif

        #if canImport(UIKit) && !os(watchOS)
            // MARK: Auto Layout baseline (UIKit)

            /// UIKit derives baseline anchors from these views' frames; the
            /// marker's top edge is kept on the math baseline by
            /// `layoutIfNeeded_`. With no rendered formula (parse error,
            /// empty input) fall back to the platform default — the same
            /// behavior as the AppKit `super` fallback.
            public override var forFirstBaselineLayout: UIView {
                layoutIfNeeded_()
                return cachedBaseline > 0 ? baselineMarker : super.forFirstBaselineLayout
            }

            public override var forLastBaselineLayout: UIView {
                layoutIfNeeded_()
                return cachedBaseline > 0 ? baselineMarker : super.forLastBaselineLayout
            }
        #endif

        // MARK: Layout + drawing

        private func invalidateContent() {
            needsContentLayout = true
            invalidateIntrinsicContentSize()
            #if canImport(UIKit) && !os(watchOS)
                setNeedsDisplay()
            #else
                cachedContents = nil
                needsDisplay = true
            #endif
        }

        private func layoutIfNeeded_() {
            guard needsContentLayout else { return }
            needsContentLayout = false
            effectiveMathColor = resolvedDynamicColor() ?? mathColor
            let result = Result { () throws(ParseError) -> DisplayList in
                try SwaTexEngine.displayList(
                    for: latex, style: mathStyle, color: effectiveMathColor, cache: .shared)
            }
            switch result {
            case .success(let list):
                displayList = list
                let m = DisplayListRenderer.metrics(for: list, options: renderOptions)
                contentSize = CGSize(width: m.width, height: m.height)
                cachedBaseline = m.baseline
                onLayout?(m)
            case .failure(let error):
                displayList = nil
                contentSize = CGSize(width: 1, height: 1)
                cachedBaseline = 0
                onError?(error)
            }
            #if canImport(UIKit) && !os(watchOS)
                // Top edge of the zero-height marker = the math baseline;
                // UIKit derives first/lastBaselineAnchor from it.
                baselineMarker.frame = CGRect(x: 0, y: cachedBaseline, width: 1, height: 0)
            #endif
        }

        // MARK: Dynamic color (dark mode)

        /// ``color`` resolved against the current traits (UIKit) or
        /// effective appearance (AppKit); nil when ``color`` is unset.
        private func resolvedDynamicColor() -> SwaTex.Color? {
            guard let color else { return nil }
            #if canImport(UIKit) && !os(watchOS)
                return SwaTex.Color(cgColor: color.resolvedColor(with: traitCollection).cgColor)
            #else
                var resolved: NSColor?
                effectiveAppearance.performAsCurrentDrawingAppearance {
                    resolved = color.usingColorSpace(.sRGB)
                }
                return resolved.flatMap { SwaTex.Color(cgColor: $0.cgColor) }
            #endif
        }

        /// Re-resolve ``color`` after an appearance change; invalidate only
        /// if the effective color actually differs (a no-op appearance
        /// change must not re-rasterize, per the P-022 discipline).
        private func appearanceDidChange() {
            guard color != nil, !needsContentLayout else { return }
            if let resolved = resolvedDynamicColor(), resolved != effectiveMathColor {
                invalidateContent()
            }
        }

        #if canImport(AppKit) && !canImport(UIKit)
            public override func viewDidChangeEffectiveAppearance() {
                super.viewDidChangeEffectiveAppearance()
                appearanceDidChange()
            }
        #endif

        #if canImport(UIKit) && !os(watchOS)
            // The backing store is bounds-sized on UIKit, so a bounds
            // change needs a re-rasterization only when it changes how the
            // content is clipped (previous or new bounds smaller than the
            // content). The editor common case — bounds == intrinsic size
            // throughout — never redraws here.
            private var lastLayoutSize = CGSize.zero

            public override func layoutSubviews() {
                super.layoutSubviews()
                guard bounds.size != lastLayoutSize else { return }
                func clips(_ s: CGSize) -> Bool {
                    s.width < contentSize.width || s.height < contentSize.height
                }
                if clips(lastLayoutSize) || clips(bounds.size) {
                    setNeedsDisplay()
                }
                lastLayoutSize = bounds.size
            }
        #endif

        #if canImport(AppKit) && !canImport(UIKit)
            // AppKit display path: updateLayer mode (P-022). The view owns a
            // rendered bitmap; any system-initiated redisplay — including a
            // view scrolling back in after AppKit purged its offscreen
            // backing store — hands the cached image to the layer in O(1)
            // instead of re-rasterizing glyphs. Rasterization happens only
            // when content actually changed (cachedContents == nil).
            // `cacheDisplay` also routes through updateLayer (probed);
            // `draw(_:)` below remains for printing/PDF and UIKit.
            private var cachedContents: CGImage?
            private var cachedContentsFlipped = false
            private var cachedContentsScale: CGFloat = 0

            public override var wantsUpdateLayer: Bool { true }

            public override func updateLayer() {
                layoutIfNeeded_()
                guard let layer else { return }
                let scale = window?.backingScaleFactor ?? 2
                // The backing layer of a flipped NSView expects contents in
                // flipped space (handing it an upright image composites
                // mirrored — caught by the centroid test). The flip is a
                // free transform at rasterization time. The cache is keyed
                // by (flip, scale) right here rather than trusting
                // viewDidChangeBackingProperties ordering — a screen change
                // must never reuse a bitmap rendered at the old scale.
                let flipped = layer.contentsAreFlipped()
                if cachedContents == nil || cachedContentsFlipped != flipped
                    || cachedContentsScale != scale,
                    let displayList
                {
                    rasterizationCount += 1
                    cachedContents = rasterize(displayList, scale: scale, flipped: flipped)
                    cachedContentsFlipped = flipped
                    cachedContentsScale = scale
                }
                layer.contents = cachedContents
                layer.contentsScale = scale
            }

            private func rasterize(
                _ list: DisplayList, scale: CGFloat, flipped: Bool
            ) -> CGImage? {
                let m = DisplayListRenderer.metrics(for: list, options: renderOptions)
                let pixelWidth = max(Int((m.width * scale).rounded(.up)), 1)
                let pixelHeight = max(Int((m.height * scale).rounded(.up)), 1)
                guard
                    let ctx = CGContext(
                        data: nil, width: pixelWidth, height: pixelHeight,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return nil }
                ctx.scaleBy(x: scale, y: scale)
                if flipped {
                    // Mirror about the full pixel canvas so rows are an
                    // exact reversal of the upright rendering.
                    ctx.translateBy(x: 0, y: CGFloat(pixelHeight) / scale)
                    ctx.scaleBy(x: 1, y: -1)
                }
                DisplayListRenderer.draw(list, in: ctx, options: renderOptions)
                return ctx.makeImage()
            }

            public override func viewDidChangeBackingProperties() {
                super.viewDidChangeBackingProperties()
                // Screen change: request a redisplay; updateLayer re-renders
                // at the new scale (its cache is scale-keyed).
                needsDisplay = true
            }
        #endif

        public override func draw(_ rect: CGRect) {
            rasterizationCount += 1
            layoutIfNeeded_()
            guard let displayList else { return }
            #if canImport(UIKit) && !os(watchOS)
                guard let ctx = UIGraphicsGetCurrentContext() else { return }
                // UIKit contexts are top-left/y-down; DisplayListRenderer
                // expects bottom-left/y-up. Flip once.
                ctx.saveGState()
                ctx.translateBy(x: 0, y: contentSize.height)
                ctx.scaleBy(x: 1, y: -1)
                DisplayListRenderer.draw(displayList, in: ctx, options: renderOptions)
                ctx.restoreGState()
            #else
                guard let ctx = NSGraphicsContext.current?.cgContext else { return }
                ctx.saveGState()
                // isFlipped == true gives a top-left/y-down context; flip to
                // the renderer's expected orientation.
                ctx.translateBy(x: 0, y: contentSize.height)
                ctx.scaleBy(x: 1, y: -1)
                DisplayListRenderer.draw(displayList, in: ctx, options: renderOptions)
                ctx.restoreGState()
            #endif
        }
    }

#endif
