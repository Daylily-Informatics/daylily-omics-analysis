#!/usr/bin/env bash
set -euo pipefail

BASE="/fsx/analysis_results/ubuntu"

# --- sentdhipmr (ILMN+PB) ---
SESSION="test-sentdhipmr-3x"
DIR="$BASE/$SESSION/daylily-omics-analysis"
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION"
tmux send-keys -t "$SESSION" "cd $DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhipmr_vcf produce_snv_concordances produce_alignstats -p -k -j 20 -T 1 -n 2>&1 | tee /tmp/${SESSION}_dryrun.log" Enter
echo "Launched dry-run: $SESSION"

# --- sentdhuomr (UG+ONT) ---
SESSION="test-sentdhuomr-3x"
DIR="$BASE/$SESSION/daylily-omics-analysis"
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION"
tmux send-keys -t "$SESSION" "cd $DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhuomr_vcf produce_snv_concordances produce_alignstats -p -k -j 20 -T 1 -n 2>&1 | tee /tmp/${SESSION}_dryrun.log" Enter
echo "Launched dry-run: $SESSION"

# --- sentdhupmr (UG+PB) ---
SESSION="test-sentdhupmr-3x"
DIR="$BASE/$SESSION/daylily-omics-analysis"
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION"
tmux send-keys -t "$SESSION" "cd $DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhupmr_vcf produce_snv_concordances produce_alignstats -p -k -j 20 -T 1 -n 2>&1 | tee /tmp/${SESSION}_dryrun.log" Enter
echo "Launched dry-run: $SESSION"

echo ""
echo "=== All 3 dry-runs launched. Check with: tmux ls ==="

