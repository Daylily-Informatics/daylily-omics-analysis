#!/usr/bin/env python3
import csv, re

for label, tsv in [("ILMN", "_analysis_data/ilmn_hg003_prod/alignstats_combo_mqc.tsv"),
                   ("ONT", "_analysis_data/agbt_ont/alignstats_combo_mqc.tsv")]:
    print(f"\n=== {label} ===")
    hdr = f"{'Sample':<55} {'Target':>6} {'WgsCovMean':>10} {'WgsCovMedian':>12}"
    print(hdr)
    with open(tsv) as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            sample = row["sample"]
            m = re.search(r"-(\d+)x-", sample)
            target = int(m.group(1)) if m else "?"
            mean_cov = float(row["WgsCoverageMean"])
            median_cov = float(row["WgsCoverageMedian"])
            print(f"{sample:<55} {target:>6} {mean_cov:>10.2f} {median_cov:>12.0f}")

