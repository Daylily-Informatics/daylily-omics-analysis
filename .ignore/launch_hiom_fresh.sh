#!/bin/bash
set -euo pipefail

HEADNODE="44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SSH="ssh -i $PEM -o StrictHostKeyChecking=no ubuntu@$HEADNODE"
BRANCH="feat/modular-hybrid-workflows"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SESSION="cmr-hiom-fix-${TIMESTAMP}"
DESC="hiom-fix-${TIMESTAMP}"
TEST_DATA_SRC=".test_data/data/agbt_2026/prod/hybrid/ilmn_ont_expanded_testfix"

echo "=== Step 1: day-clone on headnode ==="
CLONE_OUTPUT=$($SSH "source ~/.bashrc && day-clone -t $BRANCH -w ssh -d $DESC 2>&1 | tail -5")
echo "$CLONE_OUTPUT"

# Extract the analysis dir path from day-clone output
ANALYSIS_DIR=$($SSH "source ~/.bashrc && ls -td /fsx/analysis_results/ubuntu/${DESC}*/daylily-omics-analysis 2>/dev/null | head -1")
if [ -z "$ANALYSIS_DIR" ]; then
    echo "ERROR: Could not find analysis dir for $DESC"
    exit 1
fi
echo "Analysis dir: $ANALYSIS_DIR"

echo "=== Step 2: Copy testfix units.tsv and samples.tsv ==="
$SSH "cp ${ANALYSIS_DIR}/${TEST_DATA_SRC}/units.tsv ${ANALYSIS_DIR}/config/units.tsv"
$SSH "cp ${ANALYSIS_DIR}/${TEST_DATA_SRC}/samples.tsv ${ANALYSIS_DIR}/config/samples.tsv"
echo "Copied config files"

echo "=== Step 3: Verify config ==="
$SSH "wc -l ${ANALYSIS_DIR}/config/units.tsv ${ANALYSIS_DIR}/config/samples.tsv"

echo "=== Step 4: Create tmux session and launch ==="
$SSH "tmux new-session -d -s $SESSION"
$SSH "tmux send-keys -t $SESSION 'cd $ANALYSIS_DIR && source ~/.bashrc && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiom_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1' Enter"

echo ""
echo "=== LAUNCHED ==="
echo "Session: $SESSION"
echo "Analysis dir: $ANALYSIS_DIR"
echo "To check: ssh -i $PEM ubuntu@$HEADNODE 'tmux capture-pane -t $SESSION -p | tail -20'"

