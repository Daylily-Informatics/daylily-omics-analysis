#!/usr/bin/env python3
"""Find any INS_50 cell with FP > 10K in the data."""
import json, csv, re
from pathlib import Path

# 1. Check hybrid data
with open("_analysis_data/hioa_data.json") as f:
    data = json.load(f)

print("=== Hybrid INS_50 cells with FP > 1000 ===")
for u in data["units"]:
    for fp_key, fp_name in [("concordance","giabHC"), ("concordance_clinvar","clinvar"), ("concordance_hg38","hg38")]:
        c = u.get(fp_key, {}).get("INS_50", {})
        if c and c.get("FP", 0) > 1000:
            print(f"  SR{u['sr_cov']:>2}x-ONT{u['ont_cov']:>2}x {fp_name}: F={c['Fscore']:.4f} TP={c['TP']} FN={c['FN']} FP={c['FP']}")

# 2. Check single-platform data
print("\n=== Single-platform INS_50 (all footprints) ===")
for label, path in [
    ("ILMN", "_analysis_data/ilmn_hg003_prod/giab_concordance_mqc.tsv"),
    ("ONT", "_analysis_data/agbt_ont/giab_concordance_mqc.tsv"),
]:
    print(f"\n--- {label} ---")
    with open(path) as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            if row["VariantClass"] != "INS_50":
                continue
            m = re.search(r"-(\d+)x-", row["Sample"])
            if not m:
                continue
            cov = int(m.group(1))
            fp_filter = row.get("ROI", "")
            fs = float(row["Fscore"])
            tp = int(float(row["TP"]))
            fn = int(float(row["FN"]))
            fp = int(float(row["FP"]))
            print(f"  {cov:>2}x {fp_filter:>15}: F={fs:.4f}  TP={tp:>9}  FN={fn:>9}  FP={fp:>9}")

# 3. Check: does the All FP ever < sum of subclass FPs?
print("\n=== Sanity: All.FP vs sum-of-subclasses FP (hybrid giabHC) ===")
for u in data["units"]:
    c = u.get("concordance", {})
    if not c or "All" not in c:
        continue
    all_fp = c["All"]["FP"]
    sub_fp = sum(c[k]["FP"] for k in c if k != "All")
    if sub_fp != all_fp:
        print(f"  SR{u['sr_cov']:>2}x-ONT{u['ont_cov']:>2}x: All.FP={all_fp}  sum={sub_fp}  diff={sub_fp - all_fp}")
    # Check if any subclass FP > All FP
    for k in c:
        if k == "All":
            continue
        if c[k]["FP"] > all_fp:
            print(f"  *** SR{u['sr_cov']:>2}x-ONT{u['ont_cov']:>2}x {k}: FP={c[k]['FP']} > All.FP={all_fp}")

