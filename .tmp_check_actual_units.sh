#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
REF_DIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

echo "=== What units.tsv does snakemake actually read? ==="
echo "--- STD: check config for units path ---"
ssh -i "$KEY" "$HN" "grep -i 'units' $STD_DIR/config/day_profiles/slurm/config.yaml 2>/dev/null | head -5"

echo ""
echo "--- STD: check the actual units.tsv symlink target ---"
ssh -i "$KEY" "$HN" "ls -la $STD_DIR/.test_data/data/agbt_2026/prod/hybrid/ilmn_ont_expanded_testfix/units.tsv"
ssh -i "$KEY" "$HN" "readlink -f $STD_DIR/.test_data/data/agbt_2026/prod/hybrid/ilmn_ont_expanded_testfix/units.tsv 2>/dev/null || echo 'not a symlink'"

echo ""
echo "--- STD: check the units.tsv that snakemake uses (from config) ---"
ssh -i "$KEY" "$HN" "grep -i 'units' $STD_DIR/config/day_profiles/slurm/config.yaml 2>/dev/null"

echo ""
echo "--- STD: check actual units.tsv content (col 18) ---"
ssh -i "$KEY" "$HN" "awk -F'\t' '{print NR\": [\" \$18 \"]\"}' \$(grep 'units:' $STD_DIR/config/day_profiles/slurm/config.yaml | awk '{print \$2}' | sed \"s|^|$STD_DIR/|\")"

echo ""
echo "--- STD: find all units.tsv references ---"
ssh -i "$KEY" "$HN" "find $STD_DIR -name 'units.tsv' -not -path '*/.snakemake/*' | head -10"

