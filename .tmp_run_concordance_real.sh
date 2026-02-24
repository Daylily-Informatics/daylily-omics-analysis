#!/usr/bin/env bash
set -euo pipefail

HEADNODE="44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
ANALYSIS_DIR="/fsx/analysis_results/ubuntu/hiomr_xfer_shard_chr21_20260221/daylily-omics-analysis"
TMUX_SESSION="hiomr_xfer_shard_test"

# Real run (no -n flag) — run concordance with sentdhiomr caller
ssh -i "$PEM" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "ubuntu@${HEADNODE}" \
  "tmux send-keys -t ${TMUX_SESSION} 'bash bin/day_run produce_snv_concordances produce_sentdhiomr_vcf -p -j 10 -k -T 0 --rerun-triggers mtime --config snv_callers=[\"sentdhiomr\"]' Enter"

echo "Real concordance run launched in tmux session ${TMUX_SESSION}"

