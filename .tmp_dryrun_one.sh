#!/usr/bin/env bash
# Dry-run concordance for one pipeline at a time
# Usage: bash .tmp_dryrun_one.sh <dir_name> <aligner> <snv_caller>
set -euo pipefail

DIR_NAME="${1:?Usage: $0 <dir_name> <aligner> <snv_caller>}"
ALIGNER="${2:?}"
SNV_CALLER="${3:?}"

BASE="/fsx/analysis_results/ubuntu"
DIR="$BASE/$DIR_NAME/daylily-omics-analysis"

cd "$DIR"
source dyoainit --project da-us-west-2d-agbt-heavy >/dev/null 2>&1 || true
source bin/day_activate slurm hg38_broad >/dev/null 2>&1 || true

echo "=== DRY-RUN: $DIR_NAME (aligner=$ALIGNER snv_caller=$SNV_CALLER) ==="
bash bin/day_run produce_snv_concordances -n -p -k -j 20 -T 1 \
    --config aligners="['$ALIGNER']" snv_callers="['$SNV_CALLER']" 2>&1
echo "=== DONE ==="

