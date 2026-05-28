import os
import re
from pathlib import Path


def _bool(value, default=False):
    if value in [None, "", "None"]:
        return default
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def _intish(value, default):
    try:
        return int(str(value).strip())
    except Exception:
        return default


def _sanitize_run_id(value):
    text = str(value or "").strip()
    if text == "":
        return ""
    text = re.sub(r"[\\/]+", "_", text)
    text = re.sub(r"\s+", "_", text)
    text = re.sub(r"[^A-Za-z0-9._-]+", "_", text)
    text = re.sub(r"_+", "_", text)
    return text.strip("._-")


def _read_samplesheet_run_name(sample_sheet_path):
    if sample_sheet_path in ["", None, "None"]:
        return ""
    try:
        with open(sample_sheet_path, "r", encoding="utf-8") as handle:
            for line in handle:
                if line.startswith("RunName,"):
                    return line.split(",", 1)[1].strip()
    except OSError:
        return ""
    return ""


def _derive_bclconvert_run_id(sample_sheet_path):
    configured = _sanitize_run_id(BCLCFG.get("run_id", ""))
    if configured:
        return configured
    run_name = _sanitize_run_id(_read_samplesheet_run_name(sample_sheet_path))
    if run_name:
        return run_name
    return _sanitize_run_id(Path(sample_sheet_path).stem) or "bclconvert"


BCLCFG = config.get("bclconvert", {})
BCL_RUNTIME_VERSION = "4.0.3"
BCL_TARGET_REQUESTED = bool(_requested_targets() & BCL_BOOTSTRAP_TARGETS)
BCL_RUN_CONTEXT = run_context_for_platform("ILMN", require=False)
if BCL_RUN_CONTEXT is not None and BCL_TARGET_REQUESTED:
    if not _filled(BCL_RUN_CONTEXT.get("RUN_DIR", "")):
        raise WorkflowError(f"RUNID={BCL_RUN_CONTEXT['RUNID']} must populate RUN_DIR for BCL Convert.")
    if not _filled(BCL_RUN_CONTEXT.get("SAMPLE_SHEET", "")):
        raise WorkflowError(
            f"RUNID={BCL_RUN_CONTEXT['RUNID']} must populate SAMPLE_SHEET for BCL Convert."
        )

BCL_SAMPLE_SHEET = str(
    BCL_RUN_CONTEXT["SAMPLE_SHEET"]
    if BCL_RUN_CONTEXT is not None
    else (BCLCFG.get("sample_sheet", "SampleSheet.csv") or "SampleSheet.csv")
)
BCL_RUN_DIR = str(
    BCL_RUN_CONTEXT["RUN_DIR"] if BCL_RUN_CONTEXT is not None else (BCLCFG.get("run_dir", "") or "")
)
BCL_SOURCE_S3_URI = str(
    BCL_RUN_CONTEXT.get("SOURCE_S3_URI", "")
    if BCL_RUN_CONTEXT is not None
    else (BCLCFG.get("source_s3_uri", "") or "")
)
BCL_RUN_REGION = str(
    BCL_RUN_CONTEXT.get("REGION", "")
    if BCL_RUN_CONTEXT is not None
    else (BCLCFG.get("region", "") or "")
)
BCL_RUN_PROFILE = str(
    BCL_RUN_CONTEXT.get("PROFILE", "")
    if BCL_RUN_CONTEXT is not None
    else (BCLCFG.get("profile", "") or "")
)
BCL_OUTPUT_ROOT = str(
    BCL_RUN_CONTEXT["OUTPUT_ROOT_RESOLVED"]
    if BCL_RUN_CONTEXT is not None
    else (BCLCFG.get("output_root", "results/bclconvert") or "results/bclconvert")
).rstrip("/")
BCL_RUN_ID = str(
    BCL_RUN_CONTEXT["RUNID"]
    if BCL_RUN_CONTEXT is not None
    else config.get("bclconvert_bootstrap_run_id", _derive_bclconvert_run_id(BCL_SAMPLE_SHEET))
)
BCL_ROOT = (
    f"{BCL_OUTPUT_ROOT}/bclconvert"
    if BCL_RUN_CONTEXT is not None
    else f"{BCL_OUTPUT_ROOT}/{BCL_RUN_ID}"
)
BCL_FASTQ_DIR = f"{BCL_ROOT}/fastqs" if BCL_RUN_CONTEXT is not None else f"{BCL_ROOT}/fastq"
BCL_REPORT_DIR = f"{BCL_FASTQ_DIR}/Reports"
BCL_TABLE_DIR = f"{BCL_ROOT}/tables"
BCL_METRIC_DIR = f"{BCL_ROOT}/metrics"
BCL_REPORT_OUT_DIR = BCL_ROOT if BCL_RUN_CONTEXT is not None else f"{BCL_ROOT}/reports"
BCL_LOG_DIR = f"{BCL_ROOT}/logs"
BCL_BENCH_DIR = f"{BCL_ROOT}/benchmarks"
BCL_MQC_DIR = f"{BCL_ROOT}/multiqc_inputs" if BCL_RUN_CONTEXT is not None else f"{MDIR}other_reports"
BCL_MQC_LOG_DIR = f"{BCL_MQC_DIR}/logs"

BCL_VALIDATE_OK = f"{BCL_LOG_DIR}/validated.ok"
BCL_NORMALIZED_SAMPLE_SHEET = f"{BCL_ROOT}/normalized.SampleSheet.csv"
BCL_SAMPLESHEET_ROWS = f"{BCL_TABLE_DIR}/samplesheet_rows.tsv"
BCL_WARNINGS = f"{BCL_LOG_DIR}/bclconvert_validate_inputs.warnings.log"
BCL_DONE = f"{BCL_LOG_DIR}/bclconvert.done"
BCL_FASTQS_COMPLETE = f"{BCL_ROOT}/fastqs.complete"
BCL_BOOTSTRAP_COMPLETE = f"{BCL_ROOT}/bclconvert.bootstrap.complete"
BCL_MQC_COMPLETE = (
    f"{BCL_ROOT}/bclconvert_metrics_mqc.done"
    if BCL_RUN_CONTEXT is not None
    else f"{BCL_MQC_DIR}/bclconvert_metrics_mqc.done"
)

BCL_METRICS_ENV = "../envs/bclconvert_metrics_v0.1.yaml"
MULTIQC_ENV = "../envs/multiqc_v0.1.yaml"
MULTIQC_CONFIG = (
    config.get("multiqc", {})
    .get("bclconvert", {})
    .get("config_yaml", "config/external_tools/multiqc_config.yaml")
)
SAMPLES_TABLE = str(
    config.get("samples_table", os.path.abspath(os.path.join("config", "samples.tsv")))
)

BCL_THREADS = _intish(BCLCFG.get("threads", 1), 1)
BCL_MEM_MB = _intish(BCLCFG.get("mem_mb", 3000), 3000)
BCL_PARTITION = str(BCLCFG.get("partition", "i192,i192mem") or "i192,i192mem")
BCL_TMPDIR = str(BCLCFG.get("tmpdir", "/dev/shm") or "/dev/shm")
BCL_STAGING_MODE = str(BCLCFG.get("staging_mode", "direct") or "direct").strip().lower()
BCL_SCRATCH_ROOT = str(BCLCFG.get("scratch_root", "/dev/shm/dayoa_bclconvert") or "/dev/shm/dayoa_bclconvert")
BCL_SCRATCH_SIZE_MULTIPLIER = _intish(BCLCFG.get("scratch_size_multiplier", 4), 4)
BCL_RETAIN_SCRATCH = _bool(BCLCFG.get("retain_scratch", False), False)
BCL_MOUNTED_STAGE_JOBS = _intish(BCLCFG.get("mounted_stage_jobs", 64), 64)
BCL_PARALLEL_TILES = _intish(BCLCFG.get("parallel_tiles", 1), 1)
BCL_CONVERSION_THREADS = _intish(BCLCFG.get("conversion_threads", BCL_THREADS), BCL_THREADS)
BCL_COMPRESSION_THREADS = _intish(BCLCFG.get("compression_threads", BCL_THREADS), BCL_THREADS)
BCL_DECOMPRESSION_THREADS = _intish(BCLCFG.get("decompression_threads", max(1, BCL_THREADS // 2)), max(1, BCL_THREADS // 2))
BCL_FASTQ_GZIP_COMPRESSION_LEVEL = _intish(BCLCFG.get("fastq_gzip_compression_level", 1), 1)
BCL_SHARED_THREAD_ODIRECT_OUTPUT = _bool(BCLCFG.get("shared_thread_odirect_output", False), False)
BCL_FORCE = _bool(BCLCFG.get("force", False))
BCL_KEEP_UNDETERMINED = _bool(BCLCFG.get("keep_undetermined_fastqs", True), True)
BCL_SAMPLEPROJECT_SUBDIRS = _bool(BCLCFG.get("sampleproject_subdirectories", False), False)
BCL_STRICT_MODE = _bool(BCLCFG.get("strict_mode", False), False)
BCL_FIRST_TILE_ONLY = _bool(BCLCFG.get("first_tile_only", False), False)
BCL_EXTRA_ARGS = str(BCLCFG.get("extra_args", "") or "").strip()
BCL_LIBPREP = str(BCLCFG.get("libprep", "PCR-FREE") or "PCR-FREE")
BCL_SEQ_VENDOR = str(BCLCFG.get("seq_vendor", "ILMN") or "ILMN")
BCL_SEQ_PLATFORM_OVERRIDE = str(BCLCFG.get("seq_platform_override", "") or "")
BCL_CONTAINER_URI = f"docker://nfcore/bclconvert:{BCL_RUNTIME_VERSION}"


localrules:
    bclconvert_validate_inputs,
    produce_bclconvert_fastqs,
    produce_bclconvert_metrics,
    produce_bclconvert_multiqc,
    produce_bclconvert_fastqs_and_metrics,


rule bclconvert_validate_inputs:
    input:
        sample_sheet=BCL_SAMPLE_SHEET,
        samples_table=SAMPLES_TABLE,
    output:
        validated=BCL_VALIDATE_OK,
        normalized_sample_sheet=BCL_NORMALIZED_SAMPLE_SHEET,
        parsed_samplesheet_tsv=BCL_SAMPLESHEET_ROWS,
    threads:
        1
    conda:
        BCL_METRICS_ENV
    params:
        cluster_sample="bclconvert_validate_inputs",
        run_dir=BCL_RUN_DIR,
        runtime_version=BCL_RUNTIME_VERSION,
        keep_undetermined_fastqs="true" if BCL_KEEP_UNDETERMINED else "false",
        sampleproject_subdirectories="true" if BCL_SAMPLEPROJECT_SUBDIRS else "false",
        extra_args=BCL_EXTRA_ARGS,
        warnings_out=BCL_WARNINGS,
    log:
        f"{BCL_LOG_DIR}/bclconvert_validate_inputs.log",
    benchmark:
        f"{BCL_BENCH_DIR}/bclconvert_validate_inputs.bench.tsv",
    shell:
        r"""
        set -euo pipefail
        mkdir -p {BCL_LOG_DIR:q} {BCL_TABLE_DIR:q}
        : > {log:q}
        if [ -z {params.run_dir:q} ]; then
            echo "bclconvert.run_dir is required" >> {log:q}
            exit 2
        fi
        if [ ! -d {params.run_dir:q} ]; then
            echo "bclconvert.run_dir does not exist: {params.run_dir}" >> {log:q}
            exit 2
        fi
        if [ "{params.keep_undetermined_fastqs}" = "false" ]; then
            echo "keep_undetermined_fastqs=false is unsupported for the bclconvert bootstrap path" >> {log:q}
            exit 2
        fi
        bcl_extra_args={params.extra_args:q}
        if [ -n "$bcl_extra_args" ]; then
            echo "bclconvert.extra_args is not supported in this shell-only bootstrap workflow" >> {log:q}
            exit 2
        fi
        python workflow/scripts/parse_bclconvert_samplesheet.py \
          --sample-sheet {input.sample_sheet:q} \
          --samples-tsv {input.samples_table:q} \
          --normalized-out {output.normalized_sample_sheet:q} \
          --rows-out {output.parsed_samplesheet_tsv:q} \
          --runtime-version {params.runtime_version:q} \
          --sampleproject-subdirectories {params.sampleproject_subdirectories:q} \
          --warnings-out {params.warnings_out:q} \
          >> {log:q} 2>&1
        touch {output.validated:q}
        """


rule run_bclconvert:
    input:
        validated=BCL_VALIDATE_OK,
        sample_sheet=BCL_NORMALIZED_SAMPLE_SHEET,
    output:
        done=BCL_DONE,
        fastq_list=f"{BCL_REPORT_DIR}/fastq_list.csv",
        demux_stats=f"{BCL_REPORT_DIR}/Demultiplex_Stats.csv",
    threads:
        BCL_THREADS
    resources:
        partition=BCL_PARTITION,
        vcpu=BCL_THREADS,
        threads=BCL_THREADS,
        mem_mb=BCL_MEM_MB,
        tmpdir=BCL_TMPDIR,
    params:
        cluster_sample="run_bclconvert",
        run_dir=BCL_RUN_DIR,
        source_s3_uri=BCL_SOURCE_S3_URI,
        region=BCL_RUN_REGION,
        profile=BCL_RUN_PROFILE,
        container_uri=BCL_CONTAINER_URI,
        tmpdir=BCL_TMPDIR,
        staging_mode=BCL_STAGING_MODE,
        scratch_root=BCL_SCRATCH_ROOT,
        scratch_size_multiplier=BCL_SCRATCH_SIZE_MULTIPLIER,
        retain_scratch="true" if BCL_RETAIN_SCRATCH else "false",
        mounted_stage_jobs=BCL_MOUNTED_STAGE_JOBS,
        parallel_tiles=BCL_PARALLEL_TILES,
        conversion_threads=BCL_CONVERSION_THREADS,
        compression_threads=BCL_COMPRESSION_THREADS,
        decompression_threads=BCL_DECOMPRESSION_THREADS,
        fastq_gzip_compression_level=BCL_FASTQ_GZIP_COMPRESSION_LEVEL,
        shared_thread_odirect_output="true" if BCL_SHARED_THREAD_ODIRECT_OUTPUT else "false",
        force="-f" if BCL_FORCE else "",
        strict_mode="true" if BCL_STRICT_MODE else "false",
        first_tile_only="true" if BCL_FIRST_TILE_ONLY else "false",
        sampleproject_subdirectories="true" if BCL_SAMPLEPROJECT_SUBDIRS else "false",
    log:
        f"{BCL_LOG_DIR}/run_bclconvert.log",
    benchmark:
        f"{BCL_BENCH_DIR}/run_bclconvert.bench.tsv",
    shell:
        r"""
        set -euo pipefail
        mkdir -p {BCL_FASTQ_DIR:q} {BCL_LOG_DIR:q}
        : > {log:q}
        export TMPDIR={params.tmpdir:q}
        mkdir -p "$TMPDIR"

        staging_mode={params.staging_mode:q}
        scratch_root={params.scratch_root:q}
        retain_scratch={params.retain_scratch:q}
        effective_run_dir={params.run_dir:q}
        effective_output_dir={BCL_FASTQ_DIR:q}
        scratch_dir=""

        cleanup_bclconvert_scratch() {{
            if [ -n "$scratch_dir" ] && [ "$retain_scratch" != "true" ]; then
                rm -rf "$scratch_dir"
            fi
        }}
        trap cleanup_bclconvert_scratch EXIT

        echo "run_bclconvert started: $(date -Is)" >> {log:q}
        echo "host: $(hostname)" >> {log:q}
        echo "threads: {threads}" >> {log:q}
        echo "resources_mem_mb: {resources.mem_mb}" >> {log:q}
        echo "TMPDIR: $TMPDIR" >> {log:q}
        echo "staging_mode: $staging_mode" >> {log:q}
        echo "scratch_root: $scratch_root" >> {log:q}
        echo "bcl_input_directory: $effective_run_dir" >> {log:q}
        echo "source_s3_uri: {params.source_s3_uri}" >> {log:q}
        echo "output_directory: $effective_output_dir" >> {log:q}
        nproc >> {log:q} 2>&1 || true
        df -h "$TMPDIR" {BCL_FASTQ_DIR:q} >> {log:q} 2>&1 || true
        command -v singularity >> {log:q} 2>&1
        singularity exec {params.container_uri:q} bcl-convert --version >> {log:q} 2>&1

        case "$staging_mode" in
            direct)
                ;;
            output_dev_shm)
                mkdir -p "$scratch_root"
                scratch_dir="$scratch_root/${{SLURM_JOB_ID:-local}}.$$"
                scratch_output_dir="$scratch_dir/fastqs"
                mkdir -p "$scratch_dir"
                input_disk_bytes="$(du -sB1 "$effective_run_dir" | awk '{{print $1}}')"
                input_apparent_bytes="$(du -sb "$effective_run_dir" | awk '{{print $1}}')"
                required_bytes="$((input_disk_bytes * {params.scratch_size_multiplier} + 1073741824))"
                scratch_parent="$(dirname "$scratch_root")"
                available_bytes="$(df -PB1 "$scratch_parent" | awk 'NR == 2 {{print $4}}')"
                echo "scratch_dir: $scratch_dir" >> {log:q}
                echo "scratch_input_disk_bytes: $input_disk_bytes" >> {log:q}
                echo "scratch_input_apparent_bytes: $input_apparent_bytes" >> {log:q}
                echo "scratch_required_bytes: $required_bytes" >> {log:q}
                echo "scratch_available_bytes: $available_bytes" >> {log:q}
                if [ "$available_bytes" -lt "$required_bytes" ]; then
                    echo "Insufficient scratch for bclconvert.staging_mode=output_dev_shm: required=$required_bytes available=$available_bytes" >> {log:q}
                    exit 2
                fi
                effective_output_dir="$scratch_output_dir"
                df -h "$scratch_root" >> {log:q} 2>&1 || true
                ;;
            dev_shm)
                mkdir -p "$scratch_root"
                scratch_dir="$scratch_root/${{SLURM_JOB_ID:-local}}.$$"
                scratch_run_dir="$scratch_dir/run"
                scratch_output_dir="$scratch_dir/fastqs"
                mkdir -p "$scratch_run_dir"
                input_disk_bytes="$(du -sB1 "$effective_run_dir" | awk '{{print $1}}')"
                input_apparent_bytes="$(du -sb "$effective_run_dir" | awk '{{print $1}}')"
                required_bytes="$((input_disk_bytes * {params.scratch_size_multiplier} + 1073741824))"
                scratch_parent="$(dirname "$scratch_root")"
                available_bytes="$(df -PB1 "$scratch_parent" | awk 'NR == 2 {{print $4}}')"
                echo "scratch_dir: $scratch_dir" >> {log:q}
                echo "scratch_input_disk_bytes: $input_disk_bytes" >> {log:q}
                echo "scratch_input_apparent_bytes: $input_apparent_bytes" >> {log:q}
                echo "scratch_required_bytes: $required_bytes" >> {log:q}
                echo "scratch_available_bytes: $available_bytes" >> {log:q}
                if [ "$available_bytes" -lt "$required_bytes" ]; then
                    echo "Insufficient scratch for bclconvert.staging_mode=dev_shm: required=$required_bytes available=$available_bytes" >> {log:q}
                    exit 2
                fi
                echo "Copying BCL run directory to scratch: $(date -Is)" >> {log:q}
                cp -aL --sparse=always "$effective_run_dir"/. "$scratch_run_dir"/
                effective_run_dir="$scratch_run_dir"
                effective_output_dir="$scratch_output_dir"
                df -h "$scratch_root" >> {log:q} 2>&1 || true
                ;;
            mounted_dev_shm)
                mkdir -p "$scratch_root"
                scratch_dir="$scratch_root/${{SLURM_JOB_ID:-local}}.$$"
                scratch_run_dir="$scratch_dir/run"
                scratch_output_dir="$scratch_dir/fastqs"
                scratch_sync_log_dir="$scratch_dir/rsync_logs"
                stage_metadata_log="{BCL_LOG_DIR:q}/mounted_metadata.log"
                stage_files_log="{BCL_LOG_DIR:q}/mounted_files.log"
                mkdir -p "$scratch_run_dir" "$scratch_sync_log_dir"
                lane_root="$effective_run_dir/Data/Intensities/BaseCalls"
                if [ ! -d "$lane_root" ]; then
                    echo "BCL run directory is missing lane root: $lane_root" >> {log:q}
                    exit 2
                fi
                root_file_bytes="$(find "$effective_run_dir" -maxdepth 1 -type f -printf '%s\n' | awk '{{s+=$1}} END {{print s+0}}')"
                intensities_file_bytes="$(find "$effective_run_dir/Data/Intensities" -maxdepth 1 -type f -printf '%s\n' | awk '{{s+=$1}} END {{print s+0}}')"
                lane_root_disk_bytes="$(du -sB1 "$lane_root" | awk '{{print $1}}')"
                input_disk_bytes="$((root_file_bytes + intensities_file_bytes + lane_root_disk_bytes))"
                input_apparent_bytes="$input_disk_bytes"
                required_bytes="$((input_disk_bytes * {params.scratch_size_multiplier} + 1073741824))"
                scratch_parent="$(dirname "$scratch_root")"
                available_bytes="$(df -PB1 "$scratch_parent" | awk 'NR == 2 {{print $4}}')"
                echo "scratch_dir: $scratch_dir" >> {log:q}
                echo "scratch_input_basis: mounted_metadata_plus_lane_root" >> {log:q}
                echo "scratch_root_file_bytes: $root_file_bytes" >> {log:q}
                echo "scratch_intensities_file_bytes: $intensities_file_bytes" >> {log:q}
                echo "scratch_lane_root_disk_bytes: $lane_root_disk_bytes" >> {log:q}
                echo "scratch_input_disk_bytes: $input_disk_bytes" >> {log:q}
                echo "scratch_input_apparent_bytes: $input_apparent_bytes" >> {log:q}
                echo "scratch_required_bytes: $required_bytes" >> {log:q}
                echo "scratch_available_bytes: $available_bytes" >> {log:q}
                if [ "$available_bytes" -lt "$required_bytes" ]; then
                    echo "Insufficient scratch for bclconvert.staging_mode=mounted_dev_shm: required=$required_bytes available=$available_bytes" >> {log:q}
                    exit 2
                fi
                lane_ids=$(find "$lane_root" -mindepth 1 -maxdepth 1 -type d -name 'L[0-9][0-9][0-9]' -printf '%f\n' | sort)
                if [ -z "$lane_ids" ]; then
                    echo "BCL run directory has no L### lane directories under $lane_root" >> {log:q}
                    exit 2
                fi
                echo "Staging mounted BCL run directory to scratch: $(date -Is)" >> {log:q}
                echo "mounted_stage_lanes: $(printf "%s" "$lane_ids" | tr '\n' ' ')" >> {log:q}
                mounted_stage_jobs={params.mounted_stage_jobs}
                if [ "$mounted_stage_jobs" -lt 1 ]; then
                    echo "bclconvert.mounted_stage_jobs must be >= 1" >> {log:q}
                    exit 2
                fi
                echo "mounted_stage_jobs: $mounted_stage_jobs" >> {log:q}
                mkdir -p "$scratch_run_dir/Data/Intensities/BaseCalls"
                if ! {{
                    echo "Copying root-level BCL metadata"
                    find "$effective_run_dir" -maxdepth 1 -type f -print0 \
                      | xargs -0 -r cp -L --sparse=always -t "$scratch_run_dir"
                    find "$effective_run_dir/Data/Intensities" -maxdepth 1 -type f -print0 \
                      | xargs -0 -r cp -L --sparse=always -t "$scratch_run_dir/Data/Intensities"
                    echo "Skipping InterOp during BCLConvert scratch staging; run-QC rules own InterOp parsing"
                }} > "$stage_metadata_log" 2>&1; then
                    cat "$stage_metadata_log" >> {log:q} || true
                    echo "Mounted metadata staging failed" >> {log:q}
                    exit 2
                fi
                cycle_list="$scratch_sync_log_dir/cycle_dirs.txt"
                find "$lane_root" -mindepth 2 -maxdepth 2 -type d -name 'C*.1' -printf '%P\n' | sort > "$cycle_list"
                cycle_count="$(wc -l < "$cycle_list" | tr -d ' ')"
                echo "mounted_stage_cycle_dirs: $cycle_count" >> {log:q}
                if [ "$cycle_count" -lt 1 ]; then
                    echo "BCL run directory has no L###/C*.1 cycle directories under $lane_root" >> {log:q}
                    exit 2
                fi
                file_list="$scratch_sync_log_dir/basecall_files.nul"
                find "$lane_root" -mindepth 2 -type f -printf '%P\0' > "$file_list"
                file_count="$(tr -cd "\0" < "$file_list" | wc -c | tr -d " ")"
                echo "mounted_stage_regular_files: $file_count" >> {log:q}
                if [ "$file_count" -lt 1 ]; then
                    echo "BCL run directory has no regular files under $lane_root" >> {log:q}
                    exit 2
                fi
                echo "Copying mounted BCL files with sharded cp: $(date -Is)" >> {log:q}
                if ! xargs -0 -r -P "$mounted_stage_jobs" -n 64 bash -c '
                    set -euo pipefail
                    lane_root="$1"
                    scratch_run_dir="$2"
                    shift 2
                    for rel in "$@"; do
                        src="$lane_root/$rel"
                        dst="$scratch_run_dir/Data/Intensities/BaseCalls/$(dirname "$rel")"
                        mkdir -p "$dst"
                        cp -L --sparse=always "$src" "$dst/"
                    done
                ' _ "$lane_root" "$scratch_run_dir" \
                  < "$file_list" > "$stage_files_log" 2>&1; then
                    cat "$stage_metadata_log" "$stage_files_log" >> {log:q} || true
                    echo "One or more mounted BCL file copy batches failed" >> {log:q}
                    exit 2
                fi
                cat "$stage_metadata_log" "$stage_files_log" >> {log:q} || true
                echo "Mounted scratch staging complete: $(date -Is)" >> {log:q}
                du -sh "$scratch_run_dir" >> {log:q} 2>&1 || true
                effective_run_dir="$scratch_run_dir"
                effective_output_dir="$scratch_output_dir"
                df -h "$scratch_root" >> {log:q} 2>&1 || true
                ;;
            s3_dev_shm)
                mkdir -p "$scratch_root"
                scratch_dir="$scratch_root/${{SLURM_JOB_ID:-local}}.$$"
                scratch_run_dir="$scratch_dir/run"
                scratch_output_dir="$scratch_dir/fastqs"
                scratch_sync_log_dir="$scratch_dir/aws_sync_logs"
                mkdir -p "$scratch_run_dir" "$scratch_sync_log_dir"
                source_s3_uri={params.source_s3_uri:q}
                run_region={params.region:q}
                run_profile={params.profile:q}
                if [ -z "$source_s3_uri" ]; then
                    echo "bclconvert.staging_mode=s3_dev_shm requires SOURCE_S3_URI in config/runs.tsv" >> {log:q}
                    exit 2
                fi
                if [ -z "$run_region" ]; then
                    echo "bclconvert.staging_mode=s3_dev_shm requires REGION in config/runs.tsv" >> {log:q}
                    exit 2
                fi
                command -v aws >> {log:q} 2>&1
                echo "s3_stage_submit_profile: $run_profile" >> {log:q}
                echo "s3_stage_credential_mode: compute_instance_role" >> {log:q}
                AWS_REGION="$run_region" AWS_DEFAULT_REGION="$run_region" AWS_MAX_ATTEMPTS=10 AWS_RETRY_MODE=adaptive \
                  aws sts get-caller-identity >> {log:q} 2>&1
                input_disk_bytes="$(du -sB1 "$effective_run_dir" | awk '{{print $1}}')"
                input_apparent_bytes="$(du -sb "$effective_run_dir" | awk '{{print $1}}')"
                required_bytes="$((input_disk_bytes * {params.scratch_size_multiplier} + 1073741824))"
                scratch_parent="$(dirname "$scratch_root")"
                available_bytes="$(df -PB1 "$scratch_parent" | awk 'NR == 2 {{print $4}}')"
                echo "scratch_dir: $scratch_dir" >> {log:q}
                echo "scratch_input_disk_bytes: $input_disk_bytes" >> {log:q}
                echo "scratch_input_apparent_bytes: $input_apparent_bytes" >> {log:q}
                echo "scratch_required_bytes: $required_bytes" >> {log:q}
                echo "scratch_available_bytes: $available_bytes" >> {log:q}
                if [ "$available_bytes" -lt "$required_bytes" ]; then
                    echo "Insufficient scratch for bclconvert.staging_mode=s3_dev_shm: required=$required_bytes available=$available_bytes" >> {log:q}
                    exit 2
                fi
                run_uri=$(printf "%s" "$source_s3_uri" | sed 's:/*$::')
                lane_root="$effective_run_dir/Data/Intensities/BaseCalls"
                if [ ! -d "$lane_root" ]; then
                    echo "BCL run directory is missing lane root: $lane_root" >> {log:q}
                    exit 2
                fi
                lane_ids=$(find "$lane_root" -mindepth 1 -maxdepth 1 -type d -name 'L[0-9][0-9][0-9]' -printf '%f\n' | sort)
                if [ -z "$lane_ids" ]; then
                    echo "BCL run directory has no L### lane directories under $lane_root" >> {log:q}
                    exit 2
                fi
                echo "Staging BCL run directory from S3 to scratch: $(date -Is)" >> {log:q}
                echo "s3_stage_lanes: $(printf "%s" "$lane_ids" | tr '\n' ' ')" >> {log:q}
                if ! AWS_REGION="$run_region" AWS_DEFAULT_REGION="$run_region" AWS_MAX_ATTEMPTS=10 AWS_RETRY_MODE=adaptive \
                  aws s3 sync "$run_uri/" "$scratch_run_dir/" \
                    --exclude "Analysis/*" \
                    --exclude "Data/Intensities/BaseCalls/L*/*" \
                    --only-show-errors \
                    > "$scratch_sync_log_dir/root.log" 2>&1; then
                    cat "$scratch_sync_log_dir/root.log" >> {log:q}
                    echo "Root-level aws s3 sync failed" >> {log:q}
                    exit 2
                fi
                pids=()
                for lane_id in $lane_ids; do
                    (
                        AWS_REGION="$run_region" AWS_DEFAULT_REGION="$run_region" AWS_MAX_ATTEMPTS=10 AWS_RETRY_MODE=adaptive \
                          aws s3 sync "$run_uri/Data/Intensities/BaseCalls/$lane_id/" "$scratch_run_dir/Data/Intensities/BaseCalls/$lane_id/" \
                            --only-show-errors
                    ) > "$scratch_sync_log_dir/$lane_id.log" 2>&1 &
                    pids+=("$!")
                done
                sync_rc=0
                for pid in "${{pids[@]}}"; do
                    if ! wait "$pid"; then
                        sync_rc=1
                    fi
                done
                cat "$scratch_sync_log_dir"/*.log >> {log:q}
                if [ "$sync_rc" -ne 0 ]; then
                    echo "One or more lane-level aws s3 sync processes failed" >> {log:q}
                    exit 2
                fi
                echo "S3 scratch staging complete: $(date -Is)" >> {log:q}
                du -sh "$scratch_run_dir" >> {log:q} 2>&1 || true
                effective_run_dir="$scratch_run_dir"
                effective_output_dir="$scratch_output_dir"
                df -h "$scratch_root" >> {log:q} 2>&1 || true
                ;;
            *)
                echo "Unsupported bclconvert.staging_mode: $staging_mode" >> {log:q}
                exit 2
                ;;
        esac

        parallel_tiles={params.parallel_tiles}
        conversion_threads={params.conversion_threads}
        compression_threads={params.compression_threads}
        decompression_threads={params.decompression_threads}
        per_tile_threads="$((conversion_threads + compression_threads + decompression_threads))"
        if [ "$per_tile_threads" -lt 1 ]; then
            echo "BCLConvert per-tile thread total must be >= 1" >> {log:q}
            exit 2
        fi
        max_parallel_tiles="$(({threads} / per_tile_threads))"
        if [ "$max_parallel_tiles" -lt 1 ]; then
            echo "BCLConvert thread allocation is too small: threads={threads} per_tile_threads=$per_tile_threads" >> {log:q}
            exit 2
        fi
        if [ "$parallel_tiles" -gt "$max_parallel_tiles" ]; then
            echo "Reducing BCLConvert parallel tiles from $parallel_tiles to $max_parallel_tiles for threads={threads}" >> {log:q}
            parallel_tiles="$max_parallel_tiles"
        fi
        echo "bcl_num_parallel_tiles: $parallel_tiles" >> {log:q}
        echo "bcl_num_conversion_threads: $conversion_threads" >> {log:q}
        echo "bcl_num_compression_threads: $compression_threads" >> {log:q}
        echo "bcl_num_decompression_threads: $decompression_threads" >> {log:q}

        bcl_flags=(
          --bcl-input-directory "$effective_run_dir"
          --output-directory "$effective_output_dir"
          --sample-sheet {input.sample_sheet:q}
          --strict-mode {params.strict_mode}
          --first-tile-only {params.first_tile_only}
          --bcl-sampleproject-subdirectories {params.sampleproject_subdirectories}
          --fastq-gzip-compression-level {params.fastq_gzip_compression_level}
          --bcl-num-parallel-tiles "$parallel_tiles"
          --bcl-num-conversion-threads "$conversion_threads"
          --bcl-num-compression-threads "$compression_threads"
          --bcl-num-decompression-threads "$decompression_threads"
          --shared-thread-odirect-output {params.shared_thread_odirect_output}
        )
        force_arg={params.force:q}
        if [ -n "$force_arg" ]; then
            bcl_flags+=("$force_arg")
        fi

        printf 'bcl-convert command:' >> {log:q}
        printf ' %q' singularity exec {params.container_uri:q} bcl-convert "${{bcl_flags[@]}}" >> {log:q}
        printf '\n' >> {log:q}
        singularity exec {params.container_uri:q} bcl-convert "${{bcl_flags[@]}}" >> {log:q} 2>&1

        if [ "$staging_mode" = "dev_shm" ] || [ "$staging_mode" = "mounted_dev_shm" ] || [ "$staging_mode" = "s3_dev_shm" ] || [ "$staging_mode" = "output_dev_shm" ]; then
            echo "Copying BCLConvert outputs from scratch to result tree: $(date -Is)" >> {log:q}
            cp -a "$effective_output_dir"/. {BCL_FASTQ_DIR:q}/
            df -h "$scratch_root" {BCL_FASTQ_DIR:q} >> {log:q} 2>&1 || true
        fi
        test -s {output.fastq_list:q}
        test -s {output.demux_stats:q}
        echo "run_bclconvert finished: $(date -Is)" >> {log:q}
        touch {output.done:q}
        """


rule bclconvert_generate_units_tsv:
    input:
        done=BCL_DONE,
        fastq_list=f"{BCL_REPORT_DIR}/fastq_list.csv",
        sample_sheet_rows=BCL_SAMPLESHEET_ROWS,
    output:
        units=f"{BCL_TABLE_DIR}/generated.units.tsv",
    threads:
        1
    conda:
        BCL_METRICS_ENV
    params:
        cluster_sample="bclconvert_generate_units_tsv",
        run_id=BCL_RUN_ID,
        libprep=BCL_LIBPREP,
        seq_vendor=BCL_SEQ_VENDOR,
        seq_platform_override=BCL_SEQ_PLATFORM_OVERRIDE,
    log:
        f"{BCL_LOG_DIR}/bclconvert_generate_units_tsv.log",
    benchmark:
        f"{BCL_BENCH_DIR}/bclconvert_generate_units_tsv.bench.tsv",
    shell:
        r"""
        set -euo pipefail
        : > {log:q}
        seq_platform_override={params.seq_platform_override:q}
        python workflow/scripts/bclconvert_fastq_list_to_units.py \
          --fastq-list {input.fastq_list:q} \
          --sample-sheet-rows {input.sample_sheet_rows:q} \
          --run-id {params.run_id:q} \
          --libprep {params.libprep:q} \
          --seq-vendor {params.seq_vendor:q} \
          --seq-platform-override "$seq_platform_override" \
          --units-out {output.units:q} \
          >> {log:q} 2>&1
        """


rule bclconvert_metrics_summary:
    input:
        done=BCL_DONE,
        demux=f"{BCL_REPORT_DIR}/Demultiplex_Stats.csv",
        fastq_list=f"{BCL_REPORT_DIR}/fastq_list.csv",
    output:
        demux_tsv=f"{BCL_METRIC_DIR}/demultiplex_stats.tsv",
        unknown_tsv=f"{BCL_METRIC_DIR}/unknown_barcodes.tsv",
        hopping_tsv=f"{BCL_METRIC_DIR}/index_hopping.tsv",
        fastq_manifest_tsv=f"{BCL_METRIC_DIR}/fastq_manifest.tsv",
        rollup_json=f"{BCL_METRIC_DIR}/rollup.json",
    threads:
        1
    conda:
        BCL_METRICS_ENV
    params:
        cluster_sample="bclconvert_metrics_summary",
    log:
        f"{BCL_LOG_DIR}/bclconvert_metrics_summary.log",
    benchmark:
        f"{BCL_BENCH_DIR}/bclconvert_metrics_summary.bench.tsv",
    shell:
        r"""
        set -euo pipefail
        mkdir -p {BCL_METRIC_DIR:q}
        : > {log:q}
        python workflow/scripts/bclconvert_metrics_summary.py \
          --report-dir {BCL_REPORT_DIR:q} \
          --demux-out {output.demux_tsv:q} \
          --unknown-out {output.unknown_tsv:q} \
          --hopping-out {output.hopping_tsv:q} \
          --fastq-manifest-out {output.fastq_manifest_tsv:q} \
          --rollup-json-out {output.rollup_json:q} \
          >> {log:q} 2>&1
        """


rule bclconvert_metrics_multiqc_exports:
    input:
        demux_tsv=f"{BCL_METRIC_DIR}/demultiplex_stats.tsv",
        unknown_tsv=f"{BCL_METRIC_DIR}/unknown_barcodes.tsv",
        hopping_tsv=f"{BCL_METRIC_DIR}/index_hopping.tsv",
        fastq_manifest_tsv=f"{BCL_METRIC_DIR}/fastq_manifest.tsv",
        rollup_json=f"{BCL_METRIC_DIR}/rollup.json",
    output:
        demux_mqc=f"{BCL_MQC_DIR}/bclconvert_demux_mqc.tsv",
        unknown_mqc=f"{BCL_MQC_DIR}/bclconvert_unknown_barcodes_mqc.tsv",
        hopping_mqc=f"{BCL_MQC_DIR}/bclconvert_index_hopping_mqc.tsv",
        fastq_manifest_mqc=f"{BCL_MQC_DIR}/bclconvert_fastq_manifest_mqc.tsv",
        lane_summary_mqc=f"{BCL_MQC_DIR}/bclconvert_lane_summary_mqc.tsv",
        done=touch(BCL_MQC_COMPLETE),
    threads:
        1
    conda:
        BCL_METRICS_ENV
    params:
        cluster_sample="bclconvert_metrics_multiqc_exports",
    log:
        f"{BCL_MQC_LOG_DIR}/bclconvert_metrics_multiqc_exports.log",
    benchmark:
        f"{BCL_BENCH_DIR}/bclconvert_metrics_multiqc_exports.bench.tsv",
    shell:
        r"""
        set -euo pipefail
        mkdir -p {BCL_MQC_DIR:q} {BCL_MQC_LOG_DIR:q}
        : > {log:q}
        python workflow/scripts/bclconvert_metrics_to_multiqc.py \
          --demux-tsv {input.demux_tsv:q} \
          --unknown-tsv {input.unknown_tsv:q} \
          --hopping-tsv {input.hopping_tsv:q} \
          --fastq-manifest-tsv {input.fastq_manifest_tsv:q} \
          --rollup-json {input.rollup_json:q} \
          --demux-out {output.demux_mqc:q} \
          --unknown-out {output.unknown_mqc:q} \
          --hopping-out {output.hopping_mqc:q} \
          --fastq-manifest-out {output.fastq_manifest_mqc:q} \
          --lane-summary-out {output.lane_summary_mqc:q} \
          >> {log:q} 2>&1
        """


rule multiqc_bclconvert:
    input:
        done=BCL_DONE,
        demux=f"{BCL_REPORT_DIR}/Demultiplex_Stats.csv",
        fastq_list=f"{BCL_REPORT_DIR}/fastq_list.csv",
        mqc_exports=BCL_MQC_COMPLETE,
    output:
        html=f"{BCL_REPORT_OUT_DIR}/multiqc_report.html" if BCL_RUN_CONTEXT is not None else f"{BCL_REPORT_OUT_DIR}/bclconvert.multiqc.html",
    threads:
        1
    conda:
        MULTIQC_ENV
    params:
        cluster_sample="multiqc_bclconvert",
        multiqc_cfg=MULTIQC_CONFIG,
        multiqc_filename="multiqc_report.html" if BCL_RUN_CONTEXT is not None else "bclconvert.multiqc.html",
    log:
        f"{BCL_LOG_DIR}/multiqc_bclconvert.log",
    benchmark:
        f"{BCL_BENCH_DIR}/multiqc_bclconvert.bench.tsv",
    shell:
        r"""
        set -euo pipefail
        mkdir -p {BCL_REPORT_OUT_DIR:q}
        : > {log:q}
        multiqc -f \
          -m bclconvert \
          -m custom_content \
          --config {params.multiqc_cfg:q} \
          --template default \
          --filename {params.multiqc_filename:q} \
          --outdir {BCL_REPORT_OUT_DIR:q} \
          {BCL_REPORT_DIR:q} \
          {BCL_MQC_DIR:q} \
          >> {log:q} 2>&1
        test -s {output.html:q}
        """


rule produce_bclconvert_fastqs:
    input:
        BCL_VALIDATE_OK,
        BCL_DONE,
    output:
        touch(BCL_FASTQS_COMPLETE),
    shell:
        "touch {output}"


rule produce_bclconvert_metrics:  # TARGET: gather BCL Convert metrics into genome-build MultiQC custom-data TSVs
    input:
        BCL_MQC_COMPLETE,


rule produce_bclconvert_multiqc:  # TARGET: gather BCL Convert metrics and build a focused MultiQC report
    input:
        f"{BCL_REPORT_OUT_DIR}/multiqc_report.html" if BCL_RUN_CONTEXT is not None else f"{BCL_REPORT_OUT_DIR}/bclconvert.multiqc.html",


rule produce_bclconvert_fastqs_and_metrics:
    input:
        BCL_VALIDATE_OK,
        BCL_DONE,
        f"{BCL_TABLE_DIR}/generated.units.tsv",
        f"{BCL_METRIC_DIR}/demultiplex_stats.tsv",
        f"{BCL_METRIC_DIR}/unknown_barcodes.tsv",
        f"{BCL_METRIC_DIR}/index_hopping.tsv",
        f"{BCL_METRIC_DIR}/fastq_manifest.tsv",
        f"{BCL_METRIC_DIR}/rollup.json",
        BCL_MQC_COMPLETE,
        f"{BCL_REPORT_OUT_DIR}/multiqc_report.html" if BCL_RUN_CONTEXT is not None else f"{BCL_REPORT_OUT_DIR}/bclconvert.multiqc.html",
    output:
        touch(BCL_BOOTSTRAP_COMPLETE),
    shell:
        "touch {output}"
