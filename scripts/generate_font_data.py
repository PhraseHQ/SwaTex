#!/usr/bin/env python3
# NOTE: after regenerating, run: xcrun swift format --in-place --configuration .swift-format --recursive Sources

"""Convert RaTeX's generated Rust font data tables to Swift.

Sources (auto-generated from KaTeX's fontMetricsData.js / symbols.ts):
  crates/ratex-font/src/data/metrics_data.rs  -> Sources/SwaTex/Font/MetricsData.swift
  crates/ratex-font/src/data/symbols_data.rs  -> Sources/SwaTex/Font/SymbolsData.swift

Usage: generate_font_data.py <ratex-root> <swatex-root>
"""

import re
import sys
from pathlib import Path

RUST_TO_SWIFT_TABLE = {
    "AMS_REGULAR": "amsRegular",
    "CALIGRAPHIC_REGULAR": "caligraphicRegular",
    "FRAKTUR_REGULAR": "frakturRegular",
    "FRAKTUR_BOLD": "frakturBold",
    "MAIN_BOLD": "mainBold",
    "MAIN_BOLDITALIC": "mainBoldItalic",
    "MAIN_ITALIC": "mainItalic",
    "MAIN_REGULAR": "mainRegular",
    "MATH_BOLDITALIC": "mathBoldItalic",
    "MATH_ITALIC": "mathItalic",
    "SANSSERIF_BOLD": "sansSerifBold",
    "SANSSERIF_ITALIC": "sansSerifItalic",
    "SANSSERIF_REGULAR": "sansSerifRegular",
    "SCRIPT_REGULAR": "scriptRegular",
    "SIZE1_REGULAR": "size1Regular",
    "SIZE2_REGULAR": "size2Regular",
    "SIZE3_REGULAR": "size3Regular",
    "SIZE4_REGULAR": "size4Regular",
    "TYPEWRITER_REGULAR": "typewriterRegular",
}

METRICS_HEADER = """\
// Auto-generated from KaTeX fontMetricsData.js via RaTeX metrics_data.rs — DO NOT EDIT
// Regenerate with scripts/generate_font_data.py

/// Each entry is (charCode, depth, height, italic, skew, width), sorted by charCode.
typealias MetricsEntry = (code: UInt32, depth: Double, height: Double, italic: Double, skew: Double, width: Double)

enum MetricsData {
"""

SYMBOLS_HEADER = """\
// Auto-generated from KaTeX symbols.ts via RaTeX symbols_data.rs — DO NOT EDIT
// Regenerate with scripts/generate_font_data.py

/// Symbol definition: (name, mode, font, group, codepoint)
/// mode: 0 = math, 1 = text
/// font: 0 = main, 1 = ams
typealias SymbolEntry = (name: String, mode: UInt8, font: UInt8, group: String, codepoint: Unicode.Scalar?)

enum SymbolsData {
    static let symbols: [SymbolEntry] = [
"""


def convert_metrics(rust: str) -> str:
    out = [METRICS_HEADER]
    table = None
    entries = []
    for line in rust.splitlines():
        m = re.match(r"pub static (\w+): &\[MetricsEntry\] = &\[", line)
        if m:
            table = RUST_TO_SWIFT_TABLE[m.group(1)]
            entries = []
            continue
        if table is not None:
            if line.strip() == "];":
                out.append(f"    static let {table}: [MetricsEntry] = [")
                out.extend(f"        {e}" for e in entries)
                out.append("    ]\n")
                table = None
                continue
            entry = line.strip()
            if entry.startswith("("):
                entries.append(entry)  # Rust and Swift tuple literals coincide
    out.append("}")
    return "\n".join(out) + "\n"


def rust_char_to_swift_scalar(rust_char: str) -> str:
    """'\\u{2261}' -> "\\u{2261}", '(' -> "(", '\\\\' -> "\\\\", '"' -> "\\\"" """
    inner = rust_char[1:-1]  # strip single quotes
    if inner == '"':
        inner = '\\"'
    return f'"{inner}"'


SYMBOL_RE = re.compile(
    r'^\("((?:[^"\\]|\\.)*)", ([01]), ([01]), "([a-z-]+)", (None|Some\(\'(?:[^\'\\]|\\.)*\'\))\),$'
)


def convert_symbols(rust: str) -> str:
    out = [SYMBOLS_HEADER]
    count = 0
    for line in rust.splitlines():
        line = line.strip()
        if not line.startswith('("'):
            continue
        m = SYMBOL_RE.match(line)
        if not m:
            raise SystemExit(f"unparsed symbol line: {line!r}")
        name, mode, font, group, cp = m.groups()
        if cp == "None":
            scalar = "nil"
        else:
            scalar = rust_char_to_swift_scalar(cp[len("Some(") : -1])
        out.append(f'        ("{name}", {mode}, {font}, "{group}", {scalar}),')
        count += 1
    out.append("    ]")
    out.append("}")
    print(f"symbols: {count} entries")
    return "\n".join(out) + "\n"


def main() -> None:
    ratex, swatex = Path(sys.argv[1]), Path(sys.argv[2])
    data = ratex / "crates/ratex-font/src/data"
    font_dir = swatex / "Sources/SwaTex/Font"
    font_dir.mkdir(parents=True, exist_ok=True)

    (font_dir / "MetricsData.swift").write_text(
        convert_metrics((data / "metrics_data.rs").read_text())
    )
    (font_dir / "SymbolsData.swift").write_text(
        convert_symbols((data / "symbols_data.rs").read_text())
    )
    print("done")


if __name__ == "__main__":
    main()
