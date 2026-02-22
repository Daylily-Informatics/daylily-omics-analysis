#!/usr/bin/env python3
"""Generate per-VariantClass Fscore heatmaps for a given ROI.

Usage: python heatmap_fscore_hg38.py [FOOTPRINT]
  Default FOOTPRINT is 'hg38'. Pass any valid ROI value.

X-axis: Platform+Aligner+Caller (single-platform) then gap then HIO columns.
Y-axis: PrimaryCoverageBin ascending (0x bottom, 50x top).
"""

import csv
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
PANGENOME_PLACEHOLDERS = {f"ILMN+sbwa+dnascope{_PG_MARKER}"}

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
    raw = {}  # {snp_class: {(pri_cov, label): [fscore, ...]}}
    depth_raw = {}  # {snp_class: {(pri_cov, label): [measured_depth, ...]}}
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

            if row["SNVCaller"] == "clair3":
                continue

            # --- Column label overrides ---
            readlen = row.get("ReadLengthBP", "")

            if test_group == "ilmn_read_trim" and readlen:
                label = f"ILMN-sbwa-dnascope-{readlen}paired"
                paired_labels.add(label)
            elif sec_plat:  # HIO
                sec_meas_raw = row["Secondary_MeasuredMeanCov"]
                sec_meas = round(float(sec_meas_raw), 1) if sec_meas_raw and sec_meas_raw.strip() else 0.0
                if sec_meas == 0.0:
                    continue  # skip HIO rows with 0x secondary coverage
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

            # Keep only the first value per cell (first test-group order wins)
            cell_key = (pri_cov, label)
            raw.setdefault(snp_class, {})
            if cell_key not in raw[snp_class]:
                raw[snp_class][cell_key] = fscore

            # Collect measured mean depth for primary (first value only)
            pri_depth_raw = row.get("Primary_MeasuredMeanCov", "")
            pri_depth = float(pri_depth_raw) if pri_depth_raw and pri_depth_raw.strip() else float("nan")
            depth_raw.setdefault(snp_class, {})
            if cell_key not in depth_raw[snp_class]:
                depth_raw[snp_class][cell_key] = pri_depth

    # Build final dicts (all n=1)
    data = {}
    counts = {}
    depths = {}
    for sc, cells in raw.items():
        data[sc] = {}
        counts[sc] = {}
        depths[sc] = {}
        for key, val in cells.items():
            counts[sc][key] = 1
            data[sc][key] = val
        for key, dval in depth_raw.get(sc, {}).items():
            depths[sc][key] = dval

    # Inject placeholder columns into pangenome section
    pangenome_labels.update(PANGENOME_PLACEHOLDERS)

    return (data, counts, depths,
            sorted(pangenome_labels), sorted(hg38_labels),
            sorted(paired_labels), sorted(hio_labels))


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


def build_matrix(class_data, class_counts, class_depths, cov_levels, columns):
    """Build 2D numpy arrays for values, counts, and depths (cov x columns)."""
    mat = np.full((len(cov_levels), len(columns)), np.nan)
    cnt = np.zeros((len(cov_levels), len(columns)), dtype=int)
    dep = np.full((len(cov_levels), len(columns)), np.nan)
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
    return mat, cnt, dep


REF_COLUMN = "ILMN+sbwa+gatk"
REF_COV_BIN = 35  # internal bin 35 displays as "30x"

# Section header labels and their positions (computed dynamically)
SECTION_HEADERS = [
    "Pangenome",
    "Single Platform (hg38)",
    "ILMN Read Length (hg38)",
    "Hybrid (ILMN+ONT)",
]


def plot_heatmap(mat, cnt, dep, cov_levels, columns, spacer_indices,
                 snp_class, footprint, out_path):
    """Render heatmap with 4 sections separated by spacer columns."""
    n_cols = len(columns)
    n_rows = len(cov_levels)

    fig_w = max(14, n_cols * 0.95)
    fig_h = max(6, n_rows * 0.55 + 2.5)
    fig, ax = plt.subplots(figsize=(fig_w, fig_h))
    fig.patch.set_facecolor((230/255, 230/255, 240/255))
    ax.set_facecolor((230/255, 230/255, 240/255))

    cmap = plt.cm.RdYlGn.copy()
    cmap.set_bad(color=(40/255, 30/255, 10/255))

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

    def _reformat_xlabel(col):
        """Convert 'PLAT+aligner+caller' → '(PLAT) aligner+caller'."""
        if col == SPACER_LABEL:
            return "│"
        c = col.replace(_PG_MARKER, "")
        # HIO: "ILMN+ONT+aligner+caller+Nx" → "(ILMN+ONT) aligner+caller+Nx"
        if c.startswith("ILMN+ONT+"):
            rest = c[len("ILMN+ONT+"):]
            return f"(ILMN+ONT) {rest}"
        # Paired: "ILMN-sbwa-dnascope-150paired" → "(ILMN) sbwa-dnascope-150paired"
        if "-" in c and "paired" in c:
            plat, rest = c.split("-", 1)
            return f"({plat}) {rest}"
        # Single-platform: "PLAT+aligner+caller" → "(PLAT) aligner+caller"
        parts = c.split("+", 1)
        if len(parts) == 2:
            return f"({parts[0]}) {parts[1]}"
        return c

    xlabels = [_reformat_xlabel(c) for c in columns]
    ax.set_xticklabels(xlabels, rotation=55, ha="right", fontsize=10.1, fontweight="bold")

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
    ax.set_yticklabels([f"{bin_display.get(c, c)}x" for c in cov_levels], fontsize=13.5)

    # Vertical separator lines at spacers
    for si in spacer_indices:
        ax.axvline(x=si, color="#6366f1", linewidth=1.5, linestyle=":", alpha=0.55)

    # Horizontal section annotations just above the top of the heatmap grid
    boundaries = [-1] + list(spacer_indices) + [n_cols]
    _section_annotations = {
        0: "dragen: ILMN pangenome  ·  roche: public pangenome",
    }
    for sec_i, header in enumerate(SECTION_HEADERS):
        left = boundaries[sec_i] + 1
        right = boundaries[sec_i + 1]
        if right <= left:
            continue
        mid = (left + right - 1) / 2.0
        # Section header — shifted down ~20px (lower y = closer to grid)
        ax.text(mid, n_rows - 0.25, header,
                ha="center", va="bottom", fontsize=8, fontstyle="italic",
                color="#7c8594")
        # Extra annotation line for specific sections
        annot = _section_annotations.get(sec_i)
        if annot:
            ax.text(mid, n_rows - 0.35, annot,
                    ha="center", va="top", fontsize=5.5, fontstyle="italic",
                    color="#9ca3af")

    # Annotate cells
    for i in range(n_rows):
        for j in range(n_cols):
            if columns[j] == SPACER_LABEL:
                continue
            val = mat[i, j]
            n = cnt[i, j]
            d = dep[i, j]
            if np.isnan(val):
                ax.text(j, i, "—", ha="center", va="center", fontsize=6, color="#c0c0c0")
            else:
                rgba = cmap(norm(val))
                perceived_lum = 0.299 * rgba[0] + 0.587 * rgba[1] + 0.114 * rgba[2]
                color = "black" if perceived_lum > 0.5 else "white"
                ax.text(j, i, f"{val:.3f}",
                        ha="center", va="center",
                        fontsize=11, fontweight="bold", color=color)

    # Make spacer columns rgb(10,30,40) with white coverage labels
    bin_display = {25: 20, 35: 30, 45: 40}
    for si in spacer_indices:
        for i in range(n_rows):
            ax.add_patch(plt.Rectangle((si - 0.5, i - 0.5), 1, 1,
                                       facecolor=(10/255, 30/255, 40/255),
                                       edgecolor="none"))
            cov_label = f"{bin_display.get(cov_levels[i], cov_levels[i])}x"
            ax.text(si, i, cov_label, ha="center", va="center",
                    fontsize=9.75, color="white", alpha=0.7)

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

    ax.set_xlabel("(Sequencing Platforms) Analysis Pipeline Code", fontsize=16.5)
    ax.set_ylabel("Primary Measured Coverage (Binned)", fontsize=16.5)
    ax.set_title(f"Fscore — ROI={footprint} — VariantClass={snp_class}",
                 fontsize=16.25, fontweight="bold", pad=30)

    cbar = fig.colorbar(im, ax=ax, shrink=0.8, pad=0.02)
    cbar.ax.tick_params(labelsize=13.5)
    cbar.set_label("Fscore", fontsize=15)
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


def main():
    footprint = sys.argv[1] if len(sys.argv) > 1 else "hg38"
    output_dir = os.path.join(BASE_DIR, f"heatmaps_fscore_{footprint}")
    os.makedirs(output_dir, exist_ok=True)

    data, counts, depths, pg_labels, hg38_labels, paired_labels, hio_labels = load_data(footprint)
    if not data:
        print(f"No data found for ROI={footprint}", file=sys.stderr)
        sys.exit(1)

    columns, spacer_indices = build_column_order(pg_labels, hg38_labels, paired_labels, hio_labels)
    all_covs = sorted({k[0] for d in data.values() for k in d if k[0] <= 45})

    print(f"ROI: {footprint}")
    print(f"Coverage levels: {all_covs}")
    print(f"Pangenome columns ({len(pg_labels)}): {pg_labels}")
    print(f"hg38 columns ({len(hg38_labels)}): {hg38_labels}")
    print(f"Paired columns ({len(paired_labels)}): {paired_labels}")
    print(f"HIO columns ({len(hio_labels)}): {sorted(hio_labels, key=hio_sort_key)}")
    print(f"VariantClasses: {sorted(data.keys())}")
    print()

    for snp_class in sorted(data.keys()):
        mat, cnt, dep = build_matrix(data[snp_class], counts[snp_class],
                                     depths.get(snp_class, {}), all_covs, columns)
        out_path = os.path.join(output_dir, f"fscore_{footprint}_{snp_class}.svg")
        plot_heatmap(mat, cnt, dep, all_covs, columns, spacer_indices,
                     snp_class, footprint, out_path)

    print(f"\nDone — {len(data)} heatmaps in {output_dir}")


if __name__ == "__main__":
    main()

