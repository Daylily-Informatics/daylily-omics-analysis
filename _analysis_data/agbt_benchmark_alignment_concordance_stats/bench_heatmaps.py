#!/usr/bin/env python3
"""Consolidate benchmark data and generate cost/time heatmaps.

Reads all src_data/*/benchmarks_summary.tsv files, filters to 30x samples,
aggregates by (sample, aligner, caller) with stage breakdowns, writes
consolidated_bench.tsv, and generates heatmap_cost_30x.svg + heatmap_time_30x.svg.
"""

import csv
import glob
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
SRC_DATA = os.path.join(BASE_DIR, "src_data")
OUT_TSV = os.path.join(BASE_DIR, "consolidated_bench.tsv")
OUT_COST_SVG = os.path.join(BASE_DIR, "heatmap_cost_30x.svg")
OUT_TIME_SVG = os.path.join(BASE_DIR, "heatmap_time_30x.svg")

# ── Font ──
INTER_PATHS = [p for p in fm.findSystemFonts() if "Inter" in os.path.basename(p)]
if INTER_PATHS:
    for p in INTER_PATHS:
        fm.fontManager.addfont(p)
    plt.rcParams["font.family"] = "Inter"
else:
    plt.rcParams["font.family"] = "sans-serif"
plt.rcParams["font.size"] = 10

# ── 30x sample patterns ──
SAMPLE_30X_PATTERNS = [
    re.compile(r"I2-HG003-30x"),
    re.compile(r"I2-HG003-40x"),
    re.compile(r"Irl1-HG003-30x"),
    re.compile(r"Irl1-HG003-40x"),
    re.compile(r"On1c?-HG003-30x"),
    re.compile(r"On1c?-HG003-40x"),
    re.compile(r"Pb-HG003-3[05]x"),
    re.compile(r"Ug1-HG003-[34]0x"),
    re.compile(r"R30x-HG003"),
    re.compile(r"R0-HG003-30x"),
    re.compile(r"R0-HG003-40x"),
    re.compile(r"RH1-HG003-35x"),
    re.compile(r"HIOa-HG003-SR30x"),
    re.compile(r"HIOv1_HG003"),
    re.compile(r"HUOv1_HG003"),
]


def is_30x_sample(name):
    return any(p.search(name) for p in SAMPLE_30X_PATTERNS)


# ── Stage classification ──
# Alignment: alNsort, aligner-level markdup, minimap2 align, pangenome_sr align
_ALIGN_RE = re.compile(
    r"(\.alNsort$|\.mrkdup$|^pangenome_sr$|\.na\.mrkdup$|"
    r"\.dmd\.mrkdup$|\.downsample$|\.no_dedup|\.vb2$|\.norm_cov)"
)
# Variant calling: caller shards, merge, concat.fofn, peddy, stage1-3, pass1-2, etc.
_CALL_RE = re.compile(
    r"\.(sentd|deep19|clair3|oct|gatk|sentdont|sentdhio|sentdhiom|"
    r"sentdhiomr|sentdhuo|sentdug|sentdpb|sentpg|deep19r|rochehc)"
    r"[\.\d~]"
)
# Also catch single-step callers like pangenome_sr.spmd.sentpg
_CALL_SINGLE_RE = re.compile(
    r"\.(sentd|sentpg|sentdpb|sentdug|sentdhuo|rochehc)$"
)
# Concordance / evaluation
_CONC_RE = re.compile(
    r"(concordance|rtg_vcfeval|parse_vcfeval|filter_variants|prep_for_conc)"
)
# Housekeeping to skip entirely (alignstats anywhere in rule, not just at start)
_SKIP_RE = re.compile(
    r"(^alignstats|\.alignstats|produce_|^dirsetup|combine_mqc|^all\.)"
)


def classify_stage(rule):
    """Classify a rule into alignment, calling, concordance, or skip."""
    if _SKIP_RE.search(rule):
        return "skip"
    if _CONC_RE.search(rule):
        return "concordance"
    if _CALL_RE.search(rule) or _CALL_SINGLE_RE.search(rule):
        return "calling"
    if _ALIGN_RE.search(rule):
        return "alignment"
    # Hybrid sub-steps (sr_align, sr_markdup, mapq0_bed, hybrid_select, etc.)
    if re.search(r"\.(sr_align|sr_markdup|mapq0_bed|hybrid_select|"
                 r"stage[123]|pass[12]|final_norm|model_apply|"
                 r"transfer|transfer_merge)", rule):
        return "calling"
    # Catch remaining caller merges/concats
    if re.search(r"\.(merge|concat\.fofn|peddy|bsqr)$", rule):
        return "calling"
    # Default: treat as alignment (conservative)
    return "alignment"


# Caller names sorted longest-first so sentdhiomr matches before sentdhio, etc.
_CALLER_NAMES = sorted([
    "sentd", "deep19", "clair3", "oct", "gatk", "sentdont",
    "sentdhio", "sentdhiom", "sentdhiomr", "sentdhuo",
    "sentdug", "sentdpb", "sentpg", "deep19r", "rochehc",
], key=len, reverse=True)

_ALIGN_ONLY_TOKENS = {
    "alNsort", "mrkdup", "alignstats", "vb2",
    "norm_cov_eveness", "downsample", "no_dedup_roche",
    "no_dedup", "alignstats_bam",
}


def extract_aligner_caller(rule):
    """Extract (aligner, caller) from rule name.

    Patterns:
      sent.dmd.sentd.1-24       → (sent, sentd)
      bwa2a.dmd.deep19.5        → (bwa2a, deep19)
      sent.dmd.clair3.12        → (sent, clair3)
      ont.na.sentdhiomr.1-24.stage1 → (ont, sentdhiomr)
      pangenome_sr.spmd.sentpg  → (pangenome_sr, sentpg)
      roche.na.deep19r.5        → (roche, deep19r)
      sent.alNsort              → (sent, _align_only_)
      ont.vb2                   → (ont, _align_only_)
    """
    parts = rule.split(".")
    if len(parts) < 2:
        return rule, "_unknown_"
    aligner = parts[0]
    # Find the caller token (skip dedup markers: dmd, na, spmd)
    dedup_tokens = {"dmd", "na", "spmd"}
    caller = None
    for p in parts[1:]:
        if p in dedup_tokens:
            continue
        # Check if this part starts with a known caller name
        for cname in _CALLER_NAMES:
            if p == cname or p.startswith(cname):
                caller = cname
                break
        if caller:
            break
        # Alignment-only rules
        if p in _ALIGN_ONLY_TOKENS:
            return aligner, "_align_only_"
    if caller is None:
        return aligner, "_unknown_"
    return aligner, caller



# ── Display name mappings ──
ALIGNER_DISPLAY = {
    "sent": "sbwa", "bwa2a": "bwa2", "bwa2": "bwa2",
    "ont": "ont(mm2)", "sentmm2ont": "mm2-ont", "sentmm2": "mm2-pb",
    "ug": "ug", "roche": "roche", "pangenome_sr": "pangenome",
}
CALLER_DISPLAY = {
    "sentd": "dnascope", "deep19": "dv1.9", "deep19r": "dv1.9r",
    "clair3": "clair3", "oct": "octopus", "gatk": "gatk-hc",
    "sentdont": "dnascope-ont", "sentdhio": "hio",
    "sentdhiom": "hiom", "sentdhiomr": "hiomr",
    "sentdhuo": "huo", "sentdug": "dnascope-ug",
    "sentdpb": "dnascope-pb", "sentpg": "pangenome",
    "rochehc": "roche-hc",
}


def load_benchmarks():
    """Load all benchmark files and aggregate by (sample, aligner, caller).

    Returns dict keyed by (aligner, caller) → {
        "total_cost": float, "total_secs": float,
        "align_cost": float, "align_secs": float,
        "calling_cost": float, "calling_secs": float,
        "conc_cost": float, "conc_secs": float,
        "n_samples": int, "samples": set,
    }
    """
    # Per-(sample, aligner, caller) accumulators
    acc = defaultdict(lambda: defaultdict(lambda: {
        "total_cost": 0.0, "total_secs": 0.0,
        "align_cost": 0.0, "align_secs": 0.0,
        "calling_cost": 0.0, "calling_secs": 0.0,
        "conc_cost": 0.0, "conc_secs": 0.0,
    }))

    files = sorted(glob.glob(os.path.join(SRC_DATA, "*/benchmarks_summary.tsv")))
    print(f"Found {len(files)} benchmark files")

    for fpath in files:
        tg = os.path.basename(os.path.dirname(fpath))
        n_rows = 0
        n_30x = 0
        with open(fpath, "r") as f:
            reader = csv.DictReader(f, delimiter="\t")
            for row in reader:
                n_rows += 1
                sample = row.get("sample", "").strip()
                if not sample or not is_30x_sample(sample):
                    continue
                n_30x += 1
                rule = row.get("rule", "").strip()
                if not rule:
                    continue

                stage = classify_stage(rule)
                if stage == "skip":
                    continue

                aligner, caller = extract_aligner_caller(rule)
                if caller in ("_align_only_", "_unknown_"):
                    # Alignment-only rule — attribute to all callers for this
                    # aligner+sample (we'll distribute later)
                    pass

                try:
                    secs = float(row.get("s", 0))
                except (ValueError, TypeError):
                    secs = 0.0
                try:
                    cost = float(row.get("task_cost", 0))
                except (ValueError, TypeError):
                    cost = 0.0

                if caller in ("_align_only_", "_unknown_"):
                    # Store alignment costs under a special key; distribute later
                    key = (aligner, "_shared_align_")
                    acc[sample][key]["total_cost"] += cost
                    acc[sample][key]["total_secs"] += secs
                    acc[sample][key]["align_cost"] += cost
                    acc[sample][key]["align_secs"] += secs
                else:
                    key = (aligner, caller)
                    acc[sample][key]["total_cost"] += cost
                    acc[sample][key]["total_secs"] += secs
                    if stage == "alignment":
                        acc[sample][key]["align_cost"] += cost
                        acc[sample][key]["align_secs"] += secs
                    elif stage == "calling":
                        acc[sample][key]["calling_cost"] += cost
                        acc[sample][key]["calling_secs"] += secs
                    elif stage == "concordance":
                        acc[sample][key]["conc_cost"] += cost
                        acc[sample][key]["conc_secs"] += secs

        print(f"  {tg}: {n_rows} rows, {n_30x} are 30x")

    # Distribute shared alignment costs to each caller for same aligner+sample
    for sample, pipelines in acc.items():
        shared_keys = [k for k in pipelines if k[1] == "_shared_align_"]
        for sk in shared_keys:
            aligner = sk[0]
            shared = pipelines.pop(sk)
            # Find callers using this aligner
            caller_keys = [k for k in pipelines if k[0] == aligner]
            n_callers = len(caller_keys)
            if n_callers == 0:
                continue
            per_caller_cost = shared["align_cost"] / n_callers
            per_caller_secs = shared["align_secs"] / n_callers
            for ck in caller_keys:
                pipelines[ck]["total_cost"] += per_caller_cost
                pipelines[ck]["total_secs"] += per_caller_secs
                pipelines[ck]["align_cost"] += per_caller_cost
                pipelines[ck]["align_secs"] += per_caller_secs

    # Aggregate across samples → per (aligner, caller) means
    result = {}
    for sample, pipelines in acc.items():
        for (aligner, caller), vals in pipelines.items():
            if caller.startswith("_"):
                continue
            if (aligner, caller) not in result:
                result[(aligner, caller)] = {
                    "total_cost": [], "total_secs": [],
                    "align_cost": [], "align_secs": [],
                    "calling_cost": [], "calling_secs": [],
                    "conc_cost": [], "conc_secs": [],
                    "samples": set(),
                }
            r = result[(aligner, caller)]
            for field in ("total_cost", "total_secs", "align_cost", "align_secs",
                          "calling_cost", "calling_secs", "conc_cost", "conc_secs"):
                r[field].append(vals[field])
            r["samples"].add(sample)

    return result


# ── Pipeline display ordering ──
# Sections: hg38 → hybrid → long-read → pangenome
PIPELINE_SECTION_ORDER = [
    # hg38 short-read
    ("sent", "sentd"), ("sent", "gatk"), ("sent", "deep19"), ("sent", "clair3"),
    ("sent", "oct"),
    ("bwa2a", "sentd"), ("bwa2a", "deep19"), ("bwa2a", "clair3"),
    # Roche
    ("roche", "deep19r"), ("roche", "rochehc"),
    # Ultima
    ("ug", "sentdug"),
    # Hybrid
    ("ont", "sentdhio"), ("ont", "sentdhiom"), ("ont", "sentdhiomr"),
    ("ont", "sentdhuo"),
    # Long-read
    ("ont", "deep19"), ("sentmm2ont", "deep19"),
    ("sentmm2", "sentdpb"),
    # Pangenome
    ("pangenome_sr", "sentpg"),
]


def _display_label(aligner, caller):
    """Human-readable label for a pipeline."""
    a = ALIGNER_DISPLAY.get(aligner, aligner)
    c = CALLER_DISPLAY.get(caller, caller)
    return f"{a} + {c}"


def write_bench_tsv(result, path):
    """Write consolidated benchmark data to TSV."""
    header = [
        "Aligner", "Caller", "DisplayLabel", "NSamples",
        "AvgTotalCost", "AvgTotalSecs",
        "AvgAlignCost", "AvgAlignSecs",
        "AvgCallingCost", "AvgCallingSecs",
        "AvgConcCost", "AvgConcSecs",
    ]
    rows = []
    for (aligner, caller), r in sorted(result.items()):
        n = len(r["samples"])
        row = [
            aligner, caller, _display_label(aligner, caller), str(n),
        ]
        for field in ("total_cost", "total_secs", "align_cost", "align_secs",
                       "calling_cost", "calling_secs", "conc_cost", "conc_secs"):
            avg = sum(r[field]) / len(r[field]) if r[field] else 0.0
            row.append(f"{avg:.4f}")
        rows.append(row)

    with open(path, "w", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerow(header)
        for row in rows:
            writer.writerow(row)
    print(f"Wrote {len(rows)} pipelines to {path}")


def _section_for_pipeline(aligner, caller):
    """Return section label for grouping."""
    if caller in ("sentdhio", "sentdhiom", "sentdhiomr", "sentdhuo"):
        return "Hybrid (ILMN+ONT)"
    if aligner in ("pangenome_sr",):
        return "Pangenome"
    if aligner in ("sentmm2", "sentmm2ont") or (aligner == "ont" and caller == "deep19"):
        return "Long Read"
    if aligner == "roche":
        return "Roche"
    if aligner == "ug":
        return "Ultima"
    return "Short Read (hg38)"


def plot_bench_heatmap(result, metric, out_path):
    """Generate a benchmark heatmap SVG.

    metric: "cost" or "time"
    """
    # Build ordered list of pipelines present in data
    ordered = [p for p in PIPELINE_SECTION_ORDER if p in result]
    # Add any extras not in the ordering
    extras = sorted(k for k in result if k not in ordered)
    ordered.extend(extras)

    if not ordered:
        print(f"  No data for {metric} heatmap")
        return

    # Stages: alignment, calling, concordance
    stages = ["Alignment", "Calling", "Concordance"]
    stage_keys = {
        "cost": ["align_cost", "calling_cost", "conc_cost"],
        "time": ["align_secs", "calling_secs", "conc_secs"],
    }
    keys = stage_keys[metric]
    unit = "$" if metric == "cost" else "sec"
    title_word = "Cost (USD)" if metric == "cost" else "Time (seconds)"

    n_rows = len(ordered)
    n_cols = len(stages)
    mat = np.zeros((n_rows, n_cols))
    labels_y = []

    for i, (aligner, caller) in enumerate(ordered):
        r = result[(aligner, caller)]
        labels_y.append(_display_label(aligner, caller))
        for j, key in enumerate(keys):
            avg = sum(r[key]) / len(r[key]) if r[key] else 0.0
            mat[i, j] = avg

    # Also compute totals for annotation
    totals = np.sum(mat, axis=1)

    # Figure sizing
    fig_w = max(8, 3 + n_cols * 1.8)
    fig_h = max(4, 1.5 + n_rows * 0.55)
    fig, ax = plt.subplots(figsize=(fig_w, fig_h))
    fig.patch.set_facecolor("white")

    # Color map: use sequential colormap
    if metric == "cost":
        cmap = plt.cm.YlOrRd
    else:
        cmap = plt.cm.YlGnBu

    vmax = np.max(mat) if np.max(mat) > 0 else 1
    im = ax.imshow(mat, aspect="auto", cmap=cmap, vmin=0, vmax=vmax,
                   interpolation="nearest")

    # Y-axis: pipeline labels
    ax.set_yticks(range(n_rows))
    ax.set_yticklabels(labels_y, fontsize=9.5)

    # X-axis: stage labels
    ax.set_xticks(range(n_cols))
    ax.set_xticklabels(stages, fontsize=11, fontweight="bold")
    ax.xaxis.set_ticks_position("top")
    ax.xaxis.set_label_position("top")

    # Section separators on Y-axis
    prev_section = None
    section_bounds = []
    for i, (aligner, caller) in enumerate(ordered):
        sec = _section_for_pipeline(aligner, caller)
        if sec != prev_section:
            if prev_section is not None:
                ax.axhline(y=i - 0.5, color="#aaa", linewidth=0.8,
                           linestyle="--", alpha=0.6)
            section_bounds.append((i, sec))
            prev_section = sec

    # Annotate cells with values
    for i in range(n_rows):
        for j in range(n_cols):
            val = mat[i, j]
            if val < 0.005:
                txt = "—"
                color = "#999"
            elif metric == "cost":
                txt = f"${val:.2f}"
                color = "white" if val > vmax * 0.55 else "black"
            else:
                if val >= 3600:
                    txt = f"{val/3600:.1f}h"
                elif val >= 60:
                    txt = f"{val/60:.0f}m"
                else:
                    txt = f"{val:.0f}s"
                color = "white" if val > vmax * 0.55 else "black"
            ax.text(j, i, txt, ha="center", va="center",
                    fontsize=8.5, color=color, fontweight="bold")

    # Add total column annotation to the right
    for i in range(n_rows):
        total = totals[i]
        if metric == "cost":
            lbl = f"${total:.2f}"
        else:
            if total >= 3600:
                lbl = f"{total/3600:.1f}h"
            elif total >= 60:
                lbl = f"{total/60:.0f}m"
            else:
                lbl = f"{total:.0f}s"
        ax.text(n_cols - 0.3, i, f"  Σ {lbl}", ha="left", va="center",
                fontsize=8, color="#555", fontweight="bold",
                transform=ax.get_yaxis_transform())

    # Section labels on right margin
    for idx, (start, sec_name) in enumerate(section_bounds):
        end = section_bounds[idx + 1][0] if idx + 1 < len(section_bounds) else n_rows
        mid = (start + end - 1) / 2.0
        ax.text(1.02, mid, sec_name, ha="left", va="center",
                fontsize=8, color="#6366f1", fontstyle="italic",
                transform=ax.get_yaxis_transform())

    # Colorbar
    cbar = fig.colorbar(im, ax=ax, shrink=0.6, pad=0.15)
    cbar.set_label(title_word, fontsize=10)

    # Title
    n_samples_range = [len(result[k]["samples"]) for k in ordered]
    smin, smax = min(n_samples_range), max(n_samples_range)
    ax.set_title(
        f"30x Genome Pipeline Benchmark — Average {title_word}\n"
        f"({smin}–{smax} samples per pipeline)",
        fontsize=13, fontweight="bold", pad=25,
    )

    fig.tight_layout()
    fig.savefig(out_path, format="svg", bbox_inches="tight", dpi=150)
    plt.close(fig)
    print(f"Saved {out_path}")


# ── Main ──
def main():
    print("=" * 60)
    print("Benchmark Consolidation & Heatmap Generation")
    print("=" * 60)

    data = load_benchmarks()

    if not data:
        print("ERROR: No benchmark data loaded", file=sys.stderr)
        sys.exit(1)

    # Summary
    print(f"\nPipelines found: {len(data)}")
    for (al, ca) in sorted(data.keys()):
        r = data[(al, ca)]
        n = len(r["samples"])
        avg_cost = sum(r["total_cost"]) / n if n else 0
        avg_secs = sum(r["total_secs"]) / n if n else 0
        print(f"  {_display_label(al, ca):30s}  n={n:2d}  "
              f"avg_cost=${avg_cost:8.2f}  avg_time={avg_secs:10.1f}s")

    # Write TSV
    write_bench_tsv(data, OUT_TSV)

    # Generate heatmaps
    plot_bench_heatmap(data, "cost", OUT_COST_SVG)
    plot_bench_heatmap(data, "time", OUT_TIME_SVG)

    print("\nDone.")


if __name__ == "__main__":
    main()
