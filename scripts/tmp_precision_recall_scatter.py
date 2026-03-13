#!/usr/bin/env python3
"""Precision vs Recall scatter for sbwa+gatk @ 30x giabHC — AGBT plenary slide 1."""

import csv
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np

BASE_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), os.pardir,
    "_analysis_data", "agbt_benchmark_alignment_concordance_stats",
)
BASE_DIR = os.path.normpath(BASE_DIR)
INPUT_TSV = os.path.join(BASE_DIR, "consolidated_concordance.tsv")
OUT_PATH = os.path.join(BASE_DIR, "precision_recall_sbwa_gatk_30x_giabHC.svg")

# Okabe-Ito colorblind-friendly palette (9 colours)
OKABE_ITO = [
    "#E69F00",  # orange
    "#56B4E9",  # sky blue
    "#009E73",  # bluish green
    "#F0E442",  # yellow
    "#0072B2",  # blue
    "#D55E00",  # vermillion
    "#CC79A7",  # reddish purple
    "#000000",  # black
    "#999999",  # grey
]

# Marker shapes — one per variant class for redundant encoding
MARKERS = ["o", "s", "D", "^", "v", "P", "X", "h", "*"]

# Display order and labels
VC_ORDER = [
    "All", "SNPts", "SNPtv",
    "INS_50",
    "DEL_50",
    "Indel_50", "Indel_gt50",
]

VC_DISPLAY = {
    "All": "All",
    "SNPts": "SNP transitions",
    "SNPtv": "SNP transversions",
    "INS_50": "INS ≤50 bp",
    "INS_gt50": "INS >50 bp",
    "DEL_50": "DEL ≤50 bp",
    "DEL_gt50": "DEL >50 bp",
    "Indel_50": "Indel ≤50 bp",
    "Indel_gt50": "Indel >50 bp",
}


def load_points():
    """Return dict vc → (precision, recall, fscore)."""
    pts = {}
    with open(INPUT_TSV) as f:
        for row in csv.DictReader(f, delimiter="\t"):
            if (row["ROI"] != "giabHC"
                    or row["Aligner"] != "sent"
                    or row["SNVCaller"] != "gatk"
                    or row["PrimaryCoverageBin"] != "35"):
                continue
            vc = row["VariantClass"]
            prec_raw = row["Precision"]
            rec_raw = row["Sensitivity-Recall"]
            fs_raw = row["Fscore"]
            if not prec_raw or not rec_raw or not fs_raw:
                continue
            prec = float(prec_raw)
            rec = float(rec_raw)
            fs = float(fs_raw)
            pts[vc] = (prec, rec, fs)
    return pts


def main():
    pts = load_points()
    if not pts:
        print("No data found", file=sys.stderr)
        sys.exit(1)

    # 16:9 aspect ratio for widescreen
    fig, ax = plt.subplots(figsize=(14, 7.875))
    fig.patch.set_facecolor("white")
    ax.set_facecolor("#fafafa")

    for i, vc in enumerate(VC_ORDER):
        if vc not in pts:
            continue
        prec, rec, fs = pts[vc]
        color = OKABE_ITO[i % len(OKABE_ITO)]
        marker = MARKERS[i % len(MARKERS)]
        label = f"{VC_DISPLAY.get(vc, vc)}  (F = {fs:.4f})"
        ax.scatter(prec, rec, c=color, marker=marker, s=220, linewidths=0.8,
                   edgecolors="#333333", zorder=5, label=label)

    # Axes
    ax.set_xlabel("Precision", fontsize=18, fontweight="bold", labelpad=10)
    ax.set_ylabel("Recall  (Sensitivity)", fontsize=18, fontweight="bold", labelpad=10)
    ax.tick_params(axis="both", labelsize=14)

    # Grid
    ax.grid(True, linestyle="--", linewidth=0.5, alpha=0.6, color="#aaaaaa")
    ax.set_axisbelow(True)

    # Dynamic axis limits — zoom to data range with small padding
    all_prec = [pts[vc][0] for vc in VC_ORDER if vc in pts]
    all_rec = [pts[vc][1] for vc in VC_ORDER if vc in pts]
    pad = 0.008
    x_lo = min(all_prec) - pad
    x_hi = max(all_prec) + pad
    y_lo = min(all_rec) - pad
    y_hi = max(all_rec) + pad
    # Clamp to [0, 1]
    ax.set_xlim(max(0, x_lo), min(1.0005, x_hi))
    ax.set_ylim(max(0, y_lo), min(1.0005, y_hi))

    # Title
    ax.set_title(
        "Precision vs Recall — ILMN sbwa + GATK · 30× · giabHC",
        fontsize=20, fontweight="bold", pad=16,
    )

    # Subtitle
    ax.text(0.5, 1.02, "HG003 · GIAB v4.2.1 truth set · hg38",
            transform=ax.transAxes, ha="center", va="bottom",
            fontsize=13, color="#666666", fontstyle="italic")

    # Legend — outside right
    leg = ax.legend(
        fontsize=12, loc="center left", bbox_to_anchor=(1.02, 0.5),
        frameon=True, fancybox=True, shadow=False,
        edgecolor="#cccccc", framealpha=0.95,
        title="Variant Class  (F-score)", title_fontsize=13,
        handletextpad=0.8, borderpad=0.8,
        markerscale=1.3,
    )
    leg.get_title().set_fontweight("bold")

    plt.tight_layout()
    fig.savefig(OUT_PATH, format="svg", bbox_inches="tight", dpi=150)
    plt.close(fig)
    print(f"Saved: {OUT_PATH}")
    print(f"Points plotted: {sum(1 for vc in VC_ORDER if vc in pts)}")
    for vc in VC_ORDER:
        if vc in pts:
            p, r, f = pts[vc]
            print(f"  {VC_DISPLAY.get(vc, vc):22s}  Prec={p:.6f}  Rec={r:.6f}  F={f:.4f}")
        else:
            print(f"  {VC_DISPLAY.get(vc, vc):22s}  (no data)")


if __name__ == "__main__":
    main()

