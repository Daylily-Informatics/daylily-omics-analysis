#!/usr/bin/env python3
"""
Downsample paired-end FASTQ(.gz) by pair with a given fraction.

Example:
  python3 downsample_paired_fastq.py \
    -1 HG001_30x_R1.fastq.gz -2 HG001_30x_R2.fastq.gz \
    -f 0.1 -s 42 \
    -o1 HG001_3x_R1.fastq.gz -o2 HG001_3x_R2.fastq.gz
"""

import argparse, gzip, io, os, random, sys
from typing import TextIO

def open_maybe_gzip(path: str, mode: str) -> TextIO:
    # Large buffer for speed
    if "r" in mode and "b" not in mode:
        buffering = 1024 * 1024
    else:
        buffering = -1
    if path.endswith(".gz"):
        if "r" in mode:
            return gzip.open(path, mode, encoding="utf-8", newline="")
        else:
            # compresslevel 5 is a good speed/size balance
            return gzip.open(path, mode, compresslevel=5, encoding="utf-8", newline="")
    else:
        return open(path, mode, buffering=buffering, encoding="utf-8", newline="")

def norm_name(h: str) -> str:
    """
    Normalize a FASTQ header to the read name used for pair matching.
    Uses first whitespace-delimited token and strips leading '@' and any trailing '/1' or '/2'.
    """
    t = h.strip().split()[0]
    if t.startswith("@"):
        t = t[1:]
    if t.endswith("/1") or t.endswith("/2"):
        t = t[:-2]
    return t

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-1", "--r1", required=True, help="R1 FASTQ(.gz)")
    ap.add_argument("-2", "--r2", required=True, help="R2 FASTQ(.gz)")
    ap.add_argument("-f", "--fraction", required=True, type=float, help="Keep fraction (0..1)")
    ap.add_argument("-s", "--seed", type=int, default=42, help="Random seed (default: 42)")
    ap.add_argument("-o1", "--out1", required=True, help="Output R1 FASTQ(.gz)")
    ap.add_argument("-o2", "--out2", required=True, help="Output R2 FASTQ(.gz)")
    ap.add_argument("--no-check-names", action="store_true",
                    help="Skip read name consistency check (faster, but riskier).")
    args = ap.parse_args()

    if not (0.0 <= args.fraction <= 1.0):
        sys.exit("ERROR: --fraction must be in [0,1].")

    rng = random.Random(args.seed)
    total = 0
    kept = 0

    with open_maybe_gzip(args.r1, "rt") as f1, open_maybe_gzip(args.r2, "rt") as f2, \
         open_maybe_gzip(args.out1, "wt") as o1, open_maybe_gzip(args.out2, "wt") as o2:
        while True:
            h1 = f1.readline()
            if not h1:
                break
            s1 = f1.readline(); p1 = f1.readline(); q1 = f1.readline()
            h2 = f2.readline(); s2 = f2.readline(); p2 = f2.readline(); q2 = f2.readline()

            total += 1
            if not args.no-check-names:
                if norm_name(h1) != norm_name(h2):
                    sys.stderr.write(
                        f"ERROR: Read name mismatch at pair {total}:\nR1: {h1}R2: {h2}\n"
                    )
                    sys.exit(2)

            if rng.random() < args.fraction:
                o1.write(h1); o1.write(s1); o1.write(p1); o1.write(q1)
                o2.write(h2); o2.write(s2); o2.write(p2); o2.write(q2)
                kept += 1

    ratio = (kept / total) if total else 0.0
    sys.stderr.write(f"# pairs processed: {total}\n# pairs kept: {kept} (~{ratio:.6f})\n")

if __name__ == "__main__":
    main()
