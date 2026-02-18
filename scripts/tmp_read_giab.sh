#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "========================================"
echo "=== CLI ILMN+ONT: giab file details ==="
echo "========================================"
$SSH $HN "ls -la /fsx/analysis_results/ubuntu/t3-hybrid-cli-ilmn-ont-3x/daylily-omics-analysis/results/day/hg38/other_reports/giab* 2>/dev/null; echo '---CONTENT---'; head -100 /fsx/analysis_results/ubuntu/t3-hybrid-cli-ilmn-ont-3x/daylily-omics-analysis/results/day/hg38/other_reports/giab_concordance_mqc.tsv 2>/dev/null; echo '---END---'"

echo ""
echo "========================================"
echo "=== CLI UG+ONT: giab file details ==="
echo "========================================"
$SSH $HN "ls -la /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/results/day/hg38_broad/other_reports/giab* 2>/dev/null; echo '---CONTENT---'; head -100 /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv 2>/dev/null; echo '---END---'"

echo ""
echo "========================================"
echo "=== BROADER SEARCH: rtgvcfeval output ==="
echo "========================================"
for dir in t3-hybrid-cli-ilmn-ont-3x t3-hybrid-cli-ug-ont-3x; do
    echo "--- $dir ---"
    $SSH $HN "find /fsx/analysis_results/ubuntu/$dir/daylily-omics-analysis/results -path '*snv_concordance*' -o -path '*rtgvcfeval*' -o -path '*giab*' 2>/dev/null | head -20"
    echo ""
done

echo ""
echo "========================================"
echo "=== SEARCH: any summary.txt from rtg ==="
echo "========================================"
for dir in t3-hybrid-cli-ilmn-ont-3x t3-hybrid-cli-ug-ont-3x; do
    echo "--- $dir ---"
    $SSH $HN "find /fsx/analysis_results/ubuntu/$dir/daylily-omics-analysis/results -name 'summary.txt' 2>/dev/null | head -10"
    echo ""
done

