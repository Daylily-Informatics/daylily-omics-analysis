#!/usr/bin/env bash
echo "=== Check for sentdhio VCF for SR3x-ONT1x-8 ==="

# Find any sentdhio VCF for this sample
echo "--- Searching for sentdhio VCFs ---"
find /fsx/analysis_results/ubuntu/ -maxdepth 8 -path "*/SR3x-ONT1x*sentdhio*" -name "*.vcf.gz" 2>/dev/null | grep -v "sentdhiom" | head -10

echo ""
echo "--- Checking ref analysis concordance callers ---"
REF="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"
if [ -f "$REF/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" ]; then
    # Show all unique callers
    awk -F'\t' 'NR>1{print $NF}' "$REF/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" | sort -u
    echo "--- callers above ---"
    echo ""
    # Show All variant class rows with giabHC ROI
    echo "--- All giabHC rows ---"
    awk -F'\t' '$2=="All" && $16=="giabHC"' "$REF/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv"
fi

echo ""
echo "--- Check expanded analysis for sentdhio VCF for this sample ---"
find /fsx/analysis_results/ubuntu/agbt_hio_expanded/ -maxdepth 8 -path "*SR3x-ONT1x*" -name "*.snv.sort.vcf.gz" 2>/dev/null | head -10
echo "DONE"

