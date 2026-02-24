#!/usr/bin/env bash
set -euo pipefail
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
ANALYSIS="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

ssh -i "$PEM" "$HOST" "echo '=== HIOMR benchmark files ===' && find $ANALYSIS/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8*/benchmarks/ -name '*.bench.tsv' 2>/dev/null | sort && echo '' && echo '=== Contents of each benchmark file ===' && for f in \$(find $ANALYSIS/results/day/hg38_broad/HIOa-HG003-SR3x-ONT1x-8*/benchmarks/ -name '*.bench.tsv' 2>/dev/null | sort); do echo \"--- \$f ---\"; cat \"\$f\"; echo ''; done"

