#!/bin/bash
set -euo pipefail
SSH="ssh -i /Users/jmajor/.ssh/lsmc-omics-us-west-2.pem -o StrictHostKeyChecking=no -o ConnectTimeout=30"
HN=ubuntu@44.231.76.175

echo "============================================"
echo "=== CLI UG+ONT: sort_index_chunk_vcf ERR ==="
echo "============================================"
$SSH $HN "find /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/logs/slurm -name '*sort_index*err*' 2>/dev/null | head -3; for f in \$(find /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/logs/slurm -name '*sort_index*err*' 2>/dev/null | head -1); do echo '--- '\$f' ---'; tail -60 \$f; done"

echo ""
echo "=== CLI UG+ONT: sort_index_chunk_vcf LOG ==="
$SSH $HN "find /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/results -name '*sort_index*log*' 2>/dev/null | head -3; for f in \$(find /fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis/results -name '*sort_index*log*' 2>/dev/null | head -1); do echo '--- '\$f' ---'; tail -60 \$f; done"

echo ""
echo "=== CLI UG+ONT: snakemake log tail ==="
$SSH $HN "base=/fsx/analysis_results/ubuntu/t3-hybrid-cli-ug-ont-3x/daylily-omics-analysis; log=\$(ls -t \$base/.snakemake/log/*.snakemake.log 2>/dev/null | head -1); tail -40 \$log 2>/dev/null"

echo ""
echo "============================================"
echo "=== MOD ILMN+ONT: transfer ERR (old fail) ==="
echo "============================================"
$SSH $HN "base=/fsx/analysis_results/ubuntu/t4-hybrid-mod-ilmn-ont-3x/daylily-omics-analysis/results/day/hg38/R0-HG003-3x-0-D0-PCR-FREE-ILMN-NOVASEQ/align/ont/na/snv/sentdhiom/vcfs/1-24/tmp; echo '=== VCF FILES ==='; ls -la \$base/*.vcf.gz 2>/dev/null; echo; echo '=== PASS1 SAMPLES ==='; bcftools query -l \$base/initial.vcf.gz 2>/dev/null"

