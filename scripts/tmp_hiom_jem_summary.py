#!/usr/bin/env python3
import pandas as pd

BASE = "_analysis_data/agbt_benchmark_alignment_concordance_stats/hiom_jem"

# === CONCORDANCE ===
c = pd.read_csv(f"{BASE}/giab_concordance_mqc.tsv", sep="\t")
print("=" * 60)
print("CONCORDANCE SUMMARY")
print("=" * 60)
print(f"Rows: {len(c)}")
print(f"Unique samples: {c['Sample'].nunique()}")
print(f"VariantClasses: {sorted(c['VariantClass'].unique())}")
print(f"ROIs: {sorted(c['ROI'].unique())}")
print(f"Aligners: {sorted(c['Aligner'].unique())}")
print(f"SNVCallers: {sorted(c['SNVCaller'].unique())}")
print()

# F-score summary for key classes
for sc in ["SNPts", "SNPtv", "DEL_50", "INS_50"]:
    sub = c[c["VariantClass"] == sc]
    if len(sub) == 0:
        continue
    for fp in sorted(sub["ROI"].unique()):
        fsub = sub[sub["ROI"] == fp]
        print(f"\n--- {sc} | {fp} ---")
        cols = ["Sample", "Aligner", "SNVCaller", "Fscore", "Sensitivity-Recall", "PPV"]
        display = fsub[cols].copy()
        display["Fscore"] = display["Fscore"].apply(lambda x: f"{x:.6f}" if pd.notna(x) else "NA")
        display["Sensitivity-Recall"] = display["Sensitivity-Recall"].apply(lambda x: f"{x:.6f}" if pd.notna(x) else "NA")
        display["PPV"] = display["PPV"].apply(lambda x: f"{x:.6f}" if pd.notna(x) else "NA")
        display["SR_cov"] = display["Sample"].str.extract(r"SR(\d+)x")[0]
        display["ONT_cov"] = display["Sample"].str.extract(r"ONT(\d+)x")[0]
        display = display.sort_values(["SR_cov", "ONT_cov"])
        print(display[["SR_cov", "ONT_cov", "Aligner", "SNVCaller", "Fscore", "Sensitivity-Recall", "PPV"]].to_string(index=False))

# === ALIGNSTATS (COVERAGE) ===
print("\n" + "=" * 60)
print("COVERAGE SUMMARY (WgsCoverageMean / Median)")
print("=" * 60)
a = pd.read_csv(f"{BASE}/alignstats_combo_mqc.tsv", sep="\t")
if "WgsCoverageMean" in a.columns:
    a["SR_cov"] = a["sample"].str.extract(r"SR(\d+)x")[0]
    a["ONT_cov"] = a["sample"].str.extract(r"ONT(\d+)x")[0]
    display_a = a[["sample", "aligner", "WgsCoverageMean", "WgsCoverageMedian", "SR_cov", "ONT_cov"]].copy()
    display_a["WgsCoverageMean"] = display_a["WgsCoverageMean"].apply(lambda x: f"{x:.2f}")
    display_a = display_a.sort_values(["SR_cov", "ONT_cov"])
    print(display_a[["SR_cov", "ONT_cov", "aligner", "WgsCoverageMean", "WgsCoverageMedian"]].to_string(index=False))

# === BENCHMARKS ===
print("\n" + "=" * 60)
print("BENCHMARK SUMMARY")
print("=" * 60)
b = pd.read_csv(f"{BASE}/benchmarks_summary.tsv", sep="\t")
print(f"Rows: {len(b)}")
print(f"Unique rules: {sorted(b['rule'].unique())}")
print()

rule_summary = b.groupby("rule").agg(
    count=("s", "count"),
    mean_seconds=("s", "mean"),
    max_seconds=("s", "max"),
    mean_max_rss_mb=("max_rss", "mean"),
    total_task_cost=("task_cost", lambda x: x.dropna().sum()),
).reset_index()
rule_summary["mean_seconds"] = rule_summary["mean_seconds"].apply(lambda x: f"{x:.1f}")
rule_summary["max_seconds"] = rule_summary["max_seconds"].apply(lambda x: f"{x:.1f}")
rule_summary["mean_max_rss_mb"] = rule_summary["mean_max_rss_mb"].apply(lambda x: f"{x:.1f}" if pd.notna(x) else "NA")
rule_summary["total_task_cost"] = rule_summary["total_task_cost"].apply(lambda x: f"${x:.2f}")
print(rule_summary.to_string(index=False))

total_cost = b["task_cost"].dropna().sum()
print(f"\nTOTAL ESTIMATED COST: ${total_cost:.2f}")

print("\nTOP 10 MOST EXPENSIVE JOBS:")
top = b.nlargest(10, "task_cost")[["sample", "rule", "s", "max_rss", "task_cost", "instance_type"]].copy()
top["s"] = top["s"].apply(lambda x: f"{x:.0f}")
top["task_cost"] = top["task_cost"].apply(lambda x: f"${x:.2f}")
top["max_rss"] = top["max_rss"].apply(lambda x: f"{x:.0f}" if pd.notna(x) else "NA")
print(top.to_string(index=False))

