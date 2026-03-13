#!/usr/bin/env python3
import pandas as pd

BASE = "_analysis_data/agbt_benchmark_alignment_concordance_stats"
hiom = pd.read_csv(f"{BASE}/hiom_jem/giab_concordance_mqc.tsv", sep="\t")
cons = pd.read_csv(f"{BASE}/consolidated_concordance.tsv", sep="\t")

print("=== hiom_jem ===")
print(f"Rows: {len(hiom)}")
print(f"Columns: {list(hiom.columns)}")
print(f"Unique samples: {hiom['Sample'].nunique()}")
print(f"Sample examples: {sorted(hiom['Sample'].unique())[:5]}")
print(f"Aligners: {sorted(hiom['Aligner'].unique())}")
print(f"SNVCallers: {sorted(hiom['SNVCaller'].unique())}")
print(f"ROIs: {sorted(hiom['ROI'].unique())}")

print("\n=== consolidated ===")
print(f"Rows: {len(cons)}")
print(f"Columns: {list(cons.columns)}")
print(f"Unique samples: {cons['Sample'].nunique()}")
if "TestGroup" in cons.columns:
    print(f"TestGroups: {sorted(cons['TestGroup'].dropna().unique())}")

# Check overlap by Sample name
hiom_samples = set(hiom["Sample"].unique())
cons_samples = set(cons["Sample"].unique())
overlap = hiom_samples & cons_samples
only_hiom = hiom_samples - cons_samples

print(f"\n=== OVERLAP ===")
print(f"hiom_jem unique samples: {len(hiom_samples)}")
print(f"Overlap with consolidated: {len(overlap)}")
print(f"Only in hiom_jem (not in consolidated): {len(only_hiom)}")
if only_hiom:
    for s in sorted(only_hiom)[:10]:
        print(f"  {s}")
if overlap:
    print(f"Overlapping samples:")
    for s in sorted(overlap)[:10]:
        print(f"  {s}")

# Check by mqc_id for more precise matching
hiom_ids = set(hiom["mqc_id"].unique())
cons_ids = set(cons["mqc_id"].unique())
id_overlap = hiom_ids & cons_ids
print(f"\nmqc_id overlap: {len(id_overlap)} of {len(hiom_ids)} hiom_jem IDs found in consolidated")
ids_only_hiom = hiom_ids - cons_ids
if ids_only_hiom:
    print(f"IDs only in hiom_jem: {len(ids_only_hiom)}")
    for i in sorted(ids_only_hiom)[:5]:
        print(f"  {i}")
if id_overlap:
    print(f"Example overlapping IDs:")
    for i in sorted(id_overlap)[:5]:
        print(f"  {i}")

