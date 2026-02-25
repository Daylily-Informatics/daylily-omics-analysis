#!/usr/bin/env python3
"""Generate per-VariantClass concordance metric heatmaps for a given ROI.

Usage: python heatmap_fscore_hg38.py [ROI] [--metric METRIC] [--show-debug-ranges] [--apply-reassign]
  Default ROI is 'hg38'. Pass any valid ROI value.
  --metric: Fscore (default), Precision, Sensitivity-Recall, Specificity, PPV
  --show-debug-ranges: Show cov: and F: range annotations in cells (default: off)
  --apply-reassign: Apply hardcoded coverage bin reassignments (default: off)
    - ONT sentmm2ont+deep19: 8.22x→bin7, 15.0x→bin10, 21.06x→bin30
    - Ultima ug+sentdug: 17.97x→bin20

X-axis: Platform+Aligner+Caller (single-platform) then gap then HIO columns.
Y-axis: Primary Measured Coverage (Binned) ascending.
"""

import argparse
import csv
import math
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.colors as mcolors
import matplotlib.pyplot as plt
import numpy as np


# --- Issue 3: New coverage binning from Primary_MeasuredMeanCov ---
# Bin label -> (min_exclusive, max_inclusive) except bin 0 which is exact 0
# and bin 40 which is >35 to <50
COV_BIN_DEFS = [
    (0, None, 0.0),        # exactly 0
    (1, 0.0, 2.0),         # >0 to ≤2
    (3, 2.0, 4.0),         # >2 to ≤4
    (5, 4.0, 6.0),         # >4 to ≤6
    (7, 6.0, 8.0),         # >6 to ≤8
    (10, 8.0, 12.5),       # >8 to ≤12.5
    (15, 12.5, 18.75),     # >12.5 to ≤18.75
    (20, 18.75, 25.0),     # >18.75 to ≤25
    (30, 25.0, 35.0),      # >25 to <35
    (40, 35.0, 50.0),      # >35 to <50
]


def _compute_cov_bin(measured_cov):
    """Assign a coverage bin based on Primary_MeasuredMeanCov."""
    if measured_cov is None or math.isnan(measured_cov):
        return None
    if measured_cov == 0.0:
        return 0
    if measured_cov >= 50.0:
        return None  # out of range
    for bin_label, min_excl, max_incl in COV_BIN_DEFS:
        if min_excl is None:
            continue  # skip bin 0 (handled above)
        if min_excl < measured_cov <= max_incl:
            return bin_label
    return None


# --- Issue: --apply-reassign hardcoded cell reassignments ---
# Keys: (platform, aligner, caller, measured_cov_approx) -> new_bin
# These override the computed bin for specific column+coverage combinations
REASSIGN_RULES = {
    # ONT sminimap2+deep19 (sentmm2ont+deep19):
    #   8.22x (computed bin 10) -> move to bin 7
    ("ONT", "sentmm2ont", "deep19", 8.22): 7,
    #   15.0x (lower of two in bin 15) -> move to bin 10
    ("ONT", "sentmm2ont", "deep19", 15.0): 10,
    #   21.06x (higher of two in bin 20) -> move to bin 30
    ("ONT", "sentmm2ont", "deep19", 21.06): 30,
    # Ultima ug+sentdug:
    #   17.97x (higher of two in bin 15) -> move to bin 20
    ("Ultima", "ug", "sentdug", 17.97): 20,
}


def _apply_reassign(platform, aligner, caller, measured_cov, computed_bin):
    """Apply hardcoded bin reassignments if --apply-reassign is enabled."""
    # Find closest match within tolerance (0.1x coverage)
    for (p, a, c, cov), new_bin in REASSIGN_RULES.items():
        if p == platform and a == aligner and c == caller:
            if abs(measured_cov - cov) < 0.1:
                return new_bin
    return computed_bin

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
    "sentdhipmr": "dnascope-hipmr",
    "sentdhiomr": "dnascope-hiomr",
    "sentdhuo": "dnascope-huo",
    "sentpg": "dnascope-pg",
    "deep19r": "dv-roche",
}

# Hybrid callers to compress into a single column per ONT bin.
# When multiple callers exist at the same ONT bin, keep the max Fscore.
HYBRID_CALLERS = {"sentdhio", "sentdhiom", "sentdhiomr", "sentdhuomr", "sentdhipmr"}

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


# Coverage-bin display mapping: internal bin → display coverage (new bins)
_BIN_TO_DISPLAY_COV = {0: 0, 1: 1, 3: 3, 5: 5, 7: 7, 10: 10, 15: 15, 20: 20, 30: 30, 40: 40}


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


def load_data(footprint, metric="Fscore", apply_reassign=False):
    """Load consolidated TSV, filter to given ROI.

    Args:
        footprint: ROI value to filter on (e.g., 'hg38', 'giabHC', 'clinvar_genes')
        metric: Concordance metric column to use (default: 'Fscore')
        apply_reassign: If True, apply hardcoded cell reassignments for specific columns

    Returns:
        data, counts, depths: per-VariantClass dicts keyed by (pri_cov, col_label)
        pangenome_labels: pangenome column labels (dragen, roche)
        hg38_labels: hg38 single-platform column labels
        paired_labels: ILMN read-length column labels (50/100/150bp)
        hio_labels: ILMN+ONT hybrid column labels
        huo_labels: Ultima+ONT hybrid column labels
    """
    raw = {}  # {snp_class: {(pri_cov, label): metric_val}} — MAX metric per cell
    count_raw = {}  # {snp_class: {(pri_cov, label): int}} — metrics per cell
    depth_raw = {}  # {snp_class: {(pri_cov, label): measured_depth}}
    hiomr_raw = {}  # {snp_class: {(pri_cov, label): metric_val}} — sentdhiomr only
    tp_fn_raw = {}  # {snp_class: {(pri_cov, label): tp+fn}} — for SNP weighting
    # Track min/max metric and measured coverage per cell
    metric_min_raw = {}  # {snp_class: {cell_key: min_metric}}
    metric_max_raw = {}  # {snp_class: {cell_key: max_metric}}
    cov_min_raw = {}  # {snp_class: {cell_key: min_measured_cov}}
    cov_max_raw = {}  # {snp_class: {cell_key: max_measured_cov}}

    pangenome_labels = set()
    hg38_labels = set()
    paired_labels = set()
    hio_labels = set()  # ILMN+ONT hybrids
    huo_labels = set()  # Ultima+ONT hybrids

    with open(INPUT_TSV, "r") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            if row["ROI"] != footprint:
                continue

            # Deduplicate: skip test groups superseded by others
            test_group = row.get("TestGroup", "")
            if test_group in SKIP_TEST_GROUPS:
                continue

            snp_class = row["VariantClass"]

            # Issue 3: Compute coverage bin from Primary_MeasuredMeanCov
            pri_meas_raw = row.get("Primary_MeasuredMeanCov", "")
            pri_meas = float(pri_meas_raw) if pri_meas_raw and pri_meas_raw.strip() else None
            if pri_meas is None:
                continue
            pri_cov = _compute_cov_bin(pri_meas)
            if pri_cov is None:
                continue  # out of range

            pri_plat = row["PrimarySeqPlatform"]
            sec_plat = row["SecondarySeqPlatform"]
            raw_aligner = row["Aligner"]
            raw_caller = row["SNVCaller"]
            aligner = _display_name(raw_aligner, ALIGNER_DISPLAY)
            caller = _display_name(raw_caller, CALLER_DISPLAY)
            genome_build = row.get("GenomeBuild", "hg38")

            # Apply hardcoded bin reassignments if flag is set
            if apply_reassign:
                pri_cov = _apply_reassign(pri_plat, raw_aligner, raw_caller, pri_meas, pri_cov)

            if raw_caller in ("clair3", "oct"):
                continue

            # --- Merge ont+deep19 into ont+dnascope-ont column ---
            if raw_aligner == "ont" and raw_caller == "deep19":
                caller = "dnascope-ont"  # override display name

            # --- Treat ont+sentdhiomr as ILMN+ONT hybrid data ---
            # These are hybrid caller results that may have missing platform info
            is_hybrid_sentdhiomr = (raw_aligner == "ont" and raw_caller == "sentdhiomr")
            if is_hybrid_sentdhiomr:
                # Force treat as HIO hybrid even if sec_plat is missing
                sec_meas_raw = row.get("Secondary_MeasuredMeanCov", "")
                sec_meas = float(sec_meas_raw) if sec_meas_raw and sec_meas_raw.strip() else None
                # If no sec_meas, try to derive from mqc_id (SR{X}x-ONT{Y}x pattern)
                if sec_meas is None or sec_meas == 0.0:
                    import re
                    mqc_id = row.get("mqc_id", "")
                    m = re.search(r"-ONT(\d+)b?x-", mqc_id)
                    if m:
                        sec_meas = float(m.group(1)) * 0.5  # ~50% of implied cov
                    else:
                        continue  # can't determine ONT coverage
                ont_b = _ont_bin(sec_meas)
                if ont_b is None:
                    continue
                ont_disp = int(ont_b) if ont_b == int(ont_b) else ont_b
                label = f"ILMN+ONT+{aligner}+hybrid+{ont_disp}x"
                hio_labels.add(label)
            # --- Column label overrides ---
            elif test_group in ("ilmn_read_trim", "RLEN") and row.get("ReadLengthBP", ""):
                readlen = row["ReadLengthBP"]
                label = f"ILMN-sbwa-dnascope-{readlen}paired"
                paired_labels.add(label)
            elif sec_plat:  # Hybrid with secondary platform (ILMN+ONT or Ultima+ONT)
                sec_meas_raw = row["Secondary_MeasuredMeanCov"]
                sec_meas = round(float(sec_meas_raw), 1) if sec_meas_raw and sec_meas_raw.strip() else 0.0
                if sec_meas == 0.0:
                    continue  # skip HIO/HUO rows with 0x secondary coverage
                if raw_caller in HYBRID_CALLERS:
                    # Compress hybrid callers: one column per ONT bin
                    ont_b = _ont_bin(sec_meas)
                    if ont_b is None:
                        continue  # unmapped ONT coverage - skip
                    ont_disp = int(ont_b) if ont_b == int(ont_b) else ont_b
                    label = f"{pri_plat}+{sec_plat}+{aligner}+hybrid+{ont_disp}x"
                else:
                    label = f"{pri_plat}+{sec_plat}+{aligner}+{caller}+{sec_meas}x"
                # Route to appropriate hybrid section based on primary platform
                if pri_plat == "Ultima":
                    huo_labels.add(label)
                else:
                    hio_labels.add(label)
            else:  # single-platform
                label = f"{pri_plat}+{aligner}+{caller}"
                # Route pangenome to pangenome section, others to hg38 section
                if genome_build.startswith("pangenome") or "pangenome" in raw_aligner:
                    pangenome_labels.add(label)
                else:
                    hg38_labels.add(label)

            # Read the selected metric (Issue 2)
            metric_raw = row.get(metric, "")
            metric_val = float("nan") if not metric_raw or not metric_raw.strip() else float(metric_raw)

            cell_key = (pri_cov, label)
            count_raw.setdefault(snp_class, {})
            count_raw[snp_class][cell_key] = count_raw[snp_class].get(cell_key, 0) + 1
            raw.setdefault(snp_class, {})

            # Issue 1: MAX aggregation for ALL cells
            prev = raw[snp_class].get(cell_key)
            if prev is None:
                raw[snp_class][cell_key] = metric_val
            elif metric_val == metric_val:  # new value is not NaN
                if prev != prev:  # prev is NaN → replace
                    raw[snp_class][cell_key] = metric_val
                elif metric_val > prev:
                    raw[snp_class][cell_key] = metric_val

            # Track sentdhiomr separately for exclusion-zone logic (hybrid only)
            if raw_caller == "sentdhiomr":
                hiomr_raw.setdefault(snp_class, {})
                prev_h = hiomr_raw[snp_class].get(cell_key)
                if prev_h is None or (metric_val == metric_val and (
                        prev_h != prev_h or metric_val > prev_h)):
                    hiomr_raw[snp_class][cell_key] = metric_val

            # Track min/max metric per cell
            if metric_val == metric_val:  # not NaN
                metric_min_raw.setdefault(snp_class, {})
                metric_max_raw.setdefault(snp_class, {})
                cur_min = metric_min_raw[snp_class].get(cell_key)
                cur_max = metric_max_raw[snp_class].get(cell_key)
                if cur_min is None or metric_val < cur_min:
                    metric_min_raw[snp_class][cell_key] = metric_val
                if cur_max is None or metric_val > cur_max:
                    metric_max_raw[snp_class][cell_key] = metric_val

            # Track min/max measured coverage per cell
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
    metric_ranges = {}  # {snp_class: {cell_key: (min_metric, max_metric)}}
    cov_ranges = {}     # {snp_class: {cell_key: (min_cov, max_cov)}}
    for sc, cells in raw.items():
        data[sc] = {}
        counts[sc] = {}
        depths[sc] = {}
        metric_ranges[sc] = {}
        cov_ranges[sc] = {}
        for key, val in cells.items():
            counts[sc][key] = count_raw.get(sc, {}).get(key, 1)
            data[sc][key] = val
            # Metric range (Issue 1: ensure max is used as display value)
            m_min = metric_min_raw.get(sc, {}).get(key)
            m_max = metric_max_raw.get(sc, {}).get(key)
            if m_min is not None and m_max is not None:
                metric_ranges[sc][key] = (m_min, m_max)
                # Issue 1: Force max value as display value
                data[sc][key] = m_max
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

    return (data, counts, depths, metric_ranges, cov_ranges,
            sorted(pangenome_labels), sorted(hg38_labels),
            sorted(paired_labels), sorted(hio_labels),
            sorted(huo_labels), hiomr_cells, tp_fn)


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


def _filter_empty_columns(labels, data, all_covs):
    """Remove column labels that have no data in any coverage bin across all variant classes.

    A column is empty if data[snp_class][(cov, label)] is missing or NaN for all combos.
    """
    non_empty = set()
    for label in labels:
        for snp_class, class_data in data.items():
            for cov in all_covs:
                val = class_data.get((cov, label))
                if val is not None and val == val:  # not NaN
                    non_empty.add(label)
                    break
            if label in non_empty:
                break
    return [lbl for lbl in labels if lbl in non_empty]


def build_column_order(pangenome_labels, hg38_labels, paired_labels, hio_labels, huo_labels):
    """Build final column list: [cov bar] pangenome | hg38 | paired | HIO | HUO (5 sections).

    Coverage bar at start of pangenome section, then spacers between other sections.
    Total of 5 coverage indicator columns.
    """
    # Filter out empty-platform pangenome columns (those starting with '+')
    pg_sorted = sorted([lbl for lbl in pangenome_labels if not lbl.startswith("+")],
                       key=pangenome_sort_key)
    paired_sorted = sorted(paired_labels, key=paired_sort_key)
    hio_sorted = sorted(hio_labels, key=hio_sort_key)
    huo_sorted = sorted(huo_labels, key=hio_sort_key)  # same sort key as HIO
    # Coverage bar at very start, then pangenome data, then spacers between other sections
    columns = ([SPACER_LABEL] + pg_sorted + [SPACER_LABEL]
               + list(hg38_labels) + [SPACER_LABEL]
               + paired_sorted + [SPACER_LABEL]
               + hio_sorted + [SPACER_LABEL]
               + huo_sorted)
    spacer_indices = []
    spacer_indices.append(0)  # coverage bar at start
    spacer_indices.append(1 + len(pg_sorted))  # after pangenome
    spacer_indices.append(spacer_indices[-1] + 1 + len(hg38_labels))  # after hg38
    spacer_indices.append(spacer_indices[-1] + 1 + len(paired_sorted))  # after paired
    spacer_indices.append(spacer_indices[-1] + 1 + len(hio_sorted))  # after HIO
    return columns, spacer_indices


def build_matrix(class_data, class_counts, class_depths,
                 class_metric_ranges, class_cov_ranges,
                 cov_levels, columns):
    """Build 2D numpy arrays for values, counts, depths, and ranges."""
    n_rows, n_cols = len(cov_levels), len(columns)
    mat = np.full((n_rows, n_cols), np.nan)
    cnt = np.zeros((n_rows, n_cols), dtype=int)
    dep = np.full((n_rows, n_cols), np.nan)
    # Range arrays: (min, max) stored as separate arrays
    m_min = np.full((n_rows, n_cols), np.nan)
    m_max = np.full((n_rows, n_cols), np.nan)
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
            m_range = class_metric_ranges.get((cov, col))
            if m_range is not None:
                m_min[i, j], m_max[i, j] = m_range
            cov_range = class_cov_ranges.get((cov, col))
            if cov_range is not None:
                cov_min_arr[i, j], cov_max_arr[i, j] = cov_range
    return mat, cnt, dep, m_min, m_max, cov_min_arr, cov_max_arr


REF_COLUMN = "ILMN+sbwa+gatk"
REF_COV_BIN = 30  # new bin 30 = primary coverage >25 to ≤35

# Section header labels and their positions (computed dynamically)
# Future sections: "Hybrid Illumina+PacBio", "Hybrid Ultima+PacBio"
SECTION_HEADERS = [
    "Pangenome\nhprc-v2\n(3 platforms,\n3 pipelines)",
    "HuRef\nhg38\n(4 platforms,\n9 pipelines)",
    "Illumina\nRead Length\nTitration\n(1 platform,\n1 pipeline)",
    "Hybrid\nIllumina+ONT",
    "Hybrid\nUltima+ONT",
]


def plot_heatmap(mat, cnt, dep, m_min, m_max, cov_min_arr, cov_max_arr,
                 cov_levels, columns, spacer_indices,
                 snp_class, footprint, out_path, hiomr_cells=None,
                 metric_name="Fscore", show_debug_ranges=False):
    """Render heatmap with 4 sections separated by spacer columns.

    Args:
        metric_name: Name of the metric being displayed (default: Fscore)
        show_debug_ranges: If True, show cov: and metric: range annotations (Issue 5)
    """
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

    # Reference cell: ILMN+sbwa+gatk at bin 30 (new binning)
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
    ax.set_xticklabels(xlabels, rotation=55, ha="right", fontsize=12.76, fontweight="bold")  # +10%

    # Subtle background shading on x-axis labels grouped by platform (popped colors)
    _PLATFORM_COLORS = {
        "ILMN":     "#3b82f640",   # blue 25% (was 15%)
        "ILMN+ONT": "#14b8a640",   # teal 25% (was 15%)
        "ONT":      "#22c55e40",   # green 25% (was 15%)
        "PacBio":   "#f59e0b40",   # amber 25% (was 15%)
        "Ultima":   "#a855f740",   # purple 25% (was 15%)
        "Roche":    "#ef444440",   # red 25% (was 15%)
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

    # Y-axis: remove numeric labels (coverage shown via 4 spacer columns)
    ax.set_yticks(range(n_rows))
    ax.set_yticklabels([""] * n_rows)  # empty labels - coverage shown in spacer columns

    # Vertical separator lines at spacers
    for si in spacer_indices:
        ax.axvline(x=si, color="#6366f1", linewidth=1.5, linestyle=":", alpha=0.55)

    # Horizontal section annotations just above the top of the heatmap grid
    # Each section's data columns run from spacer[i]+1 to spacer[i+1]-1
    # (spacer columns themselves are coverage indicators, not data)
    for sec_i, header in enumerate(SECTION_HEADERS):
        if sec_i >= len(spacer_indices):
            break
        left = spacer_indices[sec_i] + 1  # first data column after spacer
        if sec_i + 1 < len(spacer_indices):
            right = spacer_indices[sec_i + 1]  # up to (not including) next spacer
        else:
            right = n_cols  # last section goes to end
        if right <= left:
            continue
        mid = (left + right - 1) / 2.0
        # Section header — bold, above heatmap grid, multi-line with tight spacing
        ax.text(mid, n_rows - 0.175, header,
                ha="center", va="bottom", fontsize=11.5,
                fontweight="bold", color="#4a5568", linespacing=0.9)

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
            ax.text(j, i, "-", ha="center", va="center",
                    fontsize=10.12, color="#555555", zorder=4)  # +10%
            mat[i, j] = np.nan  # prevent normal annotation from overwriting

    # Annotate cells — metric value top, ranges middle, count bottom, asterisk for non-hiomr hybrid
    for i in range(n_rows):
        for j in range(n_cols):
            col = columns[j]
            if col == SPACER_LABEL:
                continue
            val = mat[i, j]
            n = cnt[i, j]
            if np.isnan(val):
                ax.text(j, i, "-", ha="center", va="center",
                        fontsize=7.59, color="#555555")  # +10%
            else:
                rgba = cmap(norm(val))
                perceived_lum = 0.299 * rgba[0] + 0.587 * rgba[1] + 0.114 * rgba[2]
                color = "black" if perceived_lum > 0.5 else "white"
                # Check if this is a hybrid cell without hiomr data -> add *
                ont_b = _extract_ont_bin_from_label(col)
                is_hybrid = ont_b is not None
                has_hiomr = (snp_class, cov_levels[i], col) in hiomr_cells
                asterisk = "*" if is_hybrid and not has_hiomr else ""

                # Check for coverage and metric ranges
                c_min, c_max = cov_min_arr[i, j], cov_max_arr[i, j]
                f_min, f_max = m_min[i, j], m_max[i, j]
                has_cov_range = (not np.isnan(c_min) and not np.isnan(c_max)
                                 and abs(c_max - c_min) > 0.01)
                has_metric_range = (not np.isnan(f_min) and not np.isnan(f_max)
                                    and abs(f_max - f_min) > 0.0001)

                # Issue 5: Only show ranges if show_debug_ranges is True
                if show_debug_ranges and (has_cov_range or has_metric_range):
                    # Issue 4: Compact layout with 2pt extra spacing below metric value
                    ax.text(j, i + 0.24, f"{val:.3f}{asterisk}",
                            ha="center", va="center",
                            fontsize=10.25, fontweight="bold", color=color)  # -10% from 11.39
                    if has_cov_range:
                        ax.text(j, i + 0.02, f"cov:{c_min:.1f}-{c_max:.1f}x",
                                ha="center", va="center",
                                fontsize=6.33, color=color, alpha=0.8)
                    if has_metric_range:
                        y_m = i - 0.13 if has_cov_range else i + 0.02
                        ax.text(j, y_m, f"{metric_name[0]}:{f_min:.3f}-{f_max:.3f}",
                                ha="center", va="center",
                                fontsize=6.33, color=color, alpha=0.8)

                else:
                    # Standard layout (no ranges or show_debug_ranges=False)
                    ax.text(j, i + 0.1, f"{val:.3f}{asterisk}",
                            ha="center", va="center",
                            fontsize=12.53, fontweight="bold", color=color)  # -10% from 13.92


    # Make spacer columns with white coverage labels
    for si in spacer_indices:
        for i in range(n_rows):
            ax.add_patch(plt.Rectangle((si - 0.5, i - 0.5), 1, 1,
                                       facecolor="#404050",
                                       edgecolor="none"))
            cov_label = f"{cov_levels[i]}x"
            ax.text(si, i, cov_label, ha="center", va="center",
                    fontsize=12.32, color="white", alpha=0.85)  # +10%

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

    # Axis labels (+10% font size: 19.0 -> 20.9)
    ax.set_xlabel("(Sequencing Platform) Analysis Pipeline", fontsize=20.9)
    ax.set_ylabel("Primary Measured Coverage", fontsize=20.9)

    # Title: statement-style, no em-dashes, larger font
    # Map variant class to human-readable description
    vc_display = {
        "SNP": "SNP",
        "SNPts": "SNP Transitions",
        "SNPtv": "SNP Transversions",
        "Indel_50": "Indels ≤50bp",
        "Indel_gt50": "Indels >50bp",
        "INS_50": "Insertions ≤50bp",
        "INS_gt50": "Insertions >50bp",
        "DEL_50": "Deletions ≤50bp",
        "DEL_gt50": "Deletions >50bp",
        "All": "All Variants",
    }.get(snp_class, snp_class)
    roi_display = {
        "hg38": "Whole Genome",
        "giabHC": "GIAB High-Confidence Regions",
        "clinvar_genes": "ClinVar Gene Regions",
    }.get(footprint, footprint)
    ax.set_title(f"{vc_display} {metric_name} Performance: {roi_display}",
                 fontsize=21.5, fontweight="bold", pad=71)

    cbar = fig.colorbar(im, ax=ax, shrink=0.8, pad=0.02)
    cbar.ax.tick_params(labelsize=17.1)  # +10%
    cbar.set_label(metric_name, fontsize=16.5)  # +10%
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


def _synthesize_snp_class(data, counts, depths, metric_ranges, cov_ranges,
                          tp_fn, hiomr_cells):
    """Create a synthetic 'SNP' variant class from SNPts and SNPtv.

    Weighted average metric using TP+FN as weights.
    Mutates data, counts, depths, metric_ranges, cov_ranges, and hiomr_cells in place.
    """
    ts_data = data.get("SNPts", {})
    tv_data = data.get("SNPtv", {})
    if not ts_data and not tv_data:
        return

    ts_tp_fn = tp_fn.get("SNPts", {})
    tv_tp_fn = tp_fn.get("SNPtv", {})
    ts_depths = depths.get("SNPts", {})
    tv_depths = depths.get("SNPtv", {})
    ts_m_ranges = metric_ranges.get("SNPts", {})
    tv_m_ranges = metric_ranges.get("SNPtv", {})
    ts_cov_ranges = cov_ranges.get("SNPts", {})
    tv_cov_ranges = cov_ranges.get("SNPtv", {})

    all_keys = set(ts_data.keys()) | set(tv_data.keys())
    snp_data = {}
    snp_counts = {}
    snp_depths = {}
    snp_m_ranges = {}
    snp_cov_ranges = {}

    for key in all_keys:
        ts_m = ts_data.get(key)
        tv_m = tv_data.get(key)
        ts_w = ts_tp_fn.get(key, 0.0)
        tv_w = tv_tp_fn.get(key, 0.0)

        # Treat NaN as absent
        ts_valid = ts_m is not None and ts_m == ts_m  # not NaN
        tv_valid = tv_m is not None and tv_m == tv_m

        if ts_valid and tv_valid:
            total_w = ts_w + tv_w
            if total_w > 0:
                snp_data[key] = (ts_w * ts_m + tv_w * tv_m) / total_w
            else:
                snp_data[key] = (ts_m + tv_m) / 2.0  # fallback: equal weight
        elif ts_valid:
            snp_data[key] = ts_m
        elif tv_valid:
            snp_data[key] = tv_m
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

        # Metric ranges: merge min/max from ts and tv
        ts_mr = ts_m_ranges.get(key)
        tv_mr = tv_m_ranges.get(key)
        if ts_mr and tv_mr:
            snp_m_ranges[key] = (min(ts_mr[0], tv_mr[0]), max(ts_mr[1], tv_mr[1]))
        elif ts_mr:
            snp_m_ranges[key] = ts_mr
        elif tv_mr:
            snp_m_ranges[key] = tv_mr

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
    metric_ranges["SNP"] = snp_m_ranges
    cov_ranges["SNP"] = snp_cov_ranges

    # hiomr_cells: union of SNPts and SNPtv entries, re-tagged as SNP
    for sc_orig in ("SNPts", "SNPtv"):
        for entry in list(hiomr_cells):
            if entry[0] == sc_orig:
                hiomr_cells.add(("SNP", entry[1], entry[2]))


def main():
    parser = argparse.ArgumentParser(
        description="Generate per-VariantClass concordance metric heatmaps for a given ROI."
    )
    parser.add_argument("roi", nargs="?", default="hg38",
                        help="ROI/footprint to filter on (default: hg38)")
    parser.add_argument("--metric", default="Fscore",
                        help="Concordance metric column to plot (default: Fscore)")
    parser.add_argument("--show-debug-ranges", action="store_true",
                        help="Show cov: and metric range annotations in cells (default: off)")
    parser.add_argument("--apply-reassign", action="store_true",
                        help="Apply hardcoded coverage bin reassignments (default: off)")
    args = parser.parse_args()

    footprint = args.roi
    metric = args.metric
    show_debug_ranges = args.show_debug_ranges
    apply_reassign = args.apply_reassign

    # Output directory includes metric name for clarity
    metric_slug = metric.replace("-", "_").replace(" ", "_")
    output_dir = os.path.join(BASE_DIR, f"heatmaps_{metric_slug}_{footprint}")
    os.makedirs(output_dir, exist_ok=True)

    (data, counts, depths, metric_ranges, cov_ranges,
     pg_labels, hg38_labels, paired_labels,
     hio_labels, huo_labels, hiomr_cells, tp_fn) = load_data(footprint, metric=metric,
                                                              apply_reassign=apply_reassign)
    if not data:
        print(f"No data found for ROI={footprint}", file=sys.stderr)
        sys.exit(1)

    # Synthesize "SNP" variant class: weighted average of SNPts and SNPtv
    _synthesize_snp_class(data, counts, depths, metric_ranges, cov_ranges,
                          tp_fn, hiomr_cells)

    all_covs = sorted({k[0] for d in data.values() for k in d if 0 < k[0] <= 40})

    # Filter out empty columns (columns with no data in any cell)
    pg_labels = _filter_empty_columns(pg_labels, data, all_covs)
    hg38_labels = _filter_empty_columns(hg38_labels, data, all_covs)
    paired_labels = _filter_empty_columns(paired_labels, data, all_covs)
    hio_labels = _filter_empty_columns(hio_labels, data, all_covs)
    huo_labels = _filter_empty_columns(huo_labels, data, all_covs)

    columns, spacer_indices = build_column_order(pg_labels, hg38_labels, paired_labels, hio_labels, huo_labels)

    print(f"ROI: {footprint}")
    print(f"Metric: {metric}")
    print(f"Coverage levels: {all_covs}")
    print(f"Pangenome columns ({len(pg_labels)}): {pg_labels}")
    print(f"hg38 columns ({len(hg38_labels)}): {hg38_labels}")
    print(f"Paired columns ({len(paired_labels)}): {paired_labels}")
    print(f"HIO columns ({len(hio_labels)}): {sorted(hio_labels, key=hio_sort_key)}")
    print(f"HUO columns ({len(huo_labels)}): {sorted(huo_labels, key=hio_sort_key)}")
    print(f"VariantClasses: {sorted(data.keys())}")
    print()

    for snp_class in sorted(data.keys()):
        mat, cnt, dep, m_min, m_max, cov_min_arr, cov_max_arr = build_matrix(
            data[snp_class], counts[snp_class],
            depths.get(snp_class, {}),
            metric_ranges.get(snp_class, {}),
            cov_ranges.get(snp_class, {}),
            all_covs, columns)
        out_path = os.path.join(output_dir, f"{metric_slug}_{footprint}_{snp_class}.svg")
        plot_heatmap(mat, cnt, dep, m_min, m_max, cov_min_arr, cov_max_arr,
                     all_covs, columns, spacer_indices,
                     snp_class, footprint, out_path, hiomr_cells,
                     metric_name=metric, show_debug_ranges=show_debug_ranges)

    print(f"\nDone — {len(data)} heatmaps in {output_dir}")


if __name__ == "__main__":
    main()

