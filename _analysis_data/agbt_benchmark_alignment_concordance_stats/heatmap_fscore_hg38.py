#!/usr/bin/env python3
"""Generate per-VariantClass Fscore heatmaps for a given ROI.

Usage: python heatmap_fscore_hg38.py [FOOTPRINT]
  Default FOOTPRINT is 'hg38'. Pass any valid ROI value.

X-axis: Platform+Aligner+Caller (single-platform) then gap then HIO columns.
Y-axis: PrimaryCoverageBin ascending (0x bottom, 50x top).
"""

import csv
import math
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.colors as mcolors
import matplotlib.pyplot as plt
import numpy as np

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
INPUT_TSV = os.path.join(BASE_DIR, "consolidated_concordance.tsv")

SPACER_LABEL = ""  # blank column between section groups

# Test groups to skip (duplicates data already present in other groups)
SKIP_TEST_GROUPS = {"ilmn_hg003_ilmn_sentonly"}

# Force-add placeholder columns to the pangenome section (empty, no data yet).
# Internal labels use a trailing marker to avoid collision with identically-named
# hg38 columns; the marker is stripped before display on the x-axis.
_PG_MARKER = "\u200b"  # zero-width space — invisible in rendered text
PANGENOME_PLACEHOLDERS = set()  # real data now exists for all pangenome columns

# Display-name mappings for aligner and caller fields
ALIGNER_DISPLAY = {
    "bwa2a": "bwa2",
    "sent": "sbwa",
}

CALLER_DISPLAY = {
    "sentd": "dnascope",
    "sentdont": "dnascope-ont",
    "sentdpb": "dnascope-pb",
    "sentdug": "dnascope-ug",
    "sentdhio": "dnascope-hio",
    "sentdhiomr": "dnascope-hiomr",
    "sentdhuo": "dnascope-huo",
    "sentpg": "dnascope-pg",
    "deep19r": "dv-roche",
}

# Hybrid callers to compress into a single column per ONT bin.
# When multiple callers exist at the same ONT bin, keep the max Fscore.
HYBRID_CALLERS = {"sentdhio", "sentdhiom", "sentdhiomr"}

# Map measured ONT secondary coverage → display ONT bin
ONT_BIN_MAP = {
    0.5: 0.5,
    1.6: 1,
    3.6: 3,
    5.2: 5,
    7.8: 7,
}

def _ont_bin(sec_meas):
    """Map a measured ONT secondary coverage to its display bin."""
    # Find closest key in ONT_BIN_MAP
    best_key = min(ONT_BIN_MAP.keys(), key=lambda k: abs(k - sec_meas))
    if abs(best_key - sec_meas) < 1.5:
        return ONT_BIN_MAP[best_key]
    return None  # no matching bin — caller will skip this row


def _extract_ont_bin_from_label(label):
    """Extract the ONT coverage bin from a hybrid column label.

    e.g. 'ILMN+ONT+ont+hybrid+5x' → 5.0
         'ILMN+ONT+ont+hybrid+0.5x' → 0.5
    Returns None if not a hybrid label.
    """
    if "+hybrid+" not in label:
        return None
    suffix = label.rsplit("+", 1)[-1]  # e.g. "5x" or "0.5x"
    try:
        return float(suffix.rstrip("x"))
    except ValueError:
        return None


# Coverage-bin display mapping: internal bin → display coverage
_BIN_TO_DISPLAY_COV = {1: 1, 3: 3, 5: 5, 7: 7, 10: 10, 15: 15, 25: 20, 35: 30, 45: 40}


def _is_hidden_hybrid_cell(cov_bin, ont_bin_val):
    """Return True if this (SR coverage bin, ONT bin) should be hidden.

    Hidden cells:
      - Specific: SR7x+ONT5x, SR7x+ONT7x, SR10x+ONT5x, SR10x+ONT7x
      - Range: all SR≥20x AND ONT≥1x
    """
    sr_cov = _BIN_TO_DISPLAY_COV.get(cov_bin, cov_bin)

    # Specific cells
    if (sr_cov, ont_bin_val) in {(7, 5), (7, 7), (10, 5), (10, 7)}:
        return True

    # Range: SR ≥ 20x and ONT ≥ 1x
    if sr_cov >= 20 and ont_bin_val >= 1:
        return True

    return False


def _display_name(raw, mapping):
    """Return display name for a raw aligner/caller, or the raw value itself."""
    return mapping.get(raw, raw)


def load_data(footprint):
    """Load consolidated TSV, filter to given ROI.

    Returns:
        data, counts, depths: per-VariantClass dicts keyed by (pri_cov, col_label)
        pangenome_labels: pangenome column labels (dragen, roche)
        hg38_labels: hg38 single-platform column labels
        paired_labels: ILMN read-length column labels (50/100/150bp)
        hio_labels: HIO column labels
    """
    raw = {}  # {snp_class: {(pri_cov, label): fscore}} — MAX fscore per cell
    count_raw = {}  # {snp_class: {(pri_cov, label): int}} — metrics per cell
    depth_raw = {}  # {snp_class: {(pri_cov, label): measured_depth}}
    hiomr_raw = {}  # {snp_class: {(pri_cov, label): fscore}} — sentdhiomr only
    tp_fn_raw = {}  # {snp_class: {(pri_cov, label): tp+fn}} — for SNP weighting
    # Q6: Track min/max Fscore and measured coverage per cell
    fscore_min_raw = {}  # {snp_class: {cell_key: min_fscore}}
    fscore_max_raw = {}  # {snp_class: {cell_key: max_fscore}}
    cov_min_raw = {}  # {snp_class: {cell_key: min_measured_cov}}
    cov_max_raw = {}  # {snp_class: {cell_key: max_measured_cov}}

    pangenome_labels = set()
    hg38_labels = set()
    paired_labels = set()
    hio_labels = set()

    with open(INPUT_TSV, "r") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            if row["ROI"] != footprint:
                continue

            # Deduplicate: skip test groups superseded by others
            test_group = row.get("TestGroup", "")
            if test_group in SKIP_TEST_GROUPS:
                continue

            snp_class = row["VariantClass"]
            pri_bin_raw = row["PrimaryCoverageBin"]
            if not pri_bin_raw or not pri_bin_raw.strip():
                continue
            pri_cov = int(pri_bin_raw)
            pri_plat = row["PrimarySeqPlatform"]
            sec_plat = row["SecondarySeqPlatform"]
            aligner = _display_name(row["Aligner"], ALIGNER_DISPLAY)
            caller = _display_name(row["SNVCaller"], CALLER_DISPLAY)
            genome_build = row.get("GenomeBuild", "hg38")

            if row["SNVCaller"] in ("clair3", "oct"):
                continue

            # --- Merge ont+deep19 into ont+dnascope-ont column ---
            if row["Aligner"] == "ont" and row["SNVCaller"] == "deep19":
                caller = "dnascope-ont"  # override display name
                if pri_cov == 25:  # 20x → 30x cell
                    pri_cov = 35

            # --- Column label overrides ---
            readlen = row.get("ReadLengthBP", "")

            if test_group in ("ilmn_read_trim", "RLEN") and readlen:
                label = f"ILMN-sbwa-dnascope-{readlen}paired"
                paired_labels.add(label)
            elif sec_plat:  # HIO
                sec_meas_raw = row["Secondary_MeasuredMeanCov"]
                sec_meas = round(float(sec_meas_raw), 1) if sec_meas_raw and sec_meas_raw.strip() else 0.0
                if sec_meas == 0.0:
                    continue  # skip HIO rows with 0x secondary coverage
                raw_caller = row["SNVCaller"]
                if raw_caller in HYBRID_CALLERS:
                    # Compress hybrid callers: one column per ONT bin
                    ont_b = _ont_bin(sec_meas)
                    if ont_b is None:
                        continue  # unmapped ONT coverage — skip
                    ont_disp = int(ont_b) if ont_b == int(ont_b) else ont_b
                    label = f"{pri_plat}+{sec_plat}+{aligner}+hybrid+{ont_disp}x"
                else:
                    label = f"{pri_plat}+{sec_plat}+{aligner}+{caller}+{sec_meas}x"
                hio_labels.add(label)
            else:  # single-platform
                label = f"{pri_plat}+{aligner}+{caller}"
                if genome_build.startswith("pangenome"):
                    pangenome_labels.add(label)
                else:
                    hg38_labels.add(label)

            fscore_raw = row["Fscore"]
            fscore = float("nan") if not fscore_raw or not fscore_raw.strip() else float(fscore_raw)

            cell_key = (pri_cov, label)
            count_raw.setdefault(snp_class, {})
            count_raw[snp_class][cell_key] = count_raw[snp_class].get(cell_key, 0) + 1
            raw.setdefault(snp_class, {})
            raw_caller = row["SNVCaller"]

            # Q5: MAX aggregation for ALL cells (not just hybrid)
            prev = raw[snp_class].get(cell_key)
            if prev is None:
                raw[snp_class][cell_key] = fscore
            elif fscore == fscore:  # new fscore is not NaN
                if prev != prev:  # prev is NaN → replace
                    raw[snp_class][cell_key] = fscore
                elif fscore > prev:
                    raw[snp_class][cell_key] = fscore

            # Track sentdhiomr separately for exclusion-zone logic (hybrid only)
            if raw_caller == "sentdhiomr":
                hiomr_raw.setdefault(snp_class, {})
                prev_h = hiomr_raw[snp_class].get(cell_key)
                if prev_h is None or (fscore == fscore and (
                        prev_h != prev_h or fscore > prev_h)):
                    hiomr_raw[snp_class][cell_key] = fscore

            # Q6: Track min/max Fscore per cell
            if fscore == fscore:  # not NaN
                fscore_min_raw.setdefault(snp_class, {})
                fscore_max_raw.setdefault(snp_class, {})
                cur_min = fscore_min_raw[snp_class].get(cell_key)
                cur_max = fscore_max_raw[snp_class].get(cell_key)
                if cur_min is None or fscore < cur_min:
                    fscore_min_raw[snp_class][cell_key] = fscore
                if cur_max is None or fscore > cur_max:
                    fscore_max_raw[snp_class][cell_key] = fscore

            # Q6: Track min/max measured coverage per cell
            # Use Secondary_MeasuredMeanCov for hybrid, Primary_MeasuredMeanCov otherwise
            if sec_plat:  # hybrid
                meas_cov_raw = row.get("Secondary_MeasuredMeanCov", "")
            else:
                meas_cov_raw = row.get("Primary_MeasuredMeanCov", "")
            meas_cov = float(meas_cov_raw) if meas_cov_raw and meas_cov_raw.strip() else float("nan")
            if meas_cov == meas_cov:  # not NaN
                cov_min_raw.setdefault(snp_class, {})
                cov_max_raw.setdefault(snp_class, {})
                cur_cov_min = cov_min_raw[snp_class].get(cell_key)
                cur_cov_max = cov_max_raw[snp_class].get(cell_key)
                if cur_cov_min is None or meas_cov < cur_cov_min:
                    cov_min_raw[snp_class][cell_key] = meas_cov
                if cur_cov_max is None or meas_cov > cur_cov_max:
                    cov_max_raw[snp_class][cell_key] = meas_cov

            # Track TP+FN for SNPts/SNPtv weighting
            if snp_class in ("SNPts", "SNPtv"):
                tp_raw = row.get("TP", "")
                fn_raw = row.get("FN", "")
                tp_val = float(tp_raw) if tp_raw and tp_raw.strip() else 0.0
                fn_val = float(fn_raw) if fn_raw and fn_raw.strip() else 0.0
                tp_fn_raw.setdefault(snp_class, {})
                if cell_key not in tp_fn_raw[snp_class]:
                    tp_fn_raw[snp_class][cell_key] = tp_val + fn_val

            # Collect measured mean depth for primary (first value only)
            pri_depth_raw = row.get("Primary_MeasuredMeanCov", "")
            pri_depth = float(pri_depth_raw) if pri_depth_raw and pri_depth_raw.strip() else float("nan")
            depth_raw.setdefault(snp_class, {})
            if cell_key not in depth_raw[snp_class]:
                depth_raw[snp_class][cell_key] = pri_depth

    # Build final dicts — count actual metrics per cell
    data = {}
    counts = {}
    depths = {}
    fscore_ranges = {}  # {snp_class: {cell_key: (min_fs, max_fs)}}
    cov_ranges = {}     # {snp_class: {cell_key: (min_cov, max_cov)}}
    for sc, cells in raw.items():
        data[sc] = {}
        counts[sc] = {}
        depths[sc] = {}
        fscore_ranges[sc] = {}
        cov_ranges[sc] = {}
        for key, val in cells.items():
            counts[sc][key] = count_raw.get(sc, {}).get(key, 1)
            data[sc][key] = val
            # Fscore range
            fs_min = fscore_min_raw.get(sc, {}).get(key)
            fs_max = fscore_max_raw.get(sc, {}).get(key)
            if fs_min is not None and fs_max is not None:
                fscore_ranges[sc][key] = (fs_min, fs_max)
            # Coverage range
            cov_min = cov_min_raw.get(sc, {}).get(key)
            cov_max = cov_max_raw.get(sc, {}).get(key)
            if cov_min is not None and cov_max is not None:
                cov_ranges[sc][key] = (cov_min, cov_max)
        for key, dval in depth_raw.get(sc, {}).items():
            depths[sc][key] = dval

    # For exclusion-zone hybrid cells: override value with hiomr or mark absent
    hiomr_cells = set()  # (snp_class, pri_cov, label) tuples with hiomr data
    for sc in list(data.keys()):
        for key in list(data[sc].keys()):
            pri_cov, label = key
            ont_b = _extract_ont_bin_from_label(label)
            if ont_b is None:
                continue  # not a hybrid column
            if not _is_hidden_hybrid_cell(pri_cov, ont_b):
                continue  # not in exclusion zone
            hiomr_val = hiomr_raw.get(sc, {}).get(key)
            if hiomr_val is not None and hiomr_val == hiomr_val:  # not NaN
                data[sc][key] = hiomr_val  # use hiomr value, not max
                hiomr_cells.add((sc, pri_cov, label))

    # Inject placeholder columns into pangenome section
    pangenome_labels.update(PANGENOME_PLACEHOLDERS)

    # Build tp_fn final dict
    tp_fn = {}
    for sc in ("SNPts", "SNPtv"):
        tp_fn[sc] = {}
        for key, val in tp_fn_raw.get(sc, {}).items():
            tp_fn[sc][key] = val

    return (data, counts, depths, fscore_ranges, cov_ranges,
            sorted(pangenome_labels), sorted(hg38_labels),
            sorted(paired_labels), sorted(hio_labels),
            hiomr_cells, tp_fn)


def hio_sort_key(label):
    """Sort HIO labels by secondary measured coverage numerically."""
    # e.g. ILMN+ONT+ont+sentdhio+5.2x → extract 5.2
    parts = label.rsplit("+", 1)
    try:
        return float(parts[-1].rstrip("x"))
    except ValueError:
        return 0.0


def pangenome_sort_key(label):
    """Sort pangenome labels: dragen first, then dnascope, then roche."""
    if "dragen" in label.lower():
        return (0, label)
    if "dnascope" in label.lower():
        return (1, label)
    if "roche" in label.lower() or "Roche" in label:
        return (2, label)
    return (3, label)


def paired_sort_key(label):
    """Sort paired labels by read length numerically (50, 100, 150)."""
    import re as _re
    m = _re.search(r"(\d+)paired", label)
    return int(m.group(1)) if m else 0


def build_column_order(pangenome_labels, hg38_labels, paired_labels, hio_labels):
    """Build final column list: pangenome | hg38 | paired | HIO (4 sections)."""
    pg_sorted = sorted(pangenome_labels, key=pangenome_sort_key)
    paired_sorted = sorted(paired_labels, key=paired_sort_key)
    hio_sorted = sorted(hio_labels, key=hio_sort_key)
    columns = (pg_sorted + [SPACER_LABEL]
               + list(hg38_labels) + [SPACER_LABEL]
               + paired_sorted + [SPACER_LABEL]
               + hio_sorted)
    spacer_indices = []
    spacer_indices.append(len(pg_sorted))
    spacer_indices.append(spacer_indices[-1] + 1 + len(hg38_labels))
    spacer_indices.append(spacer_indices[-1] + 1 + len(paired_sorted))
    return columns, spacer_indices


def build_matrix(class_data, class_counts, class_depths,
                 class_fscore_ranges, class_cov_ranges,
                 cov_levels, columns):
    """Build 2D numpy arrays for values, counts, depths, and ranges."""
    n_rows, n_cols = len(cov_levels), len(columns)
    mat = np.full((n_rows, n_cols), np.nan)
    cnt = np.zeros((n_rows, n_cols), dtype=int)
    dep = np.full((n_rows, n_cols), np.nan)
    # Range arrays: (min, max) stored as separate arrays
    fs_min = np.full((n_rows, n_cols), np.nan)
    fs_max = np.full((n_rows, n_cols), np.nan)
    cov_min_arr = np.full((n_rows, n_cols), np.nan)
    cov_max_arr = np.full((n_rows, n_cols), np.nan)
    for i, cov in enumerate(cov_levels):
        for j, col in enumerate(columns):
            if col == SPACER_LABEL:
                continue
            val = class_data.get((cov, col))
            if val is not None:
                mat[i, j] = val
            n = class_counts.get((cov, col))
            if n is not None:
                cnt[i, j] = n
            d = class_depths.get((cov, col))
            if d is not None:
                dep[i, j] = d
            fs_range = class_fscore_ranges.get((cov, col))
            if fs_range is not None:
                fs_min[i, j], fs_max[i, j] = fs_range
            cov_range = class_cov_ranges.get((cov, col))
            if cov_range is not None:
                cov_min_arr[i, j], cov_max_arr[i, j] = cov_range
    return mat, cnt, dep, fs_min, fs_max, cov_min_arr, cov_max_arr


REF_COLUMN = "ILMN+sbwa+gatk"
REF_COV_BIN = 35  # internal bin 35 displays as "30x"

# Section header labels and their positions (computed dynamically)
SECTION_HEADERS = [
    "Pangenome",
    "Single Platform (hg38)",
    "ILMN Read Length (hg38)",
    "Hybrid (ILMN+ONT)",
]


def plot_heatmap(mat, cnt, dep, fs_min, fs_max, cov_min_arr, cov_max_arr,
                 cov_levels, columns, spacer_indices,
                 snp_class, footprint, out_path, hiomr_cells=None):
    """Render heatmap with 4 sections separated by spacer columns."""
    if hiomr_cells is None:
        hiomr_cells = set()
    n_cols = len(columns)
    n_rows = len(cov_levels)

    fig_w = max(14, n_cols * 0.95)
    fig_h = max(6, n_rows * 0.55 + 2.5)
    fig, ax = plt.subplots(figsize=(fig_w, fig_h))
    fig.patch.set_facecolor("white")
    ax.set_facecolor("white")

    cmap = plt.cm.RdYlGn.copy()
    cmap.set_bad(color="#000000")  # black for missing/unfilled data

    vmin = np.nanmin(mat) if not np.all(np.isnan(mat)) else 0
    vmax = np.nanmax(mat) if not np.all(np.isnan(mat)) else 1
    vmin = max(0, vmin - 0.02)
    vmax = min(1.0, vmax + 0.02)

    # Reference cell: ILMN+sbwa+gatk at bin 35 (displayed as 30x)
    vcenter = None
    if REF_COV_BIN in cov_levels and REF_COLUMN in columns:
        ri = cov_levels.index(REF_COV_BIN)
        ci = columns.index(REF_COLUMN)
        ref_val = mat[ri, ci]
        if not np.isnan(ref_val):
            vcenter = ref_val
    if vcenter is None:
        vcenter = (vmin + vmax) / 2.0
    vcenter = max(vmin + 1e-6, min(vmax - 1e-6, vcenter))

    norm = mcolors.TwoSlopeNorm(vmin=vmin, vcenter=vcenter, vmax=vmax)

    im = ax.imshow(mat, aspect="auto", cmap=cmap, norm=norm,
                   interpolation="nearest", origin="lower")

    # X-axis — reformat labels to "(Platform) aligner+caller"
    ax.set_xticks(range(n_cols))

    def _clean_display_label(txt):
        """Apply display-only label transformations (no raw data changes)."""
        txt = txt.replace("sentmm2ont", "sminimap2")
        txt = txt.replace("sentmm2", "sminimap2")
        # Remove suffixes: -pg (pangenome), -pb (PacBio), -ug (Ultima)
        for suffix in ("-pg", "-pb", "-ug"):
            txt = txt.replace(f"dnascope{suffix}", "dnascope")
            txt = txt.replace(f"dv{suffix}", "dv")
        return txt

    def _reformat_xlabel(col):
        """Convert 'PLAT+aligner+caller' → '(PLAT) aligner+caller'."""
        if col == SPACER_LABEL:
            return "│"
        c = col.replace(_PG_MARKER, "")
        # HIO: "ILMN+ONT+aligner+caller+Nx" → "(ILMN+ONT) aligner+caller+Nx"
        if c.startswith("ILMN+ONT+"):
            rest = c[len("ILMN+ONT+"):]
            return _clean_display_label(f"(ILMN+ONT) {rest}")
        # Paired: "ILMN-sbwa-dnascope-150paired" → "(ILMN) sbwa-dnascope-150paired"
        if "-" in c and "paired" in c:
            plat, rest = c.split("-", 1)
            return _clean_display_label(f"({plat}) {rest}")
        # Single-platform: "PLAT+aligner+caller" → "(PLAT) aligner+caller"
        parts = c.split("+", 1)
        if len(parts) == 2:
            return _clean_display_label(f"({parts[0]}) {parts[1]}")
        return _clean_display_label(c)

    xlabels = [_reformat_xlabel(c) for c in columns]
    ax.set_xticklabels(xlabels, rotation=55, ha="right", fontsize=11.6, fontweight="bold")

    # Subtle background shading on x-axis labels grouped by platform (50% alpha)
    _PLATFORM_COLORS = {
        "ILMN":     "#3b82f626",   # blue 15%
        "ILMN+ONT": "#14b8a626",   # teal 15%
        "ONT":      "#22c55e26",   # green 15%
        "PacBio":   "#f59e0b26",   # amber 15%
        "Ultima":   "#a855f726",   # purple 15%
        "Roche":    "#ef444426",   # red 15%
    }
    for tick_label in ax.get_xticklabels():
        txt = tick_label.get_text()
        if txt == "│":
            continue
        # Extract platform from "(PLAT) ..." label
        if txt.startswith("("):
            plat = txt[1:txt.index(")")] if ")" in txt else ""
        else:
            plat = txt.split("+")[0].split("-")[0]
        bg = _PLATFORM_COLORS.get(plat)
        if bg:
            tick_label.set_bbox(dict(
                facecolor=bg, edgecolor="none",
                pad=1.6, boxstyle="round,pad=0.22"))

    # Y-axis
    ax.set_yticks(range(n_rows))
    bin_display = {25: 20, 35: 30, 45: 40}
    ax.set_yticklabels([f"{bin_display.get(c, c)}x" for c in cov_levels], fontsize=15.5)

    # Vertical separator lines at spacers
    for si in spacer_indices:
        ax.axvline(x=si, color="#6366f1", linewidth=1.5, linestyle=":", alpha=0.55)

    # Horizontal section annotations just above the top of the heatmap grid
    boundaries = [-1] + list(spacer_indices) + [n_cols]
    for sec_i, header in enumerate(SECTION_HEADERS):
        left = boundaries[sec_i] + 1
        right = boundaries[sec_i + 1]
        if right <= left:
            continue
        mid = (left + right - 1) / 2.0
        # Section header — bold, above heatmap grid
        ax.text(mid, n_rows - 0.175, header,
                ha="center", va="bottom", fontsize=11.5,
                fontweight="bold", color="#4a5568")

    # Mask exclusion-zone hybrid cells that lack hiomr data
    for j in range(n_cols):
        col = columns[j]
        if col == SPACER_LABEL:
            continue
        ont_b = _extract_ont_bin_from_label(col)
        if ont_b is None:
            continue  # not a hybrid column
        for i in range(n_rows):
            cov_bin = cov_levels[i]
            if not _is_hidden_hybrid_cell(cov_bin, ont_b):
                continue
            if (snp_class, cov_bin, col) in hiomr_cells:
                continue  # has hiomr data — render normally
            # Mask: black rectangle + dash (zorder above imshow)
            ax.add_patch(plt.Rectangle(
                (j - 0.5, i - 0.5), 1, 1,
                facecolor="#000000", edgecolor="none",
                zorder=3))
            ax.text(j, i, "—", ha="center", va="center",
                    fontsize=9.2, color="#555555", zorder=4)
            mat[i, j] = np.nan  # prevent normal annotation from overwriting

    # Annotate cells — Fscore top, ranges middle, count bottom, asterisk for non-hiomr hybrid
    for i in range(n_rows):
        for j in range(n_cols):
            col = columns[j]
            if col == SPACER_LABEL:
                continue
            val = mat[i, j]
            n = cnt[i, j]
            if np.isnan(val):
                ax.text(j, i, "—", ha="center", va="center",
                        fontsize=6.9, color="#555555")
            else:
                rgba = cmap(norm(val))
                perceived_lum = 0.299 * rgba[0] + 0.587 * rgba[1] + 0.114 * rgba[2]
                color = "black" if perceived_lum > 0.5 else "white"
                # Check if this is a hybrid cell without hiomr data → add *
                ont_b = _extract_ont_bin_from_label(col)
                is_hybrid = ont_b is not None
                has_hiomr = (snp_class, cov_levels[i], col) in hiomr_cells
                asterisk = "*" if is_hybrid and not has_hiomr else ""

                # Q6: Check for coverage and Fscore ranges
                c_min, c_max = cov_min_arr[i, j], cov_max_arr[i, j]
                f_min, f_max = fs_min[i, j], fs_max[i, j]
                has_cov_range = (not np.isnan(c_min) and not np.isnan(c_max)
                                 and abs(c_max - c_min) > 0.01)
                has_fs_range = (not np.isnan(f_min) and not np.isnan(f_max)
                                and abs(f_max - f_min) > 0.0001)

                # Layout: Fscore at top, ranges in middle, n= at bottom
                if has_cov_range or has_fs_range:
                    # Compact layout with ranges
                    ax.text(j, i + 0.22, f"{val:.3f}{asterisk}",
                            ha="center", va="center",
                            fontsize=10.35, fontweight="bold", color=color)
                    if has_cov_range:
                        ax.text(j, i + 0.02, f"cov:{c_min:.1f}–{c_max:.1f}x",
                                ha="center", va="center",
                                fontsize=5.75, color=color, alpha=0.8)
                    if has_fs_range:
                        y_fs = i - 0.13 if has_cov_range else i + 0.02
                        ax.text(j, y_fs, f"F:{f_min:.3f}–{f_max:.3f}",
                                ha="center", va="center",
                                fontsize=5.75, color=color, alpha=0.8)
                    if n > 0:
                        ax.text(j, i - 0.32, f"n={n}",
                                ha="center", va="center",
                                fontsize=5.75, color=color, alpha=0.7)
                else:
                    # Original layout (no ranges)
                    ax.text(j, i + 0.1, f"{val:.3f}{asterisk}",
                            ha="center", va="center",
                            fontsize=12.65, fontweight="bold", color=color)
                    if n > 0:
                        ax.text(j, i - 0.32, f"n={n}",
                                ha="center", va="center",
                                fontsize=6.9, color=color, alpha=0.7)

    # Make spacer columns rgb(10,30,40) with white coverage labels
    bin_display = {25: 20, 35: 30, 45: 40}
    for si in spacer_indices:
        for i in range(n_rows):
            ax.add_patch(plt.Rectangle((si - 0.5, i - 0.5), 1, 1,
                                       facecolor="#404050",
                                       edgecolor="none"))
            cov_label = f"{bin_display.get(cov_levels[i], cov_levels[i])}x"
            ax.text(si, i, cov_label, ha="center", va="center",
                    fontsize=11.2, color="white", alpha=0.85)

    # Magenta border around the reference cell (ILMN+sbwa+gatk @ 30x)
    if REF_COLUMN in columns and REF_COV_BIN in cov_levels:
        ref_ci = columns.index(REF_COLUMN)
        ref_ri = cov_levels.index(REF_COV_BIN)
        ax.add_patch(plt.Rectangle(
            (ref_ci - 0.5, ref_ri - 0.5), 1, 1,
            linewidth=2.0, edgecolor="#d946ef", facecolor="none",
            linestyle="-", zorder=5))

    # Bold bottom edge on the lowest row per column where Fscore > GATK 30x
    if vcenter is not None:
        for j in range(n_cols):
            if columns[j] == SPACER_LABEL:
                continue
            for i in range(n_rows):
                val = mat[i, j]
                if not np.isnan(val) and val > vcenter:
                    ax.plot(
                        [j - 0.5, j + 0.5], [i - 0.5, i - 0.5],
                        color="black", linewidth=2.0, solid_capstyle="butt",
                        zorder=6)
                    break

    ax.set_xlabel("(Sequencing Platform) Analysis Pipeline", fontsize=19.0)
    ax.set_ylabel("Primary Measured Coverage (Binned)", fontsize=19.0)
    ax.set_title(f"Fscore — ROI={footprint} — VariantClass={snp_class}",
                 fontsize=18.7, fontweight="bold", pad=45)

    cbar = fig.colorbar(im, ax=ax, shrink=0.8, pad=0.02)
    cbar.ax.tick_params(labelsize=15.5)
    cbar.set_label("Fscore", fontsize=15)  # unchanged per spec
    # Ensure 0 and 1 appear on the colorbar scale
    existing_ticks = list(cbar.get_ticks())
    if 0.0 not in existing_ticks:
        existing_ticks.insert(0, 0.0)
    if 1.0 not in existing_ticks:
        existing_ticks.append(1.0)
    cbar.set_ticks(existing_ticks)

    plt.tight_layout()
    fig.savefig(out_path, format="svg", bbox_inches="tight")
    plt.close(fig)
    print(f"  saved: {os.path.basename(out_path)}")


def _synthesize_snp_class(data, counts, depths, fscore_ranges, cov_ranges,
                          tp_fn, hiomr_cells):
    """Create a synthetic 'SNP' variant class from SNPts and SNPtv.

    Weighted average F-score using TP+FN as weights.
    Mutates data, counts, depths, fscore_ranges, cov_ranges, and hiomr_cells in place.
    """
    ts_data = data.get("SNPts", {})
    tv_data = data.get("SNPtv", {})
    if not ts_data and not tv_data:
        return

    ts_tp_fn = tp_fn.get("SNPts", {})
    tv_tp_fn = tp_fn.get("SNPtv", {})
    ts_depths = depths.get("SNPts", {})
    tv_depths = depths.get("SNPtv", {})
    ts_fs_ranges = fscore_ranges.get("SNPts", {})
    tv_fs_ranges = fscore_ranges.get("SNPtv", {})
    ts_cov_ranges = cov_ranges.get("SNPts", {})
    tv_cov_ranges = cov_ranges.get("SNPtv", {})

    all_keys = set(ts_data.keys()) | set(tv_data.keys())
    snp_data = {}
    snp_counts = {}
    snp_depths = {}
    snp_fs_ranges = {}
    snp_cov_ranges = {}

    for key in all_keys:
        ts_fs = ts_data.get(key)
        tv_fs = tv_data.get(key)
        ts_w = ts_tp_fn.get(key, 0.0)
        tv_w = tv_tp_fn.get(key, 0.0)

        # Treat NaN as absent
        ts_valid = ts_fs is not None and ts_fs == ts_fs  # not NaN
        tv_valid = tv_fs is not None and tv_fs == tv_fs

        if ts_valid and tv_valid:
            total_w = ts_w + tv_w
            if total_w > 0:
                snp_data[key] = (ts_w * ts_fs + tv_w * tv_fs) / total_w
            else:
                snp_data[key] = (ts_fs + tv_fs) / 2.0  # fallback: equal weight
        elif ts_valid:
            snp_data[key] = ts_fs
        elif tv_valid:
            snp_data[key] = tv_fs
        else:
            snp_data[key] = float("nan")

        # Use the larger count from SNPts / SNPtv
        ts_cnt = counts.get("SNPts", {}).get(key, 0)
        tv_cnt = counts.get("SNPtv", {}).get(key, 0)
        snp_counts[key] = max(ts_cnt, tv_cnt, 1)

        # Depth: use whichever is available (prefer ts)
        d_ts = ts_depths.get(key)
        d_tv = tv_depths.get(key)
        if d_ts is not None and not math.isnan(d_ts):
            snp_depths[key] = d_ts
        elif d_tv is not None and not math.isnan(d_tv):
            snp_depths[key] = d_tv

        # Fscore ranges: merge min/max from ts and tv
        ts_fsr = ts_fs_ranges.get(key)
        tv_fsr = tv_fs_ranges.get(key)
        if ts_fsr and tv_fsr:
            snp_fs_ranges[key] = (min(ts_fsr[0], tv_fsr[0]), max(ts_fsr[1], tv_fsr[1]))
        elif ts_fsr:
            snp_fs_ranges[key] = ts_fsr
        elif tv_fsr:
            snp_fs_ranges[key] = tv_fsr

        # Coverage ranges: merge min/max from ts and tv
        ts_cr = ts_cov_ranges.get(key)
        tv_cr = tv_cov_ranges.get(key)
        if ts_cr and tv_cr:
            snp_cov_ranges[key] = (min(ts_cr[0], tv_cr[0]), max(ts_cr[1], tv_cr[1]))
        elif ts_cr:
            snp_cov_ranges[key] = ts_cr
        elif tv_cr:
            snp_cov_ranges[key] = tv_cr

    data["SNP"] = snp_data
    counts["SNP"] = snp_counts
    depths["SNP"] = snp_depths
    fscore_ranges["SNP"] = snp_fs_ranges
    cov_ranges["SNP"] = snp_cov_ranges

    # hiomr_cells: union of SNPts and SNPtv entries, re-tagged as SNP
    for sc_orig in ("SNPts", "SNPtv"):
        for entry in list(hiomr_cells):
            if entry[0] == sc_orig:
                hiomr_cells.add(("SNP", entry[1], entry[2]))


def main():
    footprint = sys.argv[1] if len(sys.argv) > 1 else "hg38"
    output_dir = os.path.join(BASE_DIR, f"heatmaps_fscore_{footprint}")
    os.makedirs(output_dir, exist_ok=True)

    (data, counts, depths, fscore_ranges, cov_ranges,
     pg_labels, hg38_labels, paired_labels,
     hio_labels, hiomr_cells, tp_fn) = load_data(footprint)
    if not data:
        print(f"No data found for ROI={footprint}", file=sys.stderr)
        sys.exit(1)

    # Synthesize "SNP" variant class: weighted average of SNPts and SNPtv
    _synthesize_snp_class(data, counts, depths, fscore_ranges, cov_ranges,
                          tp_fn, hiomr_cells)

    columns, spacer_indices = build_column_order(pg_labels, hg38_labels, paired_labels, hio_labels)
    all_covs = sorted({k[0] for d in data.values() for k in d if 0 < k[0] <= 45})

    print(f"ROI: {footprint}")
    print(f"Coverage levels: {all_covs}")
    print(f"Pangenome columns ({len(pg_labels)}): {pg_labels}")
    print(f"hg38 columns ({len(hg38_labels)}): {hg38_labels}")
    print(f"Paired columns ({len(paired_labels)}): {paired_labels}")
    print(f"HIO columns ({len(hio_labels)}): {sorted(hio_labels, key=hio_sort_key)}")
    print(f"VariantClasses: {sorted(data.keys())}")
    print()

    for snp_class in sorted(data.keys()):
        mat, cnt, dep, fs_min, fs_max, cov_min_arr, cov_max_arr = build_matrix(
            data[snp_class], counts[snp_class],
            depths.get(snp_class, {}),
            fscore_ranges.get(snp_class, {}),
            cov_ranges.get(snp_class, {}),
            all_covs, columns)
        out_path = os.path.join(output_dir, f"fscore_{footprint}_{snp_class}.svg")
        plot_heatmap(mat, cnt, dep, fs_min, fs_max, cov_min_arr, cov_max_arr,
                     all_covs, columns, spacer_indices,
                     snp_class, footprint, out_path, hiomr_cells)

    print(f"\nDone — {len(data)} heatmaps in {output_dir}")


if __name__ == "__main__":
    main()

