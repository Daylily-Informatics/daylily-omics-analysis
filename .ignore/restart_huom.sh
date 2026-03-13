#!/bin/bash
set -euo pipefail

ANALYSIS_DIR="/fsx/analysis_results/ubuntu/cmr-huom-mod-20260218-163021/daylily-omics-analysis"
cd "$ANALYSIS_DIR"

echo "=== Pulling fix into HUOM-MOD analysis dir ==="
git pull origin feat/modular-hybrid-workflows

echo ""
echo "=== Checking which units need cleanup ==="
UNIT="HUOa-HG003-SR5x-ONT10x-17-D0-PF-UG-ULTIMA"
BASE="results/day/hg38_broad/${UNIT}/align/ug/na/snv/sentdhuom/vcfs/1-24/tmp"

echo "Checking $UNIT..."
echo "stage1_hap.bam:"
ls -la "${BASE}/stage1_hap.bam" 2>/dev/null || echo "  not found"
samtools quickcheck "${BASE}/stage1_hap.bam" 2>&1 && echo "  OK" || echo "  CORRUPT"

echo ""
echo "=== Deleting corrupt stage1 outputs for SR5x-ONT10x-17 ==="
rm -fv "${BASE}/stage1_hap.bam"
rm -fv "${BASE}/stage1_hap.bam.bai"
rm -fv "${BASE}/stage1_hap.bai"
rm -fv "${BASE}/stage1_hap.bed"
rm -fv "${BASE}/stage1_hap.vcf"

echo ""
echo "=== Deleting any stage2+ outputs produced from corrupt stage1 ==="
for f in hybrid_stage2.bed hybrid_stage2_unmap.bam hybrid_stage2_unmap.bam.bai hybrid_stage2_alt.bam hybrid_stage2_alt.bam.bai; do
    rm -fv "${BASE}/${f}" 2>/dev/null || true
done

echo ""
echo "=== Cleanup complete ==="
echo "Ready to restart snakemake"

