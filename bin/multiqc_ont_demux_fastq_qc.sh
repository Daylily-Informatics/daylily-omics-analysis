#!/usr/bin/env bash
set -euo pipefail

# Run ONT demux FASTQ QC from mounted run directories.
#
# This script expects demuxed chunk FASTQs in directories shaped like:
#   <run_dir>/.../fastq_pass/<barcode>/*.fastq.gz
#   <run_dir>/.../fastq_fail/<barcode>/*.fastq.gz
#
# Required conda environment by default:
#   ONT-QC: NanoPlot, NanoStat, seqkit, nanoq, multiqc
#
# Setup reminder:
#   conda create -y -n ONT-QC -c conda-forge -c bioconda \
#     python=3.11 nanoplot nanostat seqkit nanoq multiqc r-minionqc
#
# Override defaults as needed:
#   BASE=/fsx/run_dir_mounts
#   ROOT_OUT=/fsx/analysis_results/ubuntu/run_qc_ont_all
#   ONT_QC_ENV=ONT-QC
#   THREADS=8

BASE="${BASE:-/fsx/run_dir_mounts}"
ROOT_OUT="${ROOT_OUT:-/fsx/analysis_results/ubuntu/run_qc_ont_all}"
ONT_QC_ENV="${ONT_QC_ENV:-ONT-QC}"
THREADS="${THREADS:-8}"

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

run_group_qc() {
  local run_id="$1"
  local fastq_dir="$2"
  local out_root="$3"
  local status
  local barcode
  local sample
  local sample_out
  local file_list
  local file_count
  local fastqs

  status="$(basename "$(dirname "$fastq_dir")")"
  barcode="$(basename "$fastq_dir")"
  sample="${run_id}-${status}-${barcode}"
  sample_out="$out_root/$sample"
  file_list="$sample_out/$sample.fastq_files.txt"

  mkdir -p "$sample_out/nanoplot"

  find "$fastq_dir" -maxdepth 1 -type f \( -name '*.fastq.gz' -o -name '*.fq.gz' \) \
    | sort > "$file_list"

  file_count="$(wc -l < "$file_list")"
  if [ "$file_count" -eq 0 ]; then
    echo "No FASTQs found for $sample under $fastq_dir" >&2
    exit 1
  fi

  mapfile -t fastqs < "$file_list"

  echo "QC $sample ($file_count files)"

  conda run -n "$ONT_QC_ENV" seqkit stats --tabular "${fastqs[@]}" \
    > "$sample_out/$sample.seqkit_stats.tsv" \
    2> "$sample_out/$sample.seqkit_stats.log"

  conda run -n "$ONT_QC_ENV" nanoq "${fastqs[@]}" \
    > "$sample_out/$sample.nanoq.txt" \
    2> "$sample_out/$sample.nanoq.log"

  conda run -n "$ONT_QC_ENV" NanoStat --fastq "${fastqs[@]}" \
    > "$sample_out/$sample.NanoStat.fastq.txt" \
    2> "$sample_out/$sample.NanoStat.fastq.log"

  conda run -n "$ONT_QC_ENV" NanoPlot \
    --fastq "${fastqs[@]}" \
    --loglength \
    --tsv_stats \
    --info_in_report \
    -t "$THREADS" \
    -o "$sample_out/nanoplot" \
    -p "$sample." \
    > "$sample_out/$sample.NanoPlot.fastq.log" 2>&1
}

run_multiqc() {
  conda run -n "$ONT_QC_ENV" multiqc -f \
    -m nanostat \
    -m seqkit \
    -m nanoq \
    --filename ont_demux_fastq.multiqc.html \
    --outdir "$ROOT_OUT" \
    "$ROOT_OUT"/*/demux_fastq_qc
}

require_cmd conda
require_conda_tool "$ONT_QC_ENV" NanoPlot
require_conda_tool "$ONT_QC_ENV" NanoStat
require_conda_tool "$ONT_QC_ENV" seqkit
require_conda_tool "$ONT_QC_ENV" nanoq
require_conda_tool "$ONT_QC_ENV" multiqc

mkdir -p "$ROOT_OUT"

for run_id in "${RUN_IDS[@]}"; do
  run_dir="$BASE/$run_id"
  out_dir="$ROOT_OUT/$run_id/demux_fastq_qc"
  group_list="$out_dir/$run_id.fastq_group_dirs.txt"

  echo "Processing ONT demux FASTQs: $run_id"

  if [ ! -d "$run_dir" ]; then
    echo "Missing ONT run directory: $run_dir" >&2
    exit 1
  fi

  mkdir -p "$out_dir"

  find "$run_dir" -type f \( -name '*.fastq.gz' -o -name '*.fq.gz' \) \
    | sed 's#/[^/]*$##' \
    | sort -u > "$group_list"

  if [ ! -s "$group_list" ]; then
    echo "No demux FASTQ groups found under $run_dir" >&2
    exit 1
  fi

  while IFS= read -r fastq_dir; do
    run_group_qc "$run_id" "$fastq_dir" "$out_dir"
  done < "$group_list"
done

run_multiqc

echo "ONT demux FASTQ QC written under: $ROOT_OUT"
echo "Combined demux FASTQ MultiQC report: $ROOT_OUT/ont_demux_fastq.multiqc.html"
