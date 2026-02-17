#!/usr/bin/env python3
"""Generate consolidated samples.tsv and units.tsv for each platform directory.

Reads existing per-coverage HG003_*.units.tsv files, replaces EXPERIMENTID
with the coverage label, and writes a single units.tsv per platform.
Copies the shared HG003.samples.tsv as samples.tsv into each platform dir.
"""

import os
import re
import shutil
from pathlib import Path

BASE = Path(__file__).parent
SAMPLES_SRC = BASE / "HG003.samples.tsv"

PLATFORM_DIRS = ["ilmn-solo", "ug-solo", "pb-solo", "ont-solo", "sentdhio"]

# Coverage sort key: extract numeric value for sorting
def cov_sort_key(label):
    """Sort coverage labels numerically. Handles 0.1x, 0p1x, 1p5x, etc."""
    s = label.lower().rstrip("x")
    s = s.replace("p", ".")
    try:
        return float(s)
    except ValueError:
        return 0.0


def consolidate_platform(platform_dir):
    """Read all per-coverage units files and write consolidated units.tsv."""
    pdir = BASE / platform_dir
    if not pdir.is_dir():
        print(f"  SKIP: {pdir} not found")
        return

    # Find all per-coverage units files
    pattern = re.compile(r"^HG003_(.+)\.units\.tsv$")
    cov_files = {}
    for f in sorted(pdir.iterdir()):
        m = pattern.match(f.name)
        if m:
            cov_label = m.group(1)
            cov_files[cov_label] = f

    if not cov_files:
        print(f"  SKIP: no per-coverage files in {pdir}")
        return

    # Sort by numeric coverage
    sorted_covs = sorted(cov_files.keys(), key=cov_sort_key)

    header = None
    rows = []
    for cov_label in sorted_covs:
        fpath = cov_files[cov_label]
        with open(fpath) as fh:
            lines = [l.rstrip("\n\r") for l in fh if l.strip()]
        if not lines:
            continue
        if header is None:
            header = lines[0]
        # Data row(s) — usually just 1
        for row in lines[1:]:
            fields = row.split("\t")
            # EXPERIMENTID is column index 2 — replace with coverage label
            fields[2] = cov_label
            rows.append("\t".join(fields))

    if header is None:
        print(f"  SKIP: no valid data in {pdir}")
        return

    # Write consolidated units.tsv
    units_out = pdir / "units.tsv"
    with open(units_out, "w") as fh:
        fh.write(header + "\n")
        for row in rows:
            fh.write(row + "\n")

    # Copy samples.tsv
    samples_out = pdir / "samples.tsv"
    shutil.copy2(SAMPLES_SRC, samples_out)

    print(f"  {platform_dir}: {len(rows)} coverages -> units.tsv, samples.tsv")
    for cov in sorted_covs:
        print(f"    {cov}")


def main():
    print(f"Source samples: {SAMPLES_SRC}")
    if not SAMPLES_SRC.exists():
        print(f"ERROR: {SAMPLES_SRC} not found")
        return

    for pdir in PLATFORM_DIRS:
        print(f"\nProcessing {pdir}:")
        consolidate_platform(pdir)

    print("\nDone.")


if __name__ == "__main__":
    main()

