#!/usr/bin/env python3
"""Generate heatmaps for ILMN multicaller comparison (sentd, clair3, deep19).

Reads: ~/x.log from headnode (concordance summary.txt data)
Outputs:
  _analysis_data/ilmn_multicaller_fscore_heatmap.png
  _analysis_data/ilmn_multicaller_precision_heatmap.png
  _analysis_data/ilmn_multicaller_sensitivity_heatmap.png
"""

import re
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from pathlib import Path

BASE = Path(__file__).resolve().parent

# Parse x.log data
RAW_DATA = """
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-7x-4-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    0.000            3572733        3572680      35061     259182     0.9903       0.9324     0.9604
     None            3572733        3572680      35061     259182     0.9903       0.9324     0.9604
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-7x-4-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    8.000            3514865        3515410     228082     317050     0.9391       0.9173     0.9280
     None            3651684        3652285     580798     180231     0.8628       0.9530     0.9056
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-7x-4-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    1.000            3546764        3547309      15592     285151     0.9956       0.9256     0.9593
     None            3546764        3547309      15592     285151     0.9956       0.9256     0.9593
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-20x-7-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    7.000            3797914        3798408      19765      34001     0.9948       0.9911     0.9930
     None            3805098        3805602      28188      26817     0.9926       0.9930     0.9928
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-20x-7-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    1.000            3806711        3807213       6968      25204     0.9982       0.9934     0.9958
     None            3806711        3807213       6968      25204     0.9982       0.9934     0.9958
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-20x-7-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    0.000            3812657        3812609      14252      19258     0.9963       0.9950     0.9956
     None            3812657        3812609      14252      19258     0.9963       0.9950     0.9956
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-10x-5-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    0.000            3745236        3745183      30047      86679     0.9920       0.9774     0.9847
     None            3745236        3745183      30047      86679     0.9920       0.9774     0.9847
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-10x-5-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    1.000            3728463        3729031      14233     103452     0.9962       0.9730     0.9845
     None            3728463        3729031      14233     103452     0.9962       0.9730     0.9845
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-10x-5-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    8.000            3678821        3679380      87096     153094     0.9769       0.9600     0.9684
     None            3740878        3741482     223287      91037     0.9437       0.9762     0.9597
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-1x-1-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    0.000             798621         798600      14256    3033294     0.9825       0.2084     0.3439
     None             798621         798600      14258    3033294     0.9825       0.2084     0.3439
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-1x-1-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    2.000            1015754        1015817     411040    2816161     0.7119       0.2651     0.3863
     None            1015754        1015817     411040    2816161     0.7119       0.2651     0.3863
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-15x-6-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    0.000            3804328        3804271      20542      27587     0.9946       0.9928     0.9937
     None            3804328        3804271      20542      27587     0.9946       0.9928     0.9937
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-15x-6-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    7.000            3777449        3777972      36700      54466     0.9904       0.9858     0.9881
     None            3791686        3792227      56074      40229     0.9854       0.9895     0.9875
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-15x-6-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    1.000            3795038        3795577       9914      36877     0.9974       0.9904     0.9939
     None            3795038        3795577       9914      36877     0.9974       0.9904     0.9939
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-3x-2-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    0.000            2478206        2478168      31150    1353709     0.9876       0.6467     0.7816
     None            2478206        2478168      31150    1353709     0.9876       0.6467     0.7816
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-3x-2-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    2.000            2917292        2917659    1084545     914623     0.7290       0.7613     0.7448
     None            2917292        2917659    1084545     914623     0.7290       0.7613     0.7448
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-3x-2-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    1.000            2421292        2421542      10712    1410623     0.9956       0.6319     0.7731
     None            2421292        2421542      10712    1410623     0.9956       0.6319     0.7731
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-5x-3-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    0.000            3249181        3249136      35985     582734     0.9890       0.8479     0.9131
     None            3249181        3249136      35985     582734     0.9890       0.8479     0.9131
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-5x-3-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    8.000            3232836        3233315     413458     599079     0.8866       0.8437     0.8646
     None            3487060        3487618     934916     344855     0.7886       0.9100     0.8450
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-5x-3-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    1.000            3211204        3211643      14636     620711     0.9955       0.8380     0.9100
     None            3211204        3211643      14636     620711     0.9955       0.8380     0.9100
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    0.000            3814667        3814626       7049      17248     0.9982       0.9955     0.9968
     None            3814667        3814626       7049      17248     0.9982       0.9955     0.9968
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    1.000            3811066        3811535       4129      20849     0.9989       0.9946     0.9967
     None            3811066        3811535       4129      20849     0.9989       0.9946     0.9967
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    7.000            3806786        3807273       9278      25129     0.9976       0.9934     0.9955
     None            3810843        3811339      13390      21072     0.9965       0.9945     0.9955
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-40x-9-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    0.000            3814438        3814395       3744      17477     0.9990       0.9954     0.9972
     None            3814438        3814395       3744      17477     0.9990       0.9954     0.9972
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-40x-9-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    2.000            3811588        3812046       8475      20327     0.9978       0.9947     0.9962
     None            3811588        3812046       8475      20327     0.9978       0.9947     0.9962
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-40x-9-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
Threshold  True-pos-baseline  True-pos-call  False-pos  False-neg  Precision  Sensitivity  F-measure
----------------------------------------------------------------------------------------------------
    1.000            3811692        3812155       2606      20223     0.9993       0.9947     0.9970
     None            3811692        3812155       2606      20223     0.9993       0.9947     0.9970
"""

# Parse the data
def parse_data():
    """Parse RAW_DATA and return dict: (coverage, caller) -> {precision, sensitivity, fscore, tp, fn, fp}"""
    data = {}
    lines = RAW_DATA.strip().split('\n')
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if '/snv/' in line:
            # Extract coverage and caller
            m_cov = re.search(r'-(\d+)x-', line)
            m_caller = re.search(r'/snv/(\w+)/', line)
            if m_cov and m_caller:
                cov = int(m_cov.group(1))
                caller = m_caller.group(1)
                # Skip header lines
                i += 3
                if i < len(lines):
                    # Parse first data line (threshold line)
                    parts = lines[i].split()
                    if len(parts) >= 8:
                        data[(cov, caller)] = {
                            'precision': float(parts[5]),
                            'sensitivity': float(parts[6]),
                            'fscore': float(parts[7]),
                            'tp': int(parts[1]),
                            'fn': int(parts[4]),
                            'fp': int(parts[3]),
                        }
        i += 1
    return data

data = parse_data()
print(f"Parsed {len(data)} data points")

# Extract unique coverages and callers
coverages = sorted({k[0] for k in data.keys()})
callers = sorted({k[1] for k in data.keys()})
print(f"Coverages: {coverages}")
print(f"Callers: {callers}")

# Create matrices
ncov = len(coverages)
ncaller = len(callers)
cov_idx = {c: i for i, c in enumerate(coverages)}
caller_idx = {c: i for i, c in enumerate(callers)}

fscore_mat = np.full((ncaller, ncov), np.nan)
precision_mat = np.full((ncaller, ncov), np.nan)
sensitivity_mat = np.full((ncaller, ncov), np.nan)

for (cov, caller), metrics in data.items():
    ci = caller_idx[caller]
    covi = cov_idx[cov]
    fscore_mat[ci, covi] = metrics['fscore']
    precision_mat[ci, covi] = metrics['precision']
    sensitivity_mat[ci, covi] = metrics['sensitivity']

print(f"\nF-score matrix shape: {fscore_mat.shape}")
print(f"Precision matrix shape: {precision_mat.shape}")
print(f"Sensitivity matrix shape: {sensitivity_mat.shape}")


def make_heatmap(matrix, title, cbar_label, filename, fmt_func, cmap_name="RdYlGn", vmin=0.0, vmax=1.0):
    """Create an annotated heatmap."""
    fig, ax = plt.subplots(figsize=(14, 8))

    masked = np.ma.masked_invalid(matrix)
    cmap = plt.get_cmap(cmap_name).copy()
    cmap.set_bad(color="#2d2d2d")
    norm = mcolors.Normalize(vmin=vmin, vmax=vmax)

    im = ax.imshow(masked, cmap=cmap, norm=norm, aspect="auto", origin="lower")
    cbar = fig.colorbar(im, ax=ax, shrink=0.8, pad=0.02)
    cbar.set_label(cbar_label, fontsize=12)

    ax.set_xticks(range(ncov))
    ax.set_xticklabels([f"{c}x" for c in coverages], fontsize=11)
    ax.set_yticks(range(ncaller))
    ax.set_yticklabels(callers, fontsize=11)
    ax.set_xlabel("Illumina Coverage", fontsize=13, fontweight="bold")
    ax.set_ylabel("Variant Caller", fontsize=13, fontweight="bold")
    ax.set_title(title, fontsize=14, fontweight="bold", pad=12)

    # Annotate cells
    for ci in range(ncaller):
        for covi in range(ncov):
            val = matrix[ci, covi]
            if not np.isnan(val):
                rgba = cmap(norm(val))
                lum = 0.299 * rgba[0] + 0.587 * rgba[1] + 0.114 * rgba[2]
                tc = "white" if lum < 0.5 else "black"
                ax.text(covi, ci, fmt_func(val), ha="center", va="center",
                       fontsize=9, fontweight="bold", color=tc)

    # Grid lines
    for ci in range(ncaller + 1):
        ax.axhline(ci - 0.5, color="#4a4a4a", linewidth=0.5)
    for covi in range(ncov + 1):
        ax.axvline(covi - 0.5, color="#4a4a4a", linewidth=0.5)

    fig.tight_layout()
    fig.savefig(BASE / filename, dpi=180, bbox_inches="tight",
               facecolor="white", edgecolor="none")
    plt.close(fig)
    print(f"Saved: {BASE / filename}")


# Generate heatmaps
make_heatmap(
    fscore_mat,
    "ILMN Multicaller Comparison: F-score vs Coverage\n(HG003, bwa2a, giabHC footprint)",
    "F-score",
    "ilmn_multicaller_fscore_heatmap.png",
    lambda v: f"{v:.4f}",
    cmap_name="RdYlGn",
    vmin=0.0,
    vmax=1.0,
)

make_heatmap(
    precision_mat,
    "ILMN Multicaller Comparison: Precision vs Coverage\n(HG003, bwa2a, giabHC footprint)",
    "Precision",
    "ilmn_multicaller_precision_heatmap.png",
    lambda v: f"{v:.4f}",
    cmap_name="RdYlGn",
    vmin=0.0,
    vmax=1.0,
)

make_heatmap(
    sensitivity_mat,
    "ILMN Multicaller Comparison: Sensitivity vs Coverage\n(HG003, bwa2a, giabHC footprint)",
    "Sensitivity",
    "ilmn_multicaller_sensitivity_heatmap.png",
    lambda v: f"{v:.4f}",
    cmap_name="RdYlGn",
    vmin=0.0,
    vmax=1.0,
)

print("\n✓ All heatmaps generated successfully!")

