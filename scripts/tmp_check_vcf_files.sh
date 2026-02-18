#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "=== CLI UG+ONT: ALL files in vcfs/1-24 dir ==="
$SSH $HN "ls -la /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/results/day/hg38_broad/R0-HG003-3x-0-D0-PCR-FREE-UG-ULTIMA/align/ug/na/snv/sentdhuo/vcfs/1-24/ 2>/dev/null"

echo ""
echo "=== CLI UG+ONT: file type of input vcf ==="
$SSH $HN "f=/fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/results/day/hg38_broad/R0-HG003-3x-0-D0-PCR-FREE-UG-ULTIMA/align/ug/na/snv/sentdhuo/vcfs/1-24/R0-HG003-3x-0-D0-PCR-FREE-UG-ULTIMA.ug.na.sentdhuo.1-24.snv.vcf.gz; echo '--- file type ---'; file \$f; echo '--- first 3 lines ---'; zcat \$f 2>/dev/null | head -3; echo '--- sample ---'; bcftools query -l \$f 2>/dev/null"

echo ""
echo "=== CLI UG+ONT: check the sentdhuo_snv log ==="
$SSH $HN "tail -30 /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/results/day/hg38_broad/R0-HG003-3x-0-D0-PCR-FREE-UG-ULTIMA/align/ug/na/snv/sentdhuo/log/vcfs/R0-HG003-3x-0-D0-PCR-FREE-UG-ULTIMA.ug.na.sentdhuo.1-24.snv.log 2>/dev/null"

