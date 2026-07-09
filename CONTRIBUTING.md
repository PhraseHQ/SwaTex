# Contributing to SwaTex

Thanks for helping build native math rendering for Apple platforms.

## Development setup

```sh
git clone https://github.com/PhraseHQ/SwaTex.git && cd SwaTex
swift build          # Xcode 16.3+ / Swift 6.1+
swift test           # 630+ tests, must stay green
swift run SwaTexDemo # interactive gallery (macOS)
```

## The correctness bar

SwaTex is verified against reference engines, and PRs are held to that:

- **2 541 golden fixtures** (`Tests/SwaTexTests/Resources/golden/`) assert
  numerically identical layout to the RaTeX Rust engine on every
  `swift test`. A layout change that shifts any box is either a bug or
  needs regenerated fixtures with justification.
- **Differential suites** pin hand-written fast paths to their reference
  implementations at runtime: mhchem matchers vs live ICU
  (`MhChemHandMatcherDiffTests`), size scanners vs the original regexes
  (`SizeScannerDiffTests`). If you optimize a parser path, add the same
  kind of differential test.
- Faithful-port rule: KaTeX behavior wins, including quirks. Deliberate
  divergences must be KaTeX-correct (see “Known limitations” in the
  README) and pinned by an explicit test.

## Formatting

CI enforces `swift format` with the repo config at zero findings:

```sh
xcrun swift format --in-place --configuration .swift-format --recursive Sources Tests
```

## Performance work

Include before/after measurements in the PR description — commands and
methodology are in [BENCHMARKS.md](BENCHMARKS.md) (median of 3, release,
user CPU time, machine disclosed). Regressions on the golden-corpus
throughput or the `ScrollRedrawTests` rasterization invariants block
merging.

## Regenerating generated data

`MetricsData.swift`, `SymbolsData.swift`, `KaTeXSvgData.swift`, and the
mhchem JSON are generated from upstream KaTeX by `scripts/` (marked
DO NOT EDIT). After regenerating, run the formatter and the full suite.

## PR checklist

- [ ] `swift test` green, zero build warnings
- [ ] `swift format lint --strict --configuration .swift-format --recursive Sources Tests` clean
- [ ] New behavior has tests; fixed bugs have regression tests
- [ ] Public API changes documented (doc comments + CHANGELOG entry)
