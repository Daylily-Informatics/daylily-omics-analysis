#!/bin/bash
# Tail snakemake logs from each test session
BASE=/fsx/analysis_results/ubuntu

for sess in test-ont-solo-3x test-ilmn-solo-3x test-pb-solo-3x test-ug-solo-3x test-roche-solo-3x \
            test-hybrid-cli-ilmn-ont-3x test-hybrid-cli-ug-ont-3x \
            test-hybrid-mod-ilmn-ont-3x test-hybrid-mod-ug-ont-3x \
            test-hybrid-cli-ilmn-pb-3x test-hybrid-mod-ilmn-pb-3x \
            test-hybrid-cli-ug-pb-3x test-hybrid-mod-ug-pb-3x \
            test-hybrid-mod-roche-ont-3x test-hybrid-mod-roche-pb-3x; do
    echo "=== $sess ==="
    tmux capture-pane -t "$sess" -p 2>/dev/null | tail -8
    echo ""
done

