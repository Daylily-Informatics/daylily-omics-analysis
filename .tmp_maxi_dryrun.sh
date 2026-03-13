#!/usr/bin/env bash
set -euo pipefail

# Dry-run maxi HIOMR on headnode 34.209.187.6
HEADNODE="34.209.187.6"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SSH="ssh -i $PEM -o ConnectTimeout=10 ubuntu@$HEADNODE"
ANALYSIS_DIR="/fsx/analysis_results/ubuntu/hiomr_maxi_fulltest/daylily-omics-analysis"
SESSION="hiomr_maxi_test"

echo "=== Creating tmux session and running dry-run ==="
$SSH bash -l -c "'
tmux kill-session -t $SESSION 2>/dev/null || true
tmux new-session -d -s $SESSION
tmux send-keys -t $SESSION \"cd $ANALYSIS_DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_snv_concordances -p -k -j 100 -T 1 --config snv_callers=[\\\"sentdhiomr\\\"] -n 2>&1 | tee /tmp/maxi_dryrun.log\" Enter
'"

echo "Tmux session $SESSION created. Dry-run command sent."
echo "Waiting for dry-run to complete..."
sleep 8

# Capture the dry-run output
echo "=== Capturing dry-run output ==="
$SSH bash -l -c "'cat /tmp/maxi_dryrun.log 2>/dev/null | tail -30 || tmux capture-pane -t $SESSION -p -S -50 | tail -30'"

