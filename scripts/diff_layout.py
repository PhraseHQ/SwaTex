#!/usr/bin/env python3
"""Differential layout test: RaTeX (Rust) vs SwaTex (Swift).

Feeds the same formula corpus to both engines' `layout` dump CLIs and compares
box metrics, display-list metrics and display-list item counts.

A handful of corpus formulas are *meant* to differ: SwaTex deliberately follows
KaTeX where RaTeX shares an upstream bug. Those are listed, with reasons, in
`Tests/SwaTexTests/Resources/golden/ratex_divergences.json`, which this script
reads so that an expected divergence is reported apart from a regression.

Exit status is 0 only when every difference is an expected divergence and every
expected divergence actually showed up; anything else exits 1.

That exit status is a parity gate only against the RaTeX revision the golden
fixtures were cut from (see "Provenance" in BENCHMARKS.md). RaTeX's layout
engine keeps moving, so run against a newer upstream a REGRESSION line may be
an upstream change SwaTex has not ported rather than a fault here; triage
before acting. Note too that RaTeX's dump also runs `validate_layout`, its
output-item resource guard, and prints an error row when the budget is
exceeded, which `LayoutDump` has no counterpart for — that shows up as an
`error-mismatch` and needs adversarial input to reach, not a corpus formula.

Usage:
  diff_layout.py <formulas.txt> <rust_layout_bin> <swift_layoutdump_bin>
                 [--tol 1e-4] [--divergences PATH | --no-divergences]
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

DEFAULT_DIVERGENCES = (
    Path(__file__).resolve().parent.parent
    / "Tests/SwaTexTests/Resources/golden/ratex_divergences.json"
)

# Dimensions compared on each side of the dump. The golden suites assert the
# display-list dimensions, since those are what renderers consume; the box is
# the pre-display LayoutBox and is compared too, because a mismatch there is
# worth seeing even when the display list agrees.
DIMENSIONS = ("width", "height", "depth")


def run(binary: str, formulas: str) -> list[dict]:
    try:
        proc = subprocess.run(
            [binary], input=formulas, capture_output=True, text=True, timeout=600
        )
    except subprocess.TimeoutExpired:
        sys.exit(f"{binary} did not finish the corpus within 600s")
    if proc.returncode != 0:
        # Not fatal on its own — a short dump shows up as a count mismatch —
        # but without stderr the cause is invisible.
        tail = proc.stderr.strip().splitlines()[-5:]
        print(f"WARNING: {binary} exited {proc.returncode}: " + " / ".join(tail))
    results = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line:
            results.append(json.loads(line))
    return results


def load_divergences(path: Path) -> dict[str, str]:
    """Map each deliberately divergent input to the reason it diverges."""
    doc = json.loads(path.read_text())
    reasons: dict[str, str] = {}
    for group in doc["divergences"]:
        for formula in group["inputs"]:
            reasons[formula] = group["reason"]
    return reasons


def compare(rust: dict, swift: dict, tol: float) -> str | None:
    """Describe how two dumps of one formula differ, or None if they agree."""
    if bool(rust.get("error")) != bool(swift.get("error")):
        return f"error-mismatch rust={bool(rust.get('error'))} swift={bool(swift.get('error'))}"
    if rust.get("error"):
        return None

    worst, where = 0.0, ""
    for side in ("box", "displayList"):
        for dim in DIMENSIONS:
            delta = abs(rust[side][dim] - swift[side][dim])
            if delta > worst:
                worst, where = delta, f"{side}.{dim}"

    items = (rust["displayList"]["itemCount"], swift["displayList"]["itemCount"])
    if items[0] != items[1]:
        return f"itemCount {items[0]} vs {items[1]}" + (
            f", {where} off by {worst:.6f}" if worst > tol else ""
        )
    if worst > tol:
        return f"{where} off by {worst:.6f}"
    return None


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Differential layout test: RaTeX (Rust) vs SwaTex (Swift)."
    )
    parser.add_argument("formulas", help="one formula per line")
    parser.add_argument("rust_bin", help="RaTeX ratex-layout binary")
    parser.add_argument("swift_bin", help="SwaTex LayoutDump binary")
    parser.add_argument("--tol", type=float, default=1e-4, help="dimension tolerance (em)")
    parser.add_argument(
        "--divergences",
        type=Path,
        default=DEFAULT_DIVERGENCES,
        help="expected-divergence manifest (default: the golden corpus's)",
    )
    parser.add_argument(
        "--no-divergences",
        action="store_const",
        const=None,
        dest="divergences",
        help="treat every difference as a regression",
    )
    parser.add_argument("--show", type=int, default=40, help="how many differences to list")
    args = parser.parse_args()

    if args.divergences and not args.divergences.exists():
        sys.exit(
            f"no divergence manifest at {args.divergences} — "
            "pass --divergences PATH, or --no-divergences to treat every "
            "difference as a regression"
        )
    reasons = load_divergences(args.divergences) if args.divergences else {}

    formulas = "\n".join(
        line.strip() for line in Path(args.formulas).read_text().splitlines() if line.strip()
    )
    rust = run(args.rust_bin, formulas + "\n")
    swift = run(args.swift_bin, formulas + "\n")

    failures = []
    if len(rust) != len(swift):
        failures.append(f"COUNT MISMATCH: rust={len(rust)} swift={len(swift)}")

    agreed = 0
    expected: list[tuple[str, str, str]] = []
    unexpected: list[tuple[str, str]] = []
    seen: set[str] = set()

    for line_no, (r, s) in enumerate(zip(rust, swift), start=1):
        formula = r["input"]
        # Both dumps echo their input, so a pair that disagrees means the two
        # streams have gone out of step — one engine printed an extra or a
        # short line. Every later pair would then be compared against the
        # wrong formula, so stop rather than report a page of phantom
        # regressions.
        if formula != s.get("input"):
            failures.append(
                f"DESYNC at output line {line_no}: rust {formula!r} vs swift {s.get('input')!r}"
            )
            break
        seen.add(formula)
        difference = compare(r, s, args.tol)
        if difference is None:
            agreed += 1
        elif formula in reasons:
            expected.append((formula, difference, reasons[formula]))
        else:
            unexpected.append((formula, difference))

    # A listed formula that no longer differs means the manifest is stale: the
    # divergence was undone, or RaTeX adopted the same behavior.
    stale = sorted((seen & reasons.keys()) - {formula for formula, _, _ in expected})

    print(
        f"total={len(rust)} agreed={agreed} "
        f"expected_divergence={len(expected)} unexpected={len(unexpected)} stale={len(stale)}"
    )

    for formula, difference in unexpected[: args.show]:
        print(f"REGRESSION: {formula!r}: {difference}")
    if len(unexpected) > args.show:
        print(f"... and {len(unexpected) - args.show} more regressions")
    for formula in stale[: args.show]:
        print(f"STALE DIVERGENCE (matches RaTeX now, drop it from the manifest): {formula!r}")
    if len(stale) > args.show:
        print(f"... and {len(stale) - args.show} more stale divergences")

    if unexpected:
        failures.append(f"{len(unexpected)} unexpected difference(s)")
    if stale:
        failures.append(f"{len(stale)} stale divergence(s)")
    if failures:
        print("FAIL: " + "; ".join(failures))
        sys.exit(1)
    print("OK: every difference is a documented KaTeX-correct divergence")


if __name__ == "__main__":
    main()
