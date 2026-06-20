#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 28 ]]; then
  echo "run_bclconvert_lane.sh expected 28 arguments, got $#; pass __dayoa_no_force__ or -f for the force argument" >&2
  exit 2
fi

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
tile_regex="${26:-}"
scratch_output_root="${27:-}"
scratch_available_bytes_min="${28:-0}"

final_output_dir="$lane_output_dir"
run_output_dir="$final_output_dir"
scratch_work_dir=""

cleanup_scratch() {
  local rc=$?
  local expected_scratch_prefix
  if [[ -n "$scratch_work_dir" && -d "$scratch_work_dir" ]]; then
    expected_scratch_prefix="${scratch_output_root%/}/dayoa_bclconvert_"
    if [[ -z "$scratch_output_root" || "$scratch_work_dir" != "$expected_scratch_prefix"* ]]; then
      echo "refusing BCL scratch cleanup outside expected root after exit rc=$rc: $scratch_work_dir" >> "$log_path"
      return
    fi
    echo "cleaning BCL scratch work directory after exit rc=$rc: $scratch_work_dir" >> "$log_path"
    rm -rf -- "$scratch_work_dir"
  fi
}
trap cleanup_scratch EXIT

mkdir -p "$(dirname "$final_output_dir")" "$(dirname "$lane_sample_sheet")" "$(dirname "$log_path")"
: > "$log_path"
if [[ "$force_arg" == "__dayoa_no_force__" ]]; then
  force_arg=""
elif [[ "$force_arg" != "-f" ]]; then
  echo "BCL force argument must be __dayoa_no_force__ or -f: $force_arg" >> "$log_path"
  exit 2
fi
export TMPDIR="${TMPDIR:-/dev/shm}"
mkdir -p "$TMPDIR"
if [[ ! -d "$run_dir" ]]; then
  echo "BCL input directory does not exist: $run_dir" >> "$log_path"
  exit 2
fi
if [[ -d "$final_output_dir" ]] && find "$final_output_dir" -mindepth 1 ! -type d -print -quit | grep -q .; then
  echo "BCL output directory contains existing files; refusing to overwrite: $final_output_dir" >> "$log_path"
  exit 2
fi
if [[ -n "$scratch_output_root" ]]; then
  if [[ "$scratch_output_root" != /* ]]; then
    echo "bclconvert.scratch_output_root must be an absolute path: $scratch_output_root" >> "$log_path"
    exit 2
  fi
  if [[ ! "$scratch_available_bytes_min" =~ ^[0-9]+$ ]]; then
    echo "bclconvert.scratch_available_bytes_min must be a non-negative integer: $scratch_available_bytes_min" >> "$log_path"
    exit 2
  fi
  safe_output_id="$(printf '%s' "$final_output_dir" | sed -e 's#^/##' -e 's#[^A-Za-z0-9._-]#_#g')"
  scratch_work_dir="${scratch_output_root%/}/dayoa_bclconvert_${SLURM_JOB_ID:-manual_$$}/${safe_output_id}"
  run_output_dir="${scratch_work_dir}/output"
  if [[ -e "$scratch_work_dir" ]]; then
    echo "Scratch work directory already exists; refusing to overwrite: $scratch_work_dir" >> "$log_path"
    exit 2
  fi
  mkdir -p "$scratch_work_dir"
  if [[ "$scratch_available_bytes_min" -gt 0 ]]; then
    scratch_available_bytes="$(df -PB1 "$scratch_output_root" | awk 'NR == 2 {print $4}')"
    echo "scratch_available_bytes: ${scratch_available_bytes:-<unknown>}" >> "$log_path"
    echo "scratch_available_bytes_min: $scratch_available_bytes_min" >> "$log_path"
    if [[ -z "$scratch_available_bytes" || ! "$scratch_available_bytes" =~ ^[0-9]+$ ]]; then
      echo "Unable to determine free bytes for BCL scratch output root: $scratch_output_root" >> "$log_path"
      exit 2
    fi
    if [[ "$scratch_available_bytes" -lt "$scratch_available_bytes_min" ]]; then
      echo "BCL scratch output root free bytes below required minimum: available=$scratch_available_bytes required=$scratch_available_bytes_min path=$scratch_output_root" >> "$log_path"
      exit 2
    fi
  fi
else
  mkdir -p "$(dirname "$run_output_dir")"
fi
if [[ -d "$run_output_dir" ]]; then
  find "$run_output_dir" -depth -type d -empty -delete 2>/dev/null || true
fi
if [[ -e "$run_output_dir" ]]; then
  echo "BCL run output directory exists after empty skeleton cleanup; refusing to overwrite: $run_output_dir" >> "$log_path"
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
echo "scratch_output_root: ${scratch_output_root:-<none>}" >> "$log_path"
echo "scratch_available_bytes_min: $scratch_available_bytes_min" >> "$log_path"
echo "run_output_dir: $run_output_dir" >> "$log_path"
echo "final_output_dir: $final_output_dir" >> "$log_path"
echo "bcl_input_directory: $run_dir" >> "$log_path"
echo "output_directory: $run_output_dir" >> "$log_path"
echo "sample_sheet: $lane_sample_sheet" >> "$log_path"
echo "bcl_only_lane: $lane_number" >> "$log_path"
echo "tile_regex: ${tile_regex:-<none>}" >> "$log_path"
echo "sample_sheet_settings_json: $sample_sheet_settings_json" >> "$log_path"
echo "sample_sheet_settings_by_lane_json: $sample_sheet_settings_by_lane_json" >> "$log_path"
echo "output_legacy_stats: $output_legacy_stats" >> "$log_path"
echo "num_unknown_barcodes_reported: $num_unknown_barcodes_reported" >> "$log_path"
nproc >> "$log_path" 2>&1 || true
df -h "$TMPDIR" "$run_dir" "$(dirname "$run_output_dir")" "$(dirname "$final_output_dir")" >> "$log_path" 2>&1 || true
command -v singularity >> "$log_path" 2>&1
singularity_bind_args=(--bind /fsx:/fsx)
if [[ -n "$scratch_output_root" ]]; then
  singularity_bind_args+=(--bind "$scratch_output_root:$scratch_output_root")
fi
echo "singularity_bind_args: ${singularity_bind_args[*]}" >> "$log_path"
singularity exec "${singularity_bind_args[@]}" "$container_uri" bcl-convert --version >> "$log_path" 2>&1

heavy_threads="$((parallel_tiles * conversion_threads + compression_threads + decompression_threads))"
if [[ "$heavy_threads" -lt 1 ]]; then
  echo "BCL Convert CPU-heavy thread total must be >= 1" >> "$log_path"
  exit 2
fi
if [[ "$heavy_threads" -gt "$threads" ]]; then
  echo "BCL Convert thread allocation exceeds requested threads: heavy_threads=$heavy_threads threads=$threads" >> "$log_path"
  exit 2
fi

echo "bcl_num_parallel_tiles: $parallel_tiles" >> "$log_path"
echo "bcl_num_conversion_threads: $conversion_threads" >> "$log_path"
echo "bcl_num_compression_threads: $compression_threads" >> "$log_path"
echo "bcl_num_decompression_threads: $decompression_threads" >> "$log_path"
echo "bcl_cpu_heavy_threads: $heavy_threads" >> "$log_path"

bcl_flags=(
  --bcl-input-directory "$run_dir"
  --output-directory "$run_output_dir"
  --sample-sheet "$lane_sample_sheet"
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
if [[ -n "$tile_regex" ]]; then
  bcl_flags+=(--tiles "$tile_regex")
else
  bcl_flags+=(--bcl-only-lane "$lane_number")
fi
if [[ -n "$force_arg" ]]; then
  bcl_flags+=("$force_arg")
fi

printf 'bcl-convert command:' >> "$log_path"
printf ' %q' singularity exec "${singularity_bind_args[@]}" "$container_uri" bcl-convert "${bcl_flags[@]}" >> "$log_path"
printf '\n' >> "$log_path"
singularity exec "${singularity_bind_args[@]}" "$container_uri" bcl-convert "${bcl_flags[@]}" >> "$log_path" 2>&1

run_fastq_list="$run_output_dir/Reports/fastq_list.csv"
run_demux_stats="$run_output_dir/Reports/Demultiplex_Stats.csv"
test -s "$run_fastq_list"
test -s "$run_demux_stats"
if [[ -n "$scratch_work_dir" ]]; then
  echo "moving BCL Convert output from scratch to final output directory: $(date -Is)" >> "$log_path"
  mkdir -p "$final_output_dir"
  rsync -a --remove-source-files --human-readable --stats "$run_output_dir/" "$final_output_dir/" >> "$log_path" 2>&1
  python workflow/scripts/rewrite_bclconvert_fastq_list_paths.py \
    --fastq-list "$fastq_list" \
    --from-root "$run_output_dir" \
    --to-root "$final_output_dir" \
    >> "$log_path" 2>&1
  find "$run_output_dir" -depth -type d -empty -delete 2>/dev/null || true
  find "$scratch_work_dir" -depth -type d -empty -delete 2>/dev/null || true
fi
test -s "$fastq_list"
test -s "$demux_stats"
mkdir -p "$(dirname "$done_path")"
touch "$done_path"
df -h "$TMPDIR" "$run_dir" "$final_output_dir" >> "$log_path" 2>&1 || true
echo "run_bclconvert_lane L$(printf '%03d' "$lane_number") finished: $(date -Is)" >> "$log_path"
