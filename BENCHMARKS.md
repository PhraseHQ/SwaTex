# Reproducing the benchmarks

Every number in the README was produced by the commands below. Published
figures: Apple Silicon (M-series, arm64), macOS 26, Xcode 26 /
Swift 6.3.2, `-c release`, user CPU time, **median of 3 runs**. Absolute
numbers vary by machine; the Swift-vs-Rust ratios have been stable.

## 1. Engine throughput (15.1 µs/formula, 2.6× the Rust reference)

The corpus is checked into this repo as the golden fixtures (2 541
formulas, of which **123 are deliberate error cases** — error output for
those is expected). Extract the inputs and stream them through the
`LayoutDump` CLI:

```sh
swift build -c release

python3 - <<'EOF'
import json, glob
lines = []
for f in sorted(glob.glob('Tests/SwaTexTests/Resources/golden/*.jsonl')):
    for l in open(f):
        s = json.loads(l)['input']
        if '\n' not in s:
            lines.append(s)
open('/tmp/corpus.txt', 'w').write('\n'.join(lines))
print(len(lines), 'formulas')
EOF

# 80 repetitions ≈ 203k formulas; median of 3:
for i in 1 2 3; do
  for _ in $(seq 80); do cat /tmp/corpus.txt; done > /tmp/corpus80.txt
  /usr/bin/time -p .build/release/LayoutDump < /tmp/corpus80.txt > /dev/null
done
# user seconds ÷ 203,280 = seconds per formula
```

**Rust side** (same protocol, same input file):

```sh
git clone https://github.com/erweixin/RaTeX && cd RaTeX
cargo build --release -p ratex-layout
/usr/bin/time -p target/release/ratex-layout < /tmp/corpus80.txt > /dev/null
```

Correctness gate for the comparison: `swift test` asserts all 2 541
fixtures numerically identical to the Rust engine's output (box
width/height/depth to 1e-5 em + display-list item counts), so both
engines are doing the same work.

## 2. Micro-benchmarks (cache hit 105 ns, phases, PNG)

All are env-gated test suites; timings print as `BENCH …` lines:

```sh
# Formula-cache hit, phase breakdown (parse/layout/display), batch scaling,
# hot/cold font cache, PNG encode share:
SWATEX_BENCH=1 swift test -c release -Xswiftc -enable-testing \
  --filter RenderBenchmarks

# PNG pipeline over corpus formulas (serial + parallel batch):
head -100 /tmp/corpus.txt > /tmp/corpus100.txt
SWATEX_CORPUS=/tmp/corpus100.txt swift test -c release -Xswiftc -enable-testing \
  --filter "ParallelPNGBench|CorpusPNGBench"

# Block-editor scroll simulation (200 cells; asserts 60 fps budgets):
SWATEX_BENCH=1 swift test -c release -Xswiftc -enable-testing \
  --filter editorScrollSimulation

# Interactive paths (typing = cache-miss per keystroke; scroll = warm):
SWATEX_PROFILE=1 swift test -c release -Xswiftc -enable-testing \
  --filter ProfileHarness
```

## 3. View-layer invariants (zero re-rasterization on scroll)

Not a timing but a counted invariant, enforced in the default suite on
every CI run: `ScrollRedrawTests` drives real AppKit display cycles and
asserts `rasterizationCount` stays at 1 across a full scroll pass, 0 on
forced redisplays and resizes, and exactly 1 per content change.

```sh
swift test --filter ScrollRedraw
```

## 4. README screenshots

```sh
SWATEX_SCREENSHOTS=.github/assets swift test --filter ScreenshotGenerator
```

## Provenance

- Golden fixtures were generated with RaTeX's `ratex-layout` (built from
  the RaTeX main branch, 2026-07-08) and are re-checked against the Swift
  engine on every `swift test`.
- The published Rust comparison used the same machine and the same input
  files for both engines, back to back.
