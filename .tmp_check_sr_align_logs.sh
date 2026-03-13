#!/bin/bash
# Check sr_align failure logs for both standard and refactored pipelines
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
STD_BASE="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
REF_BASE="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"
SAMPLE="HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ"

echo "========================================="
echo "=== STANDARD: sr_align slurm err files ==="
echo "========================================="
ssh -i "$PEM" "$HOST" "ls -lt ${STD_BASE}/logs/slurm/sentdhiom_sr_align/"

echo ""
echo "========================================="
echo "=== STANDARD: latest .err bwa mem lines ==="
echo "========================================="
ssh -i "$PEM" "$HOST" "LATEST=\$(ls -t ${STD_BASE}/logs/slurm/sentdhiom_sr_align/*.err 2>/dev/null | head -1) && echo File: \$LATEST && grep -n 'sentieon bwa mem' \$LATEST"

echo ""
echo "========================================="
echo "=== STANDARD: rule log ==="
echo "========================================="
ssh -i "$PEM" "$HOST" "cat ${STD_BASE}/results/day/hg38_broad/${SAMPLE}/align/ont/na/snv/sentdhiom/log/${SAMPLE}.ont.na.21.sr_align.log"

echo ""
echo "========================================="
echo "=== STANDARD: input fastq files ==="
echo "========================================="
ssh -i "$PEM" "$HOST" "ls -lh ${STD_BASE}/results/day/hg38_broad/${SAMPLE}/${SAMPLE}.R1.fastq.gz ${STD_BASE}/results/day/hg38_broad/${SAMPLE}/${SAMPLE}.R2.fastq.gz 2>&1"

echo ""
echo "========================================="
echo "=== REFACTORED: rule log ==="
echo "========================================="
ssh -i "$PEM" "$HOST" "cat ${REF_BASE}/results/day/hg38_broad/${SAMPLE}/align/ont/na/snv/sentdhiomr/log/${SAMPLE}.ont.na.21.sr_align.log 2>&1"

echo ""
echo "=== DONE ==="

