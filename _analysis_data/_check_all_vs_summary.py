#!/usr/bin/env python3
"""Check whether the 'All' SNP class in hioa_data.json matches summary.txt totals."""
import json

with open("_analysis_data/hioa_data.json") as f:
    data = json.load(f)

# Find SR40x-ONT3x
for u in data["units"]:
    if u["sr_cov"] == 40 and u["ont_cov"] == 3:
        print(f"Unit: {u['unit']}")
        print(f"Status: {u['status']}")
        print()
        print("=== giabHC concordance (all classes) ===")
        c = u.get("concordance", {})
        total_tp = total_fn = total_fp = 0
        for cls in sorted(c.keys()):
            d = c[cls]
            print(f"  {cls:>12}: F={d['Fscore']:.4f}  TP={d['TP']:>9}  FN={d['FN']:>9}  FP={d['FP']:>9}")
            if cls != "All":
                total_tp += d["TP"]
                total_fn += d["FN"]
                total_fp += d["FP"]
        print(f"\n  Sum (excl All): TP={total_tp:>9}  FN={total_fn:>9}  FP={total_fp:>9}")
        print(f"  summary.txt:    TP={3783471:>9}  FN={48444:>9}  FP={3613:>9}  F=0.9932")
        all_d = c.get("All", {})
        if all_d:
            print(f"  All class:      TP={all_d['TP']:>9}  FN={all_d['FN']:>9}  FP={all_d['FP']:>9}  F={all_d['Fscore']:.4f}")
        break

