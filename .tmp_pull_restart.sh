#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
REF_DIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

echo "=== Pull on STD clone ==="
ssh -i "$KEY" "$HN" "cd $STD_DIR && git pull origin feat/modular-hybrid-workflows 2>&1 | tail -5"

echo ""
echo "=== Pull on REF clone ==="
ssh -i "$KEY" "$HN" "cd $REF_DIR && git pull origin feat/modular-hybrid-workflows 2>&1 | tail -5"

echo ""
echo "=== Verify fix in STD ==="
ssh -i "$KEY" "$HN" "grep -n '@RG' $STD_DIR/workflow/rules/sent_hybrid_ilmn_ont_modular.smk | head -3"

echo ""
echo "=== Verify fix in REF ==="
ssh -i "$KEY" "$HN" "grep -n '@RG' $REF_DIR/workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk | head -3"

