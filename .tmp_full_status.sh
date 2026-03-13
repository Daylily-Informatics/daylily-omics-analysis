#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"

echo "=== STD log tail ==="
ssh -i "$KEY" "$HN" "tail -30 /tmp/hiom_std_chr21.log 2>/dev/null || echo 'no log'"

echo ""
echo "=== REF log tail ==="
ssh -i "$KEY" "$HN" "tail -30 /tmp/hiom_ref_chr21.log 2>/dev/null || echo 'no log'"

