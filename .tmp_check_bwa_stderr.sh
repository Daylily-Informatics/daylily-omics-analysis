#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"

echo "=== Full slurm .err (search for bwa mem messages) ==="
ssh -i "$KEY" "$HN" "ERR=\$(ls -t $STD_DIR/logs/slurm/sentdhiom_sr_align/*.err 2>/dev/null | head -1); grep -n '\\[M::\\|bwa\\|model\\|Failed\\|cannot\\|error\\|No such\\|denied' \$ERR 2>/dev/null || echo 'no matches'"

echo ""
echo "=== BWA test result ==="
ssh -i "$KEY" "$HN" "cat /tmp/bwa_done.txt 2>/dev/null || echo 'still running'; wc -l /tmp/bwa_out.sam 2>/dev/null; cat /tmp/bwa_err.txt 2>/dev/null"

