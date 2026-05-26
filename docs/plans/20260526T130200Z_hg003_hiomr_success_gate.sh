#!/usr/bin/env bash
set -euo pipefail

root="/fsx/analysis_results/ubuntu"
runs=(
  "DS-003 hg003a_altair3_hiomr_ilmn20x_ont5x_1022 /tmp/hg003a_altair3_hiomr_ilmn20x_ont5x_1022.run1024.rc"
  "DS-004 hg003a_altair3_hiomr_ilmn15x_ont10x_1022 /tmp/hg003a_altair3_hiomr_ilmn15x_ont10x_1022.run1024_j190.rc"
  "DS-005 hg003a_altair3_hiomr_ilmn15x_ont7x_1022 /tmp/hg003a_altair3_hiomr_ilmn15x_ont7x_1022.run1024_j190.rc"
)

echo "success_gate_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for row in "${runs[@]}"; do
  set -- $row
  id="$1"
  wd="$2"
  rc="$3"
  repo="${root}/${wd}/daylily-omics-analysis"
  echo "-- ${id} ${wd} --"
  if [ -f "$rc" ]; then
    cat "$rc"
  else
    echo "rc_absent ${rc}"
  fi
  if [ -f "${repo}/daylily.successful_run" ]; then
    stat -c 'success %y %s %n' "${repo}/daylily.successful_run"
  else
    echo "success_absent"
  fi
  if [ -f "${repo}/daylily.failed_run" ]; then
    stat -c 'failed %y %s %n' "${repo}/daylily.failed_run"
  else
    echo "failed_absent"
  fi
done
echo "-- squeue --"
squeue -u ubuntu
echo "-- controllers --"
ps -fu ubuntu | awk '/snakemake|dy-r|day_run/ && !/awk/ {print}'
