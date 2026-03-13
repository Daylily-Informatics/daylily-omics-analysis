#!/usr/bin/env bash
set -euo pipefail

HEADNODE="ubuntu@44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SSH="ssh -i $PEM -o ConnectTimeout=10 -o StrictHostKeyChecking=no $HEADNODE"
SCP="scp -i $PEM -o ConnectTimeout=10 -o StrictHostKeyChecking=no"
ANALYSIS_NAME="hiomr_fullgenome_3x3x_15x15x_20260222"
TMUX_SESSION="hiomr_fullgenome_test"
BRANCH="feat/modular-hybrid-workflows"
ANALYSIS_DIR="/fsx/analysis_results/ubuntu/${ANALYSIS_NAME}/daylily-omics-analysis"

echo "=== Step 1: Create analysis dir and clone repo ==="
$SSH "source ~/.bashrc && day-clone -t $BRANCH -w ssh -d $ANALYSIS_NAME 2>&1 | tail -10"

echo ""
echo "=== Step 2: Verify clone and branch ==="
$SSH "cd $ANALYSIS_DIR && git log --oneline -3 && git branch --show-current"

echo ""
echo "=== Step 3: Copy config files ==="
$SCP /tmp/hiomr_fullgenome_units.tsv ${HEADNODE}:${ANALYSIS_DIR}/config/units.tsv
$SCP /tmp/hiomr_fullgenome_samples.tsv ${HEADNODE}:${ANALYSIS_DIR}/config/samples.tsv

echo ""
echo "=== Step 4: Verify configs on headnode ==="
$SSH "cd $ANALYSIS_DIR && echo '--- units.tsv lines ---' && wc -l config/units.tsv && awk -F'\t' '{print NR\": \" \$3}' config/units.tsv && echo '--- samples.tsv ---' && head -2 config/samples.tsv | cut -f1-3"

echo ""
echo "=== Step 5: Verify full-genome chrm config (should be 1-24) ==="
$SSH "cd $ANALYSIS_DIR && grep 'sentdhio_chrms' config/day_profiles/slurm/templates/rule_config.yaml | head -3"

echo ""
echo "=== Step 6: Create tmux session and launch pipeline ==="
$SSH "tmux kill-session -t $TMUX_SESSION 2>/dev/null || true"
$SSH "tmux new-session -d -s $TMUX_SESSION"
$SSH "tmux send-keys -t $TMUX_SESSION 'cd $ANALYSIS_DIR && source ~/.bashrc && source dyoainit --project $ANALYSIS_NAME && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_snv_concordances produce_alignstats -p -k -j 76 -T 0 --config snv_callers=[\"sentdhiomr\"]' Enter"

echo ""
echo "=== Step 7: Wait 12s then check tmux output ==="
sleep 12
$SSH "tmux capture-pane -t $TMUX_SESSION -p 2>&1 | tail -40"

echo ""
echo "========================================="
echo "  LAUNCH SUMMARY"
echo "========================================="
echo "Headnode:       44.231.76.175"
echo "PEM:            ~/.ssh/lsmc-omics-us-west-2.pem"
echo "Analysis dir:   $ANALYSIS_DIR"
echo "Tmux session:   $TMUX_SESSION"
echo "Branch:         $BRANCH"
echo "Samples:        SR3x-ONT3x, SR15x-ONT15x"
echo "Genome build:   hg38_broad"
echo "Targets:        produce_snv_concordances produce_alignstats"
echo "========================================="

