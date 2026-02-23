#!/usr/bin/env python3
"""Generate HIOa hybrid workflow heatmap with ILMN multicaller columns.

Extends the standard HIOa heatmap by adding 3 columns to the LEFT of the 0x ILMN column:
- sentd (ILMN-only)
- clair3 (ILMN-only)  
- deep19 (ILMN-only)

X-axis becomes: [sentd, clair3, deep19, 0x_ONT, 1x_ONT, 3x_ONT, ...]
Y-axis remains: [0x_ILMN, 1x_ILMN, 3x_ILMN, ...]

Reads: 
  _analysis_data/hioa_data.json (hybrid data)
  x.log multicaller data (parsed inline)
Outputs:
  _analysis_data/HIOa_multicaller_fscore_all_giabhc.png
  _analysis_data/HIOa_multicaller_fscore_snpts_giabhc.png
"""

import csv
import json
import re
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from pathlib import Path

BASE = Path(__file__).resolve().parent

# ── Parse x.log multicaller data (giabHC) ───────────────────────────
MULTICALLER_DATA_GIABHC = """
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-7x-4-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
    0.000            3572733        3572680      35061     259182     0.9903       0.9324     0.9604
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-7x-4-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
    8.000            3514865        3515410     228082     317050     0.9391       0.9173     0.9280
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-7x-4-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
    1.000            3546764        3547309      15592     285151     0.9956       0.9256     0.9593
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-20x-7-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
    7.000            3797914        3798408      19765      34001     0.9948       0.9911     0.9930
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-20x-7-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
    1.000            3806711        3807213       6968      25204     0.9982       0.9934     0.9958
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-20x-7-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
    0.000            3812657        3812609      14252      19258     0.9963       0.9950     0.9956
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-10x-5-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
    0.000            3745236        3745183      30047      86679     0.9920       0.9774     0.9847
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-10x-5-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
    1.000            3728463        3729031      14233     103452     0.9962       0.9730     0.9845
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-10x-5-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
    8.000            3678821        3679380      87096     153094     0.9769       0.9600     0.9684
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-1x-1-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
    0.000             798621         798600      14256    3033294     0.9825       0.2084     0.3439
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-1x-1-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
    2.000            1015754        1015817     411040    2816161     0.7119       0.2651     0.3863
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-15x-6-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
    0.000            3804328        3804271      20542      27587     0.9946       0.9928     0.9937
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-15x-6-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
    7.000            3777449        3777972      36700      54466     0.9904       0.9858     0.9881
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-15x-6-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
    1.000            3795038        3795577       9914      36877     0.9974       0.9904     0.9939
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-3x-2-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
    0.000            2478206        2478168      31150    1353709     0.9876       0.6467     0.7816
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-3x-2-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
    2.000            2917292        2917659    1084545     914623     0.7290       0.7613     0.7448
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-3x-2-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
    1.000            2421292        2421542      10712    1410623     0.9956       0.6319     0.7731
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-5x-3-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
    0.000            3249181        3249136      35985     582734     0.9890       0.8479     0.9131
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-5x-3-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
    8.000            3232836        3233315     413458     599079     0.8866       0.8437     0.8646
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-5x-3-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
    1.000            3211204        3211643      14636     620711     0.9955       0.8380     0.9100
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
    0.000            3814667        3814626       7049      17248     0.9982       0.9955     0.9968
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
    1.000            3811066        3811535       4129      20849     0.9989       0.9946     0.9967
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
    7.000            3806786        3807273       9278      25129     0.9976       0.9934     0.9955
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-40x-9-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_giabHC/summary.txt
    0.000            3814438        3814395       3744      17477     0.9990       0.9954     0.9972
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-40x-9-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_giabHC/summary.txt
    2.000            3811588        3812046       8475      20327     0.9978       0.9947     0.9962
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-40x-9-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_giabHC/summary.txt
    1.000            3811692        3812155       2606      20223     0.9993       0.9947     0.9970
"""

# ── Parse y.log multicaller data (hg38) ──────────────────────────────
MULTICALLER_DATA_HG38 = """
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-7x-4-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_hg38/summary.txt
    9.000            3667053        3666945     783881     333023     0.8239       0.9167     0.8678
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-7x-4-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_hg38/summary.txt
    9.000            3558679        3559693     874421     441397     0.8028       0.8897     0.8440
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-7x-4-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_hg38/summary.txt
    7.000            3608306        3609065     524323     391770     0.8731       0.9021     0.8874
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-20x-7-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_hg38/summary.txt
   17.000            3839572        3840362     528212     160504     0.8791       0.9599     0.9177
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-20x-7-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_hg38/summary.txt
   17.000            3844956        3845347     433297     155120     0.8987       0.9612     0.9289
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-20x-7-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_hg38/summary.txt
   39.000            3894107        3893986     695824     105969     0.8484       0.9735     0.9067
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-10x-5-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_hg38/summary.txt
   15.000            3836510        3836425     778905     163566     0.8312       0.9591     0.8906
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-10x-5-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_hg38/summary.txt
   12.000            3736808        3737366     442669     263268     0.8941       0.9342     0.9137
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-10x-5-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_hg38/summary.txt
   11.000            3699617        3700617     686346     300459     0.8435       0.9249     0.8823
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-1x-1-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_hg38/summary.txt
    0.000             832492         832457     262860    3167584     0.7600       0.2081     0.3268
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-1x-1-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_hg38/summary.txt
    2.000            1049099        1049209     740716    2950977     0.5862       0.2623     0.3624
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-15x-6-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_hg38/summary.txt
   27.000            3888585        3888488     732184     111491     0.8415       0.9721     0.9021
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-15x-6-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_hg38/summary.txt
   15.000            3783015        3783893     552845     217061     0.8725       0.9457     0.9077
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-15x-6-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_hg38/summary.txt
   16.000            3816697        3817110     417733     183379     0.9014       0.9542     0.9270
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-3x-2-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_hg38/summary.txt
    2.000            2572652        2572553     617927    1427424     0.8063       0.6432     0.7156
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-3x-2-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_hg38/summary.txt
    7.000            2792298        2792847    1387272    1207778     0.6681       0.6981     0.6828
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-3x-2-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_hg38/summary.txt
    4.000            2491653        2492034     392124    1508423     0.8640       0.6229     0.7239
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-5x-3-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_hg38/summary.txt
    6.000            3355952        3355817     747611     644124     0.8178       0.8390     0.8283
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-5x-3-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_hg38/summary.txt
    8.000            3342824        3343693    1146854     657252     0.7446       0.8357     0.7875
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-5x-3-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_hg38/summary.txt
    6.000            3271012        3271634     475931     729064     0.8730       0.8177     0.8445
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_hg38/summary.txt
   59.000            3906263        3906166     665636      93813     0.8544       0.9765     0.9114
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_hg38/summary.txt
   19.000            3832018        3832336     408229     168058     0.9037       0.9580     0.9301
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-30x-8-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_hg38/summary.txt
   20.000            3843129        3843828     503332     156947     0.8842       0.9608     0.9209
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-40x-9-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/sentd/concordance/_hg38/summary.txt
   79.000            3909259        3909166     644803      90817     0.8584       0.9773     0.9140
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-40x-9-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/clair3/concordance/_hg38/summary.txt
   20.000            3862003        3862695     540632     138073     0.8772       0.9655     0.9192
/fsx/analysis_results/ubuntu/ilmn_multicaller_20260219/daylily-omics-analysis/results/day/hg38/I2-HG003-40x-9-D0-PF-ILMN-NOVASEQ/align/bwa2a/dmd/snv/deep19/concordance/_hg38/summary.txt
   20.000            3815740        3816029     386824     184336     0.9080       0.9539     0.9304
"""


def parse_multicaller_data(raw_data):
    """Parse MULTICALLER_DATA and return dict: (coverage, caller) -> {fscore, tp, fn, fp}"""
    data = {}
    lines = raw_data.strip().split('\n')
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if '/snv/' in line:
            m_cov = re.search(r'-(\d+)x-', line)
            m_caller = re.search(r'/snv/(\w+)/', line)
            if m_cov and m_caller:
                cov = int(m_cov.group(1))
                caller = m_caller.group(1)
                i += 1
                if i < len(lines):
                    parts = lines[i].split()
                    if len(parts) >= 8:
                        data[(cov, caller)] = {
                            'fscore': float(parts[7]),
                            'tp': int(parts[1]),
                            'fn': int(parts[4]),
                            'fp': int(parts[3]),
                        }
        i += 1
    return data


multicaller_data_giabhc = parse_multicaller_data(MULTICALLER_DATA_GIABHC)
multicaller_data_hg38 = parse_multicaller_data(MULTICALLER_DATA_HG38)
print(f"Parsed {len(multicaller_data_giabhc)} giabHC multicaller data points")
print(f"Parsed {len(multicaller_data_hg38)} hg38 multicaller data points")

# ── Load hybrid HIOa data ────────────────────────────────────────────
hioa_json = BASE / "hioa_data.json"
with open(hioa_json) as f:
    hioa_data = json.load(f)

units = hioa_data["units"]
print(f"Loaded {len(units)} HIOa units from {hioa_json}")

# ── Load single-platform ONT data ───────────────────────────────────
ONT_TSV = BASE / "agbt_ont" / "giab_concordance_mqc.tsv"
ONT_SKIP_TARGETS = {30}  # corrupt CRAM

def _load_ont_single_platform(snp_class="All", footprint="giabHC"):
    """Return dict: ont_cov -> {Fscore, TP, FN, FP}"""
    result = {}
    if not ONT_TSV.exists():
        return result
    with open(ONT_TSV) as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            if row["VariantClass"] != snp_class:
                continue
            if row.get("ROI", "") != footprint:
                continue
            m = re.search(r'-(\d+)x-', row["Sample"])
            if not m:
                continue
            cov = int(m.group(1))
            if cov in ONT_SKIP_TARGETS:
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

ont_single_giabhc = _load_ont_single_platform("All", "giabHC")
ont_single_hg38 = _load_ont_single_platform("All", "hg38")
print(f"Loaded {len(ont_single_giabhc)} ONT single-platform giabHC data points")
print(f"Loaded {len(ont_single_hg38)} ONT single-platform hg38 data points")

# ── Build axes ───────────────────────────────────────────────────────
# Y-axis: ILMN coverage (0x, 1x, 3x, 5x, 7x, 10x, 15x, 20x, 30x, 40x)
sr_covs = sorted({u["sr_cov"] for u in units})
if 0 not in sr_covs:
    sr_covs = [0] + sr_covs

# X-axis: [sentd, clair3, deep19, 0x_ONT, 1x_ONT, 3x_ONT, ...]
ont_covs = sorted({u["ont_cov"] for u in units})
if 0 not in ont_covs:
    ont_covs = [0] + ont_covs

# Prepend 3 multicaller "pseudo-coverages" (negative values to distinguish)
CALLER_PSEUDO_COVS = {"sentd": -3, "clair3": -2, "deep19": -1}
x_axis = list(CALLER_PSEUDO_COVS.values()) + ont_covs  # [-3, -2, -1, 0, 1, 3, ...]

nsr = len(sr_covs)
nx = len(x_axis)

print(f"Y-axis (ILMN): {sr_covs}")
print(f"X-axis (callers + ONT): {x_axis}")
print(f"Matrix shape: {nsr} rows × {nx} cols")

# ── Build matrices (one for each footprint) ─────────────────────────
def build_matrix(footprint_key, ont_single_data, multicaller_data):
    """Build matrix for a specific footprint."""
    mat = np.full((nsr, nx), np.nan)
    annot = {}

    sr_idx = {c: i for i, c in enumerate(sr_covs)}
    x_idx = {c: i for i, c in enumerate(x_axis)}

    # Fill multicaller columns (left 3 columns)
    for (ilmn_cov, caller), metrics in multicaller_data.items():
        if ilmn_cov not in sr_idx:
            continue
        pseudo_cov = CALLER_PSEUDO_COVS.get(caller)
        if pseudo_cov is None or pseudo_cov not in x_idx:
            continue
        si = sr_idx[ilmn_cov]
        xi = x_idx[pseudo_cov]
        mat[si, xi] = metrics['fscore']
        annot[(si, xi)] = {"TP": metrics['tp'], "FN": metrics['fn'], "FP": metrics['fp']}

    # Fill ONT 0x column (ONT-only, single platform)
    for ont_cov, metrics in ont_single_data.items():
        if ont_cov not in x_idx or 0 not in sr_idx:
            continue
        si = sr_idx[0]
        xi = x_idx[ont_cov]
        mat[si, xi] = metrics["Fscore"]
        annot[(si, xi)] = {"TP": metrics["TP"], "FN": metrics["FN"], "FP": metrics["FP"]}

    # Fill hybrid data (ILMN > 0 and ONT > 0)
    for unit in units:
        sr_c = unit["sr_cov"]
        ont_c = unit["ont_cov"]
        if sr_c not in sr_idx or ont_c not in x_idx:
            continue
        if unit.get("status") != "Complete":
            continue
        conc = unit.get(footprint_key, {}).get("All", {})
        if not conc:
            continue
        si = sr_idx[sr_c]
        xi = x_idx[ont_c]
        mat[si, xi] = conc.get("Fscore", np.nan)
        annot[(si, xi)] = {
            "TP": conc.get("TP", 0),
            "FN": conc.get("FN", 0),
            "FP": conc.get("FP", 0),
        }

    return mat, annot

fscore_mat_giabhc, annot_dict_giabhc = build_matrix("concordance", ont_single_giabhc, multicaller_data_giabhc)
fscore_mat_hg38, annot_dict_hg38 = build_matrix("concordance_hg38", ont_single_hg38, multicaller_data_hg38)

print(f"giabHC: Filled {np.sum(~np.isnan(fscore_mat_giabhc))} cells, {len(annot_dict_giabhc)} annotations")
print(f"hg38: Filled {np.sum(~np.isnan(fscore_mat_hg38))} cells, {len(annot_dict_hg38)} annotations")

# ── Build axis labels ────────────────────────────────────────────────
def _fmt_count(n):
    """Format count with k/M suffix."""
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    elif n >= 1_000:
        return f"{n/1_000:.0f}k"
    else:
        return str(n)

# Y-axis labels (ILMN coverage)
sr_labels = []
for c in sr_covs:
    if c == 0:
        sr_labels.append("0x\n(ONT only)")
    else:
        sr_labels.append(f"{c}x")

# X-axis labels (callers + ONT coverage)
x_labels = []
for c in x_axis:
    if c == -3:
        x_labels.append("sentd\n(ILMN)")
    elif c == -2:
        x_labels.append("clair3\n(ILMN)")
    elif c == -1:
        x_labels.append("deep19\n(ILMN)")
    elif c == 0:
        x_labels.append("0x\n(ILMN only)")
    else:
        x_labels.append(f"{c}x")

# ── Heatmap plotting function ────────────────────────────────────────
def make_heatmap(matrix, title, cbar_label, filename, annot):
    """Create annotated heatmap with multicaller columns."""
    fig, ax = plt.subplots(figsize=(18, 11))

    masked = np.ma.masked_invalid(matrix)
    cmap = plt.get_cmap("RdYlGn").copy()
    cmap.set_bad(color="#2d2d2d")
    norm = mcolors.Normalize(vmin=0.0, vmax=1.0)

    im = ax.imshow(masked, cmap=cmap, norm=norm, aspect="auto", origin="lower")
    cbar = fig.colorbar(im, ax=ax, shrink=0.8, pad=0.02)
    cbar.set_label(cbar_label, fontsize=12)

    ax.set_xticks(range(nx))
    ax.set_xticklabels(x_labels, fontsize=9)
    ax.set_yticks(range(nsr))
    ax.set_yticklabels(sr_labels, fontsize=10)
    ax.set_xlabel("Variant Caller (ILMN-only) | ONT Coverage (Hybrid)", fontsize=13, fontweight="bold")
    ax.set_ylabel("Illumina Coverage", fontsize=13, fontweight="bold")
    ax.set_title(title, fontsize=14, fontweight="bold", pad=12)

    # Annotate cells
    for si in range(nsr):
        for xi in range(nx):
            val = matrix[si, xi]
            if np.isnan(val):
                # Check if this is the (0,0) corner
                if sr_covs[si] == 0 and x_axis[xi] < 0:
                    continue  # Skip multicaller × ONT-only cells
                continue

            rgba = cmap(norm(val))
            lum = 0.299 * rgba[0] + 0.587 * rgba[1] + 0.114 * rgba[2]
            tc = "white" if lum < 0.5 else "black"

            # Determine if this is a single-platform or multicaller cell
            is_special = (sr_covs[si] == 0) or (x_axis[xi] < 0)
            style = "italic" if is_special else "normal"
            fs_size = 6.5 if is_special else 7.5
            detail_size = 4.5 if is_special else 5.0

            # F-score
            ax.text(xi, si + 0.22, f"{val:.4f}", ha="center", va="center",
                   fontsize=fs_size, fontweight="bold", color=tc, fontstyle=style)

            # TP/FN/FP
            a = annot.get((si, xi))
            if a:
                tp_s = _fmt_count(a["TP"])
                fn_s = _fmt_count(a["FN"])
                fp_s = _fmt_count(a["FP"])
                ax.text(xi, si - 0.02, f"TP {tp_s}",
                       ha="center", va="center", fontsize=detail_size,
                       color=tc, fontstyle=style, alpha=0.85)
                ax.text(xi, si - 0.22, f"FN {fn_s} FP {fp_s}",
                       ha="center", va="center", fontsize=detail_size,
                       color=tc, fontstyle=style, alpha=0.85)

    # Grid lines
    for si in range(nsr + 1):
        ax.axhline(si - 0.5, color="#4a4a4a", linewidth=0.5)
    for xi in range(nx + 1):
        ax.axvline(xi - 0.5, color="#4a4a4a", linewidth=0.5)

    # Thicker separator between multicaller columns and ONT columns
    # After deep19 (index 2), before 0x ONT (index 3)
    ax.axvline(2.5, color="#d4d4d4", linewidth=2.5, linestyle="--")

    # Thicker separator between 0x ILMN row and hybrid rows
    ax.axhline(0.5, color="#d4d4d4", linewidth=2.0, linestyle="--")

    # Separator between 0x ONT and 1x+ ONT
    ax.axvline(3.5, color="#d4d4d4", linewidth=2.0, linestyle="--")

    # Legend
    legend_text = ("F-score / TP / FN+FP  |  italic = single-platform or multicaller  "
                   "|  Left 3 cols = ILMN-only multicaller comparison")
    fig.text(0.5, 0.01, legend_text, ha="center", fontsize=9, color="#6b6b6b")

    fig.tight_layout(rect=[0, 0.03, 1, 1])
    fig.savefig(BASE / filename, dpi=180, bbox_inches="tight",
               facecolor="white", edgecolor="none")
    plt.close(fig)
    print(f"Saved: {BASE / filename}")


# ── Generate heatmaps ────────────────────────────────────────────────
make_heatmap(
    fscore_mat_giabhc,
    "HIOa Hybrid + ILMN Multicaller: All-Variant F-score (giabHC)\n"
    "ILMN Coverage × [Multicaller | ONT Coverage]",
    "F-score",
    "HIOa_multicaller_fscore_all_giabhc.png",
    annot_dict_giabhc,
)

make_heatmap(
    fscore_mat_hg38,
    "HIOa Hybrid + ILMN Multicaller: All-Variant F-score (hg38)\n"
    "ILMN Coverage × [Multicaller | ONT Coverage]",
    "F-score",
    "HIOa_multicaller_fscore_all_hg38.png",
    annot_dict_hg38,
)

print("\n✓ Heatmaps with multicaller columns generated successfully!")

