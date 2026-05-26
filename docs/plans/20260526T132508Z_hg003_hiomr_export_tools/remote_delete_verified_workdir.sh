#!/usr/bin/env bash
set -euo pipefail

test "$(id -un)" = "ubuntu"
test "$#" -eq 2

workdir_name="$1"
label="$2"
workdir="/fsx/analysis_results/ubuntu/${workdir_name}"
repo="${workdir}/daylily-omics-analysis"
review_log="/fsx/analysis_results/johnm/review_logs/hg003_hiomr_1022_multiagent_20260526T023334Z/review.log"

test -d "${workdir}"
test -f "${repo}/daylily.successful_run"
test ! -f "${repo}/daylily.failed_run"

rm -rf -- "${workdir}"
test ! -e "${workdir}"

{
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${label} verified DRA export completed; deleted ${workdir}."
    df -h /fsx
    echo "remaining_children=/fsx/analysis_results/ubuntu"
    find /fsx/analysis_results/ubuntu -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort
} | tee -a "${review_log}"
