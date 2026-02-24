#!/usr/bin/env bash
set -euo pipefail

PYTHON=/Users/jmajor/miniconda3/envs/DAY-EC/bin/python3
SCRIPT=_analysis_data/agbt_benchmark_alignment_concordance_stats/consolidate_concordance.py
TSV=_analysis_data/agbt_benchmark_alignment_concordance_stats/consolidated_concordance.tsv

echo "=== Running consolidation ==="
$PYTHON "$SCRIPT" 2>&1

echo ""
echo "=== Verification ==="
echo "Total lines: $(wc -l < "$TSV")"
echo "Columns: $(head -1 "$TSV" | tr '\t' '\n' | wc -l)"
echo ""
echo "=== TestGroups ==="
cut -f21 "$TSV" | sort | uniq -c | sort -rn
echo ""
echo "=== Rows per new group ==="
grep -c "hiomr_one" "$TSV" || echo "hiomr_one: 0"
grep -c "hiomr_two" "$TSV" || echo "hiomr_two: 0"

