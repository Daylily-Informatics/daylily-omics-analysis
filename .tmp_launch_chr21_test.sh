#!/bin/bash
set -euo pipefail
HEADNODE="ubuntu@44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
CLONE="/fsx/analysis_results/ubuntu/hiomr_xfer_shard_chr21_20260221/daylily-omics-analysis"
TMUX_SESSION="hiomr_xfer_shard_test"

echo "=== Kill existing session if any ==="
ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE \
  "tmux kill-session -t $TMUX_SESSION 2>/dev/null; echo 'old session cleaned'"

echo "=== Create tmux session and launch ==="
ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE \
  "tmux new-session -d -s $TMUX_SESSION"

ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE \
  "tmux send-keys -t $TMUX_SESSION 'cd $CLONE && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiomr_vcf produce_snv_concordances produce_alignstats -p -k -j 76 -T 0' Enter"

echo "=== Launched. Waiting 8s for initial output ==="
sleep 8

ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE \
  "tmux capture-pane -t $TMUX_SESSION -p -S -40" 2>&1 | tail -30

echo "=== Done ==="

