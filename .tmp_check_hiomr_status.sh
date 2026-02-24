#!/bin/bash
set -e
SSH_CMD="ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i ~/.ssh/lsmc-omics-us-west-2.pem ubuntu@44.231.76.175"

echo "=== SQUEUE ==="
$SSH_CMD 'export PATH=/opt/slurm/bin:$PATH && squeue -u ubuntu --format="%.10i %.12P %.40j %.8u %.2t %.10M" 2>&1' || echo "squeue failed"

echo ""
echo "=== SNAKEMAKE LOG (last 40 lines) ==="
$SSH_CMD 'tail -40 /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis/.snakemake/log/*.log 2>/dev/null | tail -40' || echo "no log"

echo ""
echo "=== TMUX hiomr_ref_run (last 30 lines) ==="
$SSH_CMD 'tmux capture-pane -t hiomr_ref_run -p -S -30 2>/dev/null' || echo "tmux session not found"

