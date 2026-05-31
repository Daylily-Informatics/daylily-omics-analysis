#!/usr/bin/env bash
set -euo pipefail

container_uri="$1"
run_dir="$2"
lane_output_dir="$3"
sample_sheet="$4"
lane_number="$5"
lane_sample_sheet="$6"
strict_mode="$7"
first_tile_only="$8"
sampleproject_subdirectories="$9"
fastq_gzip_compression_level="${10}"
parallel_tiles="${11}"
conversion_threads="${12}"
compression_threads="${13}"
decompression_threads="${14}"
shared_thread_odirect_output="${15}"
output_legacy_stats="${16}"
num_unknown_barcodes_reported="${17}"
sample_sheet_settings_json="${18}"
sample_sheet_settings_by_lane_json="${19}"
force_arg="${20}"
threads="${21}"
log_path="${22}"
fastq_list="${23}"
demux_stats="${24}"
done_path="${25}"

mkdir -p "$lane_output_dir" "$(dirname "$lane_sample_sheet")" "$(dirname "$log_path")"
: > "$log_path"
export TMPDIR="${TMPDIR:-/dev/shm}"
mkdir -p "$TMPDIR"
if [[ ! -d "$run_dir" ]]; then
  echo "BCL input directory does not exist: $run_dir" >> "$log_path"
  exit 2
fi

python workflow/scripts/prepare_bclconvert_lane_samplesheet.py \
  --sample-sheet "$sample_sheet" \
  --out "$lane_sample_sheet" \
  --lane "$lane_number" \
  --settings-json "$sample_sheet_settings_json" \
  --settings-by-lane-json "$sample_sheet_settings_by_lane_json" \
  >> "$log_path" 2>&1

echo "run_bclconvert_lane L$(printf '%03d' "$lane_number") started: $(date -Is)" >> "$log_path"
echo "host: $(hostname)" >> "$log_path"
echo "threads: $threads" >> "$log_path"
echo "TMPDIR: $TMPDIR" >> "$log_path"
echo "bcl_input_directory: $run_dir" >> "$log_path"
echo "output_directory: $lane_output_dir" >> "$log_path"
echo "sample_sheet: $lane_sample_sheet" >> "$log_path"
echo "bcl_only_lane: $lane_number" >> "$log_path"
echo "sample_sheet_settings_json: $sample_sheet_settings_json" >> "$log_path"
echo "sample_sheet_settings_by_lane_json: $sample_sheet_settings_by_lane_json" >> "$log_path"
echo "output_legacy_stats: $output_legacy_stats" >> "$log_path"
echo "num_unknown_barcodes_reported: $num_unknown_barcodes_reported" >> "$log_path"
nproc >> "$log_path" 2>&1 || true
df -h "$TMPDIR" "$run_dir" "$lane_output_dir" >> "$log_path" 2>&1 || true
command -v singularity >> "$log_path" 2>&1
singularity_bind_args=(--bind /fsx:/fsx)
echo "singularity_bind_args: ${singularity_bind_args[*]}" >> "$log_path"
singularity exec "${singularity_bind_args[@]}" "$container_uri" bcl-convert --version >> "$log_path" 2>&1

heavy_threads="$((parallel_tiles * conversion_threads + compression_threads + decompression_threads))"
if [[ "$heavy_threads" -lt 1 ]]; then
  echo "BCLConvert CPU-heavy thread total must be >= 1" >> "$log_path"
  exit 2
fi
if [[ "$heavy_threads" -gt "$threads" ]]; then
  echo "BCLConvert thread allocation exceeds requested threads: heavy_threads=$heavy_threads threads=$threads" >> "$log_path"
  exit 2
fi

echo "bcl_num_parallel_tiles: $parallel_tiles" >> "$log_path"
echo "bcl_num_conversion_threads: $conversion_threads" >> "$log_path"
echo "bcl_num_compression_threads: $compression_threads" >> "$log_path"
echo "bcl_num_decompression_threads: $decompression_threads" >> "$log_path"
echo "bcl_cpu_heavy_threads: $heavy_threads" >> "$log_path"

bcl_flags=(
  --bcl-input-directory "$run_dir"
  --output-directory "$lane_output_dir"
  --sample-sheet "$lane_sample_sheet"
  --bcl-only-lane "$lane_number"
  --strict-mode "$strict_mode"
  --first-tile-only "$first_tile_only"
  --bcl-sampleproject-subdirectories "$sampleproject_subdirectories"
  --fastq-gzip-compression-level "$fastq_gzip_compression_level"
  --bcl-num-parallel-tiles "$parallel_tiles"
  --bcl-num-conversion-threads "$conversion_threads"
  --bcl-num-compression-threads "$compression_threads"
  --bcl-num-decompression-threads "$decompression_threads"
  --shared-thread-odirect-output "$shared_thread_odirect_output"
  --output-legacy-stats "$output_legacy_stats"
  --num-unknown-barcodes-reported "$num_unknown_barcodes_reported"
)
if [[ -n "$force_arg" ]]; then
  bcl_flags+=("$force_arg")
fi

printf 'bcl-convert command:' >> "$log_path"
printf ' %q' singularity exec "${singularity_bind_args[@]}" "$container_uri" bcl-convert "${bcl_flags[@]}" >> "$log_path"
printf '\n' >> "$log_path"
singularity exec "${singularity_bind_args[@]}" "$container_uri" bcl-convert "${bcl_flags[@]}" >> "$log_path" 2>&1

test -s "$fastq_list"
test -s "$demux_stats"
mkdir -p "$(dirname "$done_path")"
touch "$done_path"
echo "run_bclconvert_lane L$(printf '%03d' "$lane_number") finished: $(date -Is)" >> "$log_path"
