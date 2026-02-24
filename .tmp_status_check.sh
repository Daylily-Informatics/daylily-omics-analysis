#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"

echo "=== $(date) ==="
echo ""
echo "=== Slurm queue ==="
ssh -i "$KEY" "$HN" "export PATH=/opt/slurm/bin:\$PATH && squeue -u ubuntu --format='%.10i %.40j %.8T %.10M' 2>/dev/null"

echo ""
echo "=== STD tmux (last 15 lines) ==="
ssh -i "$KEY" "$HN" "tmux capture-pane -t hiom_std_chr21 -p 2>/dev/null | tail -15"

echo ""
echo "=== REF tmux (last 15 lines) ==="
ssh -i "$KEY" "$HN" "tmux capture-pane -t hiom_ref_chr21 -p 2>/dev/null | tail -15"

