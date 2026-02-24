#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"

sleep 8

echo "=== STD tmux last 30 lines ==="
ssh -i "$KEY" "$HN" "tmux capture-pane -t hiom_std_chr21 -p -S -30"

echo ""
echo "=== REF tmux last 30 lines ==="
ssh -i "$KEY" "$HN" "tmux capture-pane -t hiom_ref_chr21 -p -S -30"

echo ""
echo "=== Slurm queue ==="
ssh -i "$KEY" "$HN" "export PATH=/opt/slurm/bin:\$PATH && squeue -u ubuntu --format='%.10i %.50j %.8T %.10M' | head -20"

