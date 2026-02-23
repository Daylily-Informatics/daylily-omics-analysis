#!/usr/bin/env python3
"""Precision vs Recall scatter for each SNP class, giabHC footprint.
Points are sized by measured coverage and colored by platform.
Arrows connect coverage levels low→high to show trajectory."""

import re
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patheffects as pe
import numpy as np
import pandas as pd

BASE = Path(__file__).resolve().parent

WORKFLOWS = {
    "agbt_ont":                    {"platform": "ONT"},
    "agbt_ug":                     {"platform": "Ultima"},
    "ilmn_hg003_prod":             {"platform": "ILMN"},
    "pb_hg003_prod":               {"platform": "PacBio"},
    "roche_hg003_coverage_series": {"platform": "Roche"},
}
FOOTPRINT = "giabHC"
SNP_CLASSES = ["SNPts", "SNPtv", "INS_50", "DEL_50", "Indel_50"]
COV_RE = re.compile(r"-(\d+)x-")

COLORS = {"ILMN": "#0072B2", "ONT": "#D55E00", "PacBio": "#009E73", "Roche": "#E69F00", "Ultima": "#CC79A7"}
MARKERS = {"ILMN": "o", "ONT": "s", "PacBio": "^", "Roche": "v", "Ultima": "D"}

# --- Load alignstats for measured coverage ---
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

# --- Load concordance (giabHC footprint) ---
conc_frames = []
for wf, meta in WORKFLOWS.items():
    p = BASE / wf / "giab_concordance_mqc.tsv"
    if not p.exists():
        continue
    df = pd.read_csv(p, sep="\t")
    mask = (df["ROI"] == FOOTPRINT) & (df["VariantClass"].isin(SNP_CLASSES))
    sub = df.loc[mask, ["Sample", "VariantClass", "Fscore", "Sensitivity-Recall", "Precision"]].copy()
    sub["platform"] = meta["platform"]
    m = sub["Sample"].str.extract(COV_RE)
    sub["nominal_cov"] = m[0].astype(float)
    conc_frames.append(sub)
conc = pd.concat(conc_frames, ignore_index=True)

merged = conc.merge(alignstats, left_on=["Sample", "platform"],
                    right_on=["sample_base", "platform"], how="left")

# --- Plot ---
fig, axes = plt.subplots(1, 5, figsize=(26, 5.5))

for i, snp_cls in enumerate(SNP_CLASSES):
    ax = axes[i]
    sub = merged[merged["VariantClass"] == snp_cls]

    for plat in sorted(sub["platform"].unique()):
        ps = sub[sub["platform"] == plat].sort_values("WgsCoverageMean")
        recall = ps["Sensitivity-Recall"].values
        prec = ps["Precision"].values
        cov = ps["WgsCoverageMean"].values
        nom = ps["nominal_cov"].values

        # Draw connecting lines
        ax.plot(recall, prec, color=COLORS[plat], linewidth=1.2, alpha=0.5, zorder=1)

        # Scatter sized by coverage
        sizes = 20 + cov * 3
        ax.scatter(recall, prec, s=sizes, color=COLORS[plat],
                   marker=MARKERS[plat], label=plat, zorder=2,
                   edgecolors="white", linewidths=0.5)

        # Label the highest-coverage point
        ax.annotate(f"{int(nom[-1])}x",
                    (recall[-1], prec[-1]),
                    fontsize=7, fontweight="bold", color=COLORS[plat],
                    textcoords="offset points", xytext=(6, -3),
                    path_effects=[pe.withStroke(linewidth=2, foreground="white")])
        # Label the lowest
        ax.annotate(f"{int(nom[0])}x",
                    (recall[0], prec[0]),
                    fontsize=7, fontweight="bold", color=COLORS[plat],
                    textcoords="offset points", xytext=(-14, 5),
                    path_effects=[pe.withStroke(linewidth=2, foreground="white")])

    ax.set_title(snp_cls, fontsize=13, fontweight="bold")
    ax.set_xlabel("Recall", fontsize=11)
    ax.grid(True, alpha=0.3)
    if i == 0:
        ax.set_ylabel("Precision", fontsize=12)
    if i == len(SNP_CLASSES) - 1:
        ax.legend(fontsize=8, loc="lower left")

    # Diagonal iso-F lines
    for f in [0.90, 0.95, 0.99]:
        r_vals = np.linspace(f / 2, 1, 200)
        p_vals = (f * r_vals) / (2 * r_vals - f)
        valid = (p_vals >= 0) & (p_vals <= 1)
        ax.plot(r_vals[valid], p_vals[valid], "k-", alpha=0.08, linewidth=0.8)
        # label
        idx = np.argmin(np.abs(r_vals[valid] - f))
        ax.text(r_vals[valid][idx], p_vals[valid][idx] + 0.003,
                f"F={f}", fontsize=6, alpha=0.3, ha="center")

fig.suptitle("HG003 — Precision vs Recall by Platform (point size ∝ measured coverage)\n"
             f"Footprint: {FOOTPRINT}  |  Coverage labels: nominal",
             fontsize=14, fontweight="bold", y=1.05)
fig.tight_layout()
out = BASE / "all_platforms_precision_vs_recall_giabHC.png"
fig.savefig(out, dpi=150, bbox_inches="tight")
plt.close(fig)
print(f"Saved: {out}")

# --- Zoomed version (0.85-1.0 on both axes) ---
fig, axes = plt.subplots(1, 5, figsize=(26, 5.5))

for i, snp_cls in enumerate(SNP_CLASSES):
    ax = axes[i]
    sub = merged[merged["VariantClass"] == snp_cls]

    for plat in sorted(sub["platform"].unique()):
        ps = sub[sub["platform"] == plat].sort_values("WgsCoverageMean")
        recall = ps["Sensitivity-Recall"].values
        prec = ps["Precision"].values
        cov = ps["WgsCoverageMean"].values
        nom = ps["nominal_cov"].values

        ax.plot(recall, prec, color=COLORS[plat], linewidth=1.2, alpha=0.5, zorder=1)
        sizes = 20 + cov * 3
        ax.scatter(recall, prec, s=sizes, color=COLORS[plat],
                   marker=MARKERS[plat], label=plat, zorder=2,
                   edgecolors="white", linewidths=0.5)

        # Label highest-coverage point visible in zoomed range
        mask_in = (recall >= 0.95) & (prec >= 0.95)
        if mask_in.any():
            last_in = np.where(mask_in)[0][-1]
            ax.annotate(f"{int(nom[last_in])}x",
                        (recall[last_in], prec[last_in]),
                        fontsize=7, fontweight="bold", color=COLORS[plat],
                        textcoords="offset points", xytext=(6, -3),
                        path_effects=[pe.withStroke(linewidth=2, foreground="white")])

    ax.set_title(snp_cls, fontsize=13, fontweight="bold")
    ax.set_xlabel("Recall", fontsize=11)
    ax.grid(True, alpha=0.3)
    ax.set_xlim(0.95, 1.002)
    ax.set_ylim(0.95, 1.002)
    ax.xaxis.set_major_locator(plt.MultipleLocator(0.02))
    ax.yaxis.set_major_locator(plt.MultipleLocator(0.02))
    if i == 0:
        ax.set_ylabel("Precision", fontsize=12)
    if i == len(SNP_CLASSES) - 1:
        ax.legend(fontsize=8, loc="lower left")

    # Iso-F lines
    for f in [0.90, 0.95, 0.99]:
        r_vals = np.linspace(f / 2, 1, 200)
        p_vals = (f * r_vals) / (2 * r_vals - f)
        valid = (p_vals >= 0.95) & (p_vals <= 1) & (r_vals >= 0.95)
        if valid.any():
            ax.plot(r_vals[valid], p_vals[valid], "k-", alpha=0.08, linewidth=0.8)

fig.suptitle("HG003 — Precision vs Recall (zoomed 0.95–1.00)\n"
             f"Footprint: {FOOTPRINT}  |  Point size ∝ measured coverage",
             fontsize=14, fontweight="bold", y=1.05)
fig.tight_layout()
out2 = BASE / "all_platforms_precision_vs_recall_giabHC_zoomed.png"
fig.savefig(out2, dpi=150, bbox_inches="tight")
plt.close(fig)
print(f"Saved: {out2}")

