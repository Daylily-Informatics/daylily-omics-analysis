#!/bin/bash
# Restart only Ultima+ONT tests after gatk config fix
# Run this ON THE HEADNODE

set -e

echo "=== Restarting Ultima+ONT tests ==="

tmux kill-session -t test-hybrid-uo-5x-run 2>/dev/null || true
tmux kill-session -t test-hybrid-uo-mod-5x-run 2>/dev/null || true

# Monolithic
echo "Monolithic..."
cd /fsx/analysis_results/ubuntu/test-hybrid-uo-5x-dry/daylily-omics-analysis
git pull origin feat/modular-hybrid-workflows
rm -rf .snakemake/locks/ || true
tmux new-session -d -s test-hybrid-uo-5x-run
tmux send-keys -t test-hybrid-uo-5x-run 'cd /fsx/analysis_results/ubuntu/test-hybrid-uo-5x-dry/daylily-omics-analysis && source ~/.bashrc && . dyoainit && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -k -j 10 -T 1 2>&1 | tee /tmp/test-hybrid-uo-5x-run.log' Enter

# Modular
echo "Modular..."
cd /fsx/analysis_results/ubuntu/test-hybrid-uo-mod-5x/daylily-omics-analysis
git pull origin feat/modular-hybrid-workflows
rm -rf .snakemake/locks/ || true
tmux new-session -d -s test-hybrid-uo-mod-5x-run
tmux send-keys -t test-hybrid-uo-mod-5x-run 'cd /fsx/analysis_results/ubuntu/test-hybrid-uo-mod-5x/daylily-omics-analysis && source ~/.bashrc && . dyoainit && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhuom_vcf produce_alignstats produce_snv_concordances -p -k -j 10 -T 1 2>&1 | tee /tmp/test-hybrid-uo-mod-5x-run.log' Enter

echo ""
echo "Done. Sessions:"
tmux ls | grep uo

