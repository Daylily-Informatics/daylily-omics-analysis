#!/usr/bin/env bash
echo "=== CLI concordance for SR3x-ONT3x-8 (closest match to our SR3x-ONT1x-8) ==="
CLI="/fsx/analysis_results/ubuntu/cmr-hio-cli-20260218-163021/daylily-omics-analysis"
FILE="$CLI/results/day/hg38/other_reports/giab_concordance_mqc.tsv"

if [ -f "$FILE" ]; then
    echo "--- Header ---"
    head -1 "$FILE"
    echo ""
    echo "--- All variant class rows for SR3x-ONT3x-8 (sentdhio CLI) ---"
    grep "SR3x-ONT3x.*All" "$FILE"
else
    echo "File not found"
fi

echo ""
echo "=== HIOMR concordance for SR3x-ONT1x-8 (our run) ==="
REF="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"
FILE2="$REF/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv"

if [ -f "$FILE2" ]; then
    echo "--- All variant class rows ---"
    grep "All" "$FILE2" | head -20
fi
echo "DONE"

