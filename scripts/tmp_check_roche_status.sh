#!/bin/bash
set -euo pipefail
SSH="ssh -i $HOME/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=60 ubuntu@44.231.76.175"

echo "=== TMUX OUTPUT ==="
$SSH "tmux capture-pane -t roche-all-run -p -S -50 2>&1 | tail -50"
echo ""
echo "=== SLURM QUEUE ==="
$SSH "squeue -u ubuntu 2>&1 | head -30"
echo ""
echo "=== LOG TAIL ==="
$SSH "tail -10 /fsx/analysis_results/ubuntu/roche_sbxd_test/daylily-omics-analysis/_roche_all_7samples.log 2>&1"

