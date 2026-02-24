#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
REF_DIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

echo "=== REF sr_align log ==="
ssh -i "$KEY" "$HN" "cat $REF_DIR/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiomr/log/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ.ont.na.21.sr_align.log 2>/dev/null || echo 'no rule log'"

echo ""
echo "=== REF slurm .err for sr_align ==="
ssh -i "$KEY" "$HN" "cat \$(ls -t $REF_DIR/logs/slurm/sentdhiomr_sr_align/*.err 2>/dev/null | head -1) 2>/dev/null || echo 'no slurm err'"

echo ""
echo "=== REF slurm .out for sr_align ==="
ssh -i "$KEY" "$HN" "cat \$(ls -t $REF_DIR/logs/slurm/sentdhiomr_sr_align/*.out 2>/dev/null | head -1) 2>/dev/null || echo 'no slurm out'"

