#!/usr/bin/env python3
"""Generate cost heatmaps from benchmark data, using the same grid layout as F-score heatmaps.

Usage: python heatmap_cost.py

Reads benchmark TSVs from each test group, sums task_cost per sample
(excluding concordance/post-processing rules), then maps each sample to
the same (column_label, coverage_bin) cell used by the F-score heatmaps.

Output: heatmaps_cost/ directory with one SVG.
"""

import csv
import os
import re
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.colors as mcolors
import matplotlib.pyplot as plt
import numpy as np

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
INPUT_TSV = os.path.join(BASE_DIR, "consolidated_concordance.tsv")

SPACER_LABEL = ""

# Test groups to skip in heatmap (duplicates)
SKIP_TEST_GROUPS = {"ilmn_hg003_ilmn_sentonly"}

# Benchmark file locations per test group (None = no benchmarks)
BENCHMARK_FILES = {
    "hio_cli": "hio_cli/benchmarks_summary.tsv",
    "hio_fillin": "hio_fillin/benchmarks_summary.tsv",
    "hio_old": "hio_old/benchmarks_summary.tsv",
    "ilmn_all_downsamples_a": "ilmn_all_downsamples_a/benchmarks_summary.tsv",
    "ilmn_hg003_ilmn_sentonly": "ilmn_hg003_ilmn_sentonly/benchmarks_summary.tsv",
    "ilmn_read_trim": "ilmn_read_trim/benchmarks_summary.tsv",
    "ont_ds": "ont_ds/ont_patch/benchmarks_summary.tsv",
    "pacbio_ds": "pacbio_ds/benchmarks_summary.tsv",
    "roche_ds": "roche_ds/benchmarks_summary.tsv",
    "roche_ds_fillinone": "roche_ds_fillinone/benchmarks_summary.tsv",
    "ultima_ds": "ultima_ds/benchmarks_summary.tsv",
    "ont_dv19": "ont_dv19/benchmarks_summary.tsv",
    "ilmn_gatk_b": "ilmn_gatk_b/benchmarks_summary.tsv",
    # No benchmarks for dragen_fullold or dragen_old
}

# Rules to exclude from cost aggregation (post-processing / global)
EXCLUDE_RULES = {
    "alignstats_smmary_compile",
    "alignstats_summary",
    "dirsetup",
}

# Rule suffixes to exclude
EXCLUDE_SUFFIXES = (".concordance",)

# Display-name mappings (same as F-score heatmap)
ALIGNER_DISPLAY = {"bwa2a": "bwa2", "sent": "sbwa"}
CALLER_DISPLAY = {
    "sentd": "dnascope", "sentdont": "dnascope-ont",
    "sentdpb": "dnascope-pb", "sentdug": "dnascope-ug",
    "sentdhio": "dnascope-hio",
}

_PG_MARKER = "\u200b"
PANGENOME_PLACEHOLDERS = {f"ILMN+sbwa+dnascope{_PG_MARKER}"}

SECTION_HEADERS = [
    "Pangenome",
    "Single Platform (hg38)",
    "ILMN Read Length (hg38)",
    "Hybrid (ILMN+ONT)",
]


def _display_name(raw, mapping):
    return mapping.get(raw, raw)


def _parse_rule_aligner(rule):
    """Extract the aligner token from a benchmark rule name.

    Rule patterns:
      sent.alNsort, sent.dmd.gatk.snv, bwa2a.dmd.deep19.1,
      ont.na.sentdont, sentmm2.alNsort, sentmm2ont.alNsort,
      ug.na.sentdug.1-24, roche.downsample, roche.na.deep19r.1
    The first dot-separated token is the aligner.
    """
    return rule.split(".")[0]


def _should_exclude_rule(rule):
    """Return True if this rule should be excluded from cost sums."""
    if rule in EXCLUDE_RULES:
        return True
    for suffix in EXCLUDE_SUFFIXES:
        if rule.endswith(suffix):
            return True
    # Exclude 'all.' pseudo-sample rows (global aggregation rules)
    return False


def load_benchmark_costs():
    """Load benchmark data and compute per-(test_group, sample, aligner) cost.

    Returns dict: (test_group, sample_base) -> {aligner: total_cost}
    where sample_base has trailing '.' stripped.
    """
    costs = {}  # (tg, sample_base) -> {aligner: cost}

    for tg, rel_path in BENCHMARK_FILES.items():
        if tg in SKIP_TEST_GROUPS:
            continue
        bench_path = os.path.join(BASE_DIR, rel_path)
        if not os.path.exists(bench_path):
            print(f"  WARN: no benchmark file for {tg}: {bench_path}", file=sys.stderr)
            continue

        with open(bench_path, "r") as f:
            reader = csv.DictReader(f, delimiter="\t")
            for row in reader:
                sample_raw = row["sample"]
                rule = row["rule"]
                cost_str = row["task_cost"]

                # Skip global rows (sample='all.')
                if sample_raw.startswith("all"):
                    continue

                if _should_exclude_rule(rule):
                    continue

                sample_base = sample_raw.rstrip(".")
                aligner = _parse_rule_aligner(rule)
                cost = float(cost_str) if cost_str else 0.0

                key = (tg, sample_base)
                costs.setdefault(key, {})
                costs[key].setdefault(aligner, 0.0)
                costs[key][aligner] += cost

    return costs


def load_cell_mapping():
    """Read consolidated concordance to build sample -> cell mapping.

    Returns dict: (test_group, sample, raw_aligner, raw_caller) ->
        (column_label, pri_cov_bin, section)
    Only uses VariantClass=All, ROI=hg38 to get one row per sample.
    """
    mapping = {}
    with open(INPUT_TSV, "r") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            if row["VariantClass"] != "All" or row["ROI"] != "hg38":
                continue
            if row.get("TestGroup", "") in SKIP_TEST_GROUPS:
                continue
            if row["SNVCaller"] in ("clair3", "oct"):
                continue

            tg = row["TestGroup"]
            sample = row["Sample"]
            raw_aligner = row["Aligner"]
            raw_caller = row["SNVCaller"]
            pri_bin_raw = row["PrimaryCoverageBin"]
            if not pri_bin_raw or not pri_bin_raw.strip():
                continue
            pri_cov = int(pri_bin_raw)

            aligner_disp = _display_name(raw_aligner, ALIGNER_DISPLAY)
            caller_disp = _display_name(raw_caller, CALLER_DISPLAY)
            pri_plat = row["PrimarySeqPlatform"]
            sec_plat = row["SecondarySeqPlatform"]
            genome_build = row.get("GenomeBuild", "hg38")
            readlen = row.get("ReadLengthBP", "")

            if tg == "ilmn_read_trim" and readlen:
                label = f"ILMN-sbwa-dnascope-{readlen}paired"
                section = "paired"
            elif sec_plat:
                sec_meas_raw = row["Secondary_MeasuredMeanCov"]
                sec_meas = round(float(sec_meas_raw), 1) if sec_meas_raw and sec_meas_raw.strip() else 0.0
                if sec_meas == 0.0:
                    continue
                label = f"{pri_plat}+{sec_plat}+{aligner_disp}+{caller_disp}+{sec_meas}x"
                section = "hio"
            else:
                label = f"{pri_plat}+{aligner_disp}+{caller_disp}"
                section = "pangenome" if genome_build.startswith("pangenome") else "hg38"

            mapping[(tg, sample, raw_aligner, raw_caller)] = (label, pri_cov, section)

    return mapping


# ── Aligner token mapping: benchmark rule aligner → concordance aligner ──
# Benchmark rules use the raw aligner token (first dot-segment).
# Concordance rows use the same raw aligner. We need to match them.
# For multi-caller test groups (ilmn_all_downsamples_a), a single aligner
# (e.g. "sent") has shared costs (alNsort, mrkdup) plus caller-specific costs.
# We split shared vs caller-specific by checking if the rule contains a caller token.

# Known caller tokens that appear in rule names (after aligner.dedup_mode.)
_CALLER_TOKENS = {
    "gatk", "sentd", "deep19", "clair3", "sentdont", "sentdpb",
    "sentdug", "sentdhio", "deep19r",
}

# Shared rule suffixes (not caller-specific)
_SHARED_SUFFIXES = {"alNsort", "mrkdup", "alignstats", "alignstats_bam",
                    "downsample", "no_dedup_roche", "norm_cov_eveness",
                    "vb2", "peddy"}


def _classify_rule(rule):
    """Classify a benchmark rule as (aligner, caller_or_None).

    Returns (aligner_token, caller_token_or_None).
    If the rule is shared (alignment/dedup/QC), caller is None.
    If the rule is caller-specific, caller is the caller token.
    """
    parts = rule.split(".")
    aligner = parts[0]

    # Check each part for a known caller token
    for p in parts[1:]:
        # Strip chunk numbers: "deep19r" from "deep19r.1"
        base = re.sub(r"\d+$", "", p).rstrip("-")
        if not base:
            continue
        if p in _CALLER_TOKENS or base in _CALLER_TOKENS:
            return aligner, p
        # Handle compound rules like "sentd.1-24" → caller is "sentd"
        if p.split(".")[0] in _CALLER_TOKENS:
            return aligner, p.split(".")[0]

    # Check for patterns like "gatk.snv", "gatk.bsqr", "gatk.1-12"
    for p in parts[1:]:
        if p in _CALLER_TOKENS:
            return aligner, p

    return aligner, None


def join_costs_to_cells(bench_costs, cell_mapping):
    """Join benchmark costs to heatmap cells.

    For each (tg, sample, aligner, caller) in cell_mapping, find the
    matching benchmark costs and compute:
      shared_cost (aligner-only rules) + caller_cost (caller-specific rules)

    Returns: {(column_label, pri_cov): [cost, ...]}
    Also returns section sets for column ordering.
    """
    cell_costs = {}  # (label, pri_cov) -> [cost, ...]
    pangenome_labels = set()
    hg38_labels = set()
    paired_labels = set()
    hio_labels = set()

    matched, unmatched = 0, 0

    for (tg, sample, raw_aligner, raw_caller), (label, pri_cov, section) in cell_mapping.items():
        # Look up benchmark costs for this (tg, sample)
        bkey = (tg, sample)
        aligner_costs = bench_costs.get(bkey)
        if not aligner_costs:
            unmatched += 1
            continue

        # Sum costs: shared (aligner-only) + caller-specific
        total = 0.0
        for bench_aligner, cost in aligner_costs.items():
            # For HIO: benchmark aligner is "ont" but concordance aligner is also "ont"
            # For multi-aligner groups: only include matching aligner
            if bench_aligner == raw_aligner:
                total += cost
            # Also check if this is a secondary aligner for HIO (sent.alNsort etc)
            # HIO benchmarks include both ont.* and sent.* rules
            # We want ALL costs for the sample (both ILMN alignment + ONT calling)

        # For HIO and multi-aligner: sum ALL costs for the sample
        # (alignment + calling are all part of the pipeline cost)
        total = sum(aligner_costs.values())

        # Keep only the first value per cell (first test-group order wins)
        cell_key = (label, pri_cov)
        if cell_key in cell_costs:
            matched += 1  # count but skip
            continue
        cell_costs[cell_key] = total
        matched += 1

        if section == "pangenome":
            pangenome_labels.add(label)
        elif section == "paired":
            paired_labels.add(label)
        elif section == "hio":
            hio_labels.add(label)
        else:
            hg38_labels.add(label)

    pangenome_labels.update(PANGENOME_PLACEHOLDERS)

    print(f"  Cost join: {matched} matched, {unmatched} unmatched (no benchmarks)")
    return cell_costs, pangenome_labels, hg38_labels, paired_labels, hio_labels



# ── Sorting helpers (same as F-score heatmap) ──

def hio_sort_key(label):
    parts = label.rsplit("+", 1)
    try:
        return float(parts[-1].rstrip("x"))
    except ValueError:
        return 0.0


def pangenome_sort_key(label):
    if "dragen" in label.lower():
        return (0, label)
    if "dnascope" in label.lower():
        return (1, label)
    if "roche" in label.lower() or "Roche" in label:
        return (2, label)
    return (3, label)


def paired_sort_key(label):
    m = re.search(r"(\d+)paired", label)
    return int(m.group(1)) if m else 0


def build_column_order(pangenome_labels, hg38_labels, paired_labels, hio_labels):
    pg_sorted = sorted(pangenome_labels, key=pangenome_sort_key)
    paired_sorted = sorted(paired_labels, key=paired_sort_key)
    hio_sorted = sorted(hio_labels, key=hio_sort_key)
    columns = (pg_sorted + [SPACER_LABEL]
               + sorted(hg38_labels) + [SPACER_LABEL]
               + paired_sorted + [SPACER_LABEL]
               + hio_sorted)
    spacer_indices = []
    spacer_indices.append(len(pg_sorted))
    spacer_indices.append(spacer_indices[-1] + 1 + len(hg38_labels))
    spacer_indices.append(spacer_indices[-1] + 1 + len(paired_sorted))
    return columns, spacer_indices


def build_cost_matrix(cell_costs, cov_levels, columns):
    """Build 2D arrays for cost and sample count (all n=1)."""
    mat = np.full((len(cov_levels), len(columns)), np.nan)
    cnt = np.zeros((len(cov_levels), len(columns)), dtype=int)
    for i, cov in enumerate(cov_levels):
        for j, col in enumerate(columns):
            if col == SPACER_LABEL:
                continue
            val = cell_costs.get((col, cov))
            if val is not None:
                mat[i, j] = val
                cnt[i, j] = 1
    return mat, cnt


# ── Platform colors for x-axis labels ──
_PLATFORM_COLORS = {
    "ILMN": "#3b82f620",
    "ONT":  "#22c55e20",
    "PacBio": "#f59e0b20",
    "Ultima": "#a855f720",
    "Roche": "#ef444420",
}

REF_COLUMN = "ILMN+sbwa+gatk"
REF_COV_BIN = 35


def plot_cost_heatmap(mat, cnt, cov_levels, columns, spacer_indices, out_path):
    """Render cost heatmap with YlOrRd colormap."""
    n_cols = len(columns)
    n_rows = len(cov_levels)

    fig_w = max(14, n_cols * 0.95)
    fig_h = max(6, n_rows * 0.55 + 2.5)
    fig, ax = plt.subplots(figsize=(fig_w, fig_h))

    cmap = plt.cm.YlOrRd.copy()
    cmap.set_bad(color="#3a3a3a")

    vmin = np.nanmin(mat) if not np.all(np.isnan(mat)) else 0
    vmax = np.nanmax(mat) if not np.all(np.isnan(mat)) else 1
    # Pad range slightly
    vmin = max(0, vmin - 0.05)
    vmax = vmax * 1.05

    norm = mcolors.Normalize(vmin=vmin, vmax=vmax)
    im = ax.imshow(mat, aspect="auto", cmap=cmap, norm=norm,
                   interpolation="nearest", origin="lower")

    # X-axis
    ax.set_xticks(range(n_cols))
    xlabels = [c.replace(_PG_MARKER, "") if c != SPACER_LABEL else "│" for c in columns]
    ax.set_xticklabels(xlabels, rotation=55, ha="right", fontsize=8)

    for tick_label in ax.get_xticklabels():
        txt = tick_label.get_text()
        if txt == "│":
            continue
        plat = txt.split("+")[0].split("-")[0]
        bg = _PLATFORM_COLORS.get(plat)
        if bg:
            tick_label.set_bbox(dict(
                facecolor=bg, edgecolor="none", pad=1.5, boxstyle="round,pad=0.2"))

    # Y-axis
    ax.set_yticks(range(n_rows))
    bin_display = {25: 20, 35: 30, 45: 40}
    ax.set_yticklabels([f"{bin_display.get(c, c)}x" for c in cov_levels], fontsize=9)

    # Vertical separators
    for si in spacer_indices:
        ax.axvline(x=si, color="#888888", linewidth=2, linestyle="--")

    # Section headers
    boundaries = [-1] + list(spacer_indices) + [n_cols]
    for sec_i, header in enumerate(SECTION_HEADERS):
        left = boundaries[sec_i] + 1
        right = boundaries[sec_i + 1]
        if right <= left:
            continue
        mid = (left + right - 1) / 2.0
        ax.text(mid, n_rows + 0.3, header,
                ha="center", va="bottom", fontsize=9, fontstyle="italic", color="#a3a3a3")

    # Pangenome annotation
    pg_right = spacer_indices[0]
    if pg_right > 0:
        pg_mid = (pg_right - 1) / 2.0
        ax.text(pg_mid, n_rows + 0.9,
                "dragen: ILMN pangenome  ·  roche: public pangenome",
                ha="center", va="bottom", fontsize=6, fontstyle="italic", color="#6b6b6b")

    # Annotate cells with cost values
    for i in range(n_rows):
        for j in range(n_cols):
            if columns[j] == SPACER_LABEL:
                continue
            val = mat[i, j]
            n = cnt[i, j]
            if np.isnan(val):
                ax.text(j, i, "—", ha="center", va="center", fontsize=6, color="#6b6b6b")
            else:
                rgba = cmap(norm(val))
                lum = 0.299 * rgba[0] + 0.587 * rgba[1] + 0.114 * rgba[2]
                color = "black" if lum > 0.5 else "white"
                ax.text(j, i, f"${val:.2f}\nn={n}",
                        ha="center", va="center",
                        fontsize=5.5, fontweight="bold", color=color, linespacing=1.2)

    # Spacer column backgrounds
    for si in spacer_indices:
        for i in range(n_rows):
            ax.add_patch(plt.Rectangle((si - 0.5, i - 0.5), 1, 1,
                                       facecolor="#1a1a1a", edgecolor="none"))

    # Magenta border on reference cell
    if REF_COLUMN in columns and REF_COV_BIN in cov_levels:
        ref_ci = columns.index(REF_COLUMN)
        ref_ri = cov_levels.index(REF_COV_BIN)
        ax.add_patch(plt.Rectangle(
            (ref_ci - 0.5, ref_ri - 0.5), 1, 1,
            linewidth=2.0, edgecolor="#d946ef", facecolor="none",
            linestyle="-", zorder=5))

    ax.set_xlabel("Platform + Aligner + Caller", fontsize=11)
    ax.set_ylabel("Primary Measured Coverage (Binned)", fontsize=11)
    ax.set_title("Pipeline Cost (USD) — All rules excl. concordance",
                 fontsize=13, fontweight="bold", pad=28)

    cbar = fig.colorbar(im, ax=ax, shrink=0.8, pad=0.02)
    cbar.set_label("Cost (USD)", fontsize=10)

    plt.tight_layout()
    fig.savefig(out_path, format="svg", bbox_inches="tight")
    plt.close(fig)
    print(f"  saved: {os.path.basename(out_path)}")


def main():
    output_dir = os.path.join(BASE_DIR, "heatmaps_cost")
    os.makedirs(output_dir, exist_ok=True)

    print("Loading benchmark costs...")
    bench_costs = load_benchmark_costs()
    print(f"  {len(bench_costs)} (test_group, sample) entries with costs")

    print("Loading cell mapping from consolidated concordance...")
    cell_mapping = load_cell_mapping()
    print(f"  {len(cell_mapping)} (tg, sample, aligner, caller) entries")

    print("Joining costs to cells...")
    cell_costs, pg_labels, hg38_labels, paired_labels, hio_labels = \
        join_costs_to_cells(bench_costs, cell_mapping)

    if not cell_costs:
        print("ERROR: no cost data matched to cells", file=sys.stderr)
        sys.exit(1)

    columns, spacer_indices = build_column_order(
        pg_labels, hg38_labels, paired_labels, hio_labels)
    all_covs = sorted({k[1] for k in cell_costs if k[1] <= 45})

    print(f"\nCoverage levels: {all_covs}")
    print(f"Pangenome columns ({len(pg_labels)}): {sorted(pg_labels, key=pangenome_sort_key)}")
    print(f"hg38 columns ({len(hg38_labels)}): {sorted(hg38_labels)}")
    print(f"Paired columns ({len(paired_labels)}): {sorted(paired_labels, key=paired_sort_key)}")
    print(f"HIO columns ({len(hio_labels)}): {sorted(hio_labels, key=hio_sort_key)}")

    mat, cnt = build_cost_matrix(cell_costs, all_covs, columns)
    out_path = os.path.join(output_dir, "cost_pipeline.svg")
    plot_cost_heatmap(mat, cnt, all_covs, columns, spacer_indices, out_path)

    print(f"\nDone — cost heatmap in {output_dir}")


if __name__ == "__main__":
    main()