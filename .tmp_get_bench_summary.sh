#!/usr/bin/env bash
set -euo pipefail
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
ANALYSIS="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"
ssh -i "$PEM" "$HOST" "head -1 $ANALYSIS/results/day/hg38_broad/reports/benchmarks_summary.tsv && grep 'sentdhiomr' $ANALYSIS/results/day/hg38_broad/reports/benchmarks_summary.tsv"

