#!/bin/bash
set -e

# Copy manifests for CLI test
echo "=== Setting up test-hybrid-cli-ug-ont-3x ==="
cd /fsx/analysis_results/ubuntu/test-hybrid-cli-ug-ont-3x/daylily-omics-analysis
cp .test_data/data/hybrid/ug_ont/hg003/3x/samples.tsv config/
cp .test_data/data/hybrid/ug_ont/hg003/3x/units.tsv config/
echo "Manifests copied for CLI test"

# Copy manifests for MOD test
echo ""
echo "=== Setting up test-hybrid-mod-ug-ont-3x ==="
cd /fsx/analysis_results/ubuntu/test-hybrid-mod-ug-ont-3x/daylily-omics-analysis
cp .test_data/data/hybrid/ug_ont/hg003/3x/samples.tsv config/
cp .test_data/data/hybrid/ug_ont/hg003/3x/units.tsv config/
echo "Manifests copied for MOD test"

# Start CLI test in tmux with hg38_broad
echo ""
echo "=== Starting test-hybrid-cli-ug-ont-3x with hg38_broad ==="
tmux new-session -d -s test-hybrid-cli-ug-ont-3x
tmux send-keys -t test-hybrid-cli-ug-ont-3x 'cd /fsx/analysis_results/ubuntu/test-hybrid-cli-ug-ont-3x/daylily-omics-analysis && source dyoainit --project test-hybrid-cli-ug-ont-3x && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 2>&1 | tee /tmp/test-hybrid-cli-ug-ont-3x.log' Enter
echo "CLI test started"

# Start MOD test in tmux with hg38_broad
echo ""
echo "=== Starting test-hybrid-mod-ug-ont-3x with hg38_broad ==="
tmux new-session -d -s test-hybrid-mod-ug-ont-3x
tmux send-keys -t test-hybrid-mod-ug-ont-3x 'cd /fsx/analysis_results/ubuntu/test-hybrid-mod-ug-ont-3x/daylily-omics-analysis && source dyoainit --project test-hybrid-mod-ug-ont-3x && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhuom_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1 2>&1 | tee /tmp/test-hybrid-mod-ug-ont-3x.log' Enter
echo "MOD test started"

echo ""
echo "=== Both tests started with hg38_broad ==="
tmux ls | grep "ug-ont-3x"

