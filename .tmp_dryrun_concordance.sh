#!/usr/bin/env bash
set -euo pipefail

HEADNODE="ubuntu@44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SSH="ssh -i $PEM -o ConnectTimeout=10 -o StrictHostKeyChecking=no $HEADNODE"
ADIR="/fsx/analysis_results/ubuntu/hiomr_fullgenome_3x3x_15x15x_20260222/daylily-omics-analysis"
SESS="hiomr_dryrun"

# Kill old session if exists
$SSH "tmux kill-session -t $SESS 2>/dev/null || true"

# Create new tmux session
$SSH "tmux new-session -d -s $SESS"

# Send the dry-run command (tmux interactive shell is login shell)
$SSH "tmux send-keys -t $SESS 'cd $ADIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_snv_concordances -p -k -j 76 -T 0 --config snv_callers=\"[\\\"sentdhiomr\\\"]\" -n 2>&1 | tee /tmp/dryrun_output.txt' Enter"

echo "Dry-run launched in tmux session: $SESS"

