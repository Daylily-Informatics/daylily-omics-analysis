#!/bin/bash
set -euo pipefail
SSH="ssh -i $HOME/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=60 ubuntu@44.231.76.175"
ADIR="/fsx/analysis_results/ubuntu/roche_sbxd_test/daylily-omics-analysis"

echo "=== Creating tmux session roche-all-run ==="
$SSH "tmux kill-session -t roche-all-run 2>/dev/null || true"
$SSH "tmux new-session -d -s roche-all-run"
$SSH "tmux send-keys -t roche-all-run 'cd $ADIR && set +euo pipefail && . dyoainit && source bin/day_activate slurm hg38 && set -uo pipefail && bin/day_run produce_deep19_r_vcf produce_alignstats -p -k -j 200 --config aligners=\"[\\\"roche\\\"]\" snv_callers=\"[\\\"deep19r\\\"]\" --keep-incomplete --notemp 2>&1 | tee _roche_all_7samples.log; echo ROCHE_ALL_RETURN_CODE: \$?' Enter"
echo "=== TMUX SESSION LAUNCHED ==="
echo "Monitor with: ssh ... 'tmux capture-pane -t roche-all-run -p -S -50'"

