#!/bin/bash
# Restart modular Illumina+ONT test and find Ultima+ONT results for comparison
# Run this ON THE HEADNODE

set -e

echo "=== Restarting modular Illumina+ONT test ==="

# Clean up and restart
tmux kill-session -t test-hybrid-io-mod-5x-run 2>/dev/null || true

cd /fsx/analysis_results/ubuntu/test-hybrid-io-mod-5x/daylily-omics-analysis
git pull origin feat/modular-hybrid-workflows

# Clean up failed state
rm -rf .snakemake/locks/ || true
rm -rf results/day/hg38/R0-HG003-X1-0-D0-PCR-FREE-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/*/tmp/initial.vcf.gz* || true

# Restart with hg38 (Illumina uses standard hg38)
tmux new-session -d -s test-hybrid-io-mod-5x-run
tmux send-keys -t test-hybrid-io-mod-5x-run 'cd /fsx/analysis_results/ubuntu/test-hybrid-io-mod-5x/daylily-omics-analysis && source ~/.bashrc && . dyoainit && source bin/day_activate slurm hg38 && bin/day_run produce_sentdhiom_vcf produce_alignstats produce_snv_concordances -p -k -j 10 -T 1 2>&1 | tee /tmp/test-hybrid-io-mod-5x-run.log' Enter

echo ""
echo "=== Searching for Ultima+ONT results ==="
echo ""

# Find alignstats
echo "--- Monolithic Ultima+ONT alignstats ---"
find /fsx/analysis_results/ubuntu/test-hybrid-uo-5x-dry/daylily-omics-analysis/results/ -name "*.alignstats.done" 2>/dev/null | head -5

echo ""
echo "--- Modular Ultima+ONT alignstats ---"
find /fsx/analysis_results/ubuntu/test-hybrid-uo-mod-5x/daylily-omics-analysis/results/ -name "*.alignstats.done" 2>/dev/null | head -5

echo ""
echo "--- Monolithic Ultima+ONT concordance ---"
find /fsx/analysis_results/ubuntu/test-hybrid-uo-5x-dry/daylily-omics-analysis/results/ -name "concordance*" -type f 2>/dev/null | head -10

echo ""
echo "--- Modular Ultima+ONT concordance ---"
find /fsx/analysis_results/ubuntu/test-hybrid-uo-mod-5x/daylily-omics-analysis/results/ -name "concordance*" -type f 2>/dev/null | head -10

echo ""
echo "=== Test Status ==="
tmux ls 2>/dev/null | grep -E 'hybrid|mod'

