#!/usr/bin/env python3
"""
extract_zip_gbk.py
eton@261008;
Extract Windows-created ZIP archives whose filenames are stored in a legacy
code page (typically GBK / cp936) *without* the UTF-8 flag set.

Fixes mojibake on Debian 13 where `unzip -O` is not available.
When a ZIP entry does not have the UTF‑8 flag (bit 0x800) set, Python's zipfile decodes the filename as CP437. CP437 maps every byte value 0x00–0xFF, so info.filename.encode("cp437") gives you back the original raw bytes — which you can then decode with the real code page (gbk / cp936).

Usage:
    python3 extract_zip_gbk.py archive.zip
    python3 extract_zip_gbk.py archive.zip -o outdir
    python3 extract_zip_gbk.py archive.zip -e gbk
    python3 extract_zip_gbk.py archive.zip -e auto      # default
"""

import argparse
import os
import sys
import zipfile
from pathlib import Path

CANDIDATES = ["gbk", "gb18030", "big5", "shift_jis", "utf-8"]


# ---------- raw name recovery ------------------------------------------------

def raw_name(info: zipfile.ZipInfo) -> bytes:
    """Return the original filename bytes as stored in the archive."""
    if info.flag_bits & 0x800:
        # UTF-8 flag set -> filename is already valid Unicode.
        return info.filename.encode("utf-8")
    # zipfile decoded the raw bytes as cp437; cp437 is reversible.
    return info.filename.encode("cp437")


# ---------- encoding detection -----------------------------------------------

# Characters that strongly indicate a wrong single-byte decoding
MOJIBAKE_FINGERPRINTS = set(
    "\u2500\u2502\u250C\u2510\u2514\u2518\u251C\u2524\u252C\u2534\u253C"  # box drawing single
    "\u2550\u2551\u2554\u2557\u255A\u255D\u2560\u2563\u2566\u2569\u256C"  # box drawing double
    "\u2568\u255C"                                                        # partial double
    "\u2591\u2592\u2593\u2588\u2584\u258C\u2590"                          # shade / block
    "\u03B1\u03B2\u03B3\u03C0\u03C3\u03A3\u03A9\u03BC"                    # Greek letters
    "\u00A0\u00A1\u00A2\u00A3\u00A5\u00A7\u00A9\u00AB\u00BB\u00BF"        # Latin-1 punctuation
    "\u00B0\u00B1\u00B2\u00B3\u00B5\u00B6\u00B7\u00B8\u00B9\u00BA\u00BC\u00BD\u00BE"  # Latin-1 symbols
)

def _score_text(s: str) -> int:
    score = 0
    for ch in s:
        code = ord(ch)
        if 0x4E00 <= code <= 0x9FFF:        # CJK Unified Ideographs
            score += 3
        elif 0x3400 <= code <= 0x4DBF:      # CJK Extension A
            score += 2
        elif 0x3000 <= code <= 0x303F:      # CJK punctuation
            score += 1
        elif 0xFF00 <= code <= 0xFFEF:      # fullwidth forms
            score += 1
        elif code == 0xFFFD:                # replacement character
            score -= 10
        elif code < 0x20:                   # control chars
            score -= 5
        elif ch in MOJIBAKE_FINGERPRINTS:   # <-- the new rule
            score -= 2
        # else: normal ASCII letters, digits, punctuation -> 0
    return score


def detect_encoding(names: list[bytes]) -> str:
    """Pick the candidate encoding that decodes all names most cleanly."""
    best, best_score = "gbk", float("-inf")
    for enc in CANDIDATES:
        total, ok = 0, True
        for raw in names:
            try:
                total += _score_text(raw.decode(enc))
            except UnicodeDecodeError:
                ok = False
                break
        if ok and total > best_score:
            best, best_score = enc, total
    return best


# ---------- extraction --------------------------------------------------------

def safe_join(base: Path, name: str) -> Path:
    """Join base + name, refusing path traversal outside base."""
    target = (base / name).resolve()
    base_r = base.resolve()
    if target != base_r and base_r not in target.parents:
        raise ValueError(f"Refusing unsafe path: {name!r}")
    return target


def extract(archive: str, outdir: str, encoding: str) -> None:
    base = Path(outdir).resolve()
    base.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(archive) as zf:
        infos = zf.infolist()

        if encoding == "auto":
            encoding = detect_encoding([raw_name(i) for i in infos])
            print(f"[i] Detected filename encoding: {encoding}")

        for info in infos:
            raw = raw_name(info)
            try:
                name = raw.decode(encoding)
            except UnicodeDecodeError:
                name = raw.decode(encoding, errors="replace")

            name = name.replace("\\", "/")   # Windows separators
            dest = safe_join(base, name)

            if info.is_dir() or name.endswith("/"):
                dest.mkdir(parents=True, exist_ok=True)
                print(f"[dir ] {name}")
                continue

            dest.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info) as src, open(dest, "wb") as dst:
                dst.write(src.read())
            print(f"[file] {name}")


# ---------- CLI ---------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(
        description="Extract a Windows ZIP with legacy-encoded filenames.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("archive", help="path to the .zip file")
    ap.add_argument("-o", "--output", default=None,
                    help="output directory (default: alongside archive, "
                         "named after it without the .zip suffix)")
    ap.add_argument("-e", "--encoding", default="auto",
                    help="filename encoding: gbk, gb18030, big5, shift_jis, "
                         "utf-8, or 'auto' (default: auto)")
    args = ap.parse_args()

    if args.output is None:
        args.output = str(Path(args.archive).with_suffix(""))

    try:
        extract(args.archive, args.output, args.encoding)
    except (zipfile.BadZipFile, ValueError) as e:
        print(f"[!] {e}", file=sys.stderr)
        return 1

    print(f"\n[✓] Extracted to: {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
