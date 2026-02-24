#!/bin/bash
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"

ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$KEY" "$HOST" "
export PATH=/opt/slurm/bin:\$PATH
echo '=== SQUEUE ==='
squeue -u ubuntu --format='%.10i %.12P %.30j %.8u %.2t %.10M' 2>&1

echo ''
echo '=== TMUX ==='
tmux capture-pane -t hiomr_ref_run -p -S -15 2>/dev/null
"

