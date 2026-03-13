#!/usr/bin/env bash
set -euo pipefail
cd _analysis_data/agbt_benchmark_alignment_concordance_stats
python consolidate_concordance.py
echo ""
echo "=== Row count ==="
wc -l consolidated_concordance.tsv
echo "=== TestGroups ==="
awk -F'\t' 'NR>1{print $21}' consolidated_concordance.tsv | sort | uniq -c | sort -rn

