#!/usr/bin/env bash
set -euo pipefail

test "$(id -un)" = "ubuntu"
test "$#" -eq 5

workdir_name="$1"
stamp="$2"
manifest_put_url="$3"
summary_put_url="$4"
label="$5"

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

curl --fail --silent --show-error -X PUT -T "${manifest}" "${manifest_put_url}" >/dev/null
curl --fail --silent --show-error -X PUT -T "${summary}" "${summary_put_url}" >/dev/null

cat "${summary}"
echo "label=${label}"
echo "fsx_manifest=${manifest}"
