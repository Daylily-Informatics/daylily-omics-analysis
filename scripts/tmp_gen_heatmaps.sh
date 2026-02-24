#!/bin/bash
set -euo pipefail
cd /Users/jmajor/projects/daylily/daylily-omics-analysis
PY=/Users/jmajor/miniconda3/envs/DAY-EC/bin/python3
SCRIPT=_analysis_data/agbt_benchmark_alignment_concordance_stats/heatmap_fscore_hg38.py

echo "========== hg38 =========="
$PY "$SCRIPT" hg38

echo ""
echo "========== clinvar_genes =========="
$PY "$SCRIPT" clinvar_genes

echo ""
echo "========== giabHC =========="
$PY "$SCRIPT" giabHC

echo ""
echo "=== SVG file counts ==="
for fp in hg38 clinvar_genes giabHC; do
    dir="_analysis_data/agbt_benchmark_alignment_concordance_stats/heatmaps_fscore_${fp}"
    cnt=$(ls "$dir"/*.svg 2>/dev/null | wc -l)
    echo "  $fp: $cnt SVGs in $dir"
done

