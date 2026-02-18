#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "========================================"
echo "=== FIND ALL summary.txt from rtgvcfeval ==="
echo "========================================"
$SSH $HN "find /fsx/analysis_results/ubuntu/ -maxdepth 10 -path '*/concordance*' -name 'summary.txt' 2>/dev/null | head -30"

echo ""
echo "========================================"
echo "=== FIND ALL concordance.mqc files ==="
echo "========================================"
$SSH $HN "find /fsx/analysis_results/ubuntu/ -maxdepth 10 -name '*concordance*.mqc*' 2>/dev/null | head -30"

echo ""
echo "========================================"
echo "=== FIND ALL giab_concordance_mqc.tsv with content ==="
echo "========================================"
$SSH $HN "find /fsx/analysis_results/ubuntu/ -maxdepth 10 -name 'giab_concordance_mqc.tsv' -size +0c 2>/dev/null | head -20"

echo ""
echo "========================================"
echo "=== FIND ALL *_summary.txt (parsed results) ==="
echo "========================================"
$SSH $HN "find /fsx/analysis_results/ubuntu/ -maxdepth 12 -path '*concordance*' -name '*_summary.txt' 2>/dev/null | head -30"

