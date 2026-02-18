#!/bin/bash
# Check concordance results for all hybrid tests
echo "=== HYBRID TEST CONCORDANCE REPORT $(date) ==="
echo ""

TESTS="test-hybrid-cli-ilmn-ont-3x test-hybrid-cli-ilmn-pb-3x test-hybrid-cli-ug-ont-3x test-hybrid-cli-ug-pb-3x test-hybrid-mod-ilmn-ont-3x test-hybrid-mod-ilmn-pb-3x test-hybrid-mod-ug-ont-3x test-hybrid-mod-ug-pb-3x test-hybrid-mod-roche-ont-3x test-hybrid-mod-roche-pb-3x"

for d in $TESTS; do
    echo "--- $d ---"
    f="/fsx/analysis_results/ubuntu/$d/daylily-omics-analysis/results/day/hg38/other_reports/giab_concordance_mqc.tsv"
    fb="/fsx/analysis_results/ubuntu/$d/daylily-omics-analysis/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv"
    
    if [[ -s "$f" ]]; then
        snp=$(grep SNPts "$f" | cut -f9 | head -1)
        indel=$(grep INDELts "$f" | cut -f9 | head -1)
        echo "SNPts F1: $snp"
        echo "INDELts F1: $indel"
    elif [[ -s "$fb" ]]; then
        snp=$(grep SNPts "$fb" | cut -f9 | head -1)
        indel=$(grep INDELts "$fb" | cut -f9 | head -1)
        echo "SNPts F1: $snp"
        echo "INDELts F1: $indel"
    else
        if [[ -f "$f" ]]; then
            echo "(hg38 file exists but empty)"
        elif [[ -f "$fb" ]]; then
            echo "(hg38_broad file exists but empty)"
        else
            echo "(no concordance file found)"
        fi
    fi
    echo ""
done

