#!/usr/bin/env bash
set -euo pipefail

test "$(id -un)" = "ubuntu"
test "$#" -eq 3

workdir_name="$1"
stamp="$2"
s3_prefix="$3"

workdir="/fsx/analysis_results/ubuntu/${workdir_name}"
monitor_dir="${workdir}/_daylily_monitor/verify/${stamp}"
manifest="${monitor_dir}/fsx_manifest.tsv"
summary="${monitor_dir}/fsx_manifest_summary.txt"

test -d "${workdir}"
mkdir -p "${monitor_dir}"
cd "${workdir}"

find . -path './_daylily_monitor' -prune -o \( -type f -o -type l \) -printf '%P\t%s\n' \
    | LC_ALL=C sort > "${manifest}"

awk -F '\t' 'BEGIN {bytes=0} {n++; bytes += $2} END {printf "fsx_files_or_symlinks=%d\nfsx_bytes=%d\n", n, bytes}' \
    "${manifest}" > "${summary}"

aws s3 cp "${manifest}" "${s3_prefix%/}/_daylily_monitor/verify/${stamp}/fsx_manifest.tsv" >/dev/null
aws s3 cp "${summary}" "${s3_prefix%/}/_daylily_monitor/verify/${stamp}/fsx_manifest_summary.txt" >/dev/null

cat "${summary}"
echo "fsx_manifest=${manifest}"
echo "s3_manifest_copy=${s3_prefix%/}/_daylily_monitor/verify/${stamp}/fsx_manifest.tsv"
