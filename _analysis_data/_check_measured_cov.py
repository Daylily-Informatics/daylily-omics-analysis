#!/usr/bin/env python3
"""Check target vs measured coverage for ILMN and ONT single-platform runs."""
import csv
import re
from pathlib import Path

BASE = Path(__file__).resolve().parent

files = {
    "ILMN": BASE / "ilmn_hg003_prod" / "alignstats_combo_mqc.tsv",
    "ONT": BASE / "agbt_ont" / "alignstats_combo_mqc.tsv",
}

for label, tsv in files.items():
    print(f"\n=== {label} ({tsv.name}) ===")
    if not tsv.exists():
        print("  FILE NOT FOUND")
        continue
    print(f"  {'Target':>6}  {'Measured':>8}  {'Ratio':>6}  Sample")
    with open(tsv) as f:
        reader = csv.DictReader(f, delimiter="\t")
        rows = []
        for row in reader:
            m = re.search(r"-(\d+)x-", row["sample"])
            if not m:
                continue
            target = int(m.group(1))
            measured = float(row["WgsCoverageMean"])
            ratio = measured / target if target > 0 else 0
            rows.append((target, measured, ratio, row["sample"]))
        for target, measured, ratio, sample in sorted(rows):
            flag = " *** SKIP (corrupt)" if label == "ONT" and target == 30 else ""
            print(f"  {target:>4}x  {measured:>8.2f}x  {ratio:>5.2f}x  {sample}{flag}")

# Also check concordance coverage levels
print("\n=== Concordance footprints available ===")
for label, tsv in [
    ("ILMN", BASE / "ilmn_hg003_prod" / "giab_concordance_mqc.tsv"),
    ("ONT", BASE / "agbt_ont" / "giab_concordance_mqc.tsv"),
]:
    if not tsv.exists():
        print(f"  {label}: FILE NOT FOUND")
        continue
    footprints = set()
    covs = set()
    with open(tsv) as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            if row["VariantClass"] == "SNPts":
                footprints.add(row.get("ROI", ""))
                m = re.search(r"-(\d+)x-", row["Sample"])
                if m:
                    covs.add(int(m.group(1)))
    print(f"  {label}: footprints={sorted(footprints)}, target_covs={sorted(covs)}")

