#!/bin/bash
set -euo pipefail
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HN="ubuntu@44.231.76.175"

echo "=== Check if ONT CRAM is pre-aligned (has @SQ headers) ==="
ssh -i "$KEY" "$HN" "samtools view -H /fsx/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ont/HG003_1x.cleaned.cram 2>/dev/null | head -20"

echo ""
echo "=== Check if .crai index exists ==="
ssh -i "$KEY" "$HN" "ls -la /fsx/data/genomic_data/organism_reads/H_sapiens/giab/agbt_2026/ont/HG003_1x.cleaned.cram*"

echo ""
echo "=== Check what alnr wildcard resolves to (ONT_CRAM_ALIGNER column) ==="
echo "From units.tsv: ONT_CRAM_ALIGNER = 'ont'"
echo "So {alnr} = 'ont', and the CRAM path is: {sample}/align/ont/{sample}.cram"

echo ""
echo "=== Check pre_prep_ont_cram output on headnode ==="
STD_DIR="/fsx/analysis_results/ubuntu/hiom_std_chr21_20260220_052436/daylily-omics-analysis"
ssh -i "$KEY" "$HN" "ls -la $STD_DIR/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ/align/ont/ 2>/dev/null | head -10 || echo 'ONT align dir not found'"

echo ""
echo "=== Check pipeline status ==="
ssh -i "$KEY" "$HN" "export PATH=/opt/slurm/bin:\$PATH && squeue -u ubuntu --format='%.10i %.50j %.8T %.10M' | head -20"

