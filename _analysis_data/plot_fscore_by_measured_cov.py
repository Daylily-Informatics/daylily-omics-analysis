#!/usr/bin/env python3
"""Plot F-scores by measured (alignstats) coverage instead of nominal coverage."""

import re
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

BASE = Path(__file__).resolve().parent

WORKFLOWS = {
    "agbt_ont":                    {"platform": "ONT",     "aligner": "ont"},
    "agbt_ug":                     {"platform": "Ultima",  "aligner": "ug"},
    "ilmn_hg003_prod":             {"platform": "ILMN",    "aligner": "sent"},
    "pb_hg003_prod":               {"platform": "PacBio",  "aligner": "sentmm2"},
    "roche_hg003_coverage_series": {"platform": "Roche",   "aligner": "roche"},
}
FOOTPRINT = "giabHC_x_clinvar_genes"
SNP_CLASSES = ["SNPts", "SNPtv", "INS_50", "DEL_50", "Indel_50"]
COV_RE = re.compile(r"-(\d+)x-")

COLORS = {"ILMN": "#0072B2", "ONT": "#D55E00", "PacBio": "#009E73", "Roche": "#F0E442", "Ultima": "#CC79A7"}
MARKERS = {"ILMN": "o", "ONT": "s", "PacBio": "^", "Roche": "v", "Ultima": "D"}


def nom_cov(name: str):
    m = COV_RE.search(name)
    return int(m.group(1)) if m else None


# --- Load alignstats ---
align_frames = []
for wf, meta in WORKFLOWS.items():
    p = BASE / wf / "alignstats_combo_mqc.tsv"
    if not p.exists():
        continue
    df = pd.read_csv(p, sep="\t", usecols=["sample", "WgsCoverageMean", "WgsCoverageMedian"])
    df["sample_base"] = df["sample"].str.rsplit(".", n=1).str[0]
    df["platform"] = meta["platform"]
    align_frames.append(df[["sample_base", "platform", "WgsCoverageMean", "WgsCoverageMedian"]])
alignstats = pd.concat(align_frames, ignore_index=True)

# --- Load concordance ---
conc_frames = []
for wf, meta in WORKFLOWS.items():
    p = BASE / wf / "giab_concordance_mqc.tsv"
    if not p.exists():
        continue
    df = pd.read_csv(p, sep="\t")
    mask = (df["CmpFootprint"] == FOOTPRINT) & (df["SNPClass"].isin(SNP_CLASSES))
    sub = df.loc[mask, ["Sample", "SNPClass", "Fscore", "Sensitivity-Recall", "Precision"]].copy()
    sub["platform"] = meta["platform"]
    conc_frames.append(sub)
conc = pd.concat(conc_frames, ignore_index=True)

# --- Merge to get measured coverage per concordance row ---
merged = conc.merge(alignstats, left_on=["Sample", "platform"],
                    right_on=["sample_base", "platform"], how="left")

# --- Plot: F-score vs measured mean coverage, faceted by SNP class ---
fig, axes = plt.subplots(1, 5, figsize=(24, 5.5), sharey=True)

for i, snp_cls in enumerate(SNP_CLASSES):
    ax = axes[i]
    sub = merged[merged["SNPClass"] == snp_cls].sort_values("WgsCoverageMean")
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
    if i == 0:
        ax.set_ylabel("F-score", fontsize=12)
    if i == len(SNP_CLASSES) - 1:
        ax.legend(fontsize=9, loc="lower right")

fig.suptitle("HG003 — F-score vs Measured Coverage (alignstats) by Platform\n"
             f"Footprint: {FOOTPRINT}",
             fontsize=14, fontweight="bold", y=1.04)
fig.tight_layout()
out = BASE / "all_platforms_fscore_by_measured_cov.png"
fig.savefig(out, dpi=150, bbox_inches="tight")
plt.close(fig)
print(f"Saved: {out}")

