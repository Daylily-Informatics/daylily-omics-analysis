#!/usr/bin/env bash
set -euo pipefail
PYTHON=/Users/jmajor/miniconda3/envs/DAY-EC/bin/python3

echo "=== Consolidation ==="
$PYTHON _analysis_data/agbt_benchmark_alignment_concordance_stats/consolidate_concordance.py 2>&1

echo ""
echo "=== Verify pan_ilmn_x coverage bins ==="
grep "pan_ilmn_x" _analysis_data/agbt_benchmark_alignment_concordance_stats/consolidated_concordance.tsv | cut -f3,24,26,27 | sort -u

echo ""
echo "=== Verify pangenome_3_and_30x coverage bins ==="
grep "pangenome_3_and_30x" _analysis_data/agbt_benchmark_alignment_concordance_stats/consolidated_concordance.tsv | cut -f3,24,26,27 | sort -u

echo ""
echo "=== Heatmaps ==="
/bin/bash scripts/tmp_gen_heatmaps.sh 2>&1

