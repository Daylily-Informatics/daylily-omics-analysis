#!/bin/bash
set -euo pipefail

HEADNODE="ubuntu@44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SSH="ssh -i $PEM -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HEADNODE"

ANALYSIS_DIR="hiomr_xfer_shard_chr21_20260221"
BRANCH="feat/modular-hybrid-workflows"
TMUX_SESSION="hiomr_xfer_shard_test"

echo "=== Step 1: Clone fresh analysis repo ==="
$SSH "source ~/.bashrc && day-clone -t $BRANCH -w ssh -d $ANALYSIS_DIR" 2>&1 | tail -5

echo ""
echo "=== Step 2: Find the cloned directory ==="
CLONE_PATH=$($SSH "ls -d /fsx/analysis_results/ubuntu/$ANALYSIS_DIR/daylily-omics-analysis 2>/dev/null" | head -1)
echo "Clone path: $CLONE_PATH"

echo ""
echo "=== Step 3: Verify branch and latest commit ==="
$SSH "cd $CLONE_PATH && git log --oneline -3"

echo ""
echo "=== Step 4: Copy units.tsv from previous chr21 run ==="
$SSH "cp /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis/config/units.tsv $CLONE_PATH/config/units.tsv"
$SSH "cat $CLONE_PATH/config/units.tsv"

echo ""
echo "=== Step 5: Set chr21-only in rule_config ==="
$SSH "sed -i 's/hg38_broad_sentdhio_chrms: \"1-24\"/hg38_broad_sentdhio_chrms: \"21\"/' $CLONE_PATH/config/day_profiles/slurm/templates/rule_config.yaml"
$SSH "grep -A 5 'hg38_broad_sentdhio_chrms' $CLONE_PATH/config/day_profiles/slurm/templates/rule_config.yaml | head -5"

echo ""
echo "=== Step 6: Create tmux session and launch pipeline ==="
$SSH "tmux kill-session -t $TMUX_SESSION 2>/dev/null || true"
$SSH "tmux new-session -d -s $TMUX_SESSION"
$SSH "tmux send-keys -t $TMUX_SESSION 'cd $CLONE_PATH && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiomr_vcf produce_snv_concordances produce_alignstats -p -k -j 76 -T 0' Enter"

echo ""
echo "=== Step 7: Wait a few seconds and capture initial output ==="
sleep 5
$SSH "tmux capture-pane -t $TMUX_SESSION -p -S -30" 2>&1 | tail -20

echo ""
echo "=== Done. Tmux session: $TMUX_SESSION ==="

