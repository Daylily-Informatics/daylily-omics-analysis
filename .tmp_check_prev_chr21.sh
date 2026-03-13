#!/bin/bash
set -euo pipefail
ssh -i ~/.ssh/lsmc-omics-us-west-2.pem -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@44.231.76.175 << 'REMOTECMD'
echo "=== Previous chr21 units.tsv ==="
cat /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis/config/units.tsv 2>/dev/null | head -20

echo ""
echo "=== Previous chr21 rule_config sentdhio section ==="
grep -A 30 "^sentdhio:" /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis/config/day_profiles/slurm/rule_config.yaml 2>/dev/null | head -35

echo ""
echo "=== Check day-clone availability ==="
which day-clone 2>/dev/null || echo "day-clone not in PATH"
source ~/.bashrc 2>/dev/null
which day-clone 2>/dev/null || echo "day-clone still not in PATH after sourcing bashrc"

echo ""
echo "=== day-clone help (first 20 lines) ==="
day-clone --help 2>&1 | head -20 || echo "day-clone --help failed"
REMOTECMD

