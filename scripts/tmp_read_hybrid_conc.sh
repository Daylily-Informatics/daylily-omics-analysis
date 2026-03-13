#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

$SSH $HN '
for d in test-hybrid-cli-ilmn-ont-3x test-hybrid-mod-ilmn-ont-3x test-hybrid-mod-ilmn-pb-3x; do
    for f in /fsx/analysis_results/ubuntu/$d/daylily-omics-analysis/results/day/*/other_reports/giab_concordance_mqc.tsv; do
        if [ -s "$f" ] 2>/dev/null; then
            echo "========== $d =========="
            cat "$f"
            echo ""
        fi
    done
done
'

