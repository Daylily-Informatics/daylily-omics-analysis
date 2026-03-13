#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"

echo "=== Check new job script for seqkit subseq ==="
ssh -i "$KEY" "$HN" "grep -r 'seqkit subseq' $STD_DIR/.snakemake/tmp.*/snakejob.sentdhiom_sr_align.*.sh 2>/dev/null || echo 'NO seqkit subseq found in job scripts (GOOD)'"

echo ""
echo "=== Check new job script for igzip (should be there without seqkit pipe) ==="
ssh -i "$KEY" "$HN" "grep -r 'igzip' $STD_DIR/.snakemake/tmp.*/snakejob.sentdhiom_sr_align.*.sh 2>/dev/null | head -5 || echo 'no igzip found'"

echo ""
echo "=== Show the bwa mem line from the new job script ==="
ssh -i "$KEY" "$HN" "grep -A5 'sentieon bwa mem' $STD_DIR/.snakemake/tmp.*/snakejob.sentdhiom_sr_align.*.sh 2>/dev/null | head -20 || echo 'no match'"

