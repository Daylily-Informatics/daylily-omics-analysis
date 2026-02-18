#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "=== CHECK STATUS ==="
$SSH $HN "echo '--- TMUX ---'; tmux ls 2>/dev/null; echo; echo '--- SLURM ---'; squeue -u ubuntu --format='%.8i %.2t %.55j %.10M' 2>/dev/null | head -20; echo; echo '--- SNAKEMAKE ---'; pgrep -af 'snakemake.*produce' 2>/dev/null | head -10"

echo ""
echo "=== PULL IN MOD ILMN+ONT ==="
$SSH $HN "cd /fsx/analysis_results/ubuntu/t4-hybrid-mod-ilmn-ont-3x/daylily-omics-analysis && git pull origin feat/modular-hybrid-workflows 2>&1 | tail -5 && echo && git log --oneline -3"

echo ""
echo "=== PULL IN MOD UG+ONT ==="
$SSH $HN "cd /fsx/analysis_results/ubuntu/t3-hybrid-mod-ug-ont-3x/daylily-omics-analysis && git pull origin feat/modular-hybrid-workflows 2>&1 | tail -5 && echo && git log --oneline -3"

echo ""
echo "=== TMUX PANE STATUS ==="
$SSH $HN "for s in t3-hybrid-cli-ilmn-ont-3x t3-hybrid-cli-ug-ont-3x t3-hybrid-mod-ug-ont-3x t4-hybrid-mod-ilmn-ont-3x; do echo \"===== \$s =====\"; tmux capture-pane -t \$s -p -S -20 2>/dev/null | grep -E 'steps.*done|SUCCESS|FAIL|Error|Submitted|Exiting|Womp|Finished' | tail -5; echo; done"

