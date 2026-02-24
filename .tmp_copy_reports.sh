#!/usr/bin/env bash
set -euo pipefail

HEADNODE="ubuntu@44.231.76.175"
PEM="$HOME/.ssh/lsmc-omics-us-west-2.pem"
SCP="scp -i $PEM -o ConnectTimeout=10 -o StrictHostKeyChecking=no"
RB="/fsx/analysis_results/ubuntu/hiomr_fullgenome_3x3x_15x15x_20260222/daylily-omics-analysis/results/day/hg38_broad"
LOCAL="./sentdhiomr_results"

rm -rf "$LOCAL"
mkdir -p "$LOCAL/other_reports" "$LOCAL/reports"

echo "=== other_reports ==="
$SCP ${HEADNODE}:${RB}/other_reports/* "$LOCAL/other_reports/" 2>&1

echo "=== reports ==="
$SCP ${HEADNODE}:${RB}/reports/* "$LOCAL/reports/" 2>&1 || echo "(reports dir empty or missing)"

echo "=== DONE ==="
find "$LOCAL" -type f | sort

