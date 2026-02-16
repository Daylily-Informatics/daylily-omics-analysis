#!/bin/bash
set -euo pipefail
SSH="ssh -i $HOME/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=60 ubuntu@44.231.76.175"
ADIR="/fsx/analysis_results/ubuntu/roche_sbxd_test/daylily-omics-analysis"

echo "=== Setting up headnode ==="
$SSH "cd $ADIR && git fetch origin && git reset --hard origin/feat/roche-sbxd-support && echo COMMIT: && git log --oneline -1"
echo "=== Restoring manifests ==="
$SSH "cd $ADIR && cp .test_data/data/roche/samples.tsv config/samples.tsv && cp .test_data/data/roche/units.tsv config/units.tsv && wc -l config/samples.tsv config/units.tsv"
echo "=== Cleaning ==="
$SSH "cd $ADIR && rm -f config/day_profiles/slurm/*.yaml && rm -rf .snakemake/locks/ && tmux kill-session -t conc-run 2>/dev/null; tmux kill-session -t deep19r-hg001 2>/dev/null; tmux kill-session -t roche-all-run 2>/dev/null; echo CLEAN_DONE"
echo "=== Verifying ==="
$SSH "cd $ADIR && grep hg38_deep_chrms config/day_profiles/slurm/templates/rule_config.yaml | head -5"
echo "=== SETUP COMPLETE ==="

