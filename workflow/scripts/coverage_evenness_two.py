#!/usr/bin/env python3
"""Compute coverage evenness metrics for BAM/CRAM files.

This script reads coverage depth using samtools depth and summarises basic
metrics for fixed-size windows across the genome.

For each window the following metrics are reported:
    - mean depth
    - median depth
    - standard deviation of depth
    - coefficient of variation (stdev/mean)
    - evenness score approximated as exp(-cv)
    - percentage of bases with depth >=0.2x mean
    - percentage of bases with depth >=0.5x mean
The output is a TSV with one line per window.

The implementation is intentionally simple and is not intended to be highly
optimised.  It demonstrates the expected interface for a more performant
future implementation.
"""

import argparse
import math
import statistics
import subprocess
import sys
from pathlib import Path


def process_window(chrom: str, start: int, depths, out):
    """Write statistics for a completed window."""
    if not depths:
        return
    n = len(depths)
    mean = sum(depths) / n
    median = statistics.median(depths)
    stdev = statistics.pstdev(depths)
    cv = stdev / mean if mean else 0.0
    even = math.exp(-cv)
    thr20 = 0.2 * mean
    thr50 = 0.5 * mean
    pct20 = sum(d >= thr20 for d in depths) / n * 100.0
    pct50 = sum(d >= thr50 for d in depths) / n * 100.0
    end = start + n
    out.write(
        f"{chrom}\t{start}\t{end}\t{mean:.4f}\t{median:.4f}\t{stdev:.4f}\t{cv:.4f}\t{even:.4f}\t{pct20:.2f}\t{pct50:.2f}\n"
    )


def coverage_evenness_two(bam: Path, window: int, outfile: Path):
    cmd = ["samtools", "depth", "-a", str(bam)]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)
    current_chr = None
    start_pos = None
    depths = []
    with outfile.open("w") as out:
        out.write(
            "chrom\tstart\tend\tmean\tmedian\tstdev\tcv\tevenness\tpct_gt_0.2xmean\tpct_gt_0.5xmean\n"
        )
        for line in proc.stdout:
            chrom, pos, depth = line.strip().split("\t")
            pos = int(pos)
            depth = int(depth)
            if current_chr is None:
                current_chr = chrom
                start_pos = pos
            if chrom != current_chr or len(depths) >= window:
                process_window(current_chr, start_pos, depths, out)
                depths = []
                current_chr = chrom
                start_pos = pos
            depths.append(depth)
        process_window(current_chr, start_pos, depths, out)
    proc.stdout.close()
    retcode = proc.wait()
    if retcode != 0:
        raise RuntimeError(f"samtools depth failed with return code {retcode}")


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("bam", help="Input BAM/CRAM file")
    p.add_argument("output", help="Output TSV file")
    p.add_argument("--window", type=int, default=100000, help="Window size")
    args = p.parse_args(argv)
    coverage_evenness_two(Path(args.bam), args.window, Path(args.output))


if __name__ == "__main__":
    main()
