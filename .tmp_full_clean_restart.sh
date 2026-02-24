#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
REF_DIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

echo "=== Full clean: wipe .snakemake and stale outputs ==="
ssh -i "$KEY" "$HN" "cd $STD_DIR && rm -rf .snakemake && rm -rf results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/ && echo STD_CLEAN_OK"
ssh -i "$KEY" "$HN" "cd $REF_DIR && rm -rf .snakemake && rm -rf results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiomr/ && echo REF_CLEAN_OK"

echo ""
echo "=== Restart STD pipeline ==="
ssh -i "$KEY" "$HN" "tmux send-keys -t hiom_std_chr21 'cd $STD_DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiom_vcf -p -k -j 2 -T 1 2>&1 | tee /tmp/hiom_std_chr21.log' Enter"

sleep 2

echo "=== Restart REF pipeline ==="
ssh -i "$KEY" "$HN" "tmux send-keys -t hiom_ref_chr21 'cd $REF_DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiomr_vcf -p -k -j 2 -T 1 2>&1 | tee /tmp/hiom_ref_chr21.log' Enter"

echo ""
echo "=== Both pipelines restarted with full clean ==="

