#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"

echo "=== Latest sr_align .err file (last 40 lines) ==="
ssh -i "$KEY" "$HN" "ERR=\$(ls -t $STD_DIR/logs/slurm/sentdhiom_sr_align/*.err 2>/dev/null | head -1); tail -40 \$ERR 2>/dev/null || echo 'no err file'"

echo ""
echo "=== BWA test status ==="
ssh -i "$KEY" "$HN" "cat /tmp/bwa_done.txt 2>/dev/null || echo 'still running'; wc -l /tmp/bwa_out.sam 2>/dev/null; tail -5 /tmp/bwa_err.txt 2>/dev/null"

