#!/usr/bin/env bash
set -euo pipefail

test "$(id -un)" = "ubuntu"

WORKDIR="/fsx/analysis_results/ubuntu/hg003a_altair3_hiomr_ilmn20x_ont7x_1022"
REPO_DIR="${WORKDIR}/daylily-omics-analysis"
REVIEW_LOG="/fsx/analysis_results/johnm/review_logs/hg003_hiomr_1022_multiagent_20260526T023334Z/review.log"

test -d "${WORKDIR}"
test -f "${REPO_DIR}/daylily.successful_run"
test ! -f "${REPO_DIR}/daylily.failed_run"

rm -rf -- "${WORKDIR}"
test ! -e "${WORKDIR}"

{
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DS-002 verified DRA export completed; deleted ${WORKDIR}."
    df -h /fsx
    echo "remaining_children=/fsx/analysis_results/ubuntu"
    find /fsx/analysis_results/ubuntu -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort
} | tee -a "${REVIEW_LOG}"
