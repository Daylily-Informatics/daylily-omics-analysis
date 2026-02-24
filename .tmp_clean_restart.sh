#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
REF_DIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

echo "=== Cancel any running slurm jobs ==="
ssh -i "$KEY" "$HN" "export PATH=/opt/slurm/bin:\$PATH && squeue -u ubuntu --format='%i' --noheader 2>/dev/null | xargs -r scancel 2>/dev/null; echo 'done'"

echo ""
echo "=== Clean STD stale outputs ==="
ssh -i "$KEY" "$HN" "cd $STD_DIR && rm -rf .snakemake/incomplete .snakemake/locks results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/ 2>/dev/null; echo 'STD cleaned'"

echo ""
echo "=== Clean REF stale outputs ==="
ssh -i "$KEY" "$HN" "cd $REF_DIR && rm -rf .snakemake/incomplete .snakemake/locks results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiomr/vcfs/ 2>/dev/null; echo 'REF cleaned'"

echo ""
echo "=== Restart STD pipeline ==="
ssh -i "$KEY" "$HN" "tmux send-keys -t hiom_std_chr21 'cd $STD_DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiom_vcf -p -k -j 2 -T 1 2>&1 | tee /tmp/hiom_std_chr21.log' Enter"

echo ""
echo "=== Restart REF pipeline ==="
ssh -i "$KEY" "$HN" "tmux send-keys -t hiom_ref_chr21 'cd $REF_DIR && source dyoainit && source bin/day_activate slurm hg38_broad && bash bin/day_run produce_sentdhiomr_vcf -p -k -j 2 -T 1 2>&1 | tee /tmp/hiom_ref_chr21.log' Enter"

echo ""
echo "Pipelines restarting..."

