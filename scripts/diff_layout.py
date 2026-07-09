#!/usr/bin/env python3
"""Differential layout test: RaTeX (Rust) vs SwaTex (Swift).

Feeds the same formula corpus to both engines' `layout` dump CLIs and compares
box metrics (width/height/depth) and display-list item counts.

Usage:
  diff_layout.py <formulas.txt> <rust_layout_bin> <swift_layoutdump_bin> [--tol 1e-4]
"""

import json
import subprocess
import sys


def run(binary: str, formulas: str) -> list[dict]:
    proc = subprocess.run(
        [binary], input=formulas, capture_output=True, text=True, timeout=600
    )
    results = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line:
            results.append(json.loads(line))
    return results


def main() -> None:
    formulas_path, rust_bin, swift_bin = sys.argv[1:4]
    tol = float(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[4] == "--tol" else 1e-4

    with open(formulas_path) as f:
        lines = [l.strip() for l in f if l.strip()]
    formulas = "\n".join(lines) + "\n"

    rust = run(rust_bin, formulas)
    swift = run(swift_bin, formulas)

    if len(rust) != len(swift):
        print(f"COUNT MISMATCH: rust={len(rust)} swift={len(swift)}")

    exact = 0
    close = 0
    item_diff = 0
    box_diff = 0
    err_diff = 0
    diffs = []

    for r, s in zip(rust, swift):
        if r.get("error") or s.get("error"):
            if bool(r.get("error")) != bool(s.get("error")):
                err_diff += 1
                diffs.append((r["input"], "error-mismatch", r, s))
            else:
                exact += 1
            continue
        rb, sb = r["box"], s["box"]
        rd, sd = r["displayList"], s["displayList"]
        dmax = max(
            abs(rb["width"] - sb["width"]),
            abs(rb["height"] - sb["height"]),
            abs(rb["depth"] - sb["depth"]),
        )
        items_equal = rd["itemCount"] == sd["itemCount"]
        if dmax == 0 and items_equal:
            exact += 1
        elif dmax <= tol and items_equal:
            close += 1
        else:
            if not items_equal:
                item_diff += 1
            if dmax > tol:
                box_diff += 1
            diffs.append((r["input"], f"dmax={dmax:.6f}", rd["itemCount"], sd["itemCount"]))

    total = len(rust)
    print(f"total={total} exact={exact} close(≤{tol})={close} "
          f"box_diff={box_diff} item_diff={item_diff} err_mismatch={err_diff}")
    for d in diffs[:40]:
        print("DIFF:", d)
    if len(diffs) > 40:
        print(f"... and {len(diffs) - 40} more")


if __name__ == "__main__":
    main()
