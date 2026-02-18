#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "=== Find all rtgvcfeval summary.txt under analysis_results ==="
$SSH $HN "find /fsx/analysis_results/ubuntu/ -maxdepth 12 -path '*concordance*' -name 'summary.txt' 2>/dev/null"

echo ""
echo "=== Find non-empty giab_concordance_mqc.tsv ==="
$SSH $HN "find /fsx/analysis_results/ubuntu/ -maxdepth 10 -name 'giab_concordance_mqc.tsv' -size +0c 2>/dev/null"

echo ""
echo "=== Find non-empty *concordance*.mqc* ==="
$SSH $HN "find /fsx/analysis_results/ubuntu/ -maxdepth 12 -name '*concordance*.mqc*' -size +0c 2>/dev/null | head -30"

