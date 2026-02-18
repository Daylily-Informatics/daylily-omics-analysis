#!/bin/bash
# Get concordance report from headnode
ssh -i ~/.ssh/lsmc-omics-us-west-2.pem -o ConnectTimeout=30 ubuntu@44.231.76.175 << 'ENDSSH'
echo "=== HYBRID TEST CONCORDANCE REPORT ==="
echo ""
for d in test-hybrid-cli-ilmn-ont-3x test-hybrid-cli-ilmn-pb-3x test-hybrid-cli-ug-ont-3x test-hybrid-cli-ug-pb-3x test-hybrid-mod-ilmn-ont-3x test-hybrid-mod-ilmn-pb-3x test-hybrid-mod-ug-ont-3x test-hybrid-mod-ug-pb-3x test-hybrid-mod-roche-ont-3x test-hybrid-mod-roche-pb-3x; do
    f="/fsx/analysis_results/ubuntu/$d/daylily-omics-analysis/results/day/hg38/other_reports/giab_concordance_mqc.tsv"
    fb="/fsx/analysis_results/ubuntu/$d/daylily-omics-analysis/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv"
    echo "--- $d ---"
    if [ -s "$f" ]; then
        snp=$(grep SNPts "$f" | cut -f9 | head -1)
        indel=$(grep INDELts "$f" | cut -f9 | head -1)
        echo "SNPts F1: $snp"
        echo "INDELts F1: $indel"
    elif [ -s "$fb" ]; then
        snp=$(grep SNPts "$fb" | cut -f9 | head -1)
        indel=$(grep INDELts "$fb" | cut -f9 | head -1)
        echo "SNPts F1: $snp"
        echo "INDELts F1: $indel"
    else
        echo "(no concordance file or empty)"
    fi
    echo ""
done
ENDSSH

