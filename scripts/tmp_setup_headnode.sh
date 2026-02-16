#!/usr/bin/env bash
set -euo pipefail
ADIR="/fsx/analysis_results/ubuntu/roche_sbxd_test/daylily-omics-analysis"
cd "$ADIR"
echo "===PULL==="
git fetch origin
git reset --hard origin/feat/roche-sbxd-support
git log --oneline -1
echo "===RESTORE_MANIFESTS==="
cp .test_data/data/roche/samples.tsv config/samples.tsv
cp .test_data/data/roche/units.tsv config/units.tsv
wc -l config/samples.tsv config/units.tsv
echo "===CLEAN==="
rm -f config/day_profiles/slurm/*.yaml
rm -rf .snakemake/locks/
echo "===VERIFY_CHRMS==="
grep hg38_deep_chrms config/day_profiles/slurm/templates/rule_config.yaml
echo "===KILL_TMUX==="
tmux kill-session -t conc-run 2>/dev/null || true
tmux kill-session -t deep19r-hg001 2>/dev/null || true
tmux kill-session -t roche-all-run 2>/dev/null || true
echo "===SETUP_DONE==="

