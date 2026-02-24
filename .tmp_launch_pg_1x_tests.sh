#!/usr/bin/env bash
set -euo pipefail

ILMN_DIR="/fsx/analysis_results/ubuntu/pg_ilmn_1x_test_20260222/daylily-omics-analysis"
UG_DIR="/fsx/analysis_results/ubuntu/pg_ug_1x_test_20260222/daylily-omics-analysis"

# Kill old tmux sessions if they exist
tmux kill-session -t pg_ilmn_1x 2>/dev/null || true
tmux kill-session -t pg_ug_1x 2>/dev/null || true

# Create Illumina 1x tmux session
echo "=== Creating tmux session: pg_ilmn_1x ==="
tmux new-session -d -s pg_ilmn_1x
tmux send-keys -t pg_ilmn_1x "cd $ILMN_DIR && source dyoainit && source bin/day_activate slurm hg38 && bash bin/day_run produce_pangenome_sr_vcf -p -j 1 -k -T 1" Enter
echo "Illumina 1x launched in tmux session pg_ilmn_1x"

# Create Ultima 1x tmux session
echo "=== Creating tmux session: pg_ug_1x ==="
tmux new-session -d -s pg_ug_1x
tmux send-keys -t pg_ug_1x "cd $UG_DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_pangenome_ug_vcf -p -j 1 -k -T 1" Enter
echo "Ultima 1x launched in tmux session pg_ug_1x"

echo ""
echo "=== Both launched ==="
echo "  tmux attach -t pg_ilmn_1x"
echo "  tmux attach -t pg_ug_1x"
echo "DONE"

