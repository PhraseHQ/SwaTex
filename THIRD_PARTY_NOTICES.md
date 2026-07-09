# Third-party notices

SwaTex is a Swift port of, and remains layout-compatible with:

## RaTeX

MIT License, Copyright (c) erweixin — <https://github.com/erweixin/RaTeX>

SwaTex's engine architecture, layout mathematics, generated data tables, and
golden-test corpus derive from RaTeX (itself KaTeX-compatible). The golden
fixtures under `Tests/SwaTexTests/Resources/golden/` are generated with
RaTeX's `layout` binary.

## KaTeX

MIT License, Copyright (c) 2013–2020 Khan Academy and other contributors —
<https://katex.org>

- The bundled fonts (`Sources/SwaTexRender/Resources/Fonts/KaTeX_*.ttf`) are
  the KaTeX fonts, licensed under the SIL Open Font License 1.1 (see
  `OFL.txt` and `FONT_NOTICE.txt` alongside the fonts).
- The font metric tables (`MetricsData.swift`), symbol tables
  (`SymbolsData.swift`), stretchy-SVG geometry (`KaTeXSvgData.swift`), macro
  set, and layout rules are derived from KaTeX's `fontMetricsData.js`,
  `symbols.js`, `svgGeometry.js`, and `macros.js`.

## mhchem

The `\ce` / `\pu` chemistry state machine derives from mhchem for KaTeX
(MIT License, Copyright (c) Martin Hensel) via RaTeX's Rust port.
