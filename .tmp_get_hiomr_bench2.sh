#!/usr/bin/env bash
set -euo pipefail
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
HOST="ubuntu@44.231.76.175"
ANALYSIS="/fsx/analysis_results/ubuntu/hiom_ref_chr21_20260220/daylily-omics-analysis"

ssh -i "$PEM" "$HOST" "echo '=== HIOMR benchmark files ===' && find $ANALYSIS/results/ -path '*/benchmarks/*sentdhiomr*' -name '*.bench.tsv' 2>/dev/null | sort && echo '' && echo '=== Contents ===' && for f in \$(find $ANALYSIS/results/ -path '*/benchmarks/*sentdhiomr*' -name '*.bench.tsv' 2>/dev/null | sort); do echo \"--- \$(basename \$f) ---\"; head -1 \$f; tail -1 \$f; echo ''; done && echo '=== Also check for any benchmarks_summary.tsv ===' && find $ANALYSIS/results/ -name 'benchmarks_summary.tsv' 2>/dev/null && echo DONE"

