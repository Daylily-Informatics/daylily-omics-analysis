#!/usr/bin/env python3
"""Consolidate giab_concordance_mqc.tsv from three sources into one deduplicated file."""
import pandas as pd
import sys

BASE = "etc"
sources = ["deep19", "deep19b", "ont"]
# ont_all appears to be a superset/duplicate of ont — skip it

frames = []
for src in sources:
    path = f"{BASE}/{src}/giab_concordance_mqc.tsv"
    try:
        df = pd.read_csv(path, sep="\t")
        print(f"{src}: {len(df)} rows, {df.columns.tolist()[:3]}...")
        df["_source"] = src
        frames.append(df)
    except Exception as e:
        print(f"ERROR reading {path}: {e}", file=sys.stderr)

combined = pd.concat(frames, ignore_index=True)
print(f"\nCombined (before dedup): {len(combined)} rows")

# Deduplicate on mqc_id (the unique row identifier)
before = len(combined)
deduped = combined.drop_duplicates(subset=["mqc_id"], keep="first")
after = len(deduped)
print(f"After dedup on mqc_id:   {after} rows  (removed {before - after} duplicates)")

# Show which sources contributed duplicates
if before != after:
    dupes = combined[combined.duplicated(subset=["mqc_id"], keep=False)]
    print(f"\nDuplicate mqc_ids found across sources:")
    for mid in dupes["mqc_id"].unique()[:5]:
        srcs = dupes[dupes["mqc_id"] == mid]["_source"].tolist()
        print(f"  {mid}: appears in {srcs}")
    if len(dupes["mqc_id"].unique()) > 5:
        print(f"  ... and {len(dupes['mqc_id'].unique()) - 5} more")

# Drop helper column and write
deduped = deduped.drop(columns=["_source"])
outpath = f"{BASE}/giab_concordance_mqc.tsv"
deduped.to_csv(outpath, sep="\t", index=False)
print(f"\nWrote {len(deduped)} unique rows to {outpath}")

# Quick summary
print(f"\nSummary:")
print(f"  Unique samples:     {deduped['Sample'].nunique()}")
print(f"  Unique AltIds:      {deduped['AltId'].nunique()}")
print(f"  Unique SNVCallers:  {sorted(deduped['SNVCaller'].unique())}")
print(f"  Unique Aligners:    {sorted(deduped['Aligner'].unique())}")
print(f"  Unique ROIs: {sorted(deduped['ROI'].unique())}")

