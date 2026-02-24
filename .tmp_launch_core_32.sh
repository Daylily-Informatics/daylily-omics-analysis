#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@34.209.187.6"

TMUX_SESSION="hiomr_core_29units"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ANALYSIS_NAME="hiomr_core_29units_${TIMESTAMP}"

echo "=== Step 1: Create tmux session and day-clone ==="
ssh -i "$KEY" "$HN" bash -l -c "'
  # Kill existing session if any
  tmux kill-session -t ${TMUX_SESSION} 2>/dev/null || true
  
  # Create new tmux session
  tmux new-session -d -s ${TMUX_SESSION}
  
  echo \"tmux session ${TMUX_SESSION} created\"
  
  # Clone the repo with the feature branch
  day-clone -t feat/modular-hybrid-workflows -w ssh -d ${ANALYSIS_NAME}
  
  # Find the analysis directory 
  ANALYSIS_DIR=\$(ls -td /fsx/analysis_results/ubuntu/${ANALYSIS_NAME}*/daylily-omics-analysis 2>/dev/null | head -1)
  echo \"ANALYSIS_DIR=\${ANALYSIS_DIR}\"
  
  if [ -z \"\${ANALYSIS_DIR}\" ]; then
    echo \"ERROR: Could not find analysis directory\"
    exit 1
  fi
  
  # Copy core_units.tsv as config/units.tsv and samples.tsv as config/samples.tsv
  cp \${ANALYSIS_DIR}/.test_data/data/agbt_2026/prod/hybrid/hiomr_ont_downsampled/core_units.tsv \${ANALYSIS_DIR}/config/units.tsv
  cp \${ANALYSIS_DIR}/.test_data/data/agbt_2026/prod/hybrid/hiomr_ont_downsampled/samples.tsv \${ANALYSIS_DIR}/config/samples.tsv
  
  echo \"=== Verify config files ==\"
  echo \"units.tsv lines: \$(wc -l < \${ANALYSIS_DIR}/config/units.tsv)\"
  echo \"samples.tsv lines: \$(wc -l < \${ANALYSIS_DIR}/config/samples.tsv)\"
  head -2 \${ANALYSIS_DIR}/config/units.tsv
  
  echo \"\"
  echo \"=== Step 2: Send pipeline launch command to tmux ==\"
  tmux send-keys -t ${TMUX_SESSION} \"cd \${ANALYSIS_DIR} && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_snv_concordances produce_alignstats -p -k -j 76 -T 0 --config snv_callers=[\\\"sentdhiomr\\\"]\" Enter
  
  echo \"Pipeline launch command sent to tmux session: ${TMUX_SESSION}\"
  echo \"Analysis dir: \${ANALYSIS_DIR}\"
'"

