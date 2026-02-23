#!/usr/bin/env python3
"""F-score by measured coverage across three concordance footprints (hg38, giabHC, clinvar_genes).
Faceted: rows=footprints, cols=SNP classes."""

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
FOOTPRINTS = ["hg38", "giabHC", "clinvar_genes"]
SNP_CLASSES = ["SNPts", "SNPtv", "INS_50", "DEL_50", "Indel_50"]
COV_RE = re.compile(r"-(\d+)x-")

COLORS = {"ILMN": "#0072B2", "ONT": "#D55E00", "PacBio": "#009E73", "Roche": "#E69F00", "Ultima": "#CC79A7"}
MARKERS = {"ILMN": "o", "ONT": "s", "PacBio": "^", "Roche": "v", "Ultima": "D"}

# --- Load alignstats ---
align_frames = []
for wf, meta in WORKFLOWS.items():
    p = BASE / wf / "alignstats_combo_mqc.tsv"
    if not p.exists():
        continue
    df = pd.read_csv(p, sep="\t", usecols=["sample", "WgsCoverageMean"])
    df["sample_base"] = df["sample"].str.rsplit(".", n=1).str[0]
    df["platform"] = meta["platform"]
    align_frames.append(df[["sample_base", "platform", "WgsCoverageMean"]])
alignstats = pd.concat(align_frames, ignore_index=True)

# --- Load concordance for all three footprints ---
conc_frames = []
for wf, meta in WORKFLOWS.items():
    p = BASE / wf / "giab_concordance_mqc.tsv"
    if not p.exists():
        continue
    df = pd.read_csv(p, sep="\t")
    mask = df["ROI"].isin(FOOTPRINTS) & df["VariantClass"].isin(SNP_CLASSES)
    sub = df.loc[mask, ["Sample", "VariantClass", "Fscore", "ROI"]].copy()
    sub["platform"] = meta["platform"]
    conc_frames.append(sub)
conc = pd.concat(conc_frames, ignore_index=True)

merged = conc.merge(alignstats, left_on=["Sample", "platform"],
                    right_on=["sample_base", "platform"], how="left")

# --- Plot: 3 rows (footprints) x 5 cols (SNP classes) ---
fig, axes = plt.subplots(3, 5, figsize=(26, 14), sharey="row", sharex=True)

for row, fp in enumerate(FOOTPRINTS):
    for col, snp_cls in enumerate(SNP_CLASSES):
        ax = axes[row][col]
        sub = merged[(merged["ROI"] == fp) & (merged["VariantClass"] == snp_cls)]
        for plat in sorted(sub["platform"].unique()):
            ps = sub[sub["platform"] == plat].sort_values("WgsCoverageMean")
            ax.plot(ps["WgsCoverageMean"], ps["Fscore"],
                    color=COLORS.get(plat, "gray"),
                    marker=MARKERS.get(plat, "x"),
                    label=plat, linewidth=1.8, markersize=6)
        ax.grid(True, alpha=0.3)
        ax.set_xlim(0, 58)
        if row == 0:
            ax.set_title(snp_cls, fontsize=12, fontweight="bold")
        if row == len(FOOTPRINTS) - 1:
            ax.set_xlabel("Measured Coverage (x)", fontsize=10)
        if col == 0:
            ax.set_ylabel(f"{fp}\nF-score", fontsize=11)
        if row == 0 and col == len(SNP_CLASSES) - 1:
            ax.legend(fontsize=8, loc="lower right")

fig.suptitle("HG003 — F-score by Measured Coverage across Concordance Footprints\n"
             "Rows: hg38 (whole genome), giabHC (high-confidence), clinvar_genes",
             fontsize=14, fontweight="bold", y=1.02)
fig.tight_layout()
out = BASE / "all_platforms_fscore_by_footprint.png"
fig.savefig(out, dpi=150, bbox_inches="tight")
plt.close(fig)
print(f"Saved: {out}")

