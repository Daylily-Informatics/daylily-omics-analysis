#!/bin/bash
set -euo pipefail
HEADNODE="ubuntu@44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
CLONE="/fsx/analysis_results/ubuntu/hiomr_xfer_shard_chr21_20260221/daylily-omics-analysis"
TMUX_SESSION="hiomr_xfer_shard_test"
SLURM_DIR="$CLONE/config/day_profiles/slurm"
TMPL_DIR="$SLURM_DIR/templates"

echo "=== Step 1: Copy template configs to active dir ==="
ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE \
  "cp $TMPL_DIR/*.yaml $SLURM_DIR/ 2>/dev/null; cp $TMPL_DIR/*.bash $SLURM_DIR/ 2>/dev/null; echo done"

echo "=== Step 2: Patch active rule_config for chr21-only ==="
ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE \
  "sed -i 's/hg38_broad_sentdhio_chrms: \"1-24\"/hg38_broad_sentdhio_chrms: \"21\"/' $SLURM_DIR/rule_config.yaml && grep 'hg38_broad_sentdhio_chrms' $SLURM_DIR/rule_config.yaml"

echo "=== Step 3: Touch active configs so they're newer ==="
ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE \
  "touch $SLURM_DIR/*.yaml $SLURM_DIR/*.bash 2>/dev/null; echo touched"

echo "=== Step 4: Kill old tmux and create fresh ==="
ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE \
  "tmux kill-session -t $TMUX_SESSION 2>/dev/null; tmux new-session -d -s $TMUX_SESSION"

echo "=== Step 5: Launch pipeline ==="
ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE \
  "tmux send-keys -t $TMUX_SESSION 'cd $CLONE && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiomr_vcf produce_snv_concordances produce_alignstats -p -k -j 76 -T 0' Enter"

echo "=== Launched ==="

