#!/usr/bin/env python3
"""Parse benchmark TSVs into per-unit, per-stage granular data.

Outputs:
  per_unit_benchmarks.tsv         – one row per unit (coverage level) with totals + per-stage costs/walltimes
  per_unit_per_stage_benchmarks.tsv – one row per unit per rule with stage classification
"""

import re
from pathlib import Path

import pandas as pd

BASE = Path(__file__).resolve().parent
COV_RE = re.compile(r"-(\d+)x-")

BENCHMARKS = {
    "agbt_ont":        {"platform": "ONT"},
    "ilmn_hg003_prod": {"platform": "ILMN"},
    "pb_hg003_rerun":  {"platform": "PacBio"},
    "agbt_ug":         {"platform": "Ultima"},
}

STAGE_ORDER = ["alignment", "markdup", "variant_calling", "concordance", "alignstats", "other"]


def categorize_stage(rule: str) -> str:
    """Map a Snakemake rule name to a pipeline stage category."""
    if "concordance" in rule:
        return "concordance"
    if "alignstats" in rule:
        return "alignstats"
    if "mrkdup" in rule:
        return "markdup"
    if "alNsort" in rule:
        return "alignment"
    if any(vc in rule for vc in ("sentd", "sentdont", "sentdpb", "sentdug")):
        return "variant_calling"
    return "other"


def extract_nominal_cov(sample: str):
    m = COV_RE.search(sample)
    return int(m.group(1)) if m else None


all_stages = []
all_units = []

for bm_key, meta in BENCHMARKS.items():
    path = BASE / "benchmarks" / f"{bm_key}_benchmarks.tsv"
    if not path.exists():
        print(f"WARN: {path} not found, skipping")
        continue
    df = pd.read_csv(path, sep="\t")

    # Drop aggregation rows (sample="all.")
    df = df[~df["sample"].str.startswith("all.")]

    # Coerce numeric columns (some rows have NA)
    for col in ("task_cost", "s", "max_rss", "cpu_efficiency", "snakemake_threads"):
        df[col] = pd.to_numeric(df[col], errors="coerce").fillna(0)

    df["platform"] = meta["platform"]
    df["nominal_cov"] = df["sample"].apply(extract_nominal_cov)
    df["stage"] = df["rule"].apply(categorize_stage)

    # Per-stage detail rows
    for _, row in df.iterrows():
        all_stages.append({
            "platform": meta["platform"],
            "sample": row["sample"],
            "nominal_cov": row["nominal_cov"],
            "rule": row["rule"],
            "stage": row["stage"],
            "cost_usd": round(row["task_cost"], 6),
            "wall_sec": round(row["s"], 2),
            "wall_min": round(row["s"] / 60, 2),
            "max_rss_mb": round(row["max_rss"], 1),
            "cpu_efficiency": round(row["cpu_efficiency"], 4),
            "snakemake_threads": int(row["snakemake_threads"]),
        })

    # Per-unit aggregates
    for sample, grp in df.groupby("sample"):
        nom = grp["nominal_cov"].iloc[0]
        stage_costs = grp.groupby("stage")["task_cost"].sum()
        stage_walls = grp.groupby("stage")["s"].sum()

        unit_row = {
            "platform": meta["platform"],
            "sample": sample,
            "nominal_cov": nom,
            "total_cost_usd": round(grp["task_cost"].sum(), 6),
            "total_wall_sec": round(grp["s"].sum(), 2),
            "total_wall_min": round(grp["s"].sum() / 60, 2),
            "peak_rss_mb": round(grp["max_rss"].max(), 1),
        }
        for stage in STAGE_ORDER:
            unit_row[f"{stage}_cost"] = round(stage_costs.get(stage, 0), 6)
            unit_row[f"{stage}_wall_sec"] = round(stage_walls.get(stage, 0), 2)
        all_units.append(unit_row)

# ---- Write outputs ----
stages_df = pd.DataFrame(all_stages)
stages_path = BASE / "per_unit_per_stage_benchmarks.tsv"
stages_df.to_csv(stages_path, sep="\t", index=False)
print(f"Saved: {stages_path} ({len(stages_df)} rows)")

units_df = pd.DataFrame(all_units).sort_values(["platform", "nominal_cov"])
units_path = BASE / "per_unit_benchmarks.tsv"
units_df.to_csv(units_path, sep="\t", index=False)
print(f"Saved: {units_path} ({len(units_df)} rows)")

# ---- Print summary ----
print("\n=== Per-Unit Cost & Walltime ===")
note = ("NOTE: ONT and Ultima benchmarks do not include alignment (pre-aligned input).\n"
        "      ILMN and PacBio benchmarks include alignment.\n")
print(note)
for plat in ["ILMN", "ONT", "PacBio", "Ultima"]:
    sub = units_df[units_df["platform"] == plat]
    if sub.empty:
        continue
    print(f"{plat} ({len(sub)} units):")
    for _, r in sub.iterrows():
        print(f"  {r['nominal_cov']:3.0f}x: ${r['total_cost_usd']:.4f} | "
              f"{r['total_wall_min']:.1f} min | "
              f"align=${r['alignment_cost']:.4f}  vc=${r['variant_calling_cost']:.4f}  "
              f"conc=${r['concordance_cost']:.4f}  stats=${r['alignstats_cost']:.4f}")
    print()

