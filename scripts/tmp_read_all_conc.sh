#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "=== READ ALL non-empty results/day giab_concordance_mqc.tsv ==="
$SSH $HN '
for f in $(find /fsx/analysis_results/ubuntu/ -maxdepth 10 -path "*/results/day/*/other_reports/giab_concordance_mqc.tsv" -size +0c 2>/dev/null | sort); do
    dir=$(echo $f | sed "s|/fsx/analysis_results/ubuntu/||" | cut -d/ -f1)
    echo "========== $dir =========="
    cat "$f"
    echo ""
done
'

