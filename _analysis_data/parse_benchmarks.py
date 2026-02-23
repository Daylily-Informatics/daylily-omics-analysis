#!/usr/bin/env python3
"""Parse benchmark TSVs and generate platform_benchmarks_summary.tsv."""

from pathlib import Path
import pandas as pd

BASE = Path(__file__).resolve().parent

BENCHMARKS = {
    "agbt_ont":          {"platform": "ONT",    "units": 10},
    "ilmn_hg003_prod":   {"platform": "ILMN",   "units": 9},
    "pb_hg003_rerun":    {"platform": "PacBio",  "units": 8},
    "agbt_ug":           {"platform": "Ultima",  "units": 10},
}

rows = []
for bm_key, meta in BENCHMARKS.items():
    path = BASE / "benchmarks" / f"{bm_key}_benchmarks.tsv"
    if not path.exists():
        print(f"WARN: {path} not found, skipping")
        continue
    df = pd.read_csv(path, sep="\t")

    total_cost = df["task_cost"].sum()
    total_secs = df["s"].sum()
    total_wall_hrs = total_secs / 3600.0
    nproc = df["nproc"].iloc[0] if "nproc" in df.columns else 192
    total_vcpu_hrs = (nproc * total_secs) / 3600.0
    avg_cpu_eff = df["cpu_efficiency"].mean()
    n_units = meta["units"]
    cost_per_unit = total_cost / n_units

    # Top 3 rules by aggregated cost
    rule_costs = df.groupby("rule")["task_cost"].sum().sort_values(ascending=False)
    top3 = list(rule_costs.head(3).items())

    row = {
        "platform": meta["platform"],
        "n_units": n_units,
        "total_cost_usd": round(total_cost, 4),
        "cost_per_unit_usd": round(cost_per_unit, 4),
        "total_wall_hours": round(total_wall_hrs, 2),
        "total_vcpu_hours": round(total_vcpu_hrs, 1),
        "avg_cpu_efficiency": round(avg_cpu_eff, 4),
        "top_rule_1": top3[0][0] if len(top3) > 0 else "",
        "top_rule_1_cost": round(top3[0][1], 4) if len(top3) > 0 else 0,
        "top_rule_2": top3[1][0] if len(top3) > 1 else "",
        "top_rule_2_cost": round(top3[1][1], 4) if len(top3) > 1 else 0,
        "top_rule_3": top3[2][0] if len(top3) > 2 else "",
        "top_rule_3_cost": round(top3[2][1], 4) if len(top3) > 2 else 0,
    }
    rows.append(row)

out = pd.DataFrame(rows)
out_path = BASE / "platform_benchmarks_summary.tsv"
out.to_csv(out_path, sep="\t", index=False)
print(f"Saved: {out_path}")
print(out.to_string(index=False))

