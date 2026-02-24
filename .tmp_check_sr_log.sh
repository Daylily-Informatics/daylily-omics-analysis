#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"

echo "=== sr_align LOG file (not slurm .err) ==="
ssh -i "$KEY" "$HN" "cat $STD_DIR/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/log/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ.ont.na.21.sr_align.log 2>/dev/null || echo 'log file not found'"

