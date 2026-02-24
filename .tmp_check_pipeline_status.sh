#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"

echo "=== STD tmux last 40 lines ==="
ssh -i "$KEY" "$HN" "tmux capture-pane -t hiom_std_chr21 -p -S -40"

echo ""
echo "=== REF tmux last 40 lines ==="
ssh -i "$KEY" "$HN" "tmux capture-pane -t hiom_ref_chr21 -p -S -40"

echo ""
echo "=== STD log tail ==="
ssh -i "$KEY" "$HN" "tail -30 /tmp/hiom_std_chr21.log 2>/dev/null || echo 'no log'"

echo ""
echo "=== REF log tail ==="
ssh -i "$KEY" "$HN" "tail -30 /tmp/hiom_ref_chr21.log 2>/dev/null || echo 'no log'"

