#!/bin/bash
set -euo pipefail
SESSION="t5-hybrid-mod-ug-ont-3x"
echo "=== Creating fresh analysis dir ==="
source ~/.bashrc
cd /fsx/analysis_results/ubuntu
day-clone -d "$SESSION" -t feat/modular-hybrid-workflows
cd "$SESSION/daylily-omics-analysis"
echo "=== Verify fix is present ==="
grep -n "stage3_pass2_reheadered" workflow/rules/sent_hybrid_ug_ont_modular.smk | head -5
echo "=== Creating tmux session ==="
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION"
tmux set-option -t "$SESSION" remain-on-exit on
echo "=== Initializing ==="
tmux send-keys -t "$SESSION" "cd /fsx/analysis_results/ubuntu/$SESSION/daylily-omics-analysis && source ~/.bashrc && . dyoainit --project hybrid-mod-ug-ont" Enter
sleep 8
echo "=== Activating slurm hg38_broad ==="
tmux send-keys -t "$SESSION" "dy-a slurm hg38_broad" Enter
sleep 8
echo "=== Launching pipeline ==="
tmux send-keys -t "$SESSION" "dy-r produce_sentdhuom_vcf -p -k -j 300" Enter
sleep 3
echo "=== Session status ==="
tmux capture-pane -t "$SESSION" -p -S -5 | tail -4
echo "Done."

