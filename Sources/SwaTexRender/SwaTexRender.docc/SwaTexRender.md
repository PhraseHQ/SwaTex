# ``SwaTexRender``

Native Apple rendering for SwaTex: CoreText/CoreGraphics drawing, SwiftUI,
UIKit/AppKit views, and fast PNG export — with the KaTeX fonts bundled.

These are the production views of
[Phrase](https://phrase.so?utm_source=docs&utm_medium=docc&utm_campaign=swatex)'s
native block editor — the editor-grade behaviors below (lazy invalidation,
zero re-rasterization on scroll, baseline anchors) exist because Phrase
ships on them.

## Overview

```swift
// SwiftUI
MathView(#"\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}"#)
    .font(size: 24)

// UIKit / AppKit (block-editor ready: intrinsic size + baseline metrics,
// lazy layout, shared formula cache — <3 µs per reused cell)
let view = SwaTexView()
view.latex = #"\frac{a}{b}"#
view.fontSize = 18
view.mathStyle = .text

// PNG (Accelerate + libz fast path; parallel batch across cores)
let png = try ImageRenderer.png(latex: #"E = mc^2"#)
let batch = await ImageRenderer.pngs(for: formulas)
```

Rendering performance is benchmarked and logged with adopt/reject decisions
in the performance log: ~70 µs hot frame, 40 µs per PNG in parallel batch,
12 ms cold layout for a 200-block document.

## Topics

### Views

- ``MathView``
- ``SwaTexView``

### Rendering

- ``DisplayListRenderer``
- ``RenderOptions``
- ``RenderMetrics``
- ``ImageRenderer``

### Fonts

- ``KaTeXFontProvider``
