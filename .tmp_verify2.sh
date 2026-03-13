#!/bin/bash
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
BASEDIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"
SAMPLE="HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ"

ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$KEY" "$HOST" "
source ~/.bashrc 2>/dev/null
export PATH=/home/ubuntu/miniconda3/envs/SAM/bin:\$PATH

HIOMR_VCF='$BASEDIR/results/day/hg38_broad/$SAMPLE/align/ont/na/snv/sentdhiomr/$SAMPLE.ont.na.sentdhiomr.snv.sort.vcf.gz'

echo '=== HIOMR VCF ==='
ls -la \$HIOMR_VCF 2>&1
echo 'Samples:' && bcftools query -l \$HIOMR_VCF 2>&1
echo 'Variant count:' && bcftools view -H \$HIOMR_VCF 2>/dev/null | wc -l

echo ''
echo '=== Looking for CLI VCF ==='
find $BASEDIR/results/day/hg38_broad/$SAMPLE/align/ont/na/snv/sentdhio* -name '*.snv.sort.vcf.gz' -not -name '*.tbi' 2>/dev/null | head -5

CLI_VCF=\$(find $BASEDIR/results/day/hg38_broad/$SAMPLE/align/ont/na/snv/sentdhio -name '*.snv.sort.vcf.gz' -not -name '*.tbi' 2>/dev/null | head -1)
if [ -n \"\$CLI_VCF\" ]; then
    echo ''
    echo '=== CLI VCF ==='
    ls -la \$CLI_VCF 2>&1
    echo 'Samples:' && bcftools query -l \$CLI_VCF 2>&1
    echo 'Variant count:' && bcftools view -H \$CLI_VCF 2>/dev/null | wc -l
    echo ''
    echo '=== ISEC ==='
    TMPD=\$(mktemp -d)
    bcftools isec -p \$TMPD \$HIOMR_VCF \$CLI_VCF 2>&1
    echo 'HIOMR-only:' && grep -c -v '^#' \$TMPD/0000.vcf 2>/dev/null
    echo 'CLI-only:' && grep -c -v '^#' \$TMPD/0001.vcf 2>/dev/null
    echo 'Shared-HIOMR:' && grep -c -v '^#' \$TMPD/0002.vcf 2>/dev/null
    echo 'Shared-CLI:' && grep -c -v '^#' \$TMPD/0003.vcf 2>/dev/null
    rm -rf \$TMPD
else
    echo 'CLI VCF not found in this analysis dir'
    echo 'Checking other dirs...'
    find /fsx/analysis_results/ubuntu/ -path '*/sentdhio/*.snv.sort.vcf.gz' -not -name '*.tbi' 2>/dev/null | head -5
fi
"

