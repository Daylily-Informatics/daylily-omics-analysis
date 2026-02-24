#!/bin/bash
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
SAMPLE="HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ"

ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$KEY" "$HOST" "
source ~/.bashrc 2>/dev/null
export PATH=/home/ubuntu/miniconda3/envs/SAM/bin:\$PATH

echo '=== Looking for sentdhio CLI VCF for SR3x-ONT1x ==='
find /fsx/analysis_results/ubuntu/ -path '*SR3x-ONT1x*sentdhio*snv.sort.vcf.gz' -not -name '*.tbi' 2>/dev/null

echo ''
echo '=== Looking for sentdhio VCF in hiom_ref dir ==='
find /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/ -path '*sentdhio*' -name '*.vcf.gz' -not -name '*.tbi' 2>/dev/null | head -10

echo ''
echo '=== Check if sentdhio was run in this analysis dir ==='
ls -la /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis/results/day/hg38_broad/$SAMPLE/align/ont/na/snv/ 2>/dev/null

echo ''
echo '=== All analysis dirs ==='
ls -d /fsx/analysis_results/ubuntu/*/ 2>/dev/null | head -15

echo ''
echo '=== Check concordance results if any exist ==='
find /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/ -name '*concordance*' -name '*.tsv' 2>/dev/null | head -10
find /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/ -name 'gatheredall*' 2>/dev/null | head -10
"

