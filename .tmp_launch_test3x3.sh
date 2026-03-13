#!/usr/bin/env bash
set -euo pipefail

# Launch 3x3 HIOMR stage1 fix validation on headnode 44.231.76.175
HEADNODE="44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SSH="ssh -i $PEM -o ConnectTimeout=10 ubuntu@$HEADNODE"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SESSION="hiomr_test3x3_${TIMESTAMP}"
ANALYSIS_DESC="hiomr_test3x3_stage1fix_${TIMESTAMP}"
BRANCH="feat/modular-hybrid-workflows"

echo "=== Step 1: day-clone on headnode ==="
CLONE_OUTPUT=$($SSH bash -l -c "'day-clone -t $BRANCH -w ssh -d $ANALYSIS_DESC 2>&1 | tail -5'")
echo "$CLONE_OUTPUT"

# Extract the analysis dir from clone output
ANALYSIS_DIR=$($SSH bash -l -c "'ls -td /fsx/analysis_results/ubuntu/${ANALYSIS_DESC}*/daylily-omics-analysis 2>/dev/null | head -1'")
if [ -z "$ANALYSIS_DIR" ]; then
    echo "ERROR: Could not find analysis dir for $ANALYSIS_DESC"
    exit 1
fi
echo "Analysis dir: $ANALYSIS_DIR"

echo "=== Step 2: Copy test data to config/ ==="
$SSH bash -l -c "'
cd $ANALYSIS_DIR
cp .test_data/data/agbt_2026/prod/hybrid/hiomr_ont_downsampled/test3x3_units.tsv config/units.tsv
cp .test_data/data/agbt_2026/prod/hybrid/hiomr_ont_downsampled/samples.tsv config/samples.tsv
echo \"units.tsv lines: \$(wc -l < config/units.tsv)\"
echo \"samples.tsv lines: \$(wc -l < config/samples.tsv)\"
awk -F\"\\t\" \"NR>1{print \\\$3}\" config/units.tsv
'"

echo "=== Step 3: Create tmux session and launch pipeline ==="
$SSH bash -l -c "'
tmux new-session -d -s $SESSION
tmux send-keys -t $SESSION \"cd $ANALYSIS_DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_snv_concordances produce_alignstats -p -k -j 20 -T 0 --config snv_callers=[\\\"sentdhiomr\\\"]\" Enter
'"

echo ""
echo "=== LAUNCHED ==="
echo "Session: $SESSION"
echo "Analysis dir: $ANALYSIS_DIR"
echo "Headnode: $HEADNODE"
echo ""
echo "Monitor with:"
echo "  ssh -i $PEM ubuntu@$HEADNODE bash -l -c \"'tmux capture-pane -t $SESSION -p -S -50'\""

