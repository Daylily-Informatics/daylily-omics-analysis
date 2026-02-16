#!/bin/bash
# Restart hybrid Ultima+ONT test with hg38_broad reference fix
# Run this ON THE HEADNODE

set -e

cd /fsx/analysis_results/ubuntu/test-hybrid-uo-5x-dry/daylily-omics-analysis

echo "=== Pulling latest code with fix ==="
git pull origin feat/modular-hybrid-workflows

echo "=== Removing stale preprocessed CRAMs ==="
rm -rf results/day/hg38/R0-HG003-X1-0-D0-PCR-FREE-UG-ULTIMA/align/ug/
rm -rf results/day/hg38/R0-HG003-X1-0-D0-PCR-FREE-UG-ULTIMA/align/ont/
rm -rf .snakemake/locks/

echo "=== Restarting tmux session ==="
tmux kill-session -t test-hybrid-uo-5x-run 2>/dev/null || true
tmux new-session -d -s test-hybrid-uo-5x-run

tmux send-keys -t test-hybrid-uo-5x-run 'cd /fsx/analysis_results/ubuntu/test-hybrid-uo-5x-dry/daylily-omics-analysis && source ~/.bashrc && . dyoainit && source bin/day_activate slurm hg38 && bin/day_run produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -k -j 10 -T 1 2>&1 | tee /tmp/test-hybrid-uo-5x-run.log' Enter

echo "=== Done - test restarted ==="
echo "Monitor with: tmux attach -t test-hybrid-uo-5x-run"

