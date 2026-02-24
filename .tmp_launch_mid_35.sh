#!/usr/bin/env bash
set -euo pipefail

HEADNODE="34.209.187.6"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
BRANCH="feat/modular-hybrid-workflows"
TMUX_SESSION="hiomr_mid_35units"
TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
ANALYSIS_DESC="hiomr_mid_35units_${TIMESTAMP}"
MID_UNITS_REL=".test_data/data/agbt_2026/prod/hybrid/hiomr_ont_downsampled/mid_units.tsv"
SAMPLES_REL=".test_data/data/agbt_2026/prod/hybrid/hiomr_ont_downsampled/samples.tsv"

echo "=== Launching mid_units (35 units) HIOMR pipeline ==="
echo "Headnode: ${HEADNODE}"
echo "Branch: ${BRANCH}"
echo "Tmux session: ${TMUX_SESSION}"
echo "Analysis dir: ${ANALYSIS_DESC}"

# Step 1: Clone repo on headnode
echo ""
echo "--- Step 1: day-clone ---"
ssh -i "${PEM}" "ubuntu@${HEADNODE}" bash -l -c "'
  day-clone -t ${BRANCH} -w ssh -d ${ANALYSIS_DESC}
'"

# Step 2: Find the analysis dir
ANALYSIS_DIR="/fsx/analysis_results/ubuntu/${ANALYSIS_DESC}/daylily-omics-analysis"
echo ""
echo "--- Step 2: Copy mid_units.tsv -> config/units.tsv, samples.tsv -> config/samples.tsv ---"
ssh -i "${PEM}" "ubuntu@${HEADNODE}" bash -l -c "'
  cd ${ANALYSIS_DIR} && \
  cp ${MID_UNITS_REL} config/units.tsv && \
  cp ${SAMPLES_REL} config/samples.tsv && \
  echo \"units.tsv rows: \$(tail -n+2 config/units.tsv | wc -l)\" && \
  echo \"samples.tsv rows: \$(tail -n+2 config/samples.tsv | wc -l)\"
'"

# Step 3: Create tmux session and launch pipeline
echo ""
echo "--- Step 3: Launch pipeline in tmux session '${TMUX_SESSION}' ---"
ssh -i "${PEM}" "ubuntu@${HEADNODE}" bash -l -c "'
  tmux kill-session -t ${TMUX_SESSION} 2>/dev/null || true
  tmux new-session -d -s ${TMUX_SESSION}
  tmux send-keys -t ${TMUX_SESSION} \"cd ${ANALYSIS_DIR} && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_snv_concordances produce_alignstats -p -k -j 76 -T 0 --config snv_callers=[\\\"sentdhiomr\\\"]\" Enter
'"

echo ""
echo "=== Pipeline launched in tmux session '${TMUX_SESSION}' ==="
echo "Analysis dir: ${ANALYSIS_DIR}"
echo "Monitor with: ssh -i ${PEM} ubuntu@${HEADNODE} bash -l -c \"'tmux capture-pane -t ${TMUX_SESSION} -p | tail -30'\""

