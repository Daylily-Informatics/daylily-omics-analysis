#!/bin/bash
KEY="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
BASEDIR="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$KEY" "$HOST" "
echo '=============================='
echo '=== HIOMR CONCORDANCE DATA ==='
echo '=============================='
cat $BASEDIR/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv 2>/dev/null

echo ''
echo '================================'
echo '=== CLI REFERENCE CONCORDANCE ==='
echo '================================'
echo '--- CLI (main hg38 report) ---'
cat /fsx/analysis_results/ubuntu/cmr-hio-cli-20260218-163021/daylily-omics-analysis/results/day/hg38/other_reports/giab_concordance_mqc.tsv 2>/dev/null

echo ''
echo '--- CLI (ONT-specific) ---'
cat /fsx/analysis_results/ubuntu/cmr-hio-cli-20260218-163021/daylily-omics-analysis/etc/ont/giab_concordance_mqc.tsv 2>/dev/null

echo ''
echo '--- CLI (ont_all) ---'
cat /fsx/analysis_results/ubuntu/cmr-hio-cli-20260218-163021/daylily-omics-analysis/etc/ont_all/giab_concordance_mqc.tsv 2>/dev/null
"

