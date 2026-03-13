#!/bin/bash
set -euo pipefail
cd /Users/jmajor/projects/daylily/daylily-omics-analysis
/Users/jmajor/miniconda3/envs/DAY-EC/bin/python3 \
    _analysis_data/agbt_benchmark_alignment_concordance_stats/consolidate_concordance.py \
    2>&1 | tee /tmp/consolidation_output.txt
echo ""
echo "=== Line count ==="
wc -l _analysis_data/agbt_benchmark_alignment_concordance_stats/consolidated_concordance.tsv

