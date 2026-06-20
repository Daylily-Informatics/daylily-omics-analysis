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


def _optional_nonnegative_int(value, *, name):
    if value in (None, "", "None"):
        return 0
    try:
        parsed = int(str(value).strip())
    except Exception as exc:
        raise WorkflowError(f"bclconvert.{name} must be a non-negative integer") from exc
    if parsed < 0:
        raise WorkflowError(f"bclconvert.{name} must be a non-negative integer")
    return parsed


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
BCL_REQUESTED_TARGETS = _requested_targets()
BCL_RUNTIME_VERSION = "4.0.3"
BCL_TARGET_REQUESTED = bool(BCL_REQUESTED_TARGETS & BCL_BOOTSTRAP_TARGETS)
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
BCL_DEMUX_FASTQC_ROOT = f"{BCL_ROOT}/demux_fastq_qc"
BCL_DEMUX_FASTQC_INPUT_DIR = f"{BCL_DEMUX_FASTQC_ROOT}/inputs"
BCL_DEMUX_FASTQC_OUTPUT_DIR = f"{BCL_DEMUX_FASTQC_ROOT}/fastqc"
BCL_DEMUX_FASTQC_TMP_DIR = f"{BCL_DEMUX_FASTQC_ROOT}/tmp"
BCL_DEMUX_FASTQC_MANIFEST = f"{BCL_DEMUX_FASTQC_ROOT}/demux_fastqc_inputs.tsv"
BCL_DEMUX_FASTQC_MQC = f"{BCL_MQC_DIR}/bclconvert_demux_fastqc_manifest_mqc.tsv"
BCL_DEMUX_FASTQC_DONE = f"{BCL_DEMUX_FASTQC_ROOT}/demux_fastqc.done"

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
FASTQC_ENV = "../envs/fastqc_v0.1.yaml"
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
BCL_MEM_MB = _intish(BCLCFG.get("mem_mb", 50000), 50000)
BCL_PARTITION = str(BCLCFG.get("partition", "i192hugenvme,i192nvme,i384nvme") or "i192hugenvme,i192nvme,i384nvme")
BCL_CONSTRAINT = str(BCLCFG.get("constraint", "") or "")
BCL_EXCLUSIVE = str(BCLCFG.get("exclusive", "--exclusive") or "")
BCL_TMPDIR = str(BCLCFG.get("tmpdir", "/dev/shm") or "/dev/shm")
BCL_SCRATCH_OUTPUT_ROOT = str(BCLCFG.get("scratch_output_root", "") or "").rstrip("/")
BCL_SCRATCH_AVAILABLE_BYTES_MIN = _intish(BCLCFG.get("scratch_available_bytes_min", 0), 0)
BCL_PARALLEL_TILES = _intish(BCLCFG.get("parallel_tiles", 1), 1)
BCL_CONVERSION_THREADS = _intish(BCLCFG.get("conversion_threads", BCL_THREADS), BCL_THREADS)
BCL_COMPRESSION_THREADS = _intish(BCLCFG.get("compression_threads", BCL_THREADS), BCL_THREADS)
BCL_DECOMPRESSION_THREADS = _intish(BCLCFG.get("decompression_threads", max(1, BCL_THREADS // 2)), max(1, BCL_THREADS // 2))
BCL_FASTQ_GZIP_COMPRESSION_LEVEL = _intish(BCLCFG.get("fastq_gzip_compression_level", 1), 1)
BCL_SHARED_THREAD_ODIRECT_OUTPUT_RAW = BCLCFG.get("shared_thread_odirect_output", False)
BCL_OUTPUT_LEGACY_STATS = _bool(BCLCFG.get("output_legacy_stats", True), True)
BCL_NUM_UNKNOWN_BARCODES_REPORTED = _intish(BCLCFG.get("num_unknown_barcodes_reported", 1000), 1000)
BCL_DEMUX_QC_THREADS = _intish(BCLCFG.get("demux_qc_threads", min(max(BCL_THREADS, 1), 32)), min(max(BCL_THREADS, 1), 32))
BCL_DEMUX_QC_MEM_MB = _intish(BCLCFG.get("demux_qc_mem_mb", 64000), 64000)
BCL_FORCE = _bool(BCLCFG.get("force", False))
BCL_MERGE_LANE_FASTQS = _bool(BCLCFG.get("merge_lane_fastqs", False), False)
BCL_MERGE_TILE_FASTQS = _bool(BCLCFG.get("merge_tile_fastqs", False), False)
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
DAYOA_BCLCONVERT_TILE_SHARDS = True
BCL_TILE_SHARD_LEVEL = str(BCLCFG.get("tile_shard_level", "lane") or "lane").strip().lower()
BCL_TILE_SHARD_LANES_RAW = BCLCFG.get("tile_shard_lanes", "")
BCL_TILE_SHARD_TILE_LIMIT = _optional_nonnegative_int(
    BCLCFG.get("tile_shard_tile_limit", 0),
    name="tile_shard_tile_limit",
)
BCL_TILE_SHARD_TILE_NAMES_RAW = BCLCFG.get("tile_shard_tile_names", "")
BCL_TILE_SHARD_THREADS = _intish(BCLCFG.get("tile_shard_threads", BCL_THREADS), BCL_THREADS)
BCL_TILE_SHARD_MEM_MB = _intish(
    BCLCFG.get("tile_shard_mem_mb", max(50000, BCL_MEM_MB // 4)),
    max(50000, BCL_MEM_MB // 4),
)
BCL_TILE_PARALLEL_TILES = _intish(BCLCFG.get("tile_parallel_tiles", BCL_PARALLEL_TILES), BCL_PARALLEL_TILES)
BCL_TILE_CONVERSION_THREADS = _intish(
    BCLCFG.get("tile_conversion_threads", BCL_CONVERSION_THREADS),
    BCL_CONVERSION_THREADS,
)
BCL_TILE_COMPRESSION_THREADS = _intish(
    BCLCFG.get("tile_compression_threads", BCL_COMPRESSION_THREADS),
    BCL_COMPRESSION_THREADS,
)
BCL_TILE_DECOMPRESSION_THREADS = _intish(
    BCLCFG.get("tile_decompression_threads", BCL_DECOMPRESSION_THREADS),
    BCL_DECOMPRESSION_THREADS,
)

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
BCL_DISCOVER_LANES_FOR_TARGET = BCL_TARGET_REQUESTED or (
    bool(BCL_REQUESTED_TARGETS)
    and bool(BCLCFG)
    and _filled(BCL_RUN_DIR)
    and BCL_TILE_SHARD_LANES_RAW in (None, "", "None", [])
)
if BCL_DISCOVER_LANES_FOR_TARGET:
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
BCL_LANE_REPORT_DIRS = expand(f"{BCL_LANE_FASTQ_ROOT}/{{lane}}/Reports", lane=BCL_LANES)


def _bcl_lane_name(value):
    text = str(value or "").strip()
    if text.upper().startswith("L"):
        text = text[1:]
    return f"L{int(text):03d}"


if not BCL_LANES and BCL_TILE_SHARD_LANES_RAW not in (None, "", "None", []):
    BCL_LANES = sorted(
        {
            _bcl_lane_name(value)
            for value in (
                [part.strip() for part in BCL_TILE_SHARD_LANES_RAW.split(",") if part.strip()]
                if isinstance(BCL_TILE_SHARD_LANES_RAW, str)
                else list(BCL_TILE_SHARD_LANES_RAW)
            )
        }
    )


def _bcl_tile_lane_set(raw):
    if raw in (None, "", "None", []):
        return set(BCL_LANES)
    values = [part.strip() for part in raw.split(",") if part.strip()] if isinstance(raw, str) else list(raw)
    lanes = {_bcl_lane_name(value) for value in values}
    unknown = sorted(lanes - set(BCL_LANES))
    if unknown:
        raise WorkflowError("bclconvert.tile_shard_lanes includes absent lanes: " + ",".join(unknown))
    return lanes


def _bcl_lane_tile_names(lane):
    lane_num = int(lane[1:])
    lane_dir = BCL_LANE_ROOT / lane
    if not lane_dir.is_dir():
        raise WorkflowError(f"BCL lane directory is missing for tile sharding: {lane_dir}")
    pattern = re.compile(rf"s_{lane_num}_[0-9]{{4}}")
    names = sorted(
        {
            path.stem
            for path in lane_dir.glob(f"s_{lane_num}_*.filter")
            if pattern.fullmatch(path.stem)
        }
    )
    if not names:
        raise WorkflowError(f"BCL lane has no filter tile names for tile sharding: {lane_dir}")
    return names


def _bcl_config_tile_names(raw, lane):
    if raw in (None, "", "None", []):
        return []
    values = [part.strip() for part in raw.split(",") if part.strip()] if isinstance(raw, str) else list(raw)
    lane_num = int(lane[1:])
    names = []
    for value in values:
        text = str(value or "").strip()
        if not text:
            continue
        if re.fullmatch(r"[0-9]+", text):
            text = f"s_{lane_num}_{int(text):04d}"
        if not re.fullmatch(rf"s_{lane_num}_[0-9]{{4}}", text):
            raise WorkflowError(
                "bclconvert.tile_shard_tile_names entries must be numeric tile ids "
                f"or exact {lane} tile names like s_{lane_num}_0001"
            )
        names.append(text)
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates:
        raise WorkflowError("bclconvert.tile_shard_tile_names contains duplicates: " + ",".join(duplicates))
    return names


def _bcl_selected_tile_names(lane, discovered_tile_names):
    configured = _bcl_config_tile_names(BCL_TILE_SHARD_TILE_NAMES_RAW, lane)
    if configured:
        missing = sorted(set(configured) - set(discovered_tile_names))
        if missing:
            raise WorkflowError(
                "bclconvert.tile_shard_tile_names includes absent tiles for "
                f"{lane}: " + ",".join(missing)
            )
        return configured
    if BCL_TILE_SHARD_TILE_LIMIT:
        if BCL_TILE_SHARD_TILE_LIMIT > len(discovered_tile_names):
            raise WorkflowError(
                f"bclconvert.tile_shard_tile_limit={BCL_TILE_SHARD_TILE_LIMIT} exceeds "
                f"{lane} discovered tile count {len(discovered_tile_names)}"
            )
        return discovered_tile_names[:BCL_TILE_SHARD_TILE_LIMIT]
    return discovered_tile_names


def _bcl_exact_tile_regex(tile_names):
    return "+".join(re.escape(name) for name in tile_names)


def _bcl_balanced_tile_shards(lane, shard_count):
    tile_names = _bcl_selected_tile_names(lane, _bcl_lane_tile_names(lane))
    tile_count = len(tile_names)
    if shard_count < 2:
        return []
    if shard_count > tile_count:
        raise WorkflowError(
            f"bclconvert.tile_shard_level={shard_count} cannot split {lane} "
            f"with only {tile_count} discovered tiles"
        )
    base_size = tile_count // shard_count
    remainder = tile_count % shard_count
    rows = []
    start = 0
    for index in range(shard_count):
        shard_size = base_size + (1 if index < remainder else 0)
        stop = start + shard_size
        rows.append(
            {
                "shard": f"{index + 1:04d}_tiles{start + 1:04d}-{stop:04d}",
                "tiles": _bcl_exact_tile_regex(tile_names[start:stop]),
            }
        )
        start = stop
    return rows


def _bcl_tile_shards_for_lane(lane):
    if BCL_TILE_SHARD_LEVEL in {"", "0", "1", "lane", "none", "false"}:
        return []
    if BCL_TILE_SHARD_LEVEL in {"tile_smoke", "tiles", "selected_tiles"}:
        tile_names = _bcl_selected_tile_names(lane, _bcl_lane_tile_names(lane))
        if not (BCL_TILE_SHARD_TILE_LIMIT or _bcl_config_tile_names(BCL_TILE_SHARD_TILE_NAMES_RAW, lane)):
            raise WorkflowError(
                "bclconvert.tile_shard_level=tile_smoke requires tile_shard_tile_limit "
                "or tile_shard_tile_names"
            )
        return [
            {
                "shard": f"0001_tiles0001-{len(tile_names):04d}",
                "tiles": _bcl_exact_tile_regex(tile_names),
            }
        ]
    if BCL_TILE_SHARD_LEVEL.isdigit():
        return _bcl_balanced_tile_shards(lane, int(BCL_TILE_SHARD_LEVEL))
    if BCL_TILE_SHARD_LEVEL in {"2", "surface"}:
        return _bcl_balanced_tile_shards(lane, 2)
    if BCL_TILE_SHARD_LEVEL in {"4", "surface_swath_pair", "surface-swath-pair"}:
        return _bcl_balanced_tile_shards(lane, 4)
    if BCL_TILE_SHARD_LEVEL in {"8", "swath", "surface_swath", "surface-swath"}:
        return _bcl_balanced_tile_shards(lane, 8)
    raise WorkflowError(
        "bclconvert.tile_shard_level must be lane, none, tile_smoke, surface, surface_swath, "
        "or an integer shard count no larger than the discovered lane tile count"
    )


BCL_TILE_SHARD_LANE_SET = _bcl_tile_lane_set(BCL_TILE_SHARD_LANES_RAW)
BCL_TILE_SHARD_ROWS = [
    {"lane": lane, **shard}
    for lane in BCL_LANES
    if lane in BCL_TILE_SHARD_LANE_SET
    for shard in _bcl_tile_shards_for_lane(lane)
]
BCL_TILE_SHARDS_BY_LANE = {
    lane: [row for row in BCL_TILE_SHARD_ROWS if row["lane"] == lane]
    for lane in BCL_LANES
}
BCL_TILE_SHARDING_ACTIVE = bool(BCL_TILE_SHARD_ROWS)
if str(BCL_SHARED_THREAD_ODIRECT_OUTPUT_RAW).strip().lower() in {"", "auto", "none"}:
    BCL_SHARED_THREAD_ODIRECT_OUTPUT = False
else:
    BCL_SHARED_THREAD_ODIRECT_OUTPUT = _bool(BCL_SHARED_THREAD_ODIRECT_OUTPUT_RAW, False)
BCL_REQUESTED_LANES = [lane for lane in BCL_LANES if lane in BCL_TILE_SHARD_LANE_SET]
BCL_DIRECT_LANES = [lane for lane in BCL_REQUESTED_LANES if not BCL_TILE_SHARDS_BY_LANE.get(lane)]
BCL_TILE_LANES = [lane for lane in BCL_REQUESTED_LANES if BCL_TILE_SHARDS_BY_LANE.get(lane)]
BCL_LANES = BCL_REQUESTED_LANES
BCL_LANE_DONE_FILES = expand(f"{BCL_LANE_REPORT_ROOT}/{{lane}}/bclconvert.done", lane=BCL_LANES)
BCL_LANE_FASTQ_LIST_FILES = expand(f"{BCL_LANE_FASTQ_ROOT}/{{lane}}/Reports/fastq_list.csv", lane=BCL_LANES)
BCL_LANE_DEMUX_STATS_FILES = expand(f"{BCL_LANE_FASTQ_ROOT}/{{lane}}/Reports/Demultiplex_Stats.csv", lane=BCL_LANES)
BCL_LANE_SAMPLE_SHEET_FILES = expand(f"{BCL_LANE_REPORT_ROOT}/{{lane}}/SampleSheet.csv", lane=BCL_LANES)
BCL_LANE_REPORT_DIRS = expand(f"{BCL_LANE_FASTQ_ROOT}/{{lane}}/Reports", lane=BCL_LANES)
BCL_DIRECT_LANE_REGEX = "|".join(re.escape(lane) for lane in BCL_DIRECT_LANES) if BCL_DIRECT_LANES else "a^"
BCL_TILE_LANE_REGEX = "|".join(re.escape(lane) for lane in BCL_TILE_LANES) if BCL_TILE_LANES else "a^"
BCL_TILE_SHARD_REGEX = "|".join(re.escape(row["shard"]) for row in BCL_TILE_SHARD_ROWS) if BCL_TILE_SHARD_ROWS else "a^"
BCL_TILE_REGEX_BY_KEY = {f'{row["lane"]}/{row["shard"]}': row["tiles"] for row in BCL_TILE_SHARD_ROWS}
BCL_TILE_FASTQ_ROOT = f"{BCL_ROOT}/tile_fastqs"
BCL_TILE_REPORT_ROOT = f"{BCL_ROOT}/tile_reports"


def _bcl_tile_shards_for_wildcards(wildcards):
    return [row["shard"] for row in BCL_TILE_SHARDS_BY_LANE.get(wildcards.lane, [])]


BCL_MERGED_FASTQ_LIST = f"{BCL_REPORT_DIR}/fastq_list.csv"
BCL_MERGED_DEMUX_STATS = f"{BCL_REPORT_DIR}/Demultiplex_Stats.csv"
if BCL_MERGE_LANE_FASTQS:
    BCL_REPORT_INPUT_FILES = [BCL_MERGED_DEMUX_STATS, BCL_MERGED_FASTQ_LIST]
    BCL_REPORT_INPUT_DIRS = [BCL_REPORT_DIR]
    BCL_FASTQ_LIST_INPUT_FILES = [BCL_MERGED_FASTQ_LIST]
else:
    BCL_REPORT_INPUT_FILES = BCL_LANE_DEMUX_STATS_FILES + BCL_LANE_FASTQ_LIST_FILES
    BCL_REPORT_INPUT_DIRS = BCL_LANE_REPORT_DIRS
    BCL_FASTQ_LIST_INPUT_FILES = BCL_LANE_FASTQ_LIST_FILES


localrules:
    bclconvert_validate_inputs,
    run_bclconvert,
    bclconvert_metrics_summary,
    bclconvert_demux_fastq_qc,
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
        lane=BCL_DIRECT_LANE_REGEX,
    threads:
        BCL_THREADS
    resources:
        partition=BCL_PARTITION,
        constraint=BCL_CONSTRAINT,
        vcpu=BCL_THREADS,
        threads=BCL_THREADS,
        mem_mb=BCL_MEM_MB,
        tmpdir=BCL_TMPDIR,
        exclusive=BCL_EXCLUSIVE,
    params:
        cluster_sample=lambda wildcards: f"run_bclconvert_{wildcards.lane}",
        run_dir=BCL_RUN_DIR,
        container_uri=BCL_CONTAINER_URI,
        tmpdir=BCL_TMPDIR,
        scratch_output_root=BCL_SCRATCH_OUTPUT_ROOT,
        scratch_available_bytes_min=BCL_SCRATCH_AVAILABLE_BYTES_MIN,
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
        force_arg="-f" if BCL_FORCE else "__dayoa_no_force__",
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
        "{params.force_arg:q} {threads:q} {log:q} {output.fastq_list:q} "
        "{output.demux_stats:q} {output.done:q} \"\" {params.scratch_output_root:q} "
        "{params.scratch_available_bytes_min:q}"


rule run_bclconvert_tile_shard:
    input:
        validated=BCL_VALIDATE_OK,
        sample_sheet=BCL_NORMALIZED_SAMPLE_SHEET,
    output:
        done=f"{BCL_TILE_REPORT_ROOT}/{{lane}}/{{shard}}/bclconvert.done",
        fastq_list=f"{BCL_TILE_FASTQ_ROOT}/{{lane}}/{{shard}}/Reports/fastq_list.csv",
        demux_stats=f"{BCL_TILE_FASTQ_ROOT}/{{lane}}/{{shard}}/Reports/Demultiplex_Stats.csv",
        lane_sample_sheet=f"{BCL_TILE_REPORT_ROOT}/{{lane}}/{{shard}}/SampleSheet.csv",
    wildcard_constraints:
        lane=BCL_TILE_LANE_REGEX,
        shard=BCL_TILE_SHARD_REGEX,
    threads:
        BCL_TILE_SHARD_THREADS
    resources:
        partition=BCL_PARTITION,
        constraint=BCL_CONSTRAINT,
        vcpu=BCL_TILE_SHARD_THREADS,
        threads=BCL_TILE_SHARD_THREADS,
        mem_mb=BCL_TILE_SHARD_MEM_MB,
        tmpdir=BCL_TMPDIR,
        exclusive=BCL_EXCLUSIVE,
    params:
        cluster_sample=lambda wildcards: f"run_bclconvert_{wildcards.lane}_{wildcards.shard}",
        run_dir=BCL_RUN_DIR,
        container_uri=BCL_CONTAINER_URI,
        tmpdir=BCL_TMPDIR,
        scratch_output_root=BCL_SCRATCH_OUTPUT_ROOT,
        scratch_available_bytes_min=BCL_SCRATCH_AVAILABLE_BYTES_MIN,
        lane_number=lambda wildcards: str(int(wildcards.lane[1:])),
        lane_output_dir=lambda wildcards: f"{BCL_TILE_FASTQ_ROOT}/{wildcards.lane}/{wildcards.shard}",
        tile_regex=lambda wildcards: BCL_TILE_REGEX_BY_KEY[f"{wildcards.lane}/{wildcards.shard}"],
        parallel_tiles=BCL_TILE_PARALLEL_TILES,
        conversion_threads=BCL_TILE_CONVERSION_THREADS,
        compression_threads=BCL_TILE_COMPRESSION_THREADS,
        decompression_threads=BCL_TILE_DECOMPRESSION_THREADS,
        fastq_gzip_compression_level=BCL_FASTQ_GZIP_COMPRESSION_LEVEL,
        shared_thread_odirect_output="true" if BCL_SHARED_THREAD_ODIRECT_OUTPUT else "false",
        output_legacy_stats="true" if BCL_OUTPUT_LEGACY_STATS else "false",
        num_unknown_barcodes_reported=BCL_NUM_UNKNOWN_BARCODES_REPORTED,
        sample_sheet_settings_json=BCL_SAMPLE_SHEET_SETTINGS_JSON,
        sample_sheet_settings_by_lane_json=BCL_SAMPLE_SHEET_SETTINGS_BY_LANE_JSON,
        force_arg="-f" if BCL_FORCE else "__dayoa_no_force__",
        strict_mode="true" if BCL_STRICT_MODE else "false",
        first_tile_only="true" if BCL_FIRST_TILE_ONLY else "false",
        sampleproject_subdirectories="true" if BCL_SAMPLEPROJECT_SUBDIRS else "false",
    log:
        f"{BCL_LOG_DIR}/run_bclconvert.{{lane}}.{{shard}}.log",
    benchmark:
        f"{BCL_BENCH_DIR}/run_bclconvert.{{lane}}.{{shard}}.bench.tsv",
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
        "{params.force_arg:q} {threads:q} {log:q} {output.fastq_list:q} "
        "{output.demux_stats:q} {output.done:q} {params.tile_regex:q} {params.scratch_output_root:q} "
        "{params.scratch_available_bytes_min:q}"


rule merge_bclconvert_tile_shards:
    input:
        done=lambda wildcards: expand(
            f"{BCL_TILE_REPORT_ROOT}/{{lane}}/{{shard}}/bclconvert.done",
            lane=[wildcards.lane],
            shard=_bcl_tile_shards_for_wildcards(wildcards),
        ),
        fastq_lists=lambda wildcards: expand(
            f"{BCL_TILE_FASTQ_ROOT}/{{lane}}/{{shard}}/Reports/fastq_list.csv",
            lane=[wildcards.lane],
            shard=_bcl_tile_shards_for_wildcards(wildcards),
        ),
        demux_stats=lambda wildcards: expand(
            f"{BCL_TILE_FASTQ_ROOT}/{{lane}}/{{shard}}/Reports/Demultiplex_Stats.csv",
            lane=[wildcards.lane],
            shard=_bcl_tile_shards_for_wildcards(wildcards),
        ),
        sample_sheet=BCL_NORMALIZED_SAMPLE_SHEET,
    output:
        done=f"{BCL_LANE_REPORT_ROOT}/{{lane}}/bclconvert.done",
        fastq_list=f"{BCL_LANE_FASTQ_ROOT}/{{lane}}/Reports/fastq_list.csv",
        demux_stats=f"{BCL_LANE_FASTQ_ROOT}/{{lane}}/Reports/Demultiplex_Stats.csv",
        lane_sample_sheet=f"{BCL_LANE_REPORT_ROOT}/{{lane}}/SampleSheet.csv",
    wildcard_constraints:
        lane=BCL_TILE_LANE_REGEX,
    threads:
        1
    resources:
        partition=BCL_PARTITION,
        constraint=BCL_CONSTRAINT,
        vcpu=1,
        threads=1,
        mem_mb=50000,
        tmpdir=BCL_TMPDIR,
    params:
        cluster_sample=lambda wildcards: f"merge_bclconvert_tile_shards_{wildcards.lane}",
        lane=lambda wildcards: wildcards.lane,
        shards=lambda wildcards: ",".join(_bcl_tile_shards_for_wildcards(wildcards)),
        merge_fastqs="true" if BCL_MERGE_TILE_FASTQS else "false",
        tile_fastq_root=BCL_TILE_FASTQ_ROOT,
        lane_output_dir=lambda wildcards: f"{BCL_LANE_FASTQ_ROOT}/{wildcards.lane}",
        report_dir=lambda wildcards: f"{BCL_LANE_FASTQ_ROOT}/{wildcards.lane}/Reports",
    log:
        f"{BCL_LOG_DIR}/merge_bclconvert_tile_shards.{{lane}}.log",
    benchmark:
        f"{BCL_BENCH_DIR}/merge_bclconvert_tile_shards.{{lane}}.bench.tsv",
    shell:
        "python workflow/scripts/merge_bclconvert_tile_shards.py "
        "--tile-fastq-root {params.tile_fastq_root:q} "
        "--lane-output-dir {params.lane_output_dir:q} "
        "--report-dir {params.report_dir:q} "
        "--lane {params.lane:q} "
        "--shards {params.shards:q} "
        "--merge-fastqs {params.merge_fastqs:q} "
        "--sample-sheet {input.sample_sheet:q} "
        "--lane-sample-sheet {output.lane_sample_sheet:q} "
        "--done {output.done:q} "
        "--log {log:q} >> {log:q} 2>&1 && "
        "test -s {output.fastq_list:q} && test -s {output.demux_stats:q}"


if BCL_MERGE_LANE_FASTQS:

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
            fastq_list=BCL_MERGED_FASTQ_LIST,
            demux_stats=BCL_MERGED_DEMUX_STATS,
        threads:
            1
        resources:
            partition=BCL_PARTITION,
            constraint=BCL_CONSTRAINT,
            vcpu=1,
            threads=1,
            mem_mb=50000,
            tmpdir="/tmp",
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
else:

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
        threads:
            1
        resources:
            partition=BCL_PARTITION,
            constraint=BCL_CONSTRAINT,
            vcpu=1,
            threads=1,
            mem_mb=50000,
            tmpdir="/tmp",
        params:
            cluster_sample="run_bclconvert_lane_fastqs_ready",
            lanes=",".join(BCL_LANES),
        log:
            f"{BCL_LOG_DIR}/run_bclconvert.lane_fastqs_ready.log",
        benchmark:
            f"{BCL_BENCH_DIR}/run_bclconvert.lane_fastqs_ready.bench.tsv",
        shell:
            r"""
            set -euo pipefail
            mkdir -p {BCL_LOG_DIR:q}
            : > {log:q}
            printf 'merge_lane_fastqs=false; lane FASTQs remain under %s for lanes %s\n' \
              {BCL_LANE_FASTQ_ROOT:q} {params.lanes:q} >> {log:q}
            touch {output.done:q}
            """


rule bclconvert_generate_units_tsv:
    input:
        done=BCL_DONE,
        fastq_lists=BCL_FASTQ_LIST_INPUT_FILES,
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
          --fastq-list {input.fastq_lists:q} \
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
        report_files=BCL_REPORT_INPUT_FILES,
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
        run_id=BCL_RUN_ID,
        report_dirs=BCL_REPORT_INPUT_DIRS,
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
          --report-dir {params.report_dirs:q} \
          --run-id {params.run_id:q} \
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


rule bclconvert_demux_fastq_qc:
    input:
        done=BCL_DONE,
        fastq_lists=BCL_FASTQ_LIST_INPUT_FILES,
    output:
        manifest=BCL_DEMUX_FASTQC_MANIFEST,
        mqc_manifest=BCL_DEMUX_FASTQC_MQC,
        done=touch(BCL_DEMUX_FASTQC_DONE),
    threads:
        BCL_DEMUX_QC_THREADS
    conda:
        FASTQC_ENV
    resources:
        partition=BCL_PARTITION,
        constraint=BCL_CONSTRAINT,
        vcpu=BCL_DEMUX_QC_THREADS,
        threads=BCL_DEMUX_QC_THREADS,
        mem_mb=BCL_DEMUX_QC_MEM_MB,
        tmpdir="/tmp",
    params:
        cluster_sample="bclconvert_demux_fastq_qc",
        run_id=BCL_RUN_ID,
        input_dir=BCL_DEMUX_FASTQC_INPUT_DIR,
        fastqc_dir=BCL_DEMUX_FASTQC_OUTPUT_DIR,
        tmp_dir=BCL_DEMUX_FASTQC_TMP_DIR,
    log:
        f"{BCL_LOG_DIR}/bclconvert_demux_fastq_qc.log",
    benchmark:
        f"{BCL_BENCH_DIR}/bclconvert_demux_fastq_qc.bench.tsv",
    shell:
        r"""
        set -euo pipefail
        rm -rf {params.input_dir:q} {params.fastqc_dir:q} {params.tmp_dir:q}
        mkdir -p {params.input_dir:q} {params.fastqc_dir:q} {params.tmp_dir:q} {BCL_MQC_DIR:q}
        : > {log:q}
        python workflow/scripts/prepare_bclconvert_demux_fastqc_inputs.py \
          --fastq-list {input.fastq_lists:q} \
          --run-id {params.run_id:q} \
          --input-dir {params.input_dir:q} \
          --manifest-out {output.manifest:q} \
          --multiqc-out {output.mqc_manifest:q} \
          --allow-report-root-remap \
          >> {log:q} 2>&1
        mapfile -t fastqc_inputs < <(awk -F '\t' 'NR > 1 {{ print $8 }}' {output.manifest:q})
        if [ "${{#fastqc_inputs[@]}}" -eq 0 ]; then
          echo "No demux FASTQ inputs were prepared for FastQC." >> {log:q}
          exit 2
        fi
        fastqc -o {params.fastqc_dir:q} -t {threads:q} -d {params.tmp_dir:q} "${{fastqc_inputs[@]}}" >> {log:q} 2>&1
        expected="${{#fastqc_inputs[@]}}"
        observed="$(find {params.fastqc_dir:q} -maxdepth 1 -name '*_fastqc.zip' -type f | wc -l | tr -d ' ')"
        if [ "$observed" != "$expected" ]; then
          echo "FastQC output count mismatch: expected $expected zip files, observed $observed" >> {log:q}
          exit 2
        fi
        """


rule multiqc_bclconvert:
    input:
        done=BCL_DONE,
        report_files=BCL_REPORT_INPUT_FILES,
        mqc_exports=BCL_MQC_COMPLETE,
        demux_fastqc=BCL_DEMUX_FASTQC_DONE,
        demux_fastqc_manifest=BCL_DEMUX_FASTQC_MQC,
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
        report_dirs=BCL_REPORT_INPUT_DIRS,
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
          -m fastqc \
          -m custom_content \
          --config {params.multiqc_cfg:q} \
          --template default \
          --filename {params.multiqc_filename:q} \
          --outdir {BCL_REPORT_OUT_DIR:q} \
          {params.report_dirs:q} \
          {BCL_DEMUX_FASTQC_OUTPUT_DIR:q} \
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
    log:
        MDIR + "logs/produce_bclconvert_fastqs.log"
    benchmark:
        "logs/benchmarks/produce_bclconvert_fastqs.bench.tsv"
    shell:
        "touch {output}"


rule produce_bclconvert_metrics:  # TARGET: gather BCL Convert metrics into genome-build MultiQC custom-data TSVs
    input:
        BCL_MQC_COMPLETE,
        BCL_DEMUX_FASTQC_MQC,
        BCL_DEMUX_FASTQC_DONE,


    log:
        MDIR + "logs/produce_bclconvert_metrics.log"
    benchmark:
        "logs/benchmarks/produce_bclconvert_metrics.bench.tsv"
rule produce_bclconvert_multiqc:  # TARGET: gather BCL Convert metrics and build a focused MultiQC report
    input:
        f"{BCL_REPORT_OUT_DIR}/multiqc_report.html" if BCL_RUN_CONTEXT is not None else f"{BCL_REPORT_OUT_DIR}/bclconvert.multiqc.html",


    log:
        MDIR + "logs/produce_bclconvert_multiqc.log"
    benchmark:
        "logs/benchmarks/produce_bclconvert_multiqc.bench.tsv"
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
        BCL_DEMUX_FASTQC_MQC,
        BCL_DEMUX_FASTQC_DONE,
        f"{BCL_REPORT_OUT_DIR}/multiqc_report.html" if BCL_RUN_CONTEXT is not None else f"{BCL_REPORT_OUT_DIR}/bclconvert.multiqc.html",
    output:
        touch(BCL_BOOTSTRAP_COMPLETE),
    log:
        MDIR + "logs/produce_bclconvert_fastqs_and_metrics.log"
    benchmark:
        "logs/benchmarks/produce_bclconvert_fastqs_and_metrics.bench.tsv"
    shell:
        "touch {output}"
