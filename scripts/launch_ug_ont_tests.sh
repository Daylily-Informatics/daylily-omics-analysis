#!/bin/bash
# Launch UG+ONT tests with hg38_broad on headnode
set -x

SSH_KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HEADNODE="ubuntu@44.231.76.175"

# Kill any existing sessions first
ssh -i "$SSH_KEY" "$HEADNODE" "tmux kill-session -t test-hybrid-cli-ug-ont-3x 2>/dev/null || true"
ssh -i "$SSH_KEY" "$HEADNODE" "tmux kill-session -t test-hybrid-mod-ug-ont-3x 2>/dev/null || true"

# Remove old directories if they exist
ssh -i "$SSH_KEY" "$HEADNODE" "rm -rf /fsx/analysis_results/ubuntu/test-hybrid-cli-ug-ont-3x /fsx/analysis_results/ubuntu/test-hybrid-mod-ug-ont-3x 2>/dev/null || true"

# Create and launch CLI test
ssh -i "$SSH_KEY" "$HEADNODE" "tmux new-session -d -s test-hybrid-cli-ug-ont-3x"
ssh -i "$SSH_KEY" "$HEADNODE" "tmux send-keys -t test-hybrid-cli-ug-ont-3x 'source ~/.bashrc && day-clone -w ssh -t feat/modular-hybrid-workflows -d test-hybrid-cli-ug-ont-3x && cd /fsx/analysis_results/ubuntu/test-hybrid-cli-ug-ont-3x/daylily-omics-analysis && cp .test_data/data/hybrid/ug_ont/hg003/3x/samples.tsv config/ && cp .test_data/data/hybrid/ug_ont/hg003/3x/units.tsv config/ && source dyoainit --project test-hybrid-cli-ug-ont-3x && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhuo_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1' Enter"

# Create and launch modular test
ssh -i "$SSH_KEY" "$HEADNODE" "tmux new-session -d -s test-hybrid-mod-ug-ont-3x"
ssh -i "$SSH_KEY" "$HEADNODE" "tmux send-keys -t test-hybrid-mod-ug-ont-3x 'source ~/.bashrc && day-clone -w ssh -t feat/modular-hybrid-workflows -d test-hybrid-mod-ug-ont-3x && cd /fsx/analysis_results/ubuntu/test-hybrid-mod-ug-ont-3x/daylily-omics-analysis && cp .test_data/data/hybrid/ug_ont/hg003/3x/samples.tsv config/ && cp .test_data/data/hybrid/ug_ont/hg003/3x/units.tsv config/ && source dyoainit --project test-hybrid-mod-ug-ont-3x && source bin/day_activate slurm hg38_broad && bin/day_run produce_sentdhuom_vcf produce_alignstats produce_snv_concordances -p -j 20 -k -T 1' Enter"

echo "=== Sessions created ==="
ssh -i "$SSH_KEY" "$HEADNODE" "tmux ls | grep ug-ont"

echo "Done. Tests are launching in tmux sessions."

