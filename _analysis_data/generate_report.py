#!/usr/bin/env python3
"""Generate comprehensive analysis report for all completed daylily workflows.

Parses concordance and alignstats data from:
  - agbt_ont (ONT solo)
  - agbt_ug (Ultima solo)
  - ilmn_hg003_prod (Illumina solo)
  - pb_hg003_prod (PacBio solo)
  - roche_hg003_coverage_series (Roche solo)

Outputs:
  - all_platforms_summary.tsv
  - all_platforms_coverage_plot.png
  - all_platforms_concordance_plot.png
"""

import re
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd
import numpy as np

# --- Configuration ---
BASE = Path(__file__).resolve().parent
WORKFLOWS = {
    "agbt_ont":                    {"platform": "ONT",     "aligner": "ont",     "caller": "sentdont"},
    "agbt_ug":                     {"platform": "Ultima",  "aligner": "ug",      "caller": "ug"},
    "ilmn_hg003_prod":             {"platform": "ILMN",    "aligner": "sent",    "caller": "sentD"},
    "pb_hg003_prod":               {"platform": "PacBio",  "aligner": "sentmm2", "caller": "sentdpb"},
    "roche_hg003_coverage_series": {"platform": "Roche",   "aligner": "roche",   "caller": "rochehc"},
}
CONCORDANCE_FOOTPRINT = "giabHC_x_clinvar_genes"
SNP_CLASSES = ["SNPts", "SNPtv", "INS_50", "DEL_50", "Indel_50"]
COV_REGEX = re.compile(r"-(\d+)x-")


def extract_nominal_cov(sample_name: str) -> int | None:
    """Extract nominal coverage from sample name like On1-HG003-10x-5-..."""
    m = COV_REGEX.search(sample_name)
    return int(m.group(1)) if m else None


def load_alignstats(wf_name: str) -> pd.DataFrame:
    path = BASE / wf_name / "alignstats_combo_mqc.tsv"
    if not path.exists():
        return pd.DataFrame()
    df = pd.read_csv(path, sep="\t")
    df["workflow"] = wf_name
    df["platform"] = WORKFLOWS[wf_name]["platform"]
    # sample col has trailing .aligner — strip for matching
    df["sample_base"] = df["sample"].str.rsplit(".", n=1).str[0]
    df["nominal_cov"] = df["sample_base"].apply(extract_nominal_cov)
    return df[["sample", "sample_base", "aligner", "platform", "workflow",
               "nominal_cov", "WgsCoverageMean", "WgsCoverageMedian"]]


def load_concordance(wf_name: str) -> pd.DataFrame:
    path = BASE / wf_name / "giab_concordance_mqc.tsv"
    if not path.exists():
        return pd.DataFrame()
    df = pd.read_csv(path, sep="\t")
    df["workflow"] = wf_name
    df["platform"] = WORKFLOWS[wf_name]["platform"]
    df["nominal_cov"] = df["Sample"].apply(extract_nominal_cov)
    # Filter to target footprint and SNP classes
    mask = (df["ROI"] == CONCORDANCE_FOOTPRINT) & (df["VariantClass"].isin(SNP_CLASSES))
    return df.loc[mask, ["Sample", "VariantClass", "Fscore", "Sensitivity-Recall",
                         "Precision", "ROI", "platform", "workflow",
                         "nominal_cov", "Aligner", "SNVCaller"]]


# --- Load all data ---
print("Loading data...")
all_align = pd.concat([load_alignstats(w) for w in WORKFLOWS], ignore_index=True)
all_conc = pd.concat([load_concordance(w) for w in WORKFLOWS if (BASE / w / "giab_concordance_mqc.tsv").exists()], ignore_index=True)

print(f"  Alignstats: {len(all_align)} rows across {all_align['platform'].nunique()} platforms")
print(f"  Concordance: {len(all_conc)} rows across {all_conc['platform'].nunique()} platforms")

# --- Build summary table ---
# Pivot concordance to get one column per SNP class Fscore
conc_pivot = all_conc.pivot_table(
    index=["Sample", "platform", "workflow", "nominal_cov"],
    columns="VariantClass",
    values="Fscore",
).reset_index()
conc_pivot.columns = [f"{c}_Fscore" if c in SNP_CLASSES else c for c in conc_pivot.columns]

# Merge with alignstats
summary = all_align.merge(
    conc_pivot,
    left_on=["sample_base", "platform", "workflow", "nominal_cov"],
    right_on=["Sample", "platform", "workflow", "nominal_cov"],
    how="left",
)
summary = summary.sort_values(["platform", "nominal_cov"]).reset_index(drop=True)

out_cols = ["platform", "sample_base", "aligner", "nominal_cov",
            "WgsCoverageMean", "WgsCoverageMedian"] + [f"{c}_Fscore" for c in SNP_CLASSES]
summary_out = summary[[c for c in out_cols if c in summary.columns]]

out_tsv = BASE / "all_platforms_summary.tsv"
summary_out.to_csv(out_tsv, sep="\t", index=False, float_format="%.6f")
print(f"\nSummary table saved: {out_tsv}")
print(summary_out.to_string(index=False))

# --- Colorblind-friendly palette ---
PLATFORM_COLORS = {
    "ILMN":   "#0072B2",  # blue
    "ONT":    "#D55E00",  # vermillion
    "PacBio": "#009E73",  # bluish green
    "Ultima": "#CC79A7",  # reddish purple
    "Roche":  "#F0E442",  # yellow
}
PLATFORM_MARKERS = {
    "ILMN": "o", "ONT": "s", "PacBio": "^", "Ultima": "D", "Roche": "v",
}

# --- Coverage Plot ---
print("\nGenerating coverage plot...")
fig, ax = plt.subplots(figsize=(10, 6))
for plat in sorted(all_align["platform"].unique()):
    sub = all_align[all_align["platform"] == plat].sort_values("nominal_cov")
    ax.plot(sub["nominal_cov"], sub["WgsCoverageMean"],
            color=PLATFORM_COLORS.get(plat, "gray"),
            marker=PLATFORM_MARKERS.get(plat, "x"),
            label=f"{plat} (mean)", linewidth=2, markersize=7)
    ax.plot(sub["nominal_cov"], sub["WgsCoverageMedian"],
            color=PLATFORM_COLORS.get(plat, "gray"),
            marker=PLATFORM_MARKERS.get(plat, "x"),
            label=f"{plat} (median)", linewidth=1, linestyle="--", alpha=0.6, markersize=5)

# Identity line
max_cov = int(all_align["nominal_cov"].max()) + 5
ax.plot([0, max_cov], [0, max_cov], "k--", alpha=0.3, label="y=x")
ax.set_xlabel("Nominal Coverage (x)", fontsize=12)
ax.set_ylabel("Measured Coverage (x)", fontsize=12)
ax.set_title("HG003 Coverage Series — Measured vs Nominal Coverage by Platform", fontsize=13, fontweight="bold")
ax.legend(fontsize=8, ncol=2, loc="upper left")
ax.grid(True, alpha=0.3)
ax.set_xlim(0, max_cov)
ax.set_ylim(0, max_cov)
fig.tight_layout()
cov_png = BASE / "all_platforms_coverage_plot.png"
fig.savefig(cov_png, dpi=150)
plt.close(fig)
print(f"Coverage plot saved: {cov_png}")

# --- Concordance Faceted Plot ---
print("\nGenerating concordance plot...")
fig, axes = plt.subplots(1, 5, figsize=(22, 5), sharey=True)
for i, snp_cls in enumerate(SNP_CLASSES):
    ax = axes[i]
    sub = all_conc[all_conc["VariantClass"] == snp_cls]
    for plat in sorted(sub["platform"].unique()):
        psub = sub[sub["platform"] == plat].sort_values("nominal_cov")
        ax.plot(psub["nominal_cov"], psub["Fscore"],
                color=PLATFORM_COLORS.get(plat, "gray"),
                marker=PLATFORM_MARKERS.get(plat, "x"),
                label=plat, linewidth=2, markersize=7)
    ax.set_title(snp_cls, fontsize=12, fontweight="bold")
    ax.set_xlabel("Nominal Coverage (x)", fontsize=10)
    ax.grid(True, alpha=0.3)
    ax.set_xlim(0, 55)
    if i == 0:
        ax.set_ylabel("F-score", fontsize=12)
    if i == len(SNP_CLASSES) - 1:
        ax.legend(fontsize=8, loc="lower right")

fig.suptitle("HG003 Coverage Series — GIAB HC × ClinVar Genes Concordance by Platform",
             fontsize=14, fontweight="bold", y=1.02)
fig.tight_layout()
conc_png = BASE / "all_platforms_concordance_plot.png"
fig.savefig(conc_png, dpi=150, bbox_inches="tight")
plt.close(fig)
print(f"Concordance plot saved: {conc_png}")

# --- Recall faceted plot (same layout) ---
print("\nGenerating recall plot...")
fig, axes = plt.subplots(1, 5, figsize=(22, 5), sharey=True)
for i, snp_cls in enumerate(SNP_CLASSES):
    ax = axes[i]
    sub = all_conc[all_conc["VariantClass"] == snp_cls]
    for plat in sorted(sub["platform"].unique()):
        psub = sub[sub["platform"] == plat].sort_values("nominal_cov")
        ax.plot(psub["nominal_cov"], psub["Sensitivity-Recall"],
                color=PLATFORM_COLORS.get(plat, "gray"),
                marker=PLATFORM_MARKERS.get(plat, "x"),
                label=plat, linewidth=2, markersize=7)
    ax.set_title(snp_cls, fontsize=12, fontweight="bold")
    ax.set_xlabel("Nominal Coverage (x)", fontsize=10)
    ax.grid(True, alpha=0.3)
    ax.set_xlim(0, 55)
    if i == 0:
        ax.set_ylabel("Recall (Sensitivity)", fontsize=12)
    if i == len(SNP_CLASSES) - 1:
        ax.legend(fontsize=8, loc="lower right")

fig.suptitle("HG003 Coverage Series — GIAB HC × ClinVar Genes Recall by Platform",
             fontsize=14, fontweight="bold", y=1.02)
fig.tight_layout()
recall_png = BASE / "all_platforms_recall_plot.png"
fig.savefig(recall_png, dpi=150, bbox_inches="tight")
plt.close(fig)
print(f"Recall plot saved: {recall_png}")

# --- Precision faceted plot ---
print("\nGenerating precision plot...")
fig, axes = plt.subplots(1, 5, figsize=(22, 5), sharey=True)
for i, snp_cls in enumerate(SNP_CLASSES):
    ax = axes[i]
    sub = all_conc[all_conc["VariantClass"] == snp_cls]
    for plat in sorted(sub["platform"].unique()):
        psub = sub[sub["platform"] == plat].sort_values("nominal_cov")
        ax.plot(psub["nominal_cov"], psub["Precision"],
                color=PLATFORM_COLORS.get(plat, "gray"),
                marker=PLATFORM_MARKERS.get(plat, "x"),
                label=plat, linewidth=2, markersize=7)
    ax.set_title(snp_cls, fontsize=12, fontweight="bold")
    ax.set_xlabel("Nominal Coverage (x)", fontsize=10)
    ax.grid(True, alpha=0.3)
    ax.set_xlim(0, 55)
    if i == 0:
        ax.set_ylabel("Precision (PPV)", fontsize=12)
    if i == len(SNP_CLASSES) - 1:
        ax.legend(fontsize=8, loc="lower right")

fig.suptitle("HG003 Coverage Series — GIAB HC × ClinVar Genes Precision by Platform",
             fontsize=14, fontweight="bold", y=1.02)
fig.tight_layout()
prec_png = BASE / "all_platforms_precision_plot.png"
fig.savefig(prec_png, dpi=150, bbox_inches="tight")
plt.close(fig)
print(f"Precision plot saved: {prec_png}")

print("\n=== Report generation complete ===")

