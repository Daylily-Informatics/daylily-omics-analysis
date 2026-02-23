#!/usr/bin/env python3
"""Generate HIOa hybrid workflow heatmap report.

Reads: _analysis_data/hioa_data.json
Outputs:
  _analysis_data/HIOa_fscore_heatmap.png
  _analysis_data/HIOa_runtime_heatmap.png
  _analysis_data/HIOa_cost_heatmap.png
  _analysis_data/HIOa_heatmap_report.md
"""

import csv
import json
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from matplotlib.patches import FancyBboxPatch
from pathlib import Path
from datetime import datetime

BASE = Path(__file__).resolve().parent

# ── Datasets to EXCLUDE (corrupt CRAMs, bad runs, etc.) ─────────────
ONT_SKIP_TARGETS = {30}  # ONT 30x CRAM suspected corrupt


# ── Load measured coverage from alignstats ───────────────────────────
def _load_measured_coverage(tsv_path):
    """Return dict: target_coverage -> WgsCoverageMean from alignstats_combo_mqc.tsv."""
    import re
    result = {}
    if not Path(tsv_path).exists():
        return result
    with open(tsv_path) as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            m = re.search(r"-(\d+)x-", row["sample"])
            if not m:
                continue
            target = int(m.group(1))
            try:
                result[target] = float(row["WgsCoverageMean"])
            except (ValueError, TypeError):
                pass
    return result


ILMN_ALIGNSTATS = BASE / "ilmn_hg003_prod" / "alignstats_combo_mqc.tsv"
ONT_ALIGNSTATS = BASE / "agbt_ont" / "alignstats_combo_mqc.tsv"

MEASURED_COV = {
    "ilmn": _load_measured_coverage(ILMN_ALIGNSTATS),
    "ont": _load_measured_coverage(ONT_ALIGNSTATS),
}
print("ILMN target→measured:", {k: f"{v:.1f}x" for k, v in sorted(MEASURED_COV["ilmn"].items())})
print("ONT  target→measured:", {k: f"{v:.1f}x" for k, v in sorted(MEASURED_COV["ont"].items())})


# ── Load single-platform concordance data for the 0x axes ───────────
SNP_CLASSES = ["SNPts", "SNPtv", "INS_50", "INS_gt50", "DEL_50", "DEL_gt50",
               "Indel_50", "Indel_gt50", "All"]
FOOTPRINTS = ["giabHC", "clinvar_genes", "hg38"]
# Map footprint → concordance key in hioa_data.json
FOOTPRINT_DATA_KEY = {
    "giabHC": "concordance",
    "clinvar_genes": "concordance_clinvar",
    "hg38": "concordance_hg38",
}


def _load_single_platform(tsv_path, footprint_filter, snp_class, skip_targets=None):
    """Return dict: target_coverage -> {Fscore, TP, FN, FP} for a given SNP class + footprint."""
    import re
    result = {}
    if not Path(tsv_path).exists():
        return result
    with open(tsv_path) as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            if row["VariantClass"] != snp_class:
                continue
            if row.get("ROI", "") != footprint_filter:
                continue
            m = re.search(r"-(\d+)x-", row["Sample"])
            if not m:
                continue
            cov = int(m.group(1))
            if skip_targets and cov in skip_targets:
                continue
            try:
                result[cov] = {
                    "Fscore": float(row["Fscore"]),
                    "TP": int(float(row.get("TP", 0))),
                    "FN": int(float(row.get("FN", 0))),
                    "FP": int(float(row.get("FP", 0))),
                }
            except (ValueError, TypeError):
                pass
    return result


# Pre-load ALL class × footprint combos for both platforms
ILMN_TSV = BASE / "ilmn_hg003_prod" / "giab_concordance_mqc.tsv"
ONT_TSV = BASE / "agbt_ont" / "giab_concordance_mqc.tsv"

SINGLE_PLATFORM = {"ilmn": {}, "ont": {}}
for _fp in FOOTPRINTS:
    for _cls in SNP_CLASSES:
        SINGLE_PLATFORM["ilmn"][(_fp, _cls)] = _load_single_platform(
            ILMN_TSV, _fp, _cls)
        SINGLE_PLATFORM["ont"][(_fp, _cls)] = _load_single_platform(
            ONT_TSV, _fp, _cls, ONT_SKIP_TARGETS)
print(f"Loaded single-platform data: {len(FOOTPRINTS)} footprints × {len(SNP_CLASSES)} classes")

# --- Currently running on slurm (snapshot 2026-02-18) ---
RUNNING_UNITS = {
    (10, 10), (3, 3), (40, 10), (5, 3), (7, 10), (7, 3),   # sentdhio_snv
    (15, 3), (15, 7), (30, 10), (40, 7), (5, 1), (7, 1),    # prep_for_concordance
}

STAGE_MAP = {
    "mrkdup": "alignment", "alignstats": "alignstats",
    "sentdhio": "variant_calling", "concordance": "concordance",
}

def classify_stage(rule):
    for key, stage in STAGE_MAP.items():
        if key in rule:
            return stage
    return "other"

# --- Load data ---
with open(BASE / "hioa_data.json") as f:
    data = json.load(f)

units = data["units"]

# Prepend 0 (single-platform axis) before the hybrid coverage levels
# Filter out ONT targets flagged for exclusion
sr_covs = [0] + sorted(set(u["sr_cov"] for u in units))
ont_covs = [0] + sorted(c for c in set(u["ont_cov"] for u in units)
                         if c not in ONT_SKIP_TARGETS)
sr_idx = {c: i for i, c in enumerate(sr_covs)}
ont_idx = {c: i for i, c in enumerate(ont_covs)}
nsr, nont = len(sr_covs), len(ont_covs)

print(f"SR axis (target):  {sr_covs}")
print(f"ONT axis (target): {ont_covs}")


# ── Helper: format axis label with measured coverage ─────────────────
def _meas_label(target_cov, platform):
    """Return axis label: 'measured_x\\n(tgt Nx)' e.g. '11.4x\\n(tgt 10x)'."""
    if target_cov == 0:
        return ""  # handled separately
    meas = MEASURED_COV[platform].get(target_cov)
    if meas is not None:
        return f"{meas:.1f}x\n(tgt {target_cov}x)"
    return f"~{target_cov}x"


# --- Build matrices ---
fscore_mat = np.full((nsr, nont), np.nan)
runtime_mat = np.full((nsr, nont), np.nan)
cost_mat = np.full((nsr, nont), np.nan)
status_mat = {}  # (sr, ont) -> status string

for u in units:
    # Skip units with excluded ONT coverage
    if u["ont_cov"] in ONT_SKIP_TARGETS:
        continue
    si, oi = sr_idx[u["sr_cov"]], ont_idx[u["ont_cov"]]
    key = (u["sr_cov"], u["ont_cov"])

    # Determine status
    if u["concordance"]:
        status_mat[key] = "Complete"
        all_cls = u["concordance"].get("All", {})
        if all_cls:
            fscore_mat[si, oi] = all_cls["Fscore"]
    elif key in RUNNING_UNITS:
        status_mat[key] = "Running"
    elif u["status"] == "Complete":
        status_mat[key] = "Complete"
    elif u["status"] in ("In Progress", "VCF_Done"):
        status_mat[key] = "Running"
    else:
        status_mat[key] = "Failed"

    # Benchmarks
    total_wall = 0
    total_cost = 0
    for b in u.get("benchmarks", []):
        total_wall += b["wall_sec"]
        total_cost += b["task_cost"]
    if total_wall > 0:
        runtime_mat[si, oi] = total_wall / 60.0  # minutes
    if total_cost > 0:
        cost_mat[si, oi] = total_cost

# Mark single-platform 0x cells as "SinglePlatform" in status_mat
# ONT0x column (col 0): ILMN-only results at each SR coverage
for sr_c in sr_covs:
    if sr_c == 0:
        continue  # (0, 0) stays NaN
    status_mat[(sr_c, 0)] = "SinglePlatform"
# SR0x row (row 0): ONT-only results at each ONT coverage
for ont_c in ont_covs:
    if ont_c == 0:
        continue  # (0, 0) stays NaN
    status_mat[(0, ont_c)] = "SinglePlatform"

# Axis labels: use MEASURED coverage from alignstats, not target
sr_labels = ["0x\n(ONT only)" if c == 0 else _meas_label(c, "ilmn") for c in sr_covs]
ont_labels = ["0x\n(ILMN only)" if c == 0 else _meas_label(c, "ont") for c in ont_covs]


def _fmt_count(n):
    """Format large counts concisely: 1234567 -> 1.23M, 12345 -> 12.3K, 999 -> 999."""
    if n >= 1_000_000:
        return f"{n/1_000_000:.2f}M"
    if n >= 10_000:
        return f"{n/1_000:.1f}K"
    if n >= 1_000:
        return f"{n/1_000:.2f}K"
    return str(n)


def make_heatmap(matrix, title, cbar_label, filename, fmt_func, cmap_name="YlOrRd",
                 low_is_good=False, vmin=None, vmax=None, annot=None):
    """Create an annotated heatmap with status overlays and optional TP/FN/FP counts.

    annot: optional dict {(si, oi): {"TP": int, "FN": int, "FP": int}}
    """
    fig, ax = plt.subplots(figsize=(14, 11))

    # Mask NaN for colormap
    masked = np.ma.masked_invalid(matrix)

    if vmin is None:
        vmin = np.nanmin(matrix) if np.any(~np.isnan(matrix)) else 0
    if vmax is None:
        vmax = np.nanmax(matrix) if np.any(~np.isnan(matrix)) else 1

    cmap = plt.get_cmap(cmap_name).copy()
    cmap.set_bad(color="#2d2d2d")
    norm = mcolors.Normalize(vmin=vmin, vmax=vmax)

    im = ax.imshow(masked, cmap=cmap, norm=norm, aspect="auto", origin="lower")
    cbar = fig.colorbar(im, ax=ax, shrink=0.8, pad=0.02)
    cbar.set_label(cbar_label, fontsize=12)

    ax.set_xticks(range(nont))
    ax.set_xticklabels(ont_labels, fontsize=10)
    ax.set_yticks(range(nsr))
    ax.set_yticklabels(sr_labels, fontsize=10)
    ax.set_xlabel("ONT Measured Coverage", fontsize=13, fontweight="bold")
    ax.set_ylabel("Illumina (SR) Measured Coverage", fontsize=13, fontweight="bold")
    ax.set_title(title, fontsize=14, fontweight="bold", pad=12)

    # Annotate cells
    for si in range(nsr):
        for oi in range(nont):
            sr_c, ont_c = sr_covs[si], ont_covs[oi]
            key = (sr_c, ont_c)
            status = status_mat.get(key, "?")
            val = matrix[si, oi]

            if not np.isnan(val) and status in ("Complete", "SinglePlatform"):
                rgba = cmap(norm(val))
                lum = 0.299 * rgba[0] + 0.587 * rgba[1] + 0.114 * rgba[2]
                tc = "white" if lum < 0.5 else "black"
                is_sp = status == "SinglePlatform"
                style = "italic" if is_sp else "normal"

                # F-score line
                fs_size = 6.5 if is_sp else 7.5
                ax.text(oi, si + 0.22, fmt_func(val), ha="center", va="center",
                        fontsize=fs_size, fontweight="bold", color=tc, fontstyle=style)

                # TP/FN/FP lines (if available)
                a = (annot or {}).get((si, oi))
                if a:
                    detail_size = 4.5 if is_sp else 5.0
                    tp_s = _fmt_count(a["TP"])
                    fn_s = _fmt_count(a["FN"])
                    fp_s = _fmt_count(a["FP"])
                    ax.text(oi, si - 0.02, f"TP {tp_s}",
                            ha="center", va="center", fontsize=detail_size,
                            color=tc, fontstyle=style, alpha=0.85)
                    ax.text(oi, si - 0.22, f"FN {fn_s} FP {fp_s}",
                            ha="center", va="center", fontsize=detail_size,
                            color=tc, fontstyle=style, alpha=0.85)

            elif status == "Running":
                ax.add_patch(plt.Circle((oi, si), 0.35, fill=True,
                             facecolor="#3b82f6", alpha=0.25, edgecolor="#3b82f6", lw=1.5))
                ax.text(oi, si, "...", ha="center", va="center",
                        fontsize=10, fontweight="bold", color="#3b82f6")
            elif status == "Failed":
                ax.add_patch(plt.Circle((oi, si), 0.35, fill=True,
                             facecolor="#ef4444", alpha=0.15, edgecolor="#ef4444", lw=1.5))
                ax.text(oi, si, "FAIL", ha="center", va="center",
                        fontsize=7, fontweight="bold", color="#ef4444")
            else:
                if not np.isnan(val):
                    txt = fmt_func(val)
                    ax.text(oi, si, txt, ha="center", va="center",
                            fontsize=7, color="#a3a3a3")

    # Grid lines
    for si in range(nsr + 1):
        ax.axhline(si - 0.5, color="#4a4a4a", linewidth=0.5)
    for oi in range(nont + 1):
        ax.axvline(oi - 0.5, color="#4a4a4a", linewidth=0.5)

    # Thicker separator between 0x (single-platform) and 1x+ (hybrid)
    ax.axhline(0.5, color="#d4d4d4", linewidth=2.0, linestyle="--")
    ax.axvline(0.5, color="#d4d4d4", linewidth=2.0, linestyle="--")

    # Legend
    legend_text = ("F-score / TP / FN+FP  |  italic = single-platform  "
                   "|  ... = running  |  FAIL = failed")
    fig.text(0.5, 0.01, legend_text, ha="center", fontsize=9, color="#6b6b6b")

    fig.tight_layout(rect=[0, 0.03, 1, 1])
    fig.savefig(BASE / filename, dpi=180, bbox_inches="tight",
                facecolor="white", edgecolor="none")
    plt.close(fig)
    print(f"Saved: {BASE / filename}")


# ── Helper: inject single-platform data into matrices ─────────────────
def fill_single_platform(matrix, annot, footprint_key, snp_class="SNPts"):
    """Fill the 0x row/column with single-platform F-scores and TP/FN/FP annotations."""
    key = (footprint_key, snp_class)
    ilmn_data = SINGLE_PLATFORM["ilmn"].get(key, {})
    ont_data = SINGLE_PLATFORM["ont"].get(key, {})
    # ONT0x column (col 0 = ont_covs[0]=0): ILMN-only at each SR coverage
    for sr_c in sr_covs:
        if sr_c == 0:
            continue
        d = ilmn_data.get(sr_c)
        if d and sr_c in sr_idx:
            si, oi = sr_idx[sr_c], ont_idx[0]
            matrix[si, oi] = d["Fscore"]
            annot[(si, oi)] = {"TP": d["TP"], "FN": d["FN"], "FP": d["FP"]}
    # SR0x row (row 0 = sr_covs[0]=0): ONT-only at each ONT coverage
    for ont_c in ont_covs:
        if ont_c == 0:
            continue
        d = ont_data.get(ont_c)
        if d and ont_c in ont_idx:
            si, oi = sr_idx[0], ont_idx[ont_c]
            matrix[si, oi] = d["Fscore"]
            annot[(si, oi)] = {"TP": d["TP"], "FN": d["FN"], "FP": d["FP"]}


# ── Generate F-score heatmaps: all SNP classes × all footprints ──────
FOOTPRINT_LABELS = {
    "giabHC": "giabHC",
    "clinvar_genes": "ClinVar Genes",
    "hg38": "hg38 whole genome",
}

# Keep a reference to the giabHC SNPts matrix for the markdown report
fscore_snpts = None

for fp in FOOTPRINTS:
    data_key = FOOTPRINT_DATA_KEY[fp]
    fp_label = FOOTPRINT_LABELS[fp]
    for cls in SNP_CLASSES:
        mat = np.full((nsr, nont), np.nan)
        annot_dict = {}
        for u in units:
            if u["ont_cov"] in ONT_SKIP_TARGETS:
                continue
            si, oi = sr_idx[u["sr_cov"]], ont_idx[u["ont_cov"]]
            cls_data = u.get(data_key, {}).get(cls, {})
            if cls_data:
                mat[si, oi] = cls_data["Fscore"]
                annot_dict[(si, oi)] = {
                    "TP": cls_data["TP"],
                    "FN": cls_data["FN"],
                    "FP": cls_data["FP"],
                }
        fill_single_platform(mat, annot_dict, fp, cls)

        # File naming: HIOa_fscore_{class}_{footprint}.png
        safe_cls = cls.lower()
        safe_fp = fp.lower().replace(" ", "_")
        filename = f"HIOa_fscore_{safe_cls}_{safe_fp}.png"

        title = (f"HIOa Hybrid: {cls} F-score ({fp_label})\n"
                 f"Illumina × ONT Coverage Matrix  (0x = single-platform baseline)")

        make_heatmap(
            mat, title, f"{cls} F-score", filename,
            lambda v: f"{v:.3f}",
            cmap_name="RdYlGn",
            vmin=0.0, vmax=1.0,
            annot=annot_dict,
        )

        # Stash the giabHC SNPts matrix for the markdown report
        if fp == "giabHC" and cls == "SNPts":
            fscore_snpts = mat

# 2. Runtime heatmap
make_heatmap(
    runtime_mat,
    "HIOa Hybrid: Total Runtime (minutes)\nIllumina × ONT Coverage Matrix",
    "Runtime (min)",
    "HIOa_runtime_heatmap.png",
    lambda v: f"{v:.0f}",
    cmap_name="YlOrRd",
)

# 3. Cost heatmap
make_heatmap(
    cost_mat,
    "HIOa Hybrid: Total Compute Cost (USD)\nIllumina × ONT Coverage Matrix",
    "Cost (USD)",
    "HIOa_cost_heatmap.png",
    lambda v: f"${v:.2f}",
    cmap_name="YlOrRd",
)


# ── Generate Markdown Report ─────────────────────────────────────────

md_path = BASE / "HIOa_heatmap_report.md"
# Filter out excluded ONT targets for reporting
_valid_units = [u for u in units if u["ont_cov"] not in ONT_SKIP_TARGETS]
complete_units = [u for u in _valid_units if status_mat.get((u["sr_cov"], u["ont_cov"])) == "Complete"]
running_units = [u for u in _valid_units if status_mat.get((u["sr_cov"], u["ont_cov"])) == "Running"]
failed_units = [u for u in _valid_units if status_mat.get((u["sr_cov"], u["ont_cov"])) == "Failed"]

with open(md_path, "w") as md:
    md.write("# HIOa Hybrid ILMN+ONT Workflow — Heatmap Report\n\n")
    md.write(f"**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
    md.write("| Parameter | Value |\n|---|---|\n")
    md.write("| Genome Build | hg38_broad |\n")
    md.write("| Sample | HG003 (Ashkenazi Jewish Father) |\n")
    md.write("| Variant Caller | Sentieon DNAscope Hybrid ILMN+ONT (sentdhio) |\n")
    md.write("| Concordance Footprint | giabHC (GIAB high-confidence regions) |\n")
    md.write(f"| Matrix | {nsr} ILMN coverages × {nont} ONT coverages = {nsr*nont} units |\n")
    md.write("| Workflow Config | `-T 1 -j 20 -k -p` (1 retry, 20 concurrent) |\n\n")

    md.write("## Unit Status\n\n")
    md.write(f"| Status | Count |\n|---|---|\n")
    md.write(f"| ✅ Complete (concordance done) | {len(complete_units)} |\n")
    md.write(f"| 🔄 Running | {len(running_units)} |\n")
    md.write(f"| ✗ Failed | {len(failed_units)} |\n")
    md.write(f"| **Total** | **{len(units)}** |\n\n")

    # ── Embed all 27 class × footprint F-score heatmaps ──────────────
    for fp in FOOTPRINTS:
        fp_label = FOOTPRINT_LABELS[fp]
        md.write(f"---\n\n## F-score Heatmaps — {fp_label}\n\n")
        for cls in SNP_CLASSES:
            safe_cls = cls.lower()
            safe_fp = fp.lower().replace(" ", "_")
            fname = f"HIOa_fscore_{safe_cls}_{safe_fp}.png"
            md.write(f"### {cls} ({fp_label})\n\n")
            md.write(f"![{cls} F-score — {fp_label}]({fname})\n\n")
    md.write("\n")

    md.write("---\n\n")
    md.write("## Runtime Heatmap\n\n")
    md.write("Total wall-clock time per unit (all stages: alignment, dedup, variant calling, concordance).\n\n")
    md.write("![Runtime Heatmap](HIOa_runtime_heatmap.png)\n\n")

    # Runtime text table
    md.write("### Runtime Matrix (minutes)\n\n")
    md.write("| SR \\ ONT | " + " | ".join(ont_labels) + " |\n")
    md.write("|---|" + "|".join(["---"] * nont) + "|\n")
    for si, sr in enumerate(sr_covs):
        cells = []
        for oi, ont in enumerate(ont_covs):
            v = runtime_mat[si, oi]
            st = status_mat.get((sr, ont), "?")
            if not np.isnan(v):
                cells.append(f"{v:.0f}")
            elif st == "Running":
                cells.append("🔄")
            else:
                cells.append("✗")
        md.write(f"| **{sr}x** | " + " | ".join(cells) + " |\n")
    md.write("\n")

    md.write("---\n\n")
    md.write("## Cost Heatmap\n\n")
    md.write("Total compute cost per unit (USD, pro-rated by thread allocation on shared nodes).\n\n")
    md.write("![Cost Heatmap](HIOa_cost_heatmap.png)\n\n")

    # Cost text table
    md.write("### Cost Matrix (USD)\n\n")
    md.write("| SR \\ ONT | " + " | ".join(ont_labels) + " |\n")
    md.write("|---|" + "|".join(["---"] * nont) + "|\n")
    for si, sr in enumerate(sr_covs):
        cells = []
        for oi, ont in enumerate(ont_covs):
            v = cost_mat[si, oi]
            st = status_mat.get((sr, ont), "?")
            if not np.isnan(v):
                cells.append(f"${v:.2f}")
            elif st == "Running":
                cells.append("🔄")
            else:
                cells.append("✗")
        md.write(f"| **{sr}x** | " + " | ".join(cells) + " |\n")
    md.write("\n")

    # Summary stats
    md.write("---\n\n")
    md.write("## Summary Statistics (completed units only)\n\n")

    valid_fs = fscore_snpts[~np.isnan(fscore_snpts)]
    valid_rt = runtime_mat[~np.isnan(runtime_mat)]
    valid_co = cost_mat[~np.isnan(cost_mat)]

    md.write("| Metric | Min | Mean | Median | Max |\n")
    md.write("|---|---|---|---|---|\n")
    if len(valid_fs) > 0:
        md.write(f"| SNPts Fscore | {np.min(valid_fs):.4f} | {np.mean(valid_fs):.4f} | "
                 f"{np.median(valid_fs):.4f} | {np.max(valid_fs):.4f} |\n")
    if len(valid_rt) > 0:
        md.write(f"| Runtime (min) | {np.min(valid_rt):.0f} | {np.mean(valid_rt):.0f} | "
                 f"{np.median(valid_rt):.0f} | {np.max(valid_rt):.0f} |\n")
    if len(valid_co) > 0:
        md.write(f"| Cost (USD) | ${np.min(valid_co):.2f} | ${np.mean(valid_co):.2f} | "
                 f"${np.median(valid_co):.2f} | ${np.max(valid_co):.2f} |\n")
    md.write(f"\n**Total cost (all units with data)**: ${np.nansum(cost_mat):.2f}\n\n")
    md.write(f"**Total runtime (all units with data)**: {np.nansum(runtime_mat)/60:.1f} hours\n\n")

    # Key observations
    md.write("---\n\n")
    md.write("## Key Observations\n\n")

    # Find best Fscore unit
    if len(valid_fs) > 0:
        best_idx = np.unravel_index(np.nanargmax(fscore_snpts), fscore_snpts.shape)
        best_sr, best_ont = sr_covs[best_idx[0]], ont_covs[best_idx[1]]
        best_val = fscore_snpts[best_idx]
        md.write(f"- **Best SNPts F-score**: SR{best_sr}x-ONT{best_ont}x = **{best_val:.4f}**\n")

        worst_idx = np.unravel_index(np.nanargmin(fscore_snpts), fscore_snpts.shape)
        worst_sr, worst_ont = sr_covs[worst_idx[0]], ont_covs[worst_idx[1]]
        worst_val = fscore_snpts[worst_idx]
        md.write(f"- **Worst SNPts F-score**: SR{worst_sr}x-ONT{worst_ont}x = **{worst_val:.4f}**\n")

    if len(valid_co) > 0:
        cheapest_idx = np.unravel_index(np.nanargmin(cost_mat), cost_mat.shape)
        cheap_sr, cheap_ont = sr_covs[cheapest_idx[0]], ont_covs[cheapest_idx[1]]
        md.write(f"- **Cheapest unit**: SR{cheap_sr}x-ONT{cheap_ont}x = **${cost_mat[cheapest_idx]:.2f}**\n")

        priciest_idx = np.unravel_index(np.nanargmax(cost_mat), cost_mat.shape)
        price_sr, price_ont = sr_covs[priciest_idx[0]], ont_covs[priciest_idx[1]]
        md.write(f"- **Most expensive unit**: SR{price_sr}x-ONT{price_ont}x = **${cost_mat[priciest_idx]:.2f}**\n")

    md.write(f"- **Failed units**: {len(failed_units)}/{len(units)} "
             f"({100*len(failed_units)/len(units):.0f}%)\n")
    md.write(f"- **Still running**: {len(running_units)}/{len(units)}\n\n")

    # Failed units table
    if failed_units:
        md.write("### Failed Units\n\n")
        md.write("| Unit | Failure Reason |\n|---|---|\n")
        for u in sorted(failed_units, key=lambda x: (x["sr_cov"], x["ont_cov"])):
            short = f"SR{u['sr_cov']}x-ONT{u['ont_cov']}x"
            reason = u.get("failure_reason", "") or "sentdhio_snv failed (no diagnostic)"
            md.write(f"| {short} | {reason} |\n")
        md.write("\n")

print(f"\nMarkdown report: {md_path}")
print(f"Complete: {len(complete_units)}, Running: {len(running_units)}, Failed: {len(failed_units)}")

