#!/usr/bin/env bash
set -euo pipefail

HEADNODE="ubuntu@34.209.187.6"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
TMUX_SESSION="hiomr_maxi53_v2"
ANALYSIS_DIR="/fsx/analysis_results/ubuntu/hiomr_maxi53_v2/daylily-omics-analysis"

# Step 1: Clone repo
echo "=== Cloning ==="
ssh -i "$PEM" -o ConnectTimeout=10 "$HEADNODE" bash -l -c "'day-clone -t feat/modular-hybrid-workflows -w ssh -d hiomr_maxi53_v2 2>&1 | tail -3'"

# Step 2: Copy test data to config/
echo "=== Copying maxi_units.tsv and samples.tsv ==="
ssh -i "$PEM" -o ConnectTimeout=10 "$HEADNODE" bash -l -c "'cd $ANALYSIS_DIR && cp .test_data/data/agbt_2026/prod/hybrid/hiomr_ont_downsampled/maxi_units.tsv config/units.tsv && cp .test_data/data/agbt_2026/prod/hybrid/hiomr_ont_downsampled/samples.tsv config/samples.tsv && echo units: && wc -l config/units.tsv && echo samples: && cat config/samples.tsv'"

# Step 3: Create tmux session and launch pipeline
echo "=== Launching pipeline in tmux session $TMUX_SESSION ==="
ssh -i "$PEM" -o ConnectTimeout=10 "$HEADNODE" bash -l -c "'tmux kill-session -t $TMUX_SESSION 2>/dev/null; tmux new-session -d -s $TMUX_SESSION && tmux send-keys -t $TMUX_SESSION \"cd $ANALYSIS_DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_snv_concordances -p -k -j 100 -T 1 --config snv_callers=[\\\\\\\"sentdhiomr\\\\\\\"]\" Enter && echo TMUX_CREATED'"

echo "=== Done ==="

