#!/usr/bin/env bash
set -euo pipefail

# Run ONT run-directory QC from mounted run directories.
#
# Required conda environments by default:
#   PYCOQC: pycoQC==2.5.2 with setuptools<81
#   DAY-EC: NanoPlot and MultiQC
#
# Override defaults as needed:
#   BASE=/fsx/run_dir_mounts
#   ROOT_OUT=/fsx/analysis_results/ubuntu/run_qc_ont_all
#   PYCOQC_ENV=PYCOQC
#   NANOPLOT_ENV=DAY-EC
#   MULTIQC_ENV=DAY-EC
#   THREADS=8
#   RUN_MINIONQC=0
#   MINIONQC_ENV=ONT-QC

BASE="${BASE:-/fsx/run_dir_mounts}"
ROOT_OUT="${ROOT_OUT:-/fsx/analysis_results/ubuntu/run_qc_ont_all}"
PYCOQC_ENV="${PYCOQC_ENV:-PYCOQC}"
NANOPLOT_ENV="${NANOPLOT_ENV:-DAY-EC}"
MULTIQC_ENV="${MULTIQC_ENV:-DAY-EC}"
MINIONQC_ENV="${MINIONQC_ENV:-ONT-QC}"
THREADS="${THREADS:-8}"
RUN_MINIONQC="${RUN_MINIONQC:-0}"

DEFAULT_RUNS=(
  "20260424_ONT_100ul"
  "20260427_ONT_300ul"
  "20260513_ONT_HG003"
)

if [ "$#" -gt 0 ]; then
  RUN_IDS=("$@")
else
  RUN_IDS=("${DEFAULT_RUNS[@]}")
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 2
  }
}

require_conda_tool() {
  local env_name="$1"
  local tool_name="$2"

  conda run -n "$env_name" bash -lc "command -v '$tool_name'" >/dev/null 2>&1 || {
    echo "Missing required tool '$tool_name' in conda env '$env_name'." >&2
    exit 2
  }
}

run_pycoqc() {
  local run_id="$1"
  local out_dir="$2"
  shift 2
  local summary_files=("$@")

  conda run -n "$PYCOQC_ENV" pycoQC \
    -f "${summary_files[@]}" \
    -o "$out_dir/${run_id}.pycoQC.html" \
    -j "$out_dir/${run_id}.pycoQC.json" \
    --report_title "$run_id" \
    > "$out_dir/${run_id}.pycoQC.log" 2>&1
}

run_nanoplot() {
  local run_id="$1"
  local out_dir="$2"
  shift 2
  local summary_files=("$@")
  local nanoplot_dir="$out_dir/nanoplot"

  mkdir -p "$nanoplot_dir"
  conda run -n "$NANOPLOT_ENV" NanoPlot \
    --summary "${summary_files[@]}" \
    --loglength \
    --tsv_stats \
    --info_in_report \
    -t "$THREADS" \
    -o "$nanoplot_dir" \
    -p "${run_id}." \
    > "$out_dir/${run_id}.NanoPlot.log" 2>&1
}

run_minionqc() {
  local run_id="$1"
  local run_dir="$2"
  local out_dir="$3"
  local minionqc_dir="$out_dir/minionqc"

  mkdir -p "$minionqc_dir"
  conda run -n "$MINIONQC_ENV" MinIONQC.R \
    -i "$run_dir" \
    -o "$minionqc_dir" \
    -p "$THREADS" \
    > "$out_dir/${run_id}.MinIONQC.log" 2>&1
}

run_multiqc() {
  local modules=(-m pycoqc -m nanostat)
  if [ "$RUN_MINIONQC" = "1" ]; then
    modules+=(-m minionqc)
  fi

  conda run -n "$MULTIQC_ENV" multiqc -f \
    "${modules[@]}" \
    --filename ont_runs.multiqc.html \
    --outdir "$ROOT_OUT" \
    "$ROOT_OUT"
}

require_cmd conda
require_conda_tool "$PYCOQC_ENV" pycoQC
require_conda_tool "$NANOPLOT_ENV" NanoPlot
require_conda_tool "$MULTIQC_ENV" multiqc
if [ "$RUN_MINIONQC" = "1" ]; then
  require_conda_tool "$MINIONQC_ENV" MinIONQC.R
fi

mkdir -p "$ROOT_OUT"

for run_id in "${RUN_IDS[@]}"; do
  run_dir="$BASE/$run_id"
  out_dir="$ROOT_OUT/$run_id"

  echo "Processing ONT run: $run_id"

  if [ ! -d "$run_dir" ]; then
    echo "Missing ONT run directory: $run_dir" >&2
    exit 1
  fi

  mapfile -t summary_files < <(find "$run_dir" -type f -name 'sequencing_summary*.txt' | sort)
  if [ "${#summary_files[@]}" -eq 0 ]; then
    echo "No sequencing_summary*.txt files found under $run_dir" >&2
    exit 1
  fi

  mkdir -p "$out_dir"
  run_pycoqc "$run_id" "$out_dir" "${summary_files[@]}"
  run_nanoplot "$run_id" "$out_dir" "${summary_files[@]}"

  if [ "$RUN_MINIONQC" = "1" ]; then
    run_minionqc "$run_id" "$run_dir" "$out_dir"
  fi
done

run_multiqc

echo "ONT QC reports written under: $ROOT_OUT"
echo "Combined MultiQC report: $ROOT_OUT/ont_runs.multiqc.html"
