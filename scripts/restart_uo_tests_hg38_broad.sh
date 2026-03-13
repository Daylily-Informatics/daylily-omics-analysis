#!/bin/bash
# Restart Ultima+ONT tests using hg38_broad genome build
# This is the CORRECT solution - use hg38_broad instead of hardcoding reference paths
# Run this ON THE HEADNODE

set -e

echo "=== Restarting Ultima+ONT tests with hg38_broad ==="

# Kill existing sessions
tmux kill-session -t test-hybrid-uo-5x-run 2>/dev/null || true
tmux kill-session -t test-hybrid-uo-mod-5x-run 2>/dev/null || true

# Clean up stale files and restart monolithic hybrid Ultima+ONT
echo "=== Restarting monolithic hybrid Ultima+ONT (sentdhuo) with hg38_broad ==="
cd /fsx/analysis_results/ubuntu/test-hybrid-uo-5x-dry/daylily-omics-analysis
git pull origin feat/modular-hybrid-workflows
rm -rf results/day/hg38/R0-HG003-X1-0-D0-PCR-FREE-UG-ULTIMA/align/ || true
rm -rf .snakemake/locks/ || true

tmux new-session -d -s test-hybrid-uo-5x-run
tmux send-keys -t test-hybrid-uo-5x-run 'cd /fsx/analysis_results/ubuntu/test-hybrid-uo-5x-dry/daylily-omics-analysis && source ~/.bashrc && . dyoainit && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -k -j 10 -T 1 2>&1 | tee /tmp/test-hybrid-uo-5x-run.log' Enter

# Clean up and restart modular hybrid Ultima+ONT
echo "=== Restarting modular hybrid Ultima+ONT (sentdhuom) with hg38_broad ==="
cd /fsx/analysis_results/ubuntu/test-hybrid-uo-mod-5x/daylily-omics-analysis
git pull origin feat/modular-hybrid-workflows
rm -rf results/day/hg38/R0-HG003-X1-0-D0-PCR-FREE-UG-ULTIMA/align/ || true
rm -rf results/day/hg38_broad/ || true
rm -rf .snakemake/locks/ || true

tmux new-session -d -s test-hybrid-uo-mod-5x-run
tmux send-keys -t test-hybrid-uo-mod-5x-run 'cd /fsx/analysis_results/ubuntu/test-hybrid-uo-mod-5x/daylily-omics-analysis && source ~/.bashrc && . dyoainit && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhuom_vcf produce_alignstats produce_snv_concordances -p -k -j 10 -T 1 2>&1 | tee /tmp/test-hybrid-uo-mod-5x-run.log' Enter

echo ""
echo "=== Tests restarted with hg38_broad ==="
tmux ls | grep uo
echo ""
echo "Monitor with:"
echo "  tmux attach -t test-hybrid-uo-5x-run"
echo "  tmux attach -t test-hybrid-uo-mod-5x-run"

