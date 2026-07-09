# ``SwaTex``

KaTeX-compatible math rendering engine in pure Swift — no JavaScript, no
WebView, no DOM.

SwaTex is built and maintained by the team behind
[Phrase](https://phrase.so?utm_source=docs&utm_medium=docc&utm_campaign=swatex),
the native block editor that turns recordings and PDFs into source-backed
AI notes — SwaTex renders every formula in Phrase.

## Overview

SwaTex parses LaTeX math, lays it out with TeX's box-and-glue rules driven by
the KaTeX font metrics, and produces a flat, renderer-agnostic ``DisplayList``.
The engine is verified numerically identical to the RaTeX Rust reference over
a 2 500+-formula golden corpus, and covers 99 %+ of KaTeX's documented
support table (see the KaTeX support table).

```swift
// One call: LaTeX → display list (em units)
let list = try SwaTexEngine.displayList(for: #"\frac{a}{b}"#)

// Repeated formulas: memoize through the shared cache (~100 ns per hit)
let cached = try SwaTexEngine.displayList(for: latex, cache: .shared)

// Whole documents: parallel batch across cores
let lists = await SwaTexEngine.displayLists(for: formulas)

// SVG output (byte-compatible with RaTeX)
let svg = SVGRenderer().render(list)
```

For native rendering (CoreText/CoreGraphics, SwiftUI, UIKit/AppKit views and
PNG export), see the `SwaTexRender` module.

## Topics

### Essentials

- ``SwaTexEngine``
- ``FormulaCache``
- ``DisplayList``
- ``DisplayItem``
- ``ParseError``

### Parsing

- ``parseLaTeX(_:)``
- ``Parser``
- ``ParseNode``
- ``MathStyle``
- ``Mode``

### Layout

- ``layout(_:options:)``
- ``LayoutOptions``
- ``LayoutBox``
- ``toDisplayList(_:)``
- ``MathConstants``
- ``CharMetrics``

### Display list primitives

- ``PathCommand``
- ``Color``
- ``Measurement``
- ``FontId``

### SVG

- ``SVGRenderer``
- ``SVGOptions``
