#!/bin/bash
set -euo pipefail
SSH="ssh -i $HOME/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=60 ubuntu@44.231.76.175"
ADIR="/fsx/analysis_results/ubuntu/roche_sbxd_test/daylily-omics-analysis"

echo "=== Pull latest on headnode ==="
$SSH "cd $ADIR && git fetch origin && git reset --hard origin/feat/roche-sbxd-support && echo COMMIT: && git log --oneline -1"

echo "=== Restore full 7-sample manifests ==="
$SSH "cd $ADIR && cp .test_data/data/roche/samples.tsv config/samples.tsv && cp .test_data/data/roche/units.tsv config/units.tsv && wc -l config/samples.tsv config/units.tsv"

echo "=== Clean stale config and locks ==="
$SSH "cd $ADIR && rm -f config/day_profiles/slurm/*.yaml && rm -rf .snakemake/locks/ && tmux kill-session -t roche-all-run 2>/dev/null; echo CLEAN_DONE"

echo "=== Launch produce_deep19_r_vcf in tmux ==="
$SSH "tmux new-session -d -s roche-all-run"
$SSH "tmux send-keys -t roche-all-run 'cd $ADIR && set +euo pipefail && . dyoainit && source bin/day_activate slurm hg38 && set -uo pipefail && bin/day_run produce_deep19_r_vcf -p -k -j 200 --config aligners=\"[\\\"roche\\\"]\" snv_callers=\"[\\\"deep19r\\\"]\" --keep-incomplete --notemp 2>&1 | tee _roche_all_deep19r.log; echo ROCHE_ALL_RETURN_CODE: \$?' Enter"
echo "=== TMUX SESSION roche-all-run LAUNCHED ==="

