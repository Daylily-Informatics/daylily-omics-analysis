#!/usr/bin/env python3
"""Generate platform cost comparison bar charts from benchmark data."""

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

BASE = Path(__file__).resolve().parent

COLORS = {
    "ILMN": "#0072B2", "ONT": "#D55E00", "PacBio": "#009E73",
    "Roche": "#F0E442", "Ultima": "#CC79A7",
}

df = pd.read_csv(BASE / "platform_benchmarks_summary.tsv", sep="\t")
df = df.sort_values("total_cost_usd")

# --- 1. Total cost comparison ---
fig, axes = plt.subplots(1, 3, figsize=(18, 5.5))

ax = axes[0]
bars = ax.barh(df["platform"], df["total_cost_usd"],
               color=[COLORS.get(p, "gray") for p in df["platform"]])
ax.set_xlabel("Total Cost (USD)", fontsize=11)
ax.set_title("Total Workflow Cost\n(all coverage levels)", fontsize=12, fontweight="bold")
for bar, val in zip(bars, df["total_cost_usd"]):
    ax.text(bar.get_width() + 0.2, bar.get_y() + bar.get_height() / 2,
            f"${val:.2f}", va="center", fontsize=10, fontweight="bold")
ax.set_xlim(0, df["total_cost_usd"].max() * 1.25)
ax.grid(axis="x", alpha=0.3)

# --- 2. Cost per unit ---
ax = axes[1]
bars = ax.barh(df["platform"], df["cost_per_unit_usd"],
               color=[COLORS.get(p, "gray") for p in df["platform"]])
ax.set_xlabel("Cost per Coverage Level (USD)", fontsize=11)
ax.set_title("Avg Cost per Unit\n(single coverage level)", fontsize=12, fontweight="bold")
for bar, val in zip(bars, df["cost_per_unit_usd"]):
    ax.text(bar.get_width() + 0.05, bar.get_y() + bar.get_height() / 2,
            f"${val:.2f}", va="center", fontsize=10, fontweight="bold")
ax.set_xlim(0, df["cost_per_unit_usd"].max() * 1.25)
ax.grid(axis="x", alpha=0.3)

# --- 3. CPU efficiency ---
ax = axes[2]
bars = ax.barh(df["platform"], df["avg_cpu_efficiency"],
               color=[COLORS.get(p, "gray") for p in df["platform"]])
ax.set_xlabel("Avg CPU Efficiency (%)", fontsize=11)
ax.set_title("Mean CPU Efficiency\n(across all rules)", fontsize=12, fontweight="bold")
for bar, val in zip(bars, df["avg_cpu_efficiency"]):
    ax.text(bar.get_width() + 0.3, bar.get_y() + bar.get_height() / 2,
            f"{val:.1f}%", va="center", fontsize=10, fontweight="bold")
ax.set_xlim(0, df["avg_cpu_efficiency"].max() * 1.3)
ax.grid(axis="x", alpha=0.3)

fig.suptitle("HG003 Coverage Series — Compute Cost & Efficiency by Platform\n"
             "Instance: m7i.48xlarge (192 vCPU), Spot @ $2.96/hr, us-west-2d",
             fontsize=14, fontweight="bold", y=1.05)
fig.tight_layout()
out = BASE / "platform_cost_comparison.png"
fig.savefig(out, dpi=150, bbox_inches="tight")
plt.close(fig)
print(f"Saved: {out}")

# --- 4. Cost breakdown by top rules (stacked bar) ---
fig, ax = plt.subplots(figsize=(10, 5))
platforms = df["platform"].tolist()
top1 = df["top_rule_1_cost"].tolist()
top2 = df["top_rule_2_cost"].tolist()
top3 = df["top_rule_3_cost"].tolist()
other = [t - (a + b + c) for t, a, b, c in zip(df["total_cost_usd"], top1, top2, top3)]

ax.barh(platforms, top1, label="Top rule (variant calling)", color="#2563eb")
ax.barh(platforms, top2, left=top1, label="2nd rule (concordance/alignment)", color="#7c3aed")
ax.barh(platforms, top3, left=[a + b for a, b in zip(top1, top2)],
        label="3rd rule", color="#db2777")
ax.barh(platforms, other, left=[a + b + c for a, b, c in zip(top1, top2, top3)],
        label="Other", color="#9ca3af")

ax.set_xlabel("Cost (USD)", fontsize=11)
ax.set_title("Cost Breakdown by Pipeline Stage", fontsize=12, fontweight="bold")
ax.legend(fontsize=9, loc="lower right")
ax.grid(axis="x", alpha=0.3)
fig.tight_layout()
out2 = BASE / "platform_cost_breakdown.png"
fig.savefig(out2, dpi=150, bbox_inches="tight")
plt.close(fig)
print(f"Saved: {out2}")

