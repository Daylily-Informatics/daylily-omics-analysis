#!/usr/bin/env bash
# Launch 3 dry-run concordance jobs in tmux sessions on headnode
set -euo pipefail

BASE="/fsx/analysis_results/ubuntu"

# Kill old sessions if they exist
for s in dryrun-dhipmr dryrun-dhuomr dryrun-dhupmr; do
    tmux kill-session -t "$s" 2>/dev/null || true
done

# sentdhipmr dry-run
tmux new-session -d -s dryrun-dhipmr
tmux send-keys -t dryrun-dhipmr "cd $BASE/test-sentdhipmr-3x/daylily-omics-analysis && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_snv_concordances -n -p -k -j 20 -T 1 --config aligners=\"['sentmm2']\" snv_callers=\"['sentdhipmr']\" 2>&1 | tee /tmp/dryrun_dhipmr.log" Enter

# sentdhuomr dry-run
tmux new-session -d -s dryrun-dhuomr
tmux send-keys -t dryrun-dhuomr "cd $BASE/test-sentdhuomr-3x/daylily-omics-analysis && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_snv_concordances -n -p -k -j 20 -T 1 --config aligners=\"['ug']\" snv_callers=\"['sentdhuomr']\" 2>&1 | tee /tmp/dryrun_dhuomr.log" Enter

# sentdhupmr dry-run
tmux new-session -d -s dryrun-dhupmr
tmux send-keys -t dryrun-dhupmr "cd $BASE/test-sentdhupmr-3x/daylily-omics-analysis && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_snv_concordances -n -p -k -j 20 -T 1 --config aligners=\"['ug']\" snv_callers=\"['sentdhupmr']\" 2>&1 | tee /tmp/dryrun_dhupmr.log" Enter

echo "Launched 3 dry-run tmux sessions: dryrun-dhipmr, dryrun-dhuomr, dryrun-dhupmr"
echo "Check output: tail /tmp/dryrun_dhipmr.log /tmp/dryrun_dhuomr.log /tmp/dryrun_dhupmr.log"

