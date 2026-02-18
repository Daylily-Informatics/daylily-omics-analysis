#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "========================================"
echo "=== CLI ILMN+ONT: giab concordance ==="
echo "========================================"
$SSH $HN "cat /fsx/analysis_results/ubuntu/t3-hybrid-cli-ilmn-ont-3x/daylily-omics-analysis/results/day/hg38/other_reports/giab_concordance_mqc.tsv 2>/dev/null"

echo ""
echo "========================================"
echo "=== CLI UG+ONT: giab concordance ==="
echo "========================================"
$SSH $HN "cat /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv 2>/dev/null"

echo ""
echo "========================================"
echo "=== FIND rtgvcfeval / giab files in all 4 dirs ==="
echo "========================================"
for dir in t3-hybrid-cli-ilmn-ont-3x t3-hybrid-cli-ug-ont-3x t3-hybrid-mod-ug-ont-3x t4-hybrid-mod-ilmn-ont-3x; do
    echo "--- $dir ---"
    $SSH $HN "find /fsx/analysis_results/ubuntu/$dir/daylily-omics-analysis/results -name 'giab*' -o -name '*rtg*' -o -name '*vcfeval*' -o -name '*f1*' -o -name '*summary*csv' 2>/dev/null | head -15"
    echo ""
done

