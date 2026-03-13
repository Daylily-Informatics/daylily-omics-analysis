#!/usr/bin/env bash
set -euo pipefail
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
ssh -i "$PEM" "$HOST" 'echo "=== Ref analysis concordance ===" && ls -la /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv && echo "" && echo "--- giabHC All row ---" && grep "sentdhiomr-All" /fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis/results/day/hg38_broad/other_reports/giab_concordance_mqc.tsv | grep "giabHC" | grep -v "x_"'

