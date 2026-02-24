#!/bin/bash
echo "=== Searching for sentdhio concordance data for SR3x-ONT1x-8 ==="

# Check expanded run
echo ""
echo "--- Expanded run (agbt_hio_expanded) ---"
EXPANDED="/fsx/analysis_results/ubuntu/agbt_hio_expanded/daylily-omics-analysis"
if [ -f "$EXPANDED/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" ]; then
    grep "SR3x-ONT1x.*sentdhio" "$EXPANDED/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" | grep -v "sentdhiom" | head -20
    echo "---"
    grep "SR3x-ONT1x.*sentdhio" "$EXPANDED/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" | grep -v "sentdhiom" | wc -l
    echo "lines total for sentdhio (CLI)"
else
    echo "No concordance file found"
fi

# Check ref analysis  
echo ""
echo "--- Ref analysis (hiom_ref_chr21_20260220) ---"
REF="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"
if [ -f "$REF/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" ]; then
    grep "SR3x-ONT1x.*sentdhio" "$REF/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" | grep -v "sentdhiom" | head -20
    echo "---"
    grep "SR3x-ONT1x.*sentdhio" "$REF/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" | grep -v "sentdhiom" | wc -l
    echo "lines total for sentdhio (CLI)"
else
    echo "No concordance file found"
fi

# Search all analysis dirs
echo ""
echo "--- All dirs with SR3x-ONT1x sentdhio concordance ---"
find /fsx/analysis_results/ubuntu/ -maxdepth 3 -name "giab_concordance_mqc.tsv" 2>/dev/null | while read f; do
    count=$(grep "SR3x-ONT1x.*sentdhio" "$f" 2>/dev/null | grep -vc "sentdhiom" 2>/dev/null || echo 0)
    if [ "$count" -gt 0 ]; then
        echo "$f: $count lines"
    fi
done
echo "DONE"

