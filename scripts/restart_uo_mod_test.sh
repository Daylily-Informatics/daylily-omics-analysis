#!/bin/bash
# Restart modular Ultima+ONT test after hybrid_select fix
set -euo pipefail

# Pull latest changes
cd /fsx/analysis_results/ubuntu/test-hybrid-uo-mod-5x/daylily-omics-analysis
git pull origin feat/modular-hybrid-workflows

# Kill existing tmux session if it exists
tmux kill-session -t test-hybrid-uo-mod-5x-run 2>/dev/null || true

# Clean up any failed outputs  
rm -f results/day/hg38_broad/R0-HG003-X1-0-D0-PCR-FREE-UG-ULTIMA/align/ont/na/snv/sentdhuom/vcfs/1-24/tmp/selected.bed 2>/dev/null || true

# Create new tmux session and run the test
tmux new-session -d -s test-hybrid-uo-mod-5x-run
tmux send-keys -t test-hybrid-uo-mod-5x-run 'cd /fsx/analysis_results/ubuntu/test-hybrid-uo-mod-5x/daylily-omics-analysis && source ~/.bashrc && . dyoainit --project da-us-west-2d-agbt-12t-usw2d && dy-a slurm hg38_broad && dy-r produce_sentdhuom_vcf -p -j 20 -k -T 2 2>&1 | tee /tmp/test-hybrid-uo-mod-5x-run.log' Enter

echo "Restarted modular Ultima+ONT test"
tmux ls | grep uo-mod || true

