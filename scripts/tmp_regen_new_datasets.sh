#!/usr/bin/env bash
set -euo pipefail
cd /Users/jmajor/projects/daylily/daylily-omics-analysis
PYTHON=/Users/jmajor/miniconda3/envs/DAY-EC/bin/python3
BD=_analysis_data/agbt_benchmark_alignment_concordance_stats

echo "=== Regenerating consolidated TSV ==="
$PYTHON "$BD/consolidate_concordance.py" 2>&1

echo ""
echo "=== Row counts by TestGroup ==="
awk -F'\t' 'NR>1{print $21}' "$BD/consolidated_concordance.tsv" | sort | uniq -c | sort -rn

echo ""
echo "=== Total rows ==="
wc -l "$BD/consolidated_concordance.tsv"

echo ""
echo "=== Regenerating heatmaps ==="
for fp in hg38 giabHC clinvar_genes ultima giabHC_x_ultima_x_clinvar hg38_m_giabHC giabHC_x_ultima giabHC_x_clinvar_genes; do
    echo "  footprint: $fp"
    $PYTHON "$BD/heatmap_fscore_hg38.py" "$fp" 2>&1 | tail -3
    echo ""
done

echo ""
echo "=== Regenerating cost heatmap ==="
$PYTHON "$BD/heatmap_cost.py" 2>&1 | tail -3

echo ""
echo "=== DONE ==="

