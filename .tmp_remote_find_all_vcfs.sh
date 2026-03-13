#!/usr/bin/env bash
echo "=== Find all concordance and VCF data for SR3x-ONT1x-8 ==="

echo "--- All analysis dirs under /fsx/analysis_results/ubuntu/ ---"
ls -d /fsx/analysis_results/ubuntu/*/ 2>/dev/null | head -20

echo ""
echo "--- Search for ANY concordance files ---"
find /fsx/analysis_results/ubuntu/ -maxdepth 4 -name "giab_concordance_mqc.tsv" 2>/dev/null

echo ""
echo "--- Search sentdhiom (standard modular) concordance ---"
find /fsx/analysis_results/ubuntu/ -maxdepth 4 -name "giab_concordance_mqc.tsv" 2>/dev/null | while read f; do
    count=$(grep -c "SR3x-ONT1x.*sentdhiom[^r]" "$f" 2>/dev/null || echo 0)
    if [ "$count" -gt 0 ]; then
        echo "$f: $count lines with sentdhiom (standard)"
    fi
done

echo ""
echo "--- Check hiom-std analysis ---"
STD="/fsx/analysis_results/ubuntu/hiom-std-20260220-143459/daylily-omics-analysis"
if [ -f "$STD/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" ]; then
    echo "Found concordance file"
    awk -F'\t' '$2=="All"' "$STD/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" | head -20
else
    echo "No concordance file at STD"
    # Check what VCFs exist
    find "$STD" -name "*.snv.sort.vcf.gz" 2>/dev/null | head -5
fi

echo ""
echo "--- Check expanded run for any completed sentdhio VCFs ---"
find /fsx/analysis_results/ubuntu/agbt_hio_expanded/daylily-omics-analysis/results/ -path "*SR3x-ONT1x*" -name "*.snv.sort.vcf.gz" 2>/dev/null | head -10
echo "DONE"

