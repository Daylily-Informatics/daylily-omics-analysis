#!/usr/bin/env bash
echo "=== Check cmr-hio-cli for concordance ==="
CLI="/fsx/analysis_results/ubuntu/cmr-hio-cli-20260218-163021/daylily-omics-analysis"

# Check concordance files
echo "--- Concordance files ---"
find "$CLI/results" -name "giab_concordance*" 2>/dev/null
find "$CLI/results" -name "*.concordance*" 2>/dev/null | head -5

echo ""
echo "--- Final VCFs ---"
find "$CLI/results" -name "*.snv.sort.vcf.gz" 2>/dev/null | head -10

echo ""
echo "--- Sample names in VCFs ---"
for f in $(find "$CLI/results" -name "*.snv.sort.vcf.gz" 2>/dev/null | head -5); do
    echo "FILE: $f"
    /home/ubuntu/miniconda3/envs/SAM/bin/bcftools query -l "$f" 2>/dev/null
done

echo ""
echo "--- Also check hiom-fresh dirs ---"
for d in hiom-fresh-20260219-010502 hiom-fresh-20260219-010532 hiom-fresh2-20260218-192859; do
    DIR="/fsx/analysis_results/ubuntu/$d/daylily-omics-analysis"
    echo "DIR: $d"
    find "$DIR/results" -name "giab_concordance*" 2>/dev/null | head -3
    find "$DIR/results" -name "*.snv.sort.vcf.gz" 2>/dev/null | head -3
done

echo ""
echo "=== Also check agbt_hio_expanded for sentdhio ==="
EXPANDED="/fsx/analysis_results/ubuntu/agbt_hio_expanded/daylily-omics-analysis"
find "$EXPANDED/results" -path "*sentdhio*" -name "*.snv.sort.vcf.gz" 2>/dev/null | grep -v "sentdhiom" | head -10

echo "DONE"

