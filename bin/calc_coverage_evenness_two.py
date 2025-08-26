#!/usr/bin/env python3
"""Calculate coverage evenness metrics over windows.

Reads `samtools depth` output from STDIN and writes windowed metrics to STDOUT.
The metrics match those produced by the previous gawk implementation in
``workflow/rules/calc_coverage_evenness_two.smk``.

Example
-------
    samtools depth -a sample.cram | \
        bin/calc_coverage_evenness_two.py --window 100000 > metrics.tsv
"""

from __future__ import annotations

import argparse
import math
import sys
from statistics import median
from typing import Iterable, List


def process_window(chrom: str, start: int, depths: List[float], out):
    """Compute and write metrics for a window of depths."""
    count = len(depths)
    if count == 0:
        return

    mean = sum(depths) / count
    med = median(depths)
    sumsq = sum((d - mean) ** 2 for d in depths)
    sd = math.sqrt(sumsq / count) if count > 0 else 0.0
    cv = sd / mean if mean > 0 else 0.0
    even = math.exp(-cv)

    thr20 = 0.2 * mean
    thr50 = 0.5 * mean
    gt20 = sum(1 for d in depths if d >= thr20)
    gt50 = sum(1 for d in depths if d >= thr50)
    pct20 = 100 * gt20 / count
    pct50 = 100 * gt50 / count

    end = start + count - 1
    out.write(
        f"{chrom}\t{start}\t{end}\t{mean:.4f}\t{med:.4f}\t{sd:.4f}\t{cv:.4f}\t{even:.4f}\t{pct20:.2f}\t{pct50:.2f}\n"
    )


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-w",
        "--window",
        type=int,
        default=100000,
        help="Number of positions per window (default: 100000)",
    )
    args = parser.parse_args(argv)

    out = sys.stdout
    out.write(
        "chrom\tstart\tend\tmean\tmedian\tstdev\tcv\tevenness\tpct_gt_0.2xmean\tpct_gt_0.5xmean\n"
    )

    current_chrom = None
    start_pos = None
    depths: List[float] = []
    expected_pos = None

    for line in sys.stdin:
        if not line.strip():
            continue
        chrom, pos_s, depth_s = line.split()[:3]
        pos = int(pos_s)
        depth = float(depth_s)

        if current_chrom is None:
            current_chrom = chrom
            start_pos = pos
            expected_pos = pos

        flush = False
        if chrom != current_chrom:
            flush = True
        elif len(depths) >= args.window or (expected_pos is not None and pos > expected_pos):
            flush = True

        if flush:
            process_window(current_chrom, start_pos, depths, out)
            depths = []
            current_chrom = chrom
            start_pos = pos

        depths.append(depth)
        expected_pos = pos + 1

    if depths:
        process_window(current_chrom, start_pos, depths, out)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
