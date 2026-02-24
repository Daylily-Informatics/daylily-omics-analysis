#!/bin/bash
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
BASEDIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$KEY" "$HOST" "
tmux send-keys -t hiomr_ref_run 'bash bin/day_run produce_snv_concordances -p -k -j 2 -T 0 --config snv_callers=\"[\\\"sentdhiomr\\\"]\" aligners=\"[\\\"ont\\\"]\" dedupers=\"[\\\"na\\\"]\"' Enter
sleep 5
tmux capture-pane -t hiomr_ref_run -p -S -30 2>/dev/null
"

