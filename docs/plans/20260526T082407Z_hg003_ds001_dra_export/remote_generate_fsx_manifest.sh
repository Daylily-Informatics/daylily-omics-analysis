#!/usr/bin/env bash
set -euo pipefail

WORKDIR="/fsx/analysis_results/ubuntu/hg003a_altair3_hiomr_ilmn20x_ont10x_1022"
STAMP="20260526T082407Z"
MONITOR_DIR="${WORKDIR}/_daylily_monitor/verify/${STAMP}"
MANIFEST="${MONITOR_DIR}/fsx_manifest.tsv"
SUMMARY="${MONITOR_DIR}/fsx_manifest_summary.txt"

mkdir -p "${MONITOR_DIR}"
cd "${WORKDIR}"

find . -path './_daylily_monitor' -prune -o \( -type f -o -type l \) -printf '%P\t%s\n' \
    | LC_ALL=C sort > "${MANIFEST}"

awk -F '\t' 'BEGIN {bytes=0} {n++; bytes += $2} END {printf "fsx_files_or_symlinks=%d\nfsx_bytes=%d\n", n, bytes}' \
    "${MANIFEST}" > "${SUMMARY}"

cat "${SUMMARY}"
echo "fsx_manifest=${MANIFEST}"
