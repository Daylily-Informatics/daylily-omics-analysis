#!/bin/bash
# Restart all hybrid tests after roche config fix
# Run this ON THE HEADNODE

set -e

echo "=== Restarting all hybrid tests after roche config fix ==="

# Kill existing sessions
echo "Killing old sessions..."
tmux kill-session -t test-hybrid-uo-5x-run 2>/dev/null || true
tmux kill-session -t test-hybrid-uo-mod-5x-run 2>/dev/null || true
tmux kill-session -t test-hybrid-io-mod-5x-run 2>/dev/null || true

# Monolithic Ultima+ONT
echo ""
echo "=== Monolithic Ultima+ONT (hg38_broad) ==="
cd /fsx/analysis_results/ubuntu/test-hybrid-uo-5x-dry/daylily-omics-analysis
git pull origin feat/modular-hybrid-workflows
rm -rf .snakemake/locks/ || true
tmux new-session -d -s test-hybrid-uo-5x-run
tmux send-keys -t test-hybrid-uo-5x-run 'cd /fsx/analysis_results/ubuntu/test-hybrid-uo-5x-dry/daylily-omics-analysis && source ~/.bashrc && . dyoainit && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -k -j 10 -T 1 2>&1 | tee /tmp/test-hybrid-uo-5x-run.log' Enter

# Modular Ultima+ONT
echo ""
echo "=== Modular Ultima+ONT (hg38_broad) ==="
cd /fsx/analysis_results/ubuntu/test-hybrid-uo-mod-5x/daylily-omics-analysis
git pull origin feat/modular-hybrid-workflows
rm -rf .snakemake/locks/ || true
tmux new-session -d -s test-hybrid-uo-mod-5x-run
tmux send-keys -t test-hybrid-uo-mod-5x-run 'cd /fsx/analysis_results/ubuntu/test-hybrid-uo-mod-5x/daylily-omics-analysis && source ~/.bashrc && . dyoainit && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhuom_vcf produce_alignstats produce_snv_concordances -p -k -j 10 -T 1 2>&1 | tee /tmp/test-hybrid-uo-mod-5x-run.log' Enter

# Modular Illumina+ONT
echo ""
echo "=== Modular Illumina+ONT (hg38) ==="
cd /fsx/analysis_results/ubuntu/test-hybrid-io-mod-5x/daylily-omics-analysis
git pull origin feat/modular-hybrid-workflows
rm -rf .snakemake/locks/ || true
tmux new-session -d -s test-hybrid-io-mod-5x-run
tmux send-keys -t test-hybrid-io-mod-5x-run 'cd /fsx/analysis_results/ubuntu/test-hybrid-io-mod-5x/daylily-omics-analysis && source ~/.bashrc && . dyoainit && source bin/day_activate slurm hg38 && bin/day_run produce_sentdhiom_vcf produce_alignstats produce_snv_concordances -p -k -j 10 -T 1 2>&1 | tee /tmp/test-hybrid-io-mod-5x-run.log' Enter

echo ""
echo "=== All hybrid tests restarted ==="
tmux ls | grep -E 'hybrid'

