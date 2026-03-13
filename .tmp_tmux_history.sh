#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"

echo "=== STD tmux history (last 50) ==="
ssh -i "$KEY" "$HN" "tmux capture-pane -t hiom_std_chr21 -p -S -50 2>/dev/null"

echo ""
echo "=============================="
echo ""
echo "=== REF tmux history (last 50) ==="
ssh -i "$KEY" "$HN" "tmux capture-pane -t hiom_ref_chr21 -p -S -50 2>/dev/null"

