#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "=== CLI UG+ONT: check sort log file ==="
$SSH $HN "base=/fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/results/day/hg38_broad/R0-HG003-3x-0-D0-PCR-FREE-UG-ULTIMA/align/ug/na/snv/sentdhuo/vcfs/1-24/log; ls -la \$base/ 2>/dev/null; echo; cat \$base/R0-HG003-3x-0-D0-PCR-FREE-UG-ULTIMA.ug.na.sentdhuo.1-24.snv.sort.vcf.gz.log 2>/dev/null | tail -20"

echo ""
echo "=== CLI UG+ONT: check input VCF exists ==="
$SSH $HN "ls -la /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/results/day/hg38_broad/R0-HG003-3x-0-D0-PCR-FREE-UG-ULTIMA/align/ug/na/snv/sentdhuo/vcfs/1-24/*.vcf* 2>/dev/null"

echo ""
echo "=== CLI UG+ONT: check if input VCF is valid ==="
$SSH $HN "vcf=/fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/results/day/hg38_broad/R0-HG003-3x-0-D0-PCR-FREE-UG-ULTIMA/align/ug/na/snv/sentdhuo/vcfs/1-24/R0-HG003-3x-0-D0-PCR-FREE-UG-ULTIMA.ug.na.sentdhuo.1-24.snv.vcf.gz; file \$vcf 2>/dev/null; echo; bcftools view -h \$vcf 2>/dev/null | tail -3; echo; bcftools query -l \$vcf 2>/dev/null"

echo ""
echo "=== MOD ILMN+ONT: check pass1 VCF header ==="
$SSH $HN "base=/fsx/analysis_results/ubuntu/t4-hybrid-mod-ilmn-ont-3x/daylily-omics-analysis/results/day/hg38/R0-HG003-3x-0-D0-PCR-FREE-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp; bcftools view -h \$base/initial.vcf.gz 2>&1 | tail -5; echo; echo '=== SAMPLES ==='; bcftools query -l \$base/initial.vcf.gz 2>&1"

