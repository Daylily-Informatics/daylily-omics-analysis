#!/usr/bin/env bash
# Check status of hybrid workflow tests on headnode
set -euo pipefail

SSH_KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HEADNODE="ubuntu@44.231.76.175"

ssh -i "$SSH_KEY" "$HEADNODE" 'bash -s' << 'ENDSSH'
echo "=== HYBRID TESTS STATUS CHECK ($(date)) ==="
echo ""

TESTS=(
    test-hybrid-cli-ilmn-ont-3x
    test-hybrid-cli-ug-ont-3x
    test-hybrid-mod-ug-ont-3x
    test-hybrid-mod-ilmn-ont-3x-conc
    test-hybrid-mod-ilmn-pb-3x-conc
)

for t in "${TESTS[@]}"; do
    echo "--- $t ---"
    tmux capture-pane -t "$t" -p 2>/dev/null | grep -E "steps.*done|SUCCESS|Error|RETURN CODE" | tail -2 || echo "(no session)"
done

echo ""
echo "=== CONCORDANCE FILES ==="

DIRS=(
    test-hybrid-cli-ilmn-ont-3x
    test-hybrid-cli-ug-ont-3x
    test-hybrid-mod-ug-ont-3x
    test-hybrid-mod-ilmn-ont-3x
    test-hybrid-mod-ilmn-pb-3x
)

for d in "${DIRS[@]}"; do
    f="/fsx/analysis_results/ubuntu/$d/daylily-omics-analysis/results/day/hg38/other_reports/giab_concordance_mqc.tsv"
    fb="/fsx/analysis_results/ubuntu/$d/daylily-omics-analysis/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv"
    echo "--- $d ---"
    if [[ -s "$f" ]]; then
        grep SNPts "$f" | cut -f1,9 | head -1
    elif [[ -s "$fb" ]]; then
        grep SNPts "$fb" | cut -f1,9 | head -1
    else
        echo "(empty or not found)"
    fi
done
ENDSSH

