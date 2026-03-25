#!/usr/bin/env bash
# Remote monitor script for analysis directories
# Produces markdown table with metrics for all analysis_results/ubuntu/* directories

set -u

BASE_PATH="/fsx/analysis_results/ubuntu"
INTERVAL="30"

while [[ $# -gt 0 ]]; do
  case $1 in
    --base-path) BASE_PATH="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: monitor_ifx_go.sh [--base-path PATH] [--interval SECONDS]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ ! -d "$BASE_PATH" ]]; then
  echo "ERROR: Base path does not exist: $BASE_PATH" >&2
  exit 1
fi

count_samples() {
  local workdir="$1"
  if [ -f "$workdir/config/samples.tsv" ]; then
    tail -n +2 "$workdir/config/samples.tsv" 2>/dev/null | wc -l | tr -d ' '
  else
    echo "0"
  fi
}

count_units() {
  local workdir="$1"
  if [ -f "$workdir/config/units.tsv" ]; then
    tail -n +2 "$workdir/config/units.tsv" 2>/dev/null | wc -l | tr -d ' '
  else
    echo "0"
  fi
}

count_running_jobs_global() {
  if ! command -v squeue &> /dev/null; then
    echo "ERROR: squeue not found on PATH" >&2
    exit 1
  fi
  squeue -u ubuntu --format='%T' 2>/dev/null | grep -c '^RUNNING$' || echo "0"
}

count_pending_jobs_global() {
  if ! command -v squeue &> /dev/null; then
    echo "ERROR: squeue not found on PATH" >&2
    exit 1
  fi
  squeue -u ubuntu --format='%T' 2>/dev/null | grep -c '^PENDING$' || echo "0"
}

has_success_marker() {
  local workdir="$1"
  [ -f "$workdir/daylily.successful_run" ] && echo "1" || echo "0"
}

count_slurm_logs() {
  local workdir="$1"
  if [ -d "$workdir/logs/slurm" ]; then
    find "$workdir/logs/slurm" -name "*.out" -type f 2>/dev/null | wc -l | tr -d ' '
  else
    echo "0"
  fi
}

get_dir_size() {
  local workdir="$1"
  du -sh "$workdir" 2>/dev/null | cut -f1
}

get_last_modified() {
  local workdir="$1"
  stat -c '%y' "$workdir" 2>/dev/null | cut -d' ' -f1 || stat -f '%Sm' "$workdir" 2>/dev/null || echo "N/A"
}

print_table_header() {
  echo "| dirname | n_samples | n_units | n_running | n_pending | last_modified | dir_size | n_success | n_failed_term | n_failed_nonterm | pct_complete |"
  echo "|---------|-----------|---------|-----------|-----------|---------------|----------|-----------|----------------|------------------|--------------| "
}

print_table_row() {
  local dirname="$1"
  local workdir="$2"
  local n_running=$3
  local n_pending=$4
  local n_samples=$(count_samples "$workdir")
  local n_units=$(count_units "$workdir")
  local last_modified=$(get_last_modified "$workdir")
  local dir_size=$(get_dir_size "$workdir")
  local n_success=$(has_success_marker "$workdir")
  local n_failed_term=$(count_slurm_logs "$workdir")
  printf "| %-20s | %9s | %7s | %9s | %9s | %13s | %8s | %9s | %14s | %16s | %12s |\n" \
    "$dirname" "$n_samples" "$n_units" "$n_running" "$n_pending" "$last_modified" "$dir_size" "$n_success" "$n_failed_term" "0" "N/A"
}

echo "# Analysis Monitor"
echo ""
echo "**Timestamp:** $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

n_running=$(count_running_jobs_global)
n_pending=$(count_pending_jobs_global)

print_table_header

for workdir in "$BASE_PATH"/*; do
  if [ -d "$workdir" ]; then
    dirname=$(basename "$workdir")
    print_table_row "$dirname" "$workdir" "$n_running" "$n_pending"
  fi
done

echo ""
echo "**Filesystem Summary:**"
echo ""
echo "\`\`\`"
df -h "$BASE_PATH" 2>/dev/null || echo "Unable to get filesystem info"
echo "\`\`\`"

