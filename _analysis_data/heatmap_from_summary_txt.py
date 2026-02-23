#!/usr/bin/env python3
"""Heatmaps from raw vcfeval summary.txt — All variants, multiple footprints."""
import csv
import re
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from pathlib import Path

BASE = Path(__file__).resolve().parent

# ── Raw data per footprint ──────────────────────────────────────────
# Format: (sr_cov, ont_cov, TP_baseline, TP_call, FP, FN, Precision, Sensitivity, F_measure)

RAW_GIABHC = [
    (10, 10, 3770853, 3770846, 12460,   61062, 0.9967, 0.9841, 0.9903),
    (15,  1, 3766697, 3766685, 16349,   65218, 0.9957, 0.9830, 0.9893),
    (15,  3, 3772850, 3772839, 13533,   59065, 0.9964, 0.9846, 0.9905),
    (15,  7, 3780392, 3780379,  9737,   51523, 0.9974, 0.9866, 0.9920),
    ( 1,  1, 1224891, 1224878, 15381, 2607024, 0.9876, 0.3197, 0.4830),
    (20, 10, 3787620, 3787619,  5976,   44295, 0.9984, 0.9884, 0.9934),
    (20,  1, 3775896, 3775894, 11440,   56019, 0.9970, 0.9854, 0.9911),
    (20,  3, 3779950, 3779946,  9449,   51965, 0.9975, 0.9864, 0.9919),
    (20,  7, 3784792, 3784790,  7042,   47123, 0.9981, 0.9877, 0.9929),
    (30, 10, 3789461, 3789458,  3601,   42454, 0.9991, 0.9889, 0.9940),
    (30,  1, 3780024, 3780022,  6184,   51891, 0.9984, 0.9865, 0.9924),
    (30,  3, 3783138, 3783134,  5147,   48777, 0.9986, 0.9873, 0.9929),
    (30,  7, 3787183, 3787180,  4135,   44732, 0.9989, 0.9883, 0.9936),
    ( 3,  1, 2670060, 2670050, 25018, 1161855, 0.9907, 0.6968, 0.8182),
    ( 3,  3, 3022185, 3022170, 23622,  809730, 0.9922, 0.7887, 0.8788),
    (40, 15, 3791588, 3791582,  2640,   40327, 0.9993, 0.9895, 0.9944),
    (40,  3, 3783471, 3783461,  3613,   48444, 0.9990, 0.9874, 0.9932),
    (40,  7, 3787322, 3787313,  3009,   44593, 0.9992, 0.9884, 0.9938),
    ( 5,  1, 3302992, 3302981, 28124,  528923, 0.9916, 0.8620, 0.9222),
    ( 5,  3, 3456588, 3456580, 24732,  375327, 0.9929, 0.9021, 0.9453),
    ( 7, 10, 3738657, 3738644, 16505,   93258, 0.9956, 0.9757, 0.9855),
    ( 7,  1, 3569716, 3569707, 27458,  262199, 0.9924, 0.9316, 0.9610),
    ( 7,  3, 3637865, 3637856, 23398,  194050, 0.9936, 0.9494, 0.9710),
]

RAW_CLINVAR = [
    (10, 10, 442796, 442789, 87706,  19163, 0.8347, 0.9585, 0.8923),
    (15,  1, 442771, 442764, 81216,  19188, 0.8450, 0.9585, 0.8982),
    (15,  3, 442131, 442123, 82455,  19828, 0.8428, 0.9571, 0.8963),
    (15,  7, 440875, 440868, 82272,  21084, 0.8427, 0.9544, 0.8951),
    ( 1,  1, 148407, 148399, 31780, 313552, 0.8236, 0.3213, 0.4622),
    (20, 10, 441503, 441498, 81230,  20456, 0.8446, 0.9557, 0.8967),
    (20,  1, 443469, 443464, 79198,  18490, 0.8485, 0.9600, 0.9008),
    (20,  3, 442469, 442462, 79996,  19490, 0.8469, 0.9578, 0.8989),
    (20,  7, 442065, 442059, 81431,  19894, 0.8444, 0.9569, 0.8972),
    (30, 10, 442983, 442975, 80078,  18976, 0.8469, 0.9589, 0.8994),
    (30,  1, 442737, 442731, 74682,  19222, 0.8557, 0.9584, 0.9041),
    (30,  3, 442176, 442168, 76292,  19783, 0.8528, 0.9572, 0.9020),
    (30,  7, 443388, 443381, 80259,  18571, 0.8467, 0.9598, 0.8997),
    ( 3,  1, 321959, 321951, 61845, 140000, 0.8389, 0.6969, 0.7613),
    ( 3,  3, 361375, 361363, 71924, 100584, 0.8340, 0.7823, 0.8073),
    (40, 15, 442221, 442215, 78178,  19738, 0.8498, 0.9573, 0.9003),
    (40,  3, 443466, 443460, 75247,  18493, 0.8549, 0.9600, 0.9044),
    (40,  7, 442861, 442855, 76859,  19098, 0.8521, 0.9587, 0.9023),
    ( 5,  1, 395659, 395654, 76076,  66300, 0.8387, 0.8565, 0.8475),
    ( 5,  3, 412475, 412470, 82507,  49484, 0.8333, 0.8929, 0.8621),
    ( 7, 10, 440963, 440961, 88919,  20996, 0.8322, 0.9545, 0.8892),
    ( 7,  1, 424068, 424065, 80553,  37892, 0.8404, 0.9180, 0.8775),
    ( 7,  3, 431446, 431440, 85214,  30513, 0.8351, 0.9339, 0.8817),
]

RAW_HG38 = [
    (10, 10, 3841160, 3841075, 796465,  158916, 0.8283, 0.9603, 0.8894),
    (15,  1, 3866500, 3866404, 736454,  133576, 0.8400, 0.9666, 0.8989),
    (15,  3, 3852740, 3852655, 744752,  147336, 0.8380, 0.9632, 0.8962),
    (15,  7, 3861786, 3861683, 776413,  138290, 0.8326, 0.9654, 0.8941),
    ( 1,  1, 1271901, 1271862, 330562, 2728175, 0.7937, 0.3180, 0.4540),
    (20, 10, 3864243, 3864158, 763408,  135833, 0.8350, 0.9660, 0.8958),
    (20,  1, 3864796, 3864704, 705032,  135280, 0.8457, 0.9662, 0.9019),
    (20,  3, 3859315, 3859234, 723758,  140761, 0.8421, 0.9648, 0.8993),
    (20,  7, 3855185, 3855105, 742597,  144891, 0.8385, 0.9638, 0.8968),
    (30, 10, 3867522, 3867444, 736707,  132554, 0.8400, 0.9669, 0.8990),
    (30,  1, 3875491, 3875398, 684114,  124585, 0.8500, 0.9689, 0.9055),
    (30,  3, 3867102, 3867022, 698101,  132974, 0.8471, 0.9668, 0.9030),
    (30,  7, 3865952, 3865875, 723602,  134124, 0.8423, 0.9665, 0.9001),
    ( 3,  1, 2771762, 2771685, 597176, 1228314, 0.8227, 0.6929, 0.7523),
    ( 3,  3, 3137835, 3137728, 705772,  862241, 0.8164, 0.7844, 0.8001),
    (40, 15, 3865439, 3865355, 722814,  134637, 0.8425, 0.9663, 0.9002),
    (40,  3, 3866874, 3866801, 675745,  133202, 0.8512, 0.9667, 0.9053),
    (40,  7, 3856129, 3856057, 686202,  143947, 0.8489, 0.9640, 0.9028),
    ( 5,  1, 3406847, 3406761, 684636,  593229, 0.8327, 0.8517, 0.8421),
    ( 5,  3, 3562675, 3562593, 752499,  437401, 0.8256, 0.8907, 0.8569),
    ( 7, 10, 3809189, 3809090, 801903,  190888, 0.8261, 0.9523, 0.8847),
    ( 7,  1, 3687192, 3687097, 748176,  312884, 0.8313, 0.9218, 0.8742),
    ( 7,  3, 3734838, 3734731, 769998,  265238, 0.8291, 0.9337, 0.8783),
]

# Measured coverage from alignstats (target -> measured)
MEAS_SR =  {1: 1.1, 3: 3.4, 5: 5.7, 7: 8.0, 10: 11.4, 15: 16.9, 20: 22.5, 30: 33.3, 40: 43.9}
MEAS_ONT = {1: 0.5, 3: 1.6, 5: 2.6, 7: 3.6, 10: 5.2, 15: 7.8, 20: 10.4, 40: 20.8, 50: 26.0}

# ── Load single-platform "All" class for a given footprint ──────────
ILMN_TSV = BASE / "ilmn_hg003_prod" / "giab_concordance_mqc.tsv"
ONT_TSV  = BASE / "agbt_ont" / "giab_concordance_mqc.tsv"
ONT_SKIP_TARGETS = {30}  # corrupt CRAM


def _load_single_platform(tsv_path, footprint_filter, skip_targets=None):
    """Return dict: target_cov -> {Fscore, TP, FN, FP} for 'All' class + given footprint."""
    result = {}
    if not Path(tsv_path).exists():
        return result
    with open(tsv_path) as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            if row["VariantClass"] != "All":
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


# ── Axes (union of both datasets, prepend 0 for single-platform) ───
_all_raw = RAW_GIABHC + RAW_CLINVAR
sr_covs  = [0] + sorted({r[0] for r in _all_raw})
ont_covs = [0] + sorted({r[1] for r in _all_raw})
nsr, nont = len(sr_covs), len(ont_covs)
sr_idx  = {c: i for i, c in enumerate(sr_covs)}
ont_idx = {c: i for i, c in enumerate(ont_covs)}


def _meas(cov, platform):
    if cov == 0:
        return "0x"
    m = MEAS_SR if platform == "ilmn" else MEAS_ONT
    v = m.get(cov)
    return f"{v:.1f}x\n(tgt {cov}x)" if v else f"{cov}x"


sr_labels  = [_meas(c, "ilmn") for c in sr_covs]
ont_labels = [_meas(c, "ont") for c in ont_covs]


def _fmt(n):
    if n >= 1_000_000: return f"{n/1_000_000:.2f}M"
    if n >= 10_000:    return f"{n/1_000:.1f}K"
    if n >= 1_000:     return f"{n/1_000:.2f}K"
    return str(n)


def plot_heatmap(raw_data, footprint_filter, footprint_label, out_filename):
    """Build matrix, fill single-platform edges, and render heatmap."""
    sp_ilmn = _load_single_platform(ILMN_TSV, footprint_filter, None)
    sp_ont  = _load_single_platform(ONT_TSV, footprint_filter, ONT_SKIP_TARGETS)
    print(f"\n[{footprint_label}] SP ILMN covs: {sorted(sp_ilmn.keys())}  "
          f"SP ONT covs: {sorted(sp_ont.keys())}")

    f_mat = np.full((nsr, nont), np.nan)
    annot = {}
    is_sp = set()

    # Hybrid data
    for sr, ont, tp_b, tp_c, fp, fn, prec, sens, fmeas in raw_data:
        si, oi = sr_idx.get(sr), ont_idx.get(ont)
        if si is not None and oi is not None:
            f_mat[si, oi] = fmeas
            annot[(si, oi)] = {"TP": tp_b, "FN": fn, "FP": fp}

    # ONT0x column: ILMN-only
    for sr_c in sr_covs:
        if sr_c == 0:
            continue
        d = sp_ilmn.get(sr_c)
        if d and sr_c in sr_idx:
            si, oi = sr_idx[sr_c], ont_idx[0]
            f_mat[si, oi] = d["Fscore"]
            annot[(si, oi)] = {"TP": d["TP"], "FN": d["FN"], "FP": d["FP"]}
            is_sp.add((si, oi))

    # SR0x row: ONT-only
    for ont_c in ont_covs:
        if ont_c == 0:
            continue
        d = sp_ont.get(ont_c)
        if d and ont_c in ont_idx:
            si, oi = sr_idx[0], ont_idx[ont_c]
            f_mat[si, oi] = d["Fscore"]
            annot[(si, oi)] = {"TP": d["TP"], "FN": d["FN"], "FP": d["FP"]}
            is_sp.add((si, oi))

    # ── Render ──
    fig, ax = plt.subplots(figsize=(14, 11))
    masked = np.ma.masked_invalid(f_mat)
    cmap = plt.get_cmap("RdYlGn").copy()
    cmap.set_bad(color="#2d2d2d")
    norm = mcolors.Normalize(vmin=0.0, vmax=1.0)

    im = ax.imshow(masked, cmap=cmap, norm=norm, aspect="auto", origin="lower")
    cbar = fig.colorbar(im, ax=ax, shrink=0.8, pad=0.02)
    cbar.set_label("F-measure (All variants)", fontsize=12)

    ax.set_xticks(range(nont))
    ax.set_xticklabels(ont_labels, fontsize=10)
    ax.set_yticks(range(nsr))
    ax.set_yticklabels(sr_labels, fontsize=10)
    ax.set_xlabel("ONT Measured Coverage", fontsize=13, fontweight="bold")
    ax.set_ylabel("Illumina (SR) Measured Coverage", fontsize=13, fontweight="bold")
    ax.set_title(f"HIOa Hybrid: All-Variant F-measure ({footprint_label}, from summary.txt)\n"
                 "Illumina × ONT Coverage Matrix — raw vcfeval totals  "
                 "(0x = single-platform baseline)",
                 fontsize=14, fontweight="bold", pad=12)

    for si in range(nsr):
        for oi in range(nont):
            val = f_mat[si, oi]
            if np.isnan(val):
                if sr_covs[si] == 0 and ont_covs[oi] == 0:
                    continue
                ax.text(oi, si, "…", ha="center", va="center",
                        fontsize=10, fontweight="bold", color="#3b82f6")
                continue
            rgba = cmap(norm(val))
            lum = 0.299 * rgba[0] + 0.587 * rgba[1] + 0.114 * rgba[2]
            tc = "white" if lum < 0.5 else "black"
            sp = (si, oi) in is_sp
            style = "italic" if sp else "normal"
            fs_size = 6.5 if sp else 7.5
            detail_size = 4.5 if sp else 5.0
            ax.text(oi, si + 0.24, f"{val:.4f}", ha="center", va="center",
                    fontsize=fs_size, fontweight="bold", color=tc, fontstyle=style)
            a = annot.get((si, oi))
            if a:
                ax.text(oi, si, f"TP {_fmt(a['TP'])}", ha="center", va="center",
                        fontsize=detail_size, color=tc, fontstyle=style, alpha=0.85)
                ax.text(oi, si - 0.22, f"FN {_fmt(a['FN'])}  FP {_fmt(a['FP'])}",
                        ha="center", va="center", fontsize=detail_size,
                        color=tc, fontstyle=style, alpha=0.85)

    for si in range(nsr + 1):
        ax.axhline(si - 0.5, color="#4a4a4a", linewidth=0.5)
    for oi in range(nont + 1):
        ax.axvline(oi - 0.5, color="#4a4a4a", linewidth=0.5)
    ax.axhline(0.5, color="#d4d4d4", linewidth=2.0, linestyle="--")
    ax.axvline(0.5, color="#d4d4d4", linewidth=2.0, linestyle="--")

    legend = ("F-measure / TP / FN+FP  |  italic = single-platform  "
              "|  source: vcfeval summary.txt  |  … = not yet complete")
    fig.text(0.5, 0.01, legend, ha="center", fontsize=9, color="#6b6b6b")
    fig.tight_layout(rect=[0, 0.03, 1, 1])
    out = BASE / out_filename
    fig.savefig(out, dpi=180, bbox_inches="tight", facecolor="white", edgecolor="none")
    plt.close(fig)
    print(f"Saved: {out}")


# ── Generate all three heatmaps ──────────────────────────────────────
plot_heatmap(RAW_GIABHC, "giabHC", "giabHC",
             "HIOa_summary_txt_all_giabhc.png")
plot_heatmap(RAW_CLINVAR, "clinvar_genes", "ClinVar Genes",
             "HIOa_summary_txt_all_clinvar_genes.png")
plot_heatmap(RAW_HG38, "hg38", "hg38 whole genome",
             "HIOa_summary_txt_all_hg38.png")

