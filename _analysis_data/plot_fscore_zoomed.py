#!/usr/bin/env python3
"""Plot F-scores by measured coverage, zoomed to 0.9–1.0 Y-axis."""

import re
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

BASE = Path(__file__).resolve().parent

WORKFLOWS = {
    "agbt_ont":                    {"platform": "ONT"},
    "agbt_ug":                     {"platform": "Ultima"},
    "ilmn_hg003_prod":             {"platform": "ILMN"},
    "pb_hg003_prod":               {"platform": "PacBio"},
    "roche_hg003_coverage_series": {"platform": "Roche"},
}
FOOTPRINT = "giabHC_x_clinvar_genes"
SNP_CLASSES = ["SNPts", "SNPtv", "INS_50", "DEL_50", "Indel_50"]
COV_RE = re.compile(r"-(\d+)x-")

COLORS = {"ILMN": "#0072B2", "ONT": "#D55E00", "PacBio": "#009E73", "Roche": "#F0E442", "Ultima": "#CC79A7"}
MARKERS = {"ILMN": "o", "ONT": "s", "PacBio": "^", "Roche": "v", "Ultima": "D"}

# --- Load alignstats ---
align_frames = []
for wf, meta in WORKFLOWS.items():
    p = BASE / wf / "alignstats_combo_mqc.tsv"
    if not p.exists():
        continue
    df = pd.read_csv(p, sep="\t", usecols=["sample", "WgsCoverageMean", "WgsCoverageMedian"])
    df["sample_base"] = df["sample"].str.rsplit(".", n=1).str[0]
    df["platform"] = meta["platform"]
    align_frames.append(df[["sample_base", "platform", "WgsCoverageMean"]])
alignstats = pd.concat(align_frames, ignore_index=True)

# --- Load concordance ---
conc_frames = []
for wf, meta in WORKFLOWS.items():
    p = BASE / wf / "giab_concordance_mqc.tsv"
    if not p.exists():
        continue
    df = pd.read_csv(p, sep="\t")
    mask = (df["ROI"] == FOOTPRINT) & (df["VariantClass"].isin(SNP_CLASSES))
    sub = df.loc[mask, ["Sample", "VariantClass", "Fscore"]].copy()
    sub["platform"] = meta["platform"]
    conc_frames.append(sub)
conc = pd.concat(conc_frames, ignore_index=True)

merged = conc.merge(alignstats, left_on=["Sample", "platform"],
                    right_on=["sample_base", "platform"], how="left")

# --- Plot: zoomed 0.9–1.0 ---
fig, axes = plt.subplots(1, 5, figsize=(24, 5.5), sharey=True)

for i, snp_cls in enumerate(SNP_CLASSES):
    ax = axes[i]
    sub = merged[merged["VariantClass"] == snp_cls]
    for plat in sorted(sub["platform"].unique()):
        ps = sub[sub["platform"] == plat].sort_values("WgsCoverageMean")
        ax.plot(ps["WgsCoverageMean"], ps["Fscore"],
                color=COLORS.get(plat, "gray"),
                marker=MARKERS.get(plat, "x"),
                label=plat, linewidth=2, markersize=7)
    ax.set_title(snp_cls, fontsize=13, fontweight="bold")
    ax.set_xlabel("Measured Mean Coverage (x)", fontsize=11)
    ax.grid(True, alpha=0.3)
    ax.set_xlim(0, 58)
    ax.set_ylim(0.9, 1.0)
    ax.yaxis.set_major_locator(plt.MultipleLocator(0.01))
    ax.yaxis.set_minor_locator(plt.MultipleLocator(0.005))
    ax.grid(True, which="minor", alpha=0.15)
    if i == 0:
        ax.set_ylabel("F-score", fontsize=12)
    if i == len(SNP_CLASSES) - 1:
        ax.legend(fontsize=9, loc="lower right")

fig.suptitle("HG003 — F-score vs Measured Coverage (zoomed 0.90–1.00)\n"
             f"Footprint: {FOOTPRINT}",
             fontsize=14, fontweight="bold", y=1.04)
fig.tight_layout()
out = BASE / "all_platforms_fscore_by_measured_cov_zoomed.png"
fig.savefig(out, dpi=150, bbox_inches="tight")
plt.close(fig)
print(f"Saved: {out}")

