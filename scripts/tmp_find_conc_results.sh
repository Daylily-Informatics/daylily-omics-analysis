#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "========================================"
echo "=== SEARCH ALL test-hybrid dirs for concordance results ==="
echo "========================================"
$SSH $HN "for d in /fsx/analysis_results/ubuntu/test-hybrid-*/daylily-omics-analysis/results; do
    found=\$(find \$d -name 'summary.txt' -o -name '*concordance*' -o -name '*rtg*' -o -name '*f1*' -o -name '*giab*' 2>/dev/null | grep -v '_mqc.tsv' | head -5)
    if [ -n \"\$found\" ]; then
        echo \"=== \$(basename \$(dirname \$(dirname \$d))) ===\"
        echo \"\$found\"
        echo
    fi
done"

echo ""
echo "========================================"
echo "=== SEARCH ALL hybrid dirs for rtgvcfeval summary.txt ==="
echo "========================================"
$SSH $HN "find /fsx/analysis_results/ubuntu/ -maxdepth 6 -path '*/snv_concordance*' -name 'summary.txt' 2>/dev/null | head -20"

echo ""
echo "========================================"
echo "=== SEARCH for any giab_HC results ==="
echo "========================================"
$SSH $HN "find /fsx/analysis_results/ubuntu/ -maxdepth 8 -name '*giab*HC*' -o -name '*giabHC*' -o -name '*giab_hc*' 2>/dev/null | head -20"

echo ""
echo "========================================"
echo "=== SEARCH for rtgvcfeval output dirs ==="
echo "========================================"
$SSH $HN "find /fsx/analysis_results/ubuntu/ -maxdepth 8 -type d -name 'rtgvcfeval' 2>/dev/null | head -20"

