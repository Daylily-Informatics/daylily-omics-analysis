#!/usr/bin/env python3
"""Audit new src_data directories not yet in consolidation script."""
import csv
import os
from collections import Counter

SRC = "_analysis_data/agbt_benchmark_alignment_concordance_stats/src_data"

NEW_DIRS = [
    "hiomr_one",
    "hiomr_two",
    "hiomr_three",
    "hiomr_four",
    "pangenome_A",
    "pangenome_B",
    "ug_pangenome_a",
]

for d in NEW_DIRS:
    dpath = os.path.join(SRC, d)
    print(f"\n{'='*70}")
    print(f"  {d}")
    print(f"{'='*70}")

    # List files
    files = sorted(os.listdir(dpath)) if os.path.isdir(dpath) else []
    print(f"  Files: {files}")

    # Find concordance TSV
    conc = None
    for f in files:
        if "concordance" in f and f.endswith(".tsv"):
            conc = os.path.join(dpath, f)
            break
    if not conc:
        # Check subdirs
        for f in files:
            sub = os.path.join(dpath, f)
            if os.path.isdir(sub):
                for sf in os.listdir(sub):
                    if "concordance" in sf and sf.endswith(".tsv"):
                        conc = os.path.join(sub, sf)
                        break

    if not conc or not os.path.exists(conc):
        print(f"  NO concordance TSV found!")
        continue

    print(f"  Concordance: {conc}")
    sz = os.path.getsize(conc)
    print(f"  Size: {sz} bytes")
    if sz == 0:
        print(f"  EMPTY FILE")
        continue

    with open(conc) as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        cols = reader.fieldnames
        rows = list(reader)

    print(f"  Columns: {cols[:6]}... ({len(cols)} total)")
    print(f"  Rows: {len(rows)}")

    # Check column names (SNPClass vs VariantClass)
    vc_col = "VariantClass" if "VariantClass" in cols else "SNPClass" if "SNPClass" in cols else None
    roi_col = "ROI" if "ROI" in cols else "CmpFootprint" if "CmpFootprint" in cols else None
    print(f"  VC column: {vc_col}  |  ROI column: {roi_col}")

    # Samples
    samples = sorted(set(r.get("Sample", "") for r in rows))
    print(f"  Samples ({len(samples)}): {samples[:5]}{'...' if len(samples) > 5 else ''}")

    # Aligners
    al = Counter(r.get("Aligner", "") for r in rows)
    print(f"  Aligners: {dict(al)}")

    # Callers
    cal = Counter(r.get("SNVCaller", "") for r in rows)
    print(f"  Callers: {dict(cal)}")

    # VariantClasses
    vcs = sorted(set(r.get(vc_col, "") for r in rows)) if vc_col else []
    print(f"  VariantClasses: {vcs}")

    # ROIs
    rois = sorted(set(r.get(roi_col, "") for r in rows)) if roi_col else []
    print(f"  ROIs: {rois}")

    # Sample name patterns (first 3)
    print(f"  Sample examples:")
    for s in samples[:5]:
        print(f"    {s}")

    # Alignstats?
    align_file = None
    for f in files:
        if "alignstats_combo" in f:
            align_file = os.path.join(dpath, f)
            break
    print(f"  Alignstats: {'YES - ' + align_file if align_file else 'NO'}")

