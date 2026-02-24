#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"

echo "=== Find units.tsv reference in config files ==="
ssh -i "$KEY" "$HN" "grep -rn 'units' $STD_DIR/config/ 2>/dev/null | grep -i 'tsv\|path\|file' | head -10"

echo ""
echo "=== Check common.smk for units loading ==="
ssh -i "$KEY" "$HN" "grep -n 'units' $STD_DIR/workflow/rules/common.smk | head -10"

echo ""
echo "=== Check the actual units.tsv being used ==="
ssh -i "$KEY" "$HN" "ls -la $STD_DIR/.test_data/units.tsv 2>/dev/null || echo 'no .test_data/units.tsv'"
ssh -i "$KEY" "$HN" "ls -la $STD_DIR/units.tsv 2>/dev/null || echo 'no root units.tsv'"

echo ""
echo "=== Find all units.tsv in the analysis dir ==="
ssh -i "$KEY" "$HN" "find $STD_DIR -maxdepth 3 -name 'units.tsv' -not -path '*/.snakemake/*' 2>/dev/null"

echo ""
echo "=== Check the units.tsv that is actually loaded (col 18 value) ==="
ssh -i "$KEY" "$HN" "for f in \$(find $STD_DIR -maxdepth 3 -name 'units.tsv' -not -path '*/.snakemake/*' 2>/dev/null); do echo \"--- \$f ---\"; awk -F'\t' 'NR==2{print \"col18: [\" \$18 \"]\"}' \$f; done"

