#!/usr/bin/env python3
"""Summarize ont_filler coverage and giabHC All F-scores, sorted by measured median."""
import csv
import os

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ont_filler", "ont_patch")

# Load alignstats
align = {}
with open(f"{BASE}/alignstats_combo_mqc.tsv") as f:
    for r in csv.DictReader(f, delimiter="\t"):
        base = r["sample"].rsplit(".", 1)[0]
        align[base] = (float(r["WgsCoverageMean"]), int(float(r["WgsCoverageMedian"])))

# Load giabHC All F-scores
fscores = {}
with open(f"{BASE}/giab_concordance_mqc.tsv") as f:
    for r in csv.DictReader(f, delimiter="\t"):
        if r["ROI"] == "giabHC" and r["VariantClass"] == "All":
            fscores[r["Sample"]] = float(r["Fscore"]) if r["Fscore"] else None

# Combine and sort by measured median, then mean
rows = []
for sample in sorted(set(align.keys()) | set(fscores.keys())):
    mean, median = align.get(sample, (0, 0))
    fs = fscores.get(sample)
    rows.append((sample, mean, median, fs))

rows.sort(key=lambda x: (x[2], x[1]))

hdr = f"{'Sample':<55} {'MeasMean':>10} {'MeasMed':>8} {'giabHC All F':>14}"
print(hdr)
print("-" * len(hdr))
for s, m, md, fs in rows:
    fs_str = f"{fs:.4f}" if fs else "---"
    print(f"{s:<55} {m:>10.3f} {md:>8} {fs_str:>14}")

