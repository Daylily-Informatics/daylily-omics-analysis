#!/usr/bin/env python3
"""Generate per-unit cost and walltime plots from granular benchmark data.

Outputs:
  per_unit_cost_vs_coverage.png      – line plot: total cost by nominal coverage per platform
  per_unit_walltime_vs_coverage.png  – line plot: total walltime by nominal coverage per platform
  per_unit_cost_by_stage.png         – 2×2 stacked bar: cost by stage for each unit, faceted by platform
  per_unit_walltime_by_stage.png     – 2×2 stacked bar: walltime by stage, faceted by platform
"""

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

BASE = Path(__file__).resolve().parent

COLORS = {"ILMN": "#0072B2", "ONT": "#D55E00", "PacBio": "#009E73", "Ultima": "#CC79A7"}
MARKERS = {"ILMN": "o", "ONT": "s", "PacBio": "^", "Ultima": "D"}
STAGE_COLORS = {
    "alignment": "#2563eb",
    "variant_calling": "#7c3aed",
    "concordance": "#db2777",
    "alignstats": "#f59e0b",
    "markdup": "#22c55e",
    "other": "#9ca3af",
}
STAGE_ORDER = ["alignment", "markdup", "variant_calling", "concordance", "alignstats", "other"]
PLATFORMS = ["ILMN", "ONT", "PacBio", "Ultima"]

df = pd.read_csv(BASE / "per_unit_benchmarks.tsv", sep="\t")

# ---------- Plot 1: Cost vs coverage (line) ----------
fig, ax = plt.subplots(figsize=(10, 6))
for plat in PLATFORMS:
    sub = df[df["platform"] == plat].sort_values("nominal_cov")
    ax.plot(sub["nominal_cov"], sub["total_cost_usd"],
            marker=MARKERS[plat], color=COLORS[plat], label=plat, linewidth=2, markersize=7)
ax.set_xlabel("Nominal Coverage (x)", fontsize=12)
ax.set_ylabel("Total Cost (USD)", fontsize=12)
ax.set_title("Per-Unit Cost by Coverage Level\nm7i.48xlarge spot @ ~$2.96/hr, us-west-2d",
             fontsize=13, fontweight="bold")
ax.legend(fontsize=10)
ax.grid(alpha=0.3)
fig.tight_layout()
out = BASE / "per_unit_cost_vs_coverage.png"
fig.savefig(out, dpi=150, bbox_inches="tight")
plt.close(fig)
print(f"Saved: {out}")

# ---------- Plot 2: Walltime vs coverage (line) ----------
fig, ax = plt.subplots(figsize=(10, 6))
for plat in PLATFORMS:
    sub = df[df["platform"] == plat].sort_values("nominal_cov")
    ax.plot(sub["nominal_cov"], sub["total_wall_min"],
            marker=MARKERS[plat], color=COLORS[plat], label=plat, linewidth=2, markersize=7)
ax.set_xlabel("Nominal Coverage (x)", fontsize=12)
ax.set_ylabel("Total Wall Time (minutes)", fontsize=12)
ax.set_title("Per-Unit Wall Time by Coverage Level\nm7i.48xlarge spot, us-west-2d",
             fontsize=13, fontweight="bold")
ax.legend(fontsize=10)
ax.grid(alpha=0.3)
fig.tight_layout()
out = BASE / "per_unit_walltime_vs_coverage.png"
fig.savefig(out, dpi=150, bbox_inches="tight")
plt.close(fig)
print(f"Saved: {out}")


def _stacked_bar_faceted(df, value_suffix, ylabel, title, out_path):
    """Draw a 2×2 faceted stacked-bar chart (one panel per platform)."""
    fig, axes = plt.subplots(2, 2, figsize=(16, 10))
    axes = axes.flatten()
    for idx, plat in enumerate(PLATFORMS):
        ax = axes[idx]
        sub = df[df["platform"] == plat].sort_values("nominal_cov")
        covs = sub["nominal_cov"].values
        x = np.arange(len(covs))
        bottom = np.zeros(len(covs))
        for stage in STAGE_ORDER:
            col = f"{stage}_{value_suffix}"
            if col not in sub.columns:
                continue
            vals = sub[col].values
            if value_suffix == "wall_sec":
                vals = vals / 60  # → minutes
            if vals.sum() < 0.001:
                continue
            ax.bar(x, vals, bottom=bottom, label=stage,
                   color=STAGE_COLORS[stage], width=0.7)
            bottom += vals
        ax.set_xticks(x)
        ax.set_xticklabels([f"{int(c)}x" for c in covs], fontsize=9)
        ax.set_xlabel("Nominal Coverage", fontsize=10)
        ax.set_ylabel(ylabel, fontsize=10)
        ax.set_title(plat, fontsize=12, fontweight="bold")
        ax.grid(axis="y", alpha=0.3)
        # Add total value label on top of each bar
        for i, total in enumerate(bottom):
            if value_suffix == "cost":
                lbl = f"${total:.2f}"
            else:
                lbl = f"{total:.0f}m"
            ax.text(i, total + bottom.max() * 0.02, lbl,
                    ha="center", va="bottom", fontsize=7, fontweight="bold")
        if idx == 0:
            ax.legend(fontsize=8, loc="upper left")
    fig.suptitle(title, fontsize=14, fontweight="bold")
    fig.tight_layout()
    fig.savefig(out_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved: {out_path}")


# ---------- Plot 3: Stacked cost by stage ----------
_stacked_bar_faceted(
    df, "cost", "Cost (USD)",
    "Cost Breakdown by Pipeline Stage per Unit",
    BASE / "per_unit_cost_by_stage.png",
)

# ---------- Plot 4: Stacked walltime by stage ----------
_stacked_bar_faceted(
    df, "wall_sec", "Wall Time (minutes)",
    "Wall Time Breakdown by Pipeline Stage per Unit",
    BASE / "per_unit_walltime_by_stage.png",
)

