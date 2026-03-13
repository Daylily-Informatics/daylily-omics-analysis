#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
REF_DIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

echo "=== Slurm queue ==="
ssh -i "$KEY" "$HN" "export PATH=/opt/slurm/bin:\$PATH && squeue -u ubuntu --format='%.10i %.50j %.8T %.10M' | head -20"

echo ""
echo "=== STD: check new job script for seqkit ==="
ssh -i "$KEY" "$HN" "grep 'seqkit' $STD_DIR/.snakemake/tmp.*/snakejob.sentdhiom_sr_align.*.sh 2>/dev/null && echo 'BAD: seqkit still present' || echo 'GOOD: no seqkit in job script'"

echo ""
echo "=== STD: check trim_head param in new job script ==="
ssh -i "$KEY" "$HN" "grep -o '\"trim_head\": \"[^\"]*\"' $STD_DIR/.snakemake/tmp.*/snakejob.sentdhiom_sr_align.*.sh 2>/dev/null || echo 'no job script yet'"

echo ""
echo "=== REF: check new job script for seqkit ==="
ssh -i "$KEY" "$HN" "grep 'seqkit' $REF_DIR/.snakemake/tmp.*/snakejob.sentdhiomr_sr_align.*.sh 2>/dev/null && echo 'BAD: seqkit still present' || echo 'GOOD: no seqkit in job script'"

echo ""
echo "=== REF: check trim_head param in new job script ==="
ssh -i "$KEY" "$HN" "grep -o '\"trim_head\": \"[^\"]*\"' $REF_DIR/.snakemake/tmp.*/snakejob.sentdhiomr_sr_align.*.sh 2>/dev/null || echo 'no job script yet'"

echo ""
echo "=== STD tmux last 15 lines ==="
ssh -i "$KEY" "$HN" "tmux capture-pane -t hiom_std_chr21 -p -S -15"

echo ""
echo "=== REF tmux last 15 lines ==="
ssh -i "$KEY" "$HN" "tmux capture-pane -t hiom_ref_chr21 -p -S -15"

