#!/usr/bin/env bash
set -euo pipefail
cd /Users/jmajor/projects/daylily/daylily-omics-analysis
PY=/Users/jmajor/miniconda3/envs/DAY-EC/bin/python3
BD=_analysis_data/agbt_benchmark_alignment_concordance_stats

echo "============================================================"
echo "FULL REBUILD — $(date)"
echo "============================================================"

echo ""
echo "=== STEP 1: Reconsolidate concordance TSV ==="
$PY "$BD/consolidate_concordance.py" 2>&1
echo ""
echo "Row count:"
wc -l "$BD/consolidated_concordance.tsv"

echo ""
echo "=== STEP 2: Regenerate F-score heatmaps (3 ROIs) ==="
for roi in hg38 giabHC clinvar_genes; do
    echo "--- ROI: $roi ---"
    $PY "$BD/heatmap_fscore_hg38.py" "$roi" 2>&1
    echo ""
done

echo "=== SVG file counts ==="
for roi in hg38 clinvar_genes giabHC; do
    dir="$BD/heatmaps_fscore_${roi}"
    cnt=$(ls "$dir"/*.svg 2>/dev/null | wc -l | tr -d ' ')
    echo "  $roi: $cnt SVGs in $dir"
done

echo ""
echo "=== STEP 3: Regenerate plot2 (30x performance comparison) ==="
$PY "$BD/plot2_30x_performance_comparison.py" 2>&1

echo ""
echo "=== STEP 4: Regenerate benchmark heatmaps ==="
$PY "$BD/bench_heatmaps.py" 2>&1

echo ""
echo "=== STEP 5: Regenerate precision-recall scatter (slide 1) ==="
$PY scripts/tmp_precision_recall_scatter.py 2>&1

echo ""
echo "============================================================"
echo "ALL DONE — $(date)"
echo "============================================================"

