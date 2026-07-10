# Changelog

## 0.3.0 — 2026-07-10

### Added
- `DisplayList.truncated`: true when a recursion guard dropped a subtree
  (layout- or emission-stage) on stack exhaustion — partial output is now
  distinguishable from a complete render. Excluded from the serialized
  wire format (RaTeX parity). `FormulaCache` never persists truncated
  results (they are thread-dependent), so a later render on a larger
  stack recomputes fully.
- Emoji rendering fixes in the CoreGraphics backend: translucent colors
  now apply to color-bitmap emoji exactly once, and non-BMP emoji resolve
  the color emoji font (previously fell back to monochrome LastResort).

### Changed (KaTeX-correctness; may affect callers of lenient inputs)
- Unterminated `\verb` and `x\limits^2` now throw `ParseError`
  (previously accepted silently, matching a RaTeX bug).
- `\gdef`/`\xdef`/`\global\def` defined inside a group now survive group
  exit; zero-arg delimited `\def` macros validate and consume their
  parameter text; `\def\a#{…}` keeps braces balanced (TeXbook §203).
- `\operatorname`/`\operatorname*` limit-control semantics now match
  KaTeX exactly; `\vcenter` physically centers ink on the math axis;
  multi-char `\cancel` no longer overlaps the following atom.
- `\middle` nested deeper than 8 `\left…\right` stretch scopes renders
  at natural size (visible, unstretched) instead of exponential work or
  invisible placeholders; `\middle` inside `\hbox` stretches correctly.
- Layout recursion on Darwin is bounded by the stack-headroom probe alone
  (no artificial 1024-depth ceiling); deep-but-legitimate trees (long
  combining-accent chains) render fully on large stacks.

### Fixed
- SVG output is well-formed XML for the emoji font stack, escapes
  provider-supplied path/href strings (including quotes fused with
  combining marks), and cache hit/miss statistics count each request
  exactly once under concurrency.

### Performance
- PNG chunk CRC-32 via libz hardware instructions (~80× the table loop);
  glyph translucency and SVG escaping hot paths trimmed; `\middle`
  containment scan short-circuits; per-node layout dispatch no longer
  copies options on Darwin.

## 0.2.0 — 2026-07-09

### Added
- Test hardening for release: fuzz smoke (2000 deterministic random
  inputs never crash), stress/boundary/finite-geometry suites,
  8-way concurrency stress, cache-capacity invariants, CD-arrow and
  prooftree coverage, core edge-path coverage (verb/char/catcode), and
  in-suite performance-regression sentinels (throughput, cache-hit,
  linear-scaling gates). Core parse/lex/macro/layout logic at ~98.7%
  line coverage; remaining gaps are documented P-013 defensive fallbacks.
- Open-source hardening: CONTRIBUTING / SECURITY / CODE_OF_CONDUCT, issue
  and PR templates, `.swift-format` config enforced in CI (`--strict`),
  DocC build job, warnings-as-errors in CI, `BENCHMARKS.md` reproduction
  guide, README known-limitations section and showcase screenshots.
- RaTeX view-parity (migration): Auto Layout baseline anchors on
  `SwaTexView` (`firstBaselineAnchor` constraints align text to the math
  baseline on both platforms); dynamic platform color
  (`SwaTexView.color: UIColor/NSColor`) with automatic dark-mode
  re-rendering; SwiftUI `MathView` baseline alignment guides,
  `MathViewAscentKey` for custom Layouts, and
  `mathColor(_: SwiftUI.Color)` with environment-resolved dynamic colors.

### Changed
- Swift tools version lowered 6.2 → 6.1: the package now resolves and
  builds with Xcode 16.3+ (nothing in the manifest or sources requires the
  6.2 toolchain).
- Platform floors lowered from OS 26 to the actual API minimums:
  iOS 18 / macOS 15 / tvOS 18 / watchOS 11 / visionOS 2
  (`Synchronization.Mutex`). Verified: full test suite on macOS, device
  builds for iOS and watchOS.

### Fixed
- macOS: `SwaTexView` rendered formulas vertically flipped in real windows
  (iOS was unaffected). The updateLayer bitmap was pre-flipped based on
  `layer.render(in:)` readbacks — an API that applies
  `contentsAreFlipped()` itself when entered at the content layer, showing
  the opposite of actual compositing. Contents are now upright;
  orientation is regression-tested through superview `cacheDisplay`
  (screen-faithful) across AppKit hosting, `NSViewRepresentable` inside
  SwiftUI, and pure SwiftUI `MathView`.
- Stack-overflow DoS: deeply nested input that passed the 512-level
  recursion-count guard could SIGBUS the process on 512 KB stacks (Swift
  Concurrency cooperative threads — including the parallel batch API — and
  test workers; parse overflowed at ~350 levels in release). The parser now
  also probes actual stack headroom (pthread stack bounds, computed once
  per parse; zero measured cost) and throws
  `ParseError.recursionLimitExceeded` instead. Found while extending test
  coverage.

### Fixed (platform)
- watchOS build: sized-font cache key used `CGFloat.native.bitPattern`,
  which is 32-bit on arm64_32.

### Performance
- Engine 29.1 → 16.3 µs/formula on the full golden corpus — 2.4× the Rust
  reference on identical corpora (`\ce` subset 100 → 42). Wins:
  hand-rolled byte scanners for size parsing (P-014), ICU-backed then
  hand-rolled mhchem tokenizer patterns keyed by exact regex source with
  ICU fallback (P-015/P-016/P-019), Substring threading (P-018), memoized
  SVG path parsing (P-020), renderer CGColor/font caches (P-017),
  index-resolved mhchem state machine (P-023), ordered-pair objects (P-024).
- `SwaTexView` (AppKit) renders via `updateLayer`: the view owns its
  rasterized bitmap and scrolling/redisplay never re-rasterizes glyphs —
  re-rasterization happens only on content, backing-scale, or flip changes
  (P-022). UIKit `contentMode` fixed from `.redraw` to `.topLeft` (no
  re-rasterization on bounds changes). 200-block editor first paint
  276 → 84 µs/cell.

### Fixed
- mhchem hand matchers now reproduce ICU's *actual* character classes
  (`\s` = `\p{White_Space}` incl. VT/NEL; `.`/`$` line-terminator sets
  incl. VT/FF; `$` never matches inside CRLF), pinned by a differential
  suite against live `NSRegularExpression` over corpus suffixes and edge
  inputs.
- mhchem `findObserveGroups` delimiter scanning is scalar-wise (Rust byte
  semantics): a combining mark on a closing brace no longer throws
  `extraClose`.
- Size-group scanning is KaTeX-correct ASCII (`\d` per KaTeX's JS, where
  Swift/Rust regex `\d` accepted Unicode digits), pinned by
  `SizeScannerDiffTests`.

## 0.1.0 — 2026-07-09

Initial release. Complete Swift port of the RaTeX engine (KaTeX-compatible
math rendering), verified numerically identical to the Rust reference over
its full 1190-formula golden corpus.

### Engine
- Lexer, macro expander (full KaTeX builtin macro set, `\def`/`\edef`/`\let`/
  `\futurelet`/`\expandafter`, `\newcommand`), KaTeX-compatible parser
  (all function handlers + 34 environments), mhchem `\ce`/`\pu`
  (byte-identical to reference on a 253-case corpus), TeX layout engine
  driven by KaTeX font metrics, flat `DisplayList` output (JSON
  wire-compatible with RaTeX).
- 99 %+ of the KaTeX support table; beyond-KaTeX:
  bussproofs proof trees, built-in mhchem, `\DeclareMathOperator`.
- KaTeX-correctness fixes over RaTeX: `\edef` expansion order,
  `\noexpand` protection scope.

### Rendering
- `SwaTexRender`: CoreText/CoreGraphics backend with bundled KaTeX fonts
  (no font registration side effects), glyph-run batching, sized-font and
  glyph-ID caches, SwiftUI `MathView`, fast PNG export
  (Accelerate + libz level-1; parallel batch API).
- SVG backend with byte-exact RaTeX-compatible output.

### Performance
- ~28 µs/formula parse+layout on the golden corpus — faster than the Rust
  reference engine.
- 100 PNGs in 4.0 ms via the parallel batch API (5–7× the Rust renderer).
- 314× formula cache for repeated content; 6× multicore batch layout.

### Testing
- 482 tests / 63 suites; ~90 % line coverage; 1190 cross-engine golden
  fixtures asserted on every run; PNG encoder round-trip pixel-identity
  tests; benchmarks gated behind `SWATEX_BENCH=1`.
