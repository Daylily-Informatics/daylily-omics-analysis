#!/usr/bin/env python3
"""Plot #2: 4-panel 30x genome performance comparison for AGBT flash talk.

Four panels (horizontal):
  1. F-score distributions by variant class (hg38 vs pangenome)
  2. Informatics analysis time (fastq→snv vcf)
  3. Informatics analysis compute cost ($)
  4. Time to sequencing data

Data: consolidated_concordance.tsv + benchmark TSVs
Output: plot2_30x_performance_comparison.svg
"""

import csv
import math
import os
import re
import sys
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import numpy as np

# ── Paths ──
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
INPUT_TSV = os.path.join(BASE_DIR, "consolidated_concordance.tsv")
SRC_DATA = os.path.join(BASE_DIR, "src_data")
OUTPUT_SVG = os.path.join(BASE_DIR, "plot2_30x_performance_comparison.svg")

# ── Font ──
INTER_PATHS = [p for p in fm.findSystemFonts() if "Inter" in os.path.basename(p)]
if INTER_PATHS:
    for p in INTER_PATHS:
        fm.fontManager.addfont(p)
    plt.rcParams["font.family"] = "Inter"
else:
    plt.rcParams["font.family"] = "sans-serif"
plt.rcParams["font.size"] = 10

# ── Constants ──
COVERAGE_BIN = 35  # 30x
ROI_ORDER = ["hg38", "giabHC", "clinvar_genes"]
ROI_DISPLAY = {"hg38": "hg38", "giabHC": "giabHC", "clinvar_genes": "clinvar_genes"}
SKIP_CALLERS = {"clair3", "oct"}
VARIANT_CLASSES = ["SNPts", "DEL_50", "INS_50"]
VC_DISPLAY = {"SNPts": "SNP", "DEL_50": "DEL_50", "INS_50": "INS_50"}

HYBRID_CALLERS = {"sentdhio", "sentdhiom", "sentdhiomr", "sentdhuo"}
PANGENOME_ALIGNERS = {"pangenome_sr"}

# Benchmark files (test_group → relative path under src_data)
BENCHMARK_FILES = {
    "ilmn_all_downsamples_a": "ilmn_all_downsamples_a/benchmarks_summary.tsv",
    "ilmn_gatk_b": "ilmn_gatk_b/benchmarks_summary.tsv",
    "ont_dv19": "ont_dv19/benchmarks_summary.tsv",
    "pacbio_ds": "pacbio_ds/benchmarks_summary.tsv",
    "ultima_ds": "ultima_ds/benchmarks_summary.tsv",
    "pangenome_3_and_30x": "pangenome_3_and_30x/benchmarks_summary.tsv",
    "pan_ilmn_x": "pan_ilmn_x/benchmarks_summary.tsv",
}

# Rules to exclude from cost/time aggregation (QC, concordance, housekeeping)
EXCLUDE_RULES_PREFIXES = [
    "concordance", "alignstats", "produce_", "dirsetup",
    "prep_for_concordance", "combine_mqc", "parse_vcfeval",
    "rtg_vcfeval", "filter_variants",
]

# 30x sample patterns for benchmark files
SAMPLE_30X_PATTERNS = [
    re.compile(r"I2-HG003-30x"),
    re.compile(r"Irl1-HG003-30x"),
    re.compile(r"On1c?-HG003-30x"),
    re.compile(r"Pb-HG003-3[05]x"),
    re.compile(r"Ug1-HG003-[34]0x"),
    re.compile(r"R30x-HG003"),
]

# Representative sequencing turnaround times (hours) per platform
# These are approximate wall-clock times from sample-prep-start to reads-available
SEQ_TIME_SHORT_READS = [24, 26, 44, 40, 24, 28, 36, 44, 24, 30]  # ILMN/Ultima/Roche
SEQ_TIME_LONG_READS = [24, 30, 72, 48, 30, 72, 24, 28, 72, 48]   # ONT/PacBio


def classify_section(aligner, caller):
    """Classify a pipeline into hg38, hybrid, or pangenome."""
    if caller in HYBRID_CALLERS:
        return "hybrid"
    if aligner in PANGENOME_ALIGNERS:
        return "pangenome"
    return "hg38"


def is_30x_sample(sample_name):
    """Check if a benchmark sample corresponds to ~30x coverage."""
    return any(p.search(sample_name) for p in SAMPLE_30X_PATTERNS)


def should_exclude_rule(rule_name):
    """Check if a benchmark rule should be excluded from cost/time."""
    return any(rule_name.startswith(pfx) for pfx in EXCLUDE_RULES_PREFIXES)


def _extract_pipeline(rule_name):
    """Extract (aligner, caller) from rule name like 'sent.dmd.sentd.1-12'."""
    parts = rule_name.split(".")
    if len(parts) >= 3:
        return parts[0], parts[2]  # aligner, caller
    if len(parts) >= 2:
        return parts[0], parts[1]
    return rule_name, "unknown"


# ── Panel 1: F-score data ──
def load_fscore_data():
    """Load F-scores at bin 35, grouped by (ROI, section, variant_class).

    Returns: {(roi, section, vc_display): [fscore, ...]}
    """
    roi_set = set(ROI_ORDER)
    data = defaultdict(list)
    seen = set()
    with open(INPUT_TSV, "r") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            if row["PrimaryCoverageBin"] != str(COVERAGE_BIN):
                continue
            roi = row["ROI"]
            if roi not in roi_set:
                continue
            vc = row["VariantClass"]
            if vc not in VARIANT_CLASSES:
                continue
            caller = row["SNVCaller"]
            if caller in SKIP_CALLERS:
                continue
            aligner = row["Aligner"]
            # Exclude ont+deep19 combination
            if aligner == "ont" and caller == "deep19":
                continue
            sample = row["Sample"]
            dedup_key = (roi, sample, aligner, caller, vc)
            if dedup_key in seen:
                continue
            seen.add(dedup_key)
            section = classify_section(aligner, caller)
            if section == "hybrid":
                continue
            try:
                fs = float(row["Fscore"])
                if math.isnan(fs):
                    continue
            except (ValueError, KeyError):
                continue
            data[(roi, section, VC_DISPLAY[vc])].append(fs)
    return data


# ── Panels 2 & 3: Benchmark cost/time ──
def load_benchmark_data():
    """Load per-pipeline cost and wall-clock time from benchmark files.

    Returns: {"hg38": [{"cost": $, "hours": h}, ...],
              "hg38-pan": [{"cost": $, "hours": h}, ...]}
    """
    # (test_group, sample, aligner, caller) → {"cost": float, "secs": float}
    pipeline_totals = defaultdict(lambda: {"cost": 0.0, "secs": 0.0})

    for tg, rel_path in BENCHMARK_FILES.items():
        fpath = os.path.join(SRC_DATA, rel_path)
        if not os.path.exists(fpath):
            continue
        with open(fpath, "r") as f:
            for row in csv.DictReader(f, delimiter="\t"):
                sample = row["sample"]
                if not is_30x_sample(sample):
                    continue
                rule = row["rule"]
                if should_exclude_rule(rule):
                    continue
                aligner, caller = _extract_pipeline(rule)
                try:
                    cost = float(row.get("task_cost") or 0)
                    secs = float(row.get("s") or 0)
                except (ValueError, TypeError):
                    continue
                key = (tg, sample, aligner, caller)
                pipeline_totals[key]["cost"] += cost
                pipeline_totals[key]["secs"] += secs

    # Classify into hg38 vs hg38-pan
    result = {"hg38": [], "hg38-pan": []}
    for (tg, sample, aligner, caller), vals in pipeline_totals.items():
        section = "hg38-pan" if aligner in PANGENOME_ALIGNERS else "hg38"
        hrs = vals["secs"] / 3600.0
        result[section].append({"cost": vals["cost"], "hours": hrs})

    return result


# ── Plotting ──
PANEL_BG_HG38 = "#f0f0f0"       # light gray
PANEL_BG_PAN = "#dce8f5"         # light blue
BOXPROPS = dict(linewidth=1.0, color="black")
MEDIANPROPS = dict(linewidth=1.5, color="black")
FLIERPROPS = dict(marker="o", markersize=4, markerfacecolor="#e67e22",
                  markeredgecolor="none", alpha=0.8)
WHISKERPROPS = dict(linewidth=1.0, color="black")
CAPPROPS = dict(linewidth=1.0, color="black")


def main():
    # ── Load data ──
    fs_data = load_fscore_data()
    bench = load_benchmark_data()

    print("F-score data points per group:")
    for k, v in sorted(fs_data.items()):
        print(f"  {k}: {len(v)} values, range [{min(v):.4f}, {max(v):.4f}]")
    print(f"Benchmark pipelines: hg38={len(bench['hg38'])}, "
          f"hg38-pan={len(bench['hg38-pan'])}")

    # ── Figure: outer grid = [Panel1-zone | P2 | P3 | P4] ──
    import matplotlib.gridspec as gridspec
    fig = plt.figure(figsize=(16, 6))
    outer_gs = gridspec.GridSpec(1, 4, figure=fig,
                                width_ratios=[4.5, 1.2, 1.2, 1.2],
                                wspace=0.35)

    # Subdivide Panel 1 zone into 3 ROI sub-axes
    inner_gs = gridspec.GridSpecFromSubplotSpec(
        1, len(ROI_ORDER), subplot_spec=outer_gs[0],
        wspace=0.25)
    roi_axes = [fig.add_subplot(inner_gs[0, i]) for i in range(len(ROI_ORDER))]

    # Panels 2-4 as normal axes
    axes = [None,
            fig.add_subplot(outer_gs[1]),
            fig.add_subplot(outer_gs[2]),
            fig.add_subplot(outer_gs[3])]

    # ── Suptitle ──
    fig.suptitle("The human 30x genome\u2026",
                 fontsize=22, fontweight="bold", y=0.97)
    subtitle_y = 0.92 - 14 / (fig.get_size_inches()[1] * 72)
    fig.text(0.5, subtitle_y,
             "(HG003, multiple platforms, multiple performance factors)",
             ha="center", fontsize=10, fontstyle="italic", color="#555555")

    # ═══════════════════════════════════════════════════════════════════
    # Panel 1: F-score by ROI — each ROI gets its own sub-axis + Y-scale
    # ═══════════════════════════════════════════════════════════════════
    vc_order = ["SNP", "DEL_50", "INS_50"]
    genome_types = ["hg38", "pangenome"]
    n_vc = len(vc_order)
    n_gt = len(genome_types)
    sub_gap = 0.6
    box_w = 0.55

    for ri, roi in enumerate(ROI_ORDER):
        ax = roi_axes[ri]
        positions = []
        box_data = []
        tick_labels = []
        bg_spans = []

        cur = 1.0
        for gi, gt in enumerate(genome_types):
            sg_left = cur - 0.5 * box_w - 0.15
            for vi, vc in enumerate(vc_order):
                positions.append(cur)
                vals = fs_data.get((roi, gt, vc), [])
                box_data.append(vals)
                tick_labels.append(vc)
                cur += 1.0
            sg_right = cur - 1.0 + 0.5 * box_w + 0.15
            bg_spans.append((sg_left, sg_right, gt))
            if gi < n_gt - 1:
                cur += sub_gap

        # Background shading
        for left, right, gt in bg_spans:
            color = PANEL_BG_HG38 if gt == "hg38" else PANEL_BG_PAN
            ax.axvspan(left, right, color=color, zorder=0)

        # Genome type labels above shaded bands
        for left, right, gt in bg_spans:
            mid = (left + right) / 2.0
            ax.text(mid, 1.003, gt, ha="center", va="bottom",
                    fontsize=5, fontstyle="italic", color="#555555",
                    transform=ax.get_xaxis_transform())

        # Boxplots
        if any(len(d) > 0 for d in box_data):
            ax.boxplot(box_data, positions=positions, widths=box_w,
                       patch_artist=False,
                       boxprops=BOXPROPS, medianprops=MEDIANPROPS,
                       flierprops=FLIERPROPS, whiskerprops=WHISKERPROPS,
                       capprops=CAPPROPS)

        # X-axis
        ax.set_xticks(positions)
        ax.set_xticklabels(tick_labels, rotation=45, ha="right", fontsize=5)
        ax.set_xlim(bg_spans[0][0] - 0.3, bg_spans[-1][1] + 0.3)

        # Auto-scale Y to data range with 5% margin; giabHC floor at 0.95
        all_vals = [v for bd in box_data for v in bd]
        if all_vals:
            dmin, dmax = min(all_vals), max(all_vals)
            margin = (dmax - dmin) * 0.05 if dmax > dmin else 0.01
            y_bottom = 0.95 if roi == "giabHC" else dmin - margin
            ax.set_ylim(bottom=y_bottom, top=dmax + margin)

        ax.grid(axis="y", alpha=0.3, linewidth=0.5)

        # ROI title below the sub-axis
        ax.set_xlabel(ROI_DISPLAY[roi], fontsize=8, fontweight="bold",
                      labelpad=8)

        # Y-label only on leftmost sub-axis
        if ri == 0:
            ax.set_ylabel("fscore", fontsize=9)
        else:
            ax.tick_params(axis="y", labelsize=7)

        # Sub-panel title (only on center)
        if ri == 1:
            ax.set_title("Fscore by ROI and Variant Class\n"
                         "(hg38 vs pangenome reference)",
                         fontsize=7, pad=6)

    # ═══════════════════════════════════════════════════════════════════
    # Panel 2: Informatics Analysis Time
    # ═══════════════════════════════════════════════════════════════════
    ax2 = axes[1]
    ax2.set_title("Informatics Analysis\nTime (fastq\u2192snv vcf)", fontsize=7, pad=4)

    time_hg38 = [d["hours"] for d in bench["hg38"]]
    time_pan = [d["hours"] for d in bench["hg38-pan"]]
    bp2 = ax2.boxplot([time_hg38, time_pan], positions=[1, 2], widths=0.5,
                       patch_artist=False,
                       boxprops=BOXPROPS, medianprops=MEDIANPROPS,
                       flierprops=FLIERPROPS, whiskerprops=WHISKERPROPS,
                       capprops=CAPPROPS)
    ax2.set_xticks([1, 2])
    ax2.set_xticklabels(["hg38", "hg38-pan"], rotation=45, ha="right", fontsize=8)
    ax2.set_ylabel("time, hours", fontsize=9)
    ax2.grid(axis="y", alpha=0.3, linewidth=0.5)

    # ═══════════════════════════════════════════════════════════════════
    # Panel 3: Informatics Analysis Compute Cost ($)
    # ═══════════════════════════════════════════════════════════════════
    ax3 = axes[2]
    ax3.set_title("Informatics Analysis\nCompute Cost ($)", fontsize=7, pad=4)

    cost_hg38 = [d["cost"] for d in bench["hg38"]]
    cost_pan = [d["cost"] for d in bench["hg38-pan"]]
    bp3 = ax3.boxplot([cost_hg38, cost_pan], positions=[1, 2], widths=0.5,
                       patch_artist=False,
                       boxprops=BOXPROPS, medianprops=MEDIANPROPS,
                       flierprops=FLIERPROPS, whiskerprops=WHISKERPROPS,
                       capprops=CAPPROPS)
    ax3.set_xticks([1, 2])
    ax3.set_xticklabels(["hg38", "hg38-pan"], rotation=45, ha="right", fontsize=8)
    ax3.set_ylabel("US dollars", fontsize=9)
    ax3.grid(axis="y", alpha=0.3, linewidth=0.5)

    # ═══════════════════════════════════════════════════════════════════
    # Panel 4: Time To Sequencing Data
    # ═══════════════════════════════════════════════════════════════════
    ax4 = axes[3]
    ax4.set_title("Time To\nSequencing Data", fontsize=7, pad=4)

    bp4 = ax4.boxplot([SEQ_TIME_SHORT_READS, SEQ_TIME_LONG_READS],
                       positions=[1, 2], widths=0.5, patch_artist=False,
                       boxprops=BOXPROPS, medianprops=MEDIANPROPS,
                       flierprops=FLIERPROPS, whiskerprops=WHISKERPROPS,
                       capprops=CAPPROPS)
    ax4.set_xticks([1, 2])
    ax4.set_xticklabels(["Short reads\nAvailable", "Long reads\nAvailable"],
                         rotation=45, ha="right", fontsize=8)
    ax4.set_ylabel("time, hours", fontsize=9)
    ax4.grid(axis="y", alpha=0.3, linewidth=0.5)

    # ── Final layout ──
    fig.subplots_adjust(left=0.05, right=0.98, bottom=0.18, top=0.88)
    fig.savefig(OUTPUT_SVG, format="svg", bbox_inches="tight", dpi=150)
    plt.close(fig)
    print(f"\nSaved: {OUTPUT_SVG}")


if __name__ == "__main__":
    main()
