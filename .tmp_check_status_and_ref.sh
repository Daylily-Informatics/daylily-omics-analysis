#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
REF_DIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

echo "=== Slurm queue ==="
ssh -i "$KEY" "$HN" "export PATH=/opt/slurm/bin:\$PATH && squeue -u ubuntu --format='%.10i %.50j %.8T %.10M' | head -20"

echo ""
echo "=== STD sr_align log tail ==="
ssh -i "$KEY" "$HN" "tail -5 $STD_DIR/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/log/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ.ont.na.21.sr_align.log 2>/dev/null || echo 'no log yet'"

echo ""
echo "=== REF: check if the bwa mem in slurm job .err has seqkit ==="
ssh -i "$KEY" "$HN" "grep -c 'seqkit' \$(ls -t $REF_DIR/logs/slurm/sentdhiomr_sr_align/*.err 2>/dev/null | head -1) 2>/dev/null || echo '0'"

echo ""
echo "=== REF: show bwa mem line from slurm .err ==="
ssh -i "$KEY" "$HN" "grep -A2 'sentieon bwa mem' \$(ls -t $REF_DIR/logs/slurm/sentdhiomr_sr_align/*.err 2>/dev/null | head -1) 2>/dev/null | head -10"

echo ""
echo "=== REF: verify code has backslash fix ==="
ssh -i "$KEY" "$HN" "sed -n '145,148p' $REF_DIR/workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk"

