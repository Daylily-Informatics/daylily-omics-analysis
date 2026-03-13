#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"

echo "=== BWA test done? ==="
ssh -i "$KEY" "$HN" "cat /tmp/bwa_done.txt 2>/dev/null || echo 'not done yet'"

echo ""
echo "=== BWA stderr ==="
ssh -i "$KEY" "$HN" "cat /tmp/bwa_err.txt 2>/dev/null || echo 'no stderr file'"

echo ""
echo "=== BWA output line count ==="
ssh -i "$KEY" "$HN" "wc -l /tmp/bwa_out.sam 2>/dev/null || echo 'no output file'"

echo ""
echo "=== BWA output header + first alignment ==="
ssh -i "$KEY" "$HN" "head -30 /tmp/bwa_out.sam 2>/dev/null || echo 'no output'"

