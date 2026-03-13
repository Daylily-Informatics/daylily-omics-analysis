#!/bin/bash
# Search for CLI (sentdhio) concordance data for the SR3x-ONT1x-8 sample on the headnode
ssh -i ~/.ssh/lsmc-omics-us-west-2.pem ubuntu@44.231.76.175 bash -c '
echo "=== Searching for sentdhio concordance data for SR3x-ONT1x-8 ==="

# Check expanded run
echo ""
echo "--- Expanded run (agbt_hio_expanded) ---"
EXPANDED="/fsx/analysis_results/ubuntu/agbt_hio_expanded/daylily-omics-analysis"
if [ -f "$EXPANDED/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" ]; then
    grep "SR3x-ONT1x.*sentdhio[^m]" "$EXPANDED/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" | head -20
    echo "..."
    grep "SR3x-ONT1x.*sentdhio[^m]" "$EXPANDED/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" | wc -l
    echo "lines total"
else
    echo "No concordance file found at expanded run"
fi

# Check ref analysis
echo ""
echo "--- Ref analysis (hiom_ref_chr21_20260220) ---"
REF="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"
if [ -f "$REF/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" ]; then
    grep "SR3x-ONT1x.*sentdhio[^m]" "$REF/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" | head -20
    echo "..."
    grep "SR3x-ONT1x.*sentdhio[^m]" "$REF/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv" | wc -l
    echo "lines total"
else
    echo "No concordance file found at ref analysis"
fi

# Search all analysis dirs
echo ""
echo "--- All analysis dirs with concordance files ---"
find /fsx/analysis_results/ubuntu/ -maxdepth 3 -name "giab_concordance_mqc.tsv" 2>/dev/null | while read f; do
    count=$(grep -c "SR3x-ONT1x.*sentdhio[^m]" "$f" 2>/dev/null || echo 0)
    if [ "$count" -gt 0 ]; then
        echo "$f: $count lines with SR3x-ONT1x sentdhio"
    fi
done
'

