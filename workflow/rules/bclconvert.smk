import json
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
BCL_PARTITION = str(BCLCFG.get("partition", "i192mem,i192bigmem") or "i192mem,i192bigmem")
BCL_TMPDIR = str(BCLCFG.get("tmpdir", "/dev/shm") or "/dev/shm")
BCL_PARALLEL_TILES = _intish(BCLCFG.get("parallel_tiles", 1), 1)
BCL_CONVERSION_THREADS = _intish(BCLCFG.get("conversion_threads", BCL_THREADS), BCL_THREADS)
BCL_COMPRESSION_THREADS = _intish(BCLCFG.get("compression_threads", BCL_THREADS), BCL_THREADS)
BCL_DECOMPRESSION_THREADS = _intish(BCLCFG.get("decompression_threads", max(1, BCL_THREADS // 2)), max(1, BCL_THREADS // 2))
BCL_FASTQ_GZIP_COMPRESSION_LEVEL = _intish(BCLCFG.get("fastq_gzip_compression_level", 1), 1)
BCL_SHARED_THREAD_ODIRECT_OUTPUT = _bool(BCLCFG.get("shared_thread_odirect_output", True), True)
BCL_OUTPUT_LEGACY_STATS = _bool(BCLCFG.get("output_legacy_stats", True), True)
BCL_NUM_UNKNOWN_BARCODES_REPORTED = _intish(BCLCFG.get("num_unknown_barcodes_reported", 1000), 1000)
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
DAYOA_BCLCONVERT_LANE_SPLIT = True

# Barcode mismatch settings are injected through the lane sample sheet so the
# container sees the same BCL Convert contract on every lane. Other settings use
# this same path but remain unset unless config supplies explicit values.
BCL_SAMPLE_SHEET_SETTING_CONFIG_KEYS = {
    "AdapterRead1": "adapter_read1",
    "AdapterRead2": "adapter_read2",
    "AdapterBehavior": "adapter_behavior",
    "AdapterStringency": "adapter_stringency",
    "MinimumAdapterOverlap": "minimum_adapter_overlap",
    "BarcodeMismatchesIndex1": "barcode_mismatches_index1",
    "BarcodeMismatchesIndex2": "barcode_mismatches_index2",
    "CreateFastqForIndexReads": "create_fastq_for_index_reads",
    "MinimumTrimmedReadLength": "minimum_trimmed_read_length",
    "MaskShortReads": "mask_short_reads",
    "OverrideCycles": "override_cycles",
    "SoftwareVersion": "software_version",
    "TrimUMI": "trim_umi",
    "NoLaneSplitting": "no_lane_splitting",
}


def _bcl_mapping(value, *, name):
    if value in (None, "", "None"):
        return {}
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError as exc:
            raise WorkflowError(f"bclconvert.{name} must be a mapping or JSON object string") from exc
        if not isinstance(parsed, dict):
            raise WorkflowError(f"bclconvert.{name} must be a mapping or JSON object string")
        return parsed
    raise WorkflowError(f"bclconvert.{name} must be a mapping or JSON object string")


def _bcl_setting_value(config_key):
    if config_key not in BCLCFG:
        return ""
    value = BCLCFG.get(config_key)
    if value is None or value == "":
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value).strip()


BCL_SAMPLE_SHEET_SETTINGS = {
    canonical: value
    for canonical, config_key in BCL_SAMPLE_SHEET_SETTING_CONFIG_KEYS.items()
    for value in [_bcl_setting_value(config_key)]
    if value
}
BCL_SAMPLE_SHEET_SETTINGS.update(
    _bcl_mapping(BCLCFG.get("sample_sheet_settings", {}), name="sample_sheet_settings")
)
BCL_SAMPLE_SHEET_SETTINGS_BY_LANE = _bcl_mapping(
    BCLCFG.get("sample_sheet_settings_by_lane", {}), name="sample_sheet_settings_by_lane"
)
BCL_SAMPLE_SHEET_SETTINGS_JSON = json.dumps(BCL_SAMPLE_SHEET_SETTINGS, sort_keys=True)
BCL_SAMPLE_SHEET_SETTINGS_BY_LANE_JSON = json.dumps(BCL_SAMPLE_SHEET_SETTINGS_BY_LANE, sort_keys=True)

BCL_LANE_ROOT = Path(BCL_RUN_DIR) / "Data" / "Intensities" / "BaseCalls"
if BCL_TARGET_REQUESTED:
    if not BCL_LANE_ROOT.is_dir():
        raise WorkflowError(f"BCL run directory is missing lane root: {BCL_LANE_ROOT}")
    BCL_LANES = sorted(
        path.name
        for path in BCL_LANE_ROOT.iterdir()
        if path.is_dir() and re.fullmatch(r"L[0-9][0-9][0-9]", path.name)
    )
    if not BCL_LANES:
        raise WorkflowError(f"BCL run directory has no L### lane directories under {BCL_LANE_ROOT}")
else:
    BCL_LANES = []
BCL_LANE_FASTQ_ROOT = f"{BCL_ROOT}/lane_fastqs"
BCL_LANE_REPORT_ROOT = f"{BCL_ROOT}/lane_reports"
BCL_LANE_DONE_FILES = expand(f"{BCL_LANE_REPORT_ROOT}/{{lane}}/bclconvert.done", lane=BCL_LANES)
BCL_LANE_FASTQ_LIST_FILES = expand(f"{BCL_LANE_FASTQ_ROOT}/{{lane}}/Reports/fastq_list.csv", lane=BCL_LANES)
BCL_LANE_DEMUX_STATS_FILES = expand(f"{BCL_LANE_FASTQ_ROOT}/{{lane}}/Reports/Demultiplex_Stats.csv", lane=BCL_LANES)
BCL_LANE_SAMPLE_SHEET_FILES = expand(f"{BCL_LANE_REPORT_ROOT}/{{lane}}/SampleSheet.csv", lane=BCL_LANES)


localrules:
    bclconvert_validate_inputs,
    run_bclconvert,
    bclconvert_metrics_summary,
    bclconvert_generate_units_tsv,
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



rule run_bclconvert_lane:
    input:
        validated=BCL_VALIDATE_OK,
        sample_sheet=BCL_NORMALIZED_SAMPLE_SHEET,
    output:
        done=f"{BCL_LANE_REPORT_ROOT}/{{lane}}/bclconvert.done",
        fastq_list=f"{BCL_LANE_FASTQ_ROOT}/{{lane}}/Reports/fastq_list.csv",
        demux_stats=f"{BCL_LANE_FASTQ_ROOT}/{{lane}}/Reports/Demultiplex_Stats.csv",
        lane_sample_sheet=f"{BCL_LANE_REPORT_ROOT}/{{lane}}/SampleSheet.csv",
    wildcard_constraints:
        lane="L[0-9][0-9][0-9]",
    threads:
        BCL_THREADS
    resources:
        partition=BCL_PARTITION,
        vcpu=BCL_THREADS,
        threads=BCL_THREADS,
        mem_mb=BCL_MEM_MB,
        tmpdir=BCL_TMPDIR,
        exclusive="--exclusive",
    params:
        cluster_sample=lambda wildcards: f"run_bclconvert_{wildcards.lane}",
        run_dir=BCL_RUN_DIR,
        container_uri=BCL_CONTAINER_URI,
        tmpdir=BCL_TMPDIR,
        lane_number=lambda wildcards: str(int(wildcards.lane[1:])),
        lane_output_dir=lambda wildcards: f"{BCL_LANE_FASTQ_ROOT}/{wildcards.lane}",
        parallel_tiles=BCL_PARALLEL_TILES,
        conversion_threads=BCL_CONVERSION_THREADS,
        compression_threads=BCL_COMPRESSION_THREADS,
        decompression_threads=BCL_DECOMPRESSION_THREADS,
        fastq_gzip_compression_level=BCL_FASTQ_GZIP_COMPRESSION_LEVEL,
        shared_thread_odirect_output="true" if BCL_SHARED_THREAD_ODIRECT_OUTPUT else "false",
        output_legacy_stats="true" if BCL_OUTPUT_LEGACY_STATS else "false",
        num_unknown_barcodes_reported=BCL_NUM_UNKNOWN_BARCODES_REPORTED,
        sample_sheet_settings_json=BCL_SAMPLE_SHEET_SETTINGS_JSON,
        sample_sheet_settings_by_lane_json=BCL_SAMPLE_SHEET_SETTINGS_BY_LANE_JSON,
        force="-f" if BCL_FORCE else "",
        strict_mode="true" if BCL_STRICT_MODE else "false",
        first_tile_only="true" if BCL_FIRST_TILE_ONLY else "false",
        sampleproject_subdirectories="true" if BCL_SAMPLEPROJECT_SUBDIRS else "false",
    log:
        f"{BCL_LOG_DIR}/run_bclconvert.{{lane}}.log",
    benchmark:
        f"{BCL_BENCH_DIR}/run_bclconvert.{{lane}}.bench.tsv",
    shell:
        "TMPDIR={params.tmpdir:q} bash workflow/scripts/run_bclconvert_lane.sh "
        "{params.container_uri:q} {params.run_dir:q} {params.lane_output_dir:q} {input.sample_sheet:q} "
        "{params.lane_number:q} {output.lane_sample_sheet:q} {params.strict_mode:q} "
        "{params.first_tile_only:q} {params.sampleproject_subdirectories:q} "
        "{params.fastq_gzip_compression_level:q} {params.parallel_tiles:q} "
        "{params.conversion_threads:q} {params.compression_threads:q} "
        "{params.decompression_threads:q} {params.shared_thread_odirect_output:q} "
        "{params.output_legacy_stats:q} {params.num_unknown_barcodes_reported:q} "
        "{params.sample_sheet_settings_json:q} {params.sample_sheet_settings_by_lane_json:q} "
        "{params.force:q} {threads:q} {log:q} {output.fastq_list:q} "
        "{output.demux_stats:q} {output.done:q}"


rule run_bclconvert:
    input:
        validated=BCL_VALIDATE_OK,
        sample_sheet=BCL_NORMALIZED_SAMPLE_SHEET,
        lane_done=BCL_LANE_DONE_FILES,
        fastq_lists=BCL_LANE_FASTQ_LIST_FILES,
        demux_stats=BCL_LANE_DEMUX_STATS_FILES,
        lane_sample_sheets=BCL_LANE_SAMPLE_SHEET_FILES,
    output:
        done=BCL_DONE,
        fastq_list=f"{BCL_REPORT_DIR}/fastq_list.csv",
        demux_stats=f"{BCL_REPORT_DIR}/Demultiplex_Stats.csv",
    threads:
        1
    resources:
        partition=BCL_PARTITION,
        vcpu=1,
        threads=1,
        mem_mb=3000,
        tmpdir=BCL_TMPDIR,
    params:
        cluster_sample="run_bclconvert_merge_lanes",
        lanes=",".join(BCL_LANES),
        lane_fastq_root=BCL_LANE_FASTQ_ROOT,
        final_fastq_dir=BCL_FASTQ_DIR,
        report_dir=BCL_REPORT_DIR,
    log:
        f"{BCL_LOG_DIR}/run_bclconvert.merge_lanes.log",
    benchmark:
        f"{BCL_BENCH_DIR}/run_bclconvert.merge_lanes.bench.tsv",
    shell:
        "python workflow/scripts/merge_bclconvert_lanes.py "
        "--lane-fastq-root {params.lane_fastq_root:q} "
        "--final-fastq-dir {params.final_fastq_dir:q} "
        "--report-dir {params.report_dir:q} "
        "--lanes {params.lanes:q} "
        "--done {output.done:q} "
        "--log {log:q} >> {log:q} 2>&1 && "
        "test -s {output.fastq_list:q} && test -s {output.demux_stats:q}"


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
