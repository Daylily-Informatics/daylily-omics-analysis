#!/bin/bash
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
BASEDIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"
SAMPLE="HIOa-HG003-SR3x-ONT1x-8-D0-PF-ILMN-NOVASEQ"

# Check final HIOMR VCF
HIOMR_VCF="$BASEDIR/results/day/hg38_broad/$SAMPLE/align/ont/na/snv/sentdhiomr/$SAMPLE.ont.na.sentdhiomr.snv.sort.vcf.gz"

# Check CLI reference VCF
CLI_VCF="$BASEDIR/results/day/hg38_broad/$SAMPLE/align/ont/na/snv/sentdhio/$SAMPLE.ont.na.sentdhio.snv.sort.vcf.gz"

ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$KEY" "$HOST" "
echo '=== HIOMR VCF ==='
echo 'File:' && ls -la $HIOMR_VCF 2>&1
echo 'Samples:' && bcftools query -l $HIOMR_VCF 2>&1
echo 'Variant count:' && bcftools view -H $HIOMR_VCF 2>/dev/null | wc -l
echo ''
echo '=== CLI VCF ==='
echo 'File:' && ls -la $CLI_VCF 2>&1
echo 'Samples:' && bcftools query -l $CLI_VCF 2>&1
echo 'Variant count:' && bcftools view -H $CLI_VCF 2>/dev/null | wc -l
echo ''
echo '=== HEADER DIFF (just samples + FORMAT fields) ==='
diff <(bcftools view -h $HIOMR_VCF 2>/dev/null | grep -E '^#CHROM|^##FORMAT') \
     <(bcftools view -h $CLI_VCF 2>/dev/null | grep -E '^#CHROM|^##FORMAT') 2>&1 || echo 'Headers differ'
echo ''
echo '=== ISEC STATS (shared/unique variants) ==='
TMPD=\$(mktemp -d)
bcftools isec -p \$TMPD $HIOMR_VCF $CLI_VCF 2>&1
echo 'HIOMR-only:' && wc -l < \$TMPD/0000.vcf 2>/dev/null
echo 'CLI-only:' && wc -l < \$TMPD/0001.vcf 2>/dev/null
echo 'Shared-HIOMR:' && wc -l < \$TMPD/0002.vcf 2>/dev/null
echo 'Shared-CLI:' && wc -l < \$TMPD/0003.vcf 2>/dev/null
rm -rf \$TMPD
"

