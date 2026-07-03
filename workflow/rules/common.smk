from snakemake.utils import validate
from snakemake.exceptions import WorkflowError
import importlib.util
import csv
import re
import os
import sys
import pandas as pd

from daylily_omics_analysis.slurm.spot_partition_order import (
    SpotPartitionError,
    derive_partition_order as _derive_partition_order,
)
from daylily_omics_analysis.workflow_resources import (
    ResourceConfigError,
    derive_doppelmark_mem_mb as _derive_doppelmark_mem_mb,
)


def derive_partition_order(partition_csv):
    try:
        return _derive_partition_order(partition_csv)
    except SpotPartitionError as exc:
        raise WorkflowError(f"dynamic partition ordering failed: {exc}") from exc


def _is_dry_run():
    return any(arg in {"-n", "--dry-run", "--dryrun"} for arg in sys.argv[1:])


def derive_doppelmark_mem_mb(wildcards, input):
    try:
        return _derive_doppelmark_mem_mb(
            input.bam,
            config["doppelmark"],
            day_profile=os.environ.get("DAY_PROFILE"),
            allow_missing_input=True,
        )
    except ResourceConfigError as exc:
        raise WorkflowError(f"dynamic doppelmark memory sizing failed: {exc}") from exc


def _as_boolish(value):
    if isinstance(value, bool):
        return value
    if value in [None, ""]:
        return False
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def _as_config_list(value):
    if value in [None, "", "None"]:
        return []
    if isinstance(value, str):
        return [item.strip() for item in value.split(",") if item.strip()]
    return [str(item).strip() for item in value if str(item).strip()]


def _requested_targets():
    return {arg for arg in sys.argv[1:] if not str(arg).startswith("-")}


def _filled(value):
    return str(value or "").strip() not in {"", "None", "none", "NA", "na"}


RUN_CONTEXT_REQUIRED_COLUMNS = [
    "RUNID",
    "PLATFORM",
    "RUN_DIR",
    "SOURCE_S3_URI",
    "MOUNT_ID",
    "SAMPLE_SHEET",
    "BASECALLING_STATE",
    "RUN_STATUS",
    "OUTPUT_ROOT",
    "REGION",
    "PROFILE",
]


def _resolve_run_context_file():
    configured = config.get("run_context_file", "")
    if _filled(configured):
        path = os.path.abspath(str(configured))
        if not os.path.exists(path):
            raise WorkflowError(
                f"The run context file specified via --config run_context_file={configured} was not found."
            )
        return path

    default_path = os.path.abspath(os.path.join("config", "runs.tsv"))
    if os.path.exists(default_path):
        return default_path
    return ""


def _validate_run_context_run_id(run_id):
    if not _filled(run_id):
        raise WorkflowError("config/runs.tsv RUNID is required and must not be blank.")
    text = str(run_id).strip()
    if not re.match(r"^[A-Za-z0-9._-]+$", text):
        raise WorkflowError(
            f"config/runs.tsv RUNID contains unsupported path characters: {text!r}."
        )
    return text


def _validate_run_context_platform(platform):
    text = str(platform or "").strip().upper()
    supported = {"ILMN", "ONT", "ULTIMA", "PACBIO", "OTHER"}
    if text not in supported:
        raise WorkflowError(
            "config/runs.tsv PLATFORM must be one of "
            + ", ".join(sorted(supported))
            + f"; observed {platform!r}."
        )
    return text


def _normalize_run_context_row(row):
    normalized = {column: str(row.get(column, "") or "").strip() for column in RUN_CONTEXT_REQUIRED_COLUMNS}
    normalized["RUNID"] = _validate_run_context_run_id(normalized["RUNID"])
    normalized["PLATFORM"] = _validate_run_context_platform(normalized["PLATFORM"])
    if not _filled(normalized["RUN_DIR"]) and not _filled(normalized["SOURCE_S3_URI"]):
        raise WorkflowError(
            f"config/runs.tsv row for RUNID={normalized['RUNID']} must populate RUN_DIR or SOURCE_S3_URI."
        )
    if _filled(normalized["SOURCE_S3_URI"]) and not normalized["SOURCE_S3_URI"].startswith("s3://"):
        raise WorkflowError(
            f"config/runs.tsv SOURCE_S3_URI for RUNID={normalized['RUNID']} must start with s3://."
        )
    if (
        _filled(normalized["SOURCE_S3_URI"])
        and not _filled(normalized["RUN_DIR"])
        and not _filled(normalized["PROFILE"])
    ):
        raise WorkflowError(
            f"config/runs.tsv PROFILE for RUNID={normalized['RUNID']} is required for S3 mode."
        )
    if (
        _filled(normalized["SOURCE_S3_URI"])
        and not _filled(normalized["RUN_DIR"])
        and str(normalized["PROFILE"]).strip() == "default"
    ):
        raise WorkflowError(
            f"config/runs.tsv PROFILE for RUNID={normalized['RUNID']} must not be default."
        )
    output_root = normalized["OUTPUT_ROOT"].rstrip("/")
    if not _filled(output_root):
        output_root = f"results/runs/{normalized['RUNID']}"
    normalized["OUTPUT_ROOT_RESOLVED"] = output_root
    return normalized


def _load_run_context_rows():
    path = _resolve_run_context_file()
    if not path:
        config["run_context_file"] = ""
        return []

    df = pd.read_csv(path, sep="\t", dtype=str, keep_default_na=False)
    df.columns = [column.upper() for column in df.columns]
    missing = [column for column in RUN_CONTEXT_REQUIRED_COLUMNS if column not in df.columns]
    if missing:
        raise WorkflowError(
            "config/runs.tsv is missing required column(s): " + ", ".join(missing)
        )
    if df.empty:
        raise WorkflowError("config/runs.tsv has headers but no run rows.")

    config["run_context_file"] = path
    return [_normalize_run_context_row(row) for row in df.to_dict(orient="records")]


RUN_CONTEXT_ROWS = _load_run_context_rows()
RUN_CONTEXT_BY_RUNID = {row["RUNID"]: row for row in RUN_CONTEXT_ROWS}
RUN_CONTEXTS_BY_PLATFORM = {}
for _run_context_row in RUN_CONTEXT_ROWS:
    RUN_CONTEXTS_BY_PLATFORM.setdefault(
        _run_context_row["PLATFORM"], _run_context_row
    )

RUN_CONTEXT_RUN_ID_OVERRIDE = str(
    config.get("run_context_run_id", config.get("run_id", "")) or ""
).strip()
if RUN_CONTEXT_RUN_ID_OVERRIDE and RUN_CONTEXT_RUN_ID_OVERRIDE not in RUN_CONTEXT_BY_RUNID:
    raise WorkflowError(
        f"--config run_context_run_id={RUN_CONTEXT_RUN_ID_OVERRIDE} was not found in config/runs.tsv."
    )


def run_context_for_platform(platform=None, *, require=False):
    if not RUN_CONTEXT_ROWS:
        if require:
            raise WorkflowError(
                "This run-analysis target requires config/runs.tsv or --config run_context_file=/path/to/runs.tsv."
            )
        return None

    platform_key = str(platform or "").strip().upper()
    if RUN_CONTEXT_RUN_ID_OVERRIDE:
        row = RUN_CONTEXT_BY_RUNID[RUN_CONTEXT_RUN_ID_OVERRIDE]
        if platform_key and row["PLATFORM"] != platform_key:
            raise WorkflowError(
                f"Run context {RUN_CONTEXT_RUN_ID_OVERRIDE} has PLATFORM={row['PLATFORM']}, not {platform_key}."
            )
        return row

    if platform_key:
        row = RUN_CONTEXTS_BY_PLATFORM.get(platform_key)
        if row is None and require:
            raise WorkflowError(f"config/runs.tsv has no row with PLATFORM={platform_key}.")
        return row

    return RUN_CONTEXT_ROWS[0]


def run_context_output_root(platform=None, *, require=False):
    row = run_context_for_platform(platform, require=require)
    if row is None:
        return ""
    return row["OUTPUT_ROOT_RESOLVED"].rstrip("/")


config["_run_context_rows"] = RUN_CONTEXT_ROWS
config["_run_context_run_ids"] = sorted(RUN_CONTEXT_BY_RUNID)


MULTIQC_QC_LONG_RUNNING_TOOLS = {
    "contam_identity",
    "metagenomics",
    "unmapped_metagenomics",
    "unmapped_metagenomics_ganon2",
    "unmapped_metagenomics_sourmash",
    "vep",
}

SUPPORTED_HTD_CALLERS = (
    "gauchian",
    "cyrius",
    "smn12",
    "parascopy",
    "smaca",
    "sma_finder",
    "hapsma",
)


def _supporting_file_name(entry):
    if isinstance(entry, dict):
        return str(entry.get("name", ""))
    return str(entry)


def _config_int(value, default):
    if value in [None, "", "None"]:
        return int(default)
    return int(value)


def _verifybamid2_panel_config(panel_id):
    panels = config.get("verifybamid2_contam", {}).get("panels", {})
    if panel_id not in panels:
        raise WorkflowError(
            f"Unsupported VerifyBamID2 panel: {panel_id}. "
            f"Configured panels: {', '.join(sorted(panels))}"
        )
    merged = dict(panels[panel_id])
    supporting_panels = (
        config.get("supporting_files", {})
        .get("files", {})
        .get("verifybam2", {})
        .get("panels", {})
    )
    if panel_id in supporting_panels:
        merged.update(supporting_panels[panel_id])
    svd_prefix_overrides = config.get("verifybamid2_panel_svd_prefixes", {})
    if panel_id in svd_prefix_overrides:
        merged["svd_prefix"] = {"name": str(svd_prefix_overrides[panel_id])}
    return merged


def verifybamid2_selected_panels(*, require_non_empty=False):
    vb2_cfg = config.get("verifybamid2_contam", {})
    selected = _as_config_list(
        config.get("verifybamid2_panels", vb2_cfg.get("active_panels", []))
    )
    if not selected and vb2_cfg.get("default_panel", "") not in ["", None, "None"]:
        selected = [str(vb2_cfg["default_panel"])]

    configured = set(vb2_cfg.get("panels", {}).keys())
    invalid = sorted(set(selected) - configured)
    if invalid:
        raise WorkflowError(
            "Unsupported verifybamid2_panels value(s): "
            + ", ".join(invalid)
            + ". Supported values: "
            + ", ".join(sorted(configured))
        )
    if require_non_empty and not selected:
        raise WorkflowError(
            "The requested VerifyBamID2 target requires --config "
            "verifybamid2_panels=[...] or verifybamid2_contam.active_panels."
        )
    return selected


VERIFYBAMID2_PANELS = verifybamid2_selected_panels()
VERIFYBAMID2_PANEL_IDS = tuple(
    sorted(config.get("verifybamid2_contam", {}).get("panels", {}).keys())
)


def verifybamid2_panel_svd_prefix(wildcards):
    panel_cfg = _verifybamid2_panel_config(wildcards.vb2panel)
    return _supporting_file_name(panel_cfg["svd_prefix"])


def day_stage_sample_id(sample, *components):
    return ".".join(
        [str(sample)] + [str(component) for component in components if str(component)]
    )


def verifybamid2_panel_label(wildcards):
    panel_cfg = _verifybamid2_panel_config(wildcards.vb2panel)
    return str(panel_cfg.get("label", wildcards.vb2panel))


def verifybamid2_panel_snp_count(wildcards):
    panel_cfg = _verifybamid2_panel_config(wildcards.vb2panel)
    return str(panel_cfg.get("snp_count", ""))


def verifybamid2_panel_threads(wildcards):
    panel_cfg = _verifybamid2_panel_config(wildcards.vb2panel)
    return _config_int(
        panel_cfg.get("threads", None),
        config["verifybamid2_contam"]["threads"],
    )


def verifybamid2_panel_mem_mb(wildcards):
    panel_cfg = _verifybamid2_panel_config(wildcards.vb2panel)
    return _config_int(
        panel_cfg.get("mem_mb", None),
        config["verifybamid2_contam"].get("mem_mb", 50000),
    )


def verifybamid2_panel_partition(wildcards):
    panel_cfg = _verifybamid2_panel_config(wildcards.vb2panel)
    return str(
        panel_cfg.get(
            "partition",
            config["verifybamid2_contam"]["partition"],
        )
    )


def htd_callers_selected(*, require_non_empty=False):
    callers = _as_config_list(config.get("htd_callers", []))
    invalid = sorted(set(callers) - set(SUPPORTED_HTD_CALLERS))
    if invalid:
        raise WorkflowError(
            "Unsupported htd_callers value(s): "
            + ", ".join(invalid)
            + ". Supported values: "
            + ", ".join(SUPPORTED_HTD_CALLERS)
        )
    if require_non_empty and not callers:
        raise WorkflowError(
            "produce_htd_calls requires a non-empty --config htd_callers=[...]. "
            "Supported values: " + ", ".join(SUPPORTED_HTD_CALLERS)
        )
    return callers


HTD_CALLERS = htd_callers_selected()


def qc_tool_enabled(tool, *, long_running=False, default=True):
    """Return whether a QC integration belongs in routine staged MultiQC targets."""
    cfg = config.get("multiqc_qc", {})
    enabled = set(_as_config_list(cfg.get("enable_tools", [])))
    disabled = set(_as_config_list(cfg.get("disable_tools", [])))
    if tool in disabled:
        return False
    if tool in enabled:
        return True
    is_long = long_running or tool in MULTIQC_QC_LONG_RUNNING_TOOLS
    if is_long and not _as_boolish(cfg.get("enable_long_running", False)):
        return False
    return default


def qc_alignment_dedupers():
    cfg = config.get("multiqc_qc", {})
    ddups = set(DDUP)
    if _as_boolish(cfg.get("include_no_dedup_alignment_qc", True)):
        ddups.add("na")
    return sorted(ddups)


def qc_contamination_dedupers():
    return sorted(set(DDUP))


def qc_variant_dedupers():
    return sorted(ddup for ddup in set(DDUP) if ddup != "na")


def qc_relatedness_dedupers():
    return sorted(set(DDUP))


def qc_aligner_deduper_pairs(dedupers=None):
    """Return only CRAM-producing aligner/deduper pairs for generic QC rules."""
    if dedupers is None:
        dedupers = DDUP
    active_aligners = set(globals().get("QC_CRAM_ALIGNERS", []))
    ordinary_aligners = set(globals().get("OG_ALIGNERS", []))
    cram_aligners = set(globals().get("CRAM_ALIGNERS", []))
    pairs = []
    for ddup in sorted(set(dedupers)):
        if ddup == "na":
            candidates = active_aligners & cram_aligners
        else:
            candidates = active_aligners & ordinary_aligners
        for alnr in sorted(candidates):
            pairs.append((alnr, ddup))
    return pairs


def valid_alnr_ddup_pairs(all_aligners, ddups):
    """Return valid aligner/deduper pairs without cross-product expansion."""
    allowed_pairs = set(qc_aligner_deduper_pairs(ddups))
    return [
        (alnr, ddup)
        for alnr in sorted(set(all_aligners))
        for ddup in sorted(set(ddups))
        if (alnr, ddup) in allowed_pairs
    ]


def qc_alignment_pairs():
    return qc_aligner_deduper_pairs(qc_alignment_dedupers())


def qc_contamination_pairs():
    return qc_aligner_deduper_pairs(qc_contamination_dedupers())


def qc_relatedness_pairs():
    return qc_aligner_deduper_pairs(qc_relatedness_dedupers())


def expand_qc_pairs(pattern, sample_ids=None, pairs=None):
    if sample_ids is None:
        sample_ids = globals().get("SSAMPS", [])
    if pairs is None:
        pairs = qc_alignment_pairs()
    return [
        pattern.format(sample=sample, alnr=alnr, ddup=ddup)
        for sample in sample_ids
        for alnr, ddup in pairs
    ]


def expand_qc_alignment(pattern, sample_ids=None, **_contract_markers):
    return expand_qc_pairs(pattern, sample_ids=sample_ids, pairs=qc_alignment_pairs())


def expand_qc_contamination(pattern, sample_ids=None, **_contract_markers):
    return expand_qc_pairs(pattern, sample_ids=sample_ids, pairs=qc_contamination_pairs())


BOOTSTRAP_UNIT_COLUMNS = [
    "RUNID",
    "SAMPLEID",
    "EXPERIMENTID",
    "LANEID",
    "BARCODEID",
    "LIBPREP",
    "SEQ_PLATFORM",
    "SEQ_VENDOR",
    "ILMN_R1_PATH",
    "ILMN_R2_PATH",
    "PACBIO_R1_PATH",
    "PACBIO_R2_PATH",
    "ONT_R1_PATH",
    "ONT_R2_PATH",
    "UG_R1_PATH",
    "UG_R2_PATH",
    "SUBSAMPLE_PCT",
    "ILMN_TRIM_READ_LENGTH",
    "LONGREADTRIM_READ_LENGTH",
    "LONGREADTRIM_MODE",
    "ONT_BAM",
    "ONT_BAM_ALIGNER",
    "ONT_BAM_SNV_CALLER",
    "ROCHE_BAM",
    "ROCHE_BAM_ALIGNER",
    "SR_VCF_PATH",
    "LR_VCF_PATH",
    "ROCHE_BAM_SNV_CALLER",
    "ROCHE_DOWNSAMPLE_RATIO",
    "AMPLIFICATION_TYPE",
    "ALIGNED_REF_UID",
]


def _resolve_units_table_path():
    override_path = config.get("units_table", "")
    if override_path not in ["", None, "None"]:
        return os.path.abspath(str(override_path))
    return os.path.abspath(os.path.join("config", "units.tsv"))


def _load_units_table(path: str, allow_bootstrap: bool = False):
    if not os.path.exists(path):
        if allow_bootstrap:
            return None
        raise WorkflowError(
            f"The units table was not found at {path}. Create config/units.tsv or set --config units_table=/path/to/units.tsv."
        )

    if os.path.getsize(path) == 0:
        if allow_bootstrap:
            return None
        raise WorkflowError(f"The units table at {path} is empty.")

    unit_df = load_tsv_as_str(path)
    if unit_df.empty:
        if allow_bootstrap:
            return None
        raise WorkflowError(
            f"The units table at {path} has headers but no data rows."
        )
    return unit_df


def _bootstrap_sample_id(sample_df: pd.DataFrame) -> str:
    preferred = config.get("just_this_sample", "")
    if preferred not in ["", None, "None"]:
        preferred = str(preferred)
        if "SAMPLEID" in sample_df.columns:
            sample_ids = set(sample_df["SAMPLEID"].astype(str).tolist())
            if preferred in sample_ids:
                return preferred
    if sample_df.empty:
        raise WorkflowError(
            "Bootstrap mode requires at least one sample row in samples.tsv."
        )
    return str(sample_df.iloc[0]["SAMPLEID"])


def _build_bootstrap_unit_records(sample_df: pd.DataFrame) -> pd.DataFrame:
    sample_id = _bootstrap_sample_id(sample_df)
    bclconvert_cfg = config.get("bclconvert", {})
    run_id = config["bclconvert_bootstrap_run_id"]
    bootstrap_row = {column: "na" for column in BOOTSTRAP_UNIT_COLUMNS}
    bootstrap_row.update(
        {
            "RUNID": run_id,
            "SAMPLEID": sample_id,
            "EXPERIMENTID": run_id,
            "LANEID": "1",
            "BARCODEID": "bootstrap",
            "LIBPREP": str(bclconvert_cfg.get("libprep", "na") or "na"),
            "SEQ_PLATFORM": str(
                bclconvert_cfg.get("seq_platform_override", "na") or "na"
            ),
            "SEQ_VENDOR": str(bclconvert_cfg.get("seq_vendor", "na") or "na"),
            "ILMN_R1_PATH": "na",
            "ILMN_R2_PATH": "na",
        }
    )
    return pd.DataFrame([bootstrap_row])
import yaml
import multiprocessing
import random
import shutil
import datetime as dtm

## TODO: sweep through this thing and prune out the no longer needed/experimental stuff

# ec2=os.popen('echo "EC2instance:$(bin/helpers/get_ec2_type.sh)"').readline().rstrip()
# print(ec2, file=sys.stderr)

EX = [""]
RU = [""]
# ##### these are globally avail, but  make the linters freak out b/c it's hidden from them by snakemake, quieting the complaints.
config = config  # noqa   ### Just needed to quiet linters
cluster_config = cluster_config  # noqa   ### Just needed to quiet linters

BCL_BOOTSTRAP_TARGETS = {
    "bclconvert_generate_units_tsv",
    "bclconvert_metrics_multiqc_exports",
    "bclconvert_metrics_summary",
    "bclconvert_validate_inputs",
    "multiqc_bclconvert",
    "produce_bclconvert_fastqs",
    "produce_bclconvert_metrics",
    "produce_bclconvert_multiqc",
    "produce_bclconvert_fastqs_and_metrics",
    "produce_illumina_run_qc_and_bclconvert",
    "run_bclconvert",
}


def _boolish(value, default=False):
    if value in [None, "", "None"]:
        return default
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def _bclconvert_enabled_for_multiqc():
    cfg = config.get("multiqc_qc", {})
    enabled = cfg.get("enable_tools", [])
    if isinstance(enabled, str):
        enabled = [item.strip() for item in enabled.split(",") if item.strip()]
    return "bclconvert" in {str(item).strip() for item in enabled}


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


def _derive_bcl_bootstrap_run_id():
    run_context = run_context_for_platform("ILMN", require=False)
    if run_context is not None:
        return run_context["RUNID"]
    bcl_cfg = config.get("bclconvert", {})
    configured = _sanitize_run_id(bcl_cfg.get("run_id", ""))
    if configured:
        return configured
    sample_sheet = bcl_cfg.get("sample_sheet", "SampleSheet.csv")
    run_name = _sanitize_run_id(_read_samplesheet_run_name(sample_sheet))
    if run_name:
        return run_name
    fallback = _sanitize_run_id(os.path.splitext(os.path.basename(sample_sheet))[0])
    return fallback or "bclconvert_bootstrap"


BCL_BOOTSTRAP_MODE = bool(_requested_targets() & BCL_BOOTSTRAP_TARGETS) or _boolish(
    config.get("bootstrap_bclconvert", False)
) or _bclconvert_enabled_for_multiqc()
BCL_BOOTSTRAP_RUN_ID = _derive_bcl_bootstrap_run_id()
config["bootstrap_bclconvert"] = BCL_BOOTSTRAP_MODE
config["bclconvert_bootstrap_run_id"] = BCL_BOOTSTRAP_RUN_ID
config["_bclconvert_bootstrap_mode"] = BCL_BOOTSTRAP_MODE
config["_bclconvert_run_id"] = BCL_BOOTSTRAP_RUN_ID


# ##### Generate the day top level directories
if "conda_prefix" not in config:
    config["conda_prefix"] = "etc/"


config["jem_dot"] = os.environ["DAY_ROOT"] + "/.jemalloc_loc"
os.system(f"touch {config['jem_dot']}")


# ##### A place to track failed samples so they can be tallied up at the end.
# NOT REALLY IMPLEMENTED YET
config["failed_samples"] = {}  ### USE SAMPLE SHEET FOR THIS


def first_val(df, col):
    if df.empty:
        return None
    return df.iloc[0].get(col)


WORKFLOW_TARGET_ALIAS_PATH = os.path.join("config", "workflow_target_aliases.tsv")


def _load_workflow_target_aliases():
    aliases = []
    with open(WORKFLOW_TARGET_ALIAS_PATH, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            aliases.append({key: str(value or "") for key, value in row.items()})
    return aliases


WORKFLOW_TARGET_ALIASES = _load_workflow_target_aliases()
TARGET_ALIAS_BY_KIND = {}
for _alias in WORKFLOW_TARGET_ALIASES:
    TARGET_ALIAS_BY_KIND.setdefault(_alias["kind"], []).append(_alias)


def _target_alias_code_map(kind):
    return {
        row["target"]: row["code"]
        for row in TARGET_ALIAS_BY_KIND.get(kind, [])
        if row["code"] and row["code"] != "all"
    }


def _target_alias_codes_from_argv(kind):
    codes = set()
    for arg in sys.argv:
        for row in TARGET_ALIAS_BY_KIND.get(kind, []):
            if row["target"] != arg or not row["code"]:
                continue
            if row["code"] == "all":
                codes.update(_current_alias_codes(kind))
            else:
                codes.add(row["code"])
    return codes


def _current_alias_codes(kind):
    return sorted(
        {
            row["code"]
            for row in TARGET_ALIAS_BY_KIND.get(kind, [])
            if row["status"] == "current" and row["code"] and row["code"] != "all"
        }
    )


def _current_alias_targets(kind, *, include_all=False):
    return [
        row["target"]
        for row in TARGET_ALIAS_BY_KIND.get(kind, [])
        if row["status"] == "current"
        and row["target"]
        and (include_all or row["code"] != "all")
    ]


def _delegate_targets(kind):
    return [
        row["delegates_to"]
        for row in TARGET_ALIAS_BY_KIND.get(kind, [])
        if row["status"] == "current" and row["delegates_to"]
    ]


CANONICAL_ALIGNER_CODES = _current_alias_codes("aligner")
CANONICAL_DEDUPER_CODES = _current_alias_codes("deduper")
CANONICAL_SNV_CALLER_CODES = _current_alias_codes("snv_caller")
CANONICAL_SV_CALLER_CODES = _current_alias_codes("sv_caller")

# ####  PARSE SUPPORTING DATA FILES/DIRS INTO CONFIG
# -----------------------------------
# suppporting dirs

config["supporting_files"] = f"config/supporting_files/{config['genome_build']}_supporting_files.yaml"

a_yaml_file = open(config["supporting_dirs"])
parsed_yaml_file = yaml.load(a_yaml_file, Loader=yaml.FullLoader)
config["supporting_dirs_obj"] = parsed_yaml_file

files_yaml_file = open(config["supporting_data"]["supporting_files_conf"])
files_yaml_file = yaml.load(files_yaml_file, Loader=yaml.FullLoader)

# supporting files
config["supporting_files"] = {
    "files": files_yaml_file["supporting_files"]["files"],
    "root": files_yaml_file["supporting_files"]["root"],
}

genome_build_chrm_prefix_map = {
    "b37": "",
    "hg38": "chr", 
    "hg38_broad": "chr",
} 

GENOME_CHR_PREFIX="na"
if os.environ.get("DAY_GENOME_BUILD","na") in genome_build_chrm_prefix_map:
    GENOME_CHR_PREFIX = genome_build_chrm_prefix_map[os.environ.get("DAY_GENOME_BUILD")]
    print(
        f"INFO::: The genome build {os.environ.get('DAY_GENOME_BUILD')} is supported.  The genome build prefix is '{GENOME_CHR_PREFIX}''.",
        file=sys.stderr,
    )
else:
    err_msg=f"ERROR::: The genome build {os.environ.get('DAY_GENOME_BUILD')} is not supported.  Please check the config file and try again. No genome build prefix was set."
    print(
        err_msg,
        file=sys.stderr,
    )
    raise Exception(
        err_msg
    )


def _day_chrm_token_to_contig(raw):
    pchr = GENOME_CHR_PREFIX
    mito_code = "MT" if "b37" == config['genome_build'] else "M"
    chrm_map = {'23': 'X', '24': 'Y', '25': mito_code}
    token = str(raw).replace('chr', '')
    return pchr + chrm_map.get(token, token)

# SNV caller chunk arrays
SENTD_CHRMS = config["sentD"][f"{config['genome_build']}_sentD_chrms"].split(",")
CGT7P_CHRMS = config["cgt7p"][f"{config['genome_build']}_cgt7p_chrms"].split(",")
DEEPD_CHRMS = config["deepvariant"][f"{config['genome_build']}_deep_chrms"].split(",")
DEEP19R_CHRMS = config["deepvariant_1_9_roche"][f"{config['genome_build']}_deep_chrms"].split(",")
OCTO_CHRMS = config["octopus"][f"{config['genome_build']}_octo_chrms"].split(",")
CLAIR3_CHRMS = config["clair3"][f"{config['genome_build']}_clair3_chrms"].split(",")
LOFREQ_CHRMS = config["lofreq2"][f"{config['genome_build']}_lofreq_chrms"].split(",")
DVSOM_CHRMS = config["deepsomatic"][f"{config['genome_build']}_dvsom_chrms"].split(",")
M2_CHRMS = config["mutect2"][f"{config['genome_build']}_mutect2_chrms"].split(",")
SENTTN_CHRMS = config["senttn"][f"{config['genome_build']}_senttn_chrms"].split(",")
# STRELKA2_CHRMS = config["strelka2"][f"{config['genome_build']}_strelka2_chrms"].split(",")

VARN_CHRMS = (
    []
    if "varn" not in config
    else config["varn"][f"{config['genome_build']}_varn_chrms"].split(",")
)
AIV_CHRMS = (
    []
    if "aiv" not in config
    else config["aiv"][f"{config['genome_build']}_aiv_chrms"].split(",")
)
SENTDUG_CHRMS = config["sentdug"][f"{config['genome_build']}_sentdug_chrms"].split(",")
SENTDONT_CHRMS = config["sentdont"][f"{config['genome_build']}_sentdont_chrms"].split(",")
SENTDHUO_CHRMS = config["sentdhuo"][f"{config['genome_build']}_sentdhuo_chrms"].split(",")
SENTDHIO_CHRMS = config["sentdhio"][f"{config['genome_build']}_sentdhio_chrms"].split(",")

# Per-chromosome expansion of SENTDHIO_CHRMS for transfer-step sharding.
# Converts range notation like "1-24" into individual values ["1","2",...,"24"].
# Single values and comma-separated lists are preserved as-is.
def _expand_chrm_ranges(chrm_list):
    """Expand chromosome range strings (e.g. '1-24') into individual values."""
    expanded = []
    for entry in chrm_list:
        parts = entry.split("-")
        if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
            for i in range(int(parts[0]), int(parts[1]) + 1):
                expanded.append(str(i))
        else:
            expanded.append(entry)
    return expanded

SENTDHIO_CHRMS_TRANSFER = _expand_chrm_ranges(SENTDHIO_CHRMS)
VEP_CHRMS = [
    _day_chrm_token_to_contig(chrm)
    for chrm in _expand_chrm_ranges(
        config["vep"][f"{config['genome_build']}_vep_chrms"].split(",")
    )
]

SENTDPB_CHRMS = config["sentdpb"][f"{config['genome_build']}_sentdpb_chrms"].split(",")

# CLI hybrid workflows
SENTDHIP_CHRMS = config["sentdhip"][f"{config['genome_build']}_sentdhip_chrms"].split(",")
SENTDHUP_CHRMS = config["sentdhup"][f"{config['genome_build']}_sentdhup_chrms"].split(",")

# Modular hybrid workflows reuse the same chromosome configs as their CLI counterparts
SENTDHUOM_CHRMS = SENTDHUO_CHRMS  # Modular Ultima+ONT hybrid
SENTDHIOM_CHRMS = SENTDHIO_CHRMS  # Modular Illumina+ONT hybrid
SENTDHIPM_CHRMS = SENTDHIP_CHRMS  # Modular Illumina+PacBio hybrid
SENTDHUPM_CHRMS = SENTDHUP_CHRMS  # Modular Ultima+PacBio hybrid
SENTDHROM_CHRMS = config["sentdhrom"][f"{config['genome_build']}_sentdhrom_chrms"].split(",")  # Modular Roche+ONT hybrid
SENTDHRPM_CHRMS = config["sentdhrpm"][f"{config['genome_build']}_sentdhrpm_chrms"].split(",")  # Modular Roche+PacBio hybrid

# Modular refactored hybrid workflows - each uses its own config section (r-suffix)
SENTDHIOMR_CHRMS = config["sentdhiomr"][f"{config['genome_build']}_sentdhiomr_chrms"].split(",")
SENTDHIOMR_CHRMS_TRANSFER = _expand_chrm_ranges(SENTDHIOMR_CHRMS)
SENTDHIPMR_CHRMS = config["sentdhipmr"][f"{config['genome_build']}_sentdhipmr_chrms"].split(",")
SENTDHIPMR_CHRMS_TRANSFER = _expand_chrm_ranges(SENTDHIPMR_CHRMS)
SENTDHUPMR_CHRMS = config["sentdhupmr"][f"{config['genome_build']}_sentdhupmr_chrms"].split(",")
SENTDHUPMR_CHRMS_TRANSFER = _expand_chrm_ranges(SENTDHUPMR_CHRMS)
SENTDHUOMR_CHRMS = config["sentdhuomr"][f"{config['genome_build']}_sentdhuomr_chrms"].split(",")
SENTDHUOMR_CHRMS_TRANSFER = _expand_chrm_ranges(SENTDHUOMR_CHRMS)

# Sharded Sentieon Ultima pangenome caller. Uses the same HIOMR-style shard
# token syntax as the hybrid modular rules, including contiguous ranges.
SENTPGS_CHRMS = config["sentieon_pangenome_ug"][f"{config['genome_build']}_sentpgs_chrms"].split(",")

# Sentieon GATK HaplotypeCaller
GATK_CHRMS = config["sentieon_gatk"][f"{config['genome_build']}_sentieon_gatk_chrms"].split(",")

# ##### Setting the allowed aligners to run and to which deduper to use.
# presently, 1+ aligners may run, but all must use the same deduper


# Handle aligners
# ------------------------------------------------------------------
# Primary auto-detection happens in bin/day_run (bash, before snakemake).
# The sys.argv fallback below covers edge cases where bin/day_run
# is bypassed (e.g. direct snakemake invocation).
# ------------------------------------------------------------------

ALIGNERS = []
if 'aligners' not in config or config.get('aligners') is None or len(config.get('aligners', [])) == 0:
    os.system(
        f'''colr "...WARNING: No aligners set in the config." "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
    )
else:
    ALIGNERS = sorted(set(config["aligners"]))
    os.system(
        f"""colr 'aligners: {ALIGNERS}' "$DY_WT1" "$DY_B1" "$DY_WS1" 1>&2;"""
    )

# Fallback: auto-detect aligners from env var set by bin/day_run,
# or from sys.argv for direct snakemake invocations.
if not ALIGNERS:
    _auto_aligners_env = os.environ.get('_DY_AUTO_ALIGNERS', '')
    if _auto_aligners_env:
        ALIGNERS = sorted(set(_auto_aligners_env.split(',')))
        os.system(
            f'''colr "...INFO: Auto-detected aligners from env: {ALIGNERS}" "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
        )
    else:
        _cli_aligner_codes = _target_alias_codes_from_argv("aligner")
        if _cli_aligner_codes:
            ALIGNERS = sorted(_cli_aligner_codes)
            os.system(
                f'''colr "...INFO: Auto-detected aligner targets on CLI. ALIGNERS set to: {ALIGNERS}" "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
            )

os.system(
    f"""colr 'aligners (final): {ALIGNERS}' "$DY_WT1" "$DY_B1" "$DY_WS1" 1>&2;"""
)

# Handle dedupers
# Valid dedup codes: dmd (doppelmark), smd (sentieon markdup), spmd
# (Sentieon pangenome markdup/realignment output), na (no dedup / skip)
# Deprecated legacy codes dppl and dppl_sent are mapped to dmd and smd respectively.
# If no dedupers specified, defaults to ['na'] (no dedup).
DDUP_LEGACY_MAP = {"dppl": "dmd", "dppl_sent": "smd"}
DDUP_VALID_CODES = set(CANONICAL_DEDUPER_CODES) | {"spmd"}

DDUP = []
if 'dedupers' not in config or config.get('dedupers') is None or len(config.get('dedupers', [])) == 0:
    DDUP = ["na"]
    os.system(
        f'''colr "...INFO: No dedupers set in config. Defaulting to na (no dedup)." "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
    )
else:
    _raw_ddup = sorted(set(config["dedupers"]))
    _legacy_ddup = sorted(set(_raw_ddup) & set(DDUP_LEGACY_MAP))
    if _legacy_ddup:
        os.system(
            f'''colr "...WARNING: Deprecated deduper code(s) {_legacy_ddup} were normalized to canonical deduper code(s). Use dmd/smd/na instead." "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
        )
    DDUP = sorted(set(DDUP_LEGACY_MAP.get(d, d) for d in _raw_ddup))
    _unknown = set(DDUP) - DDUP_VALID_CODES
    if _unknown:
        raise WorkflowError(
            f"Unknown deduper code(s): {sorted(_unknown)}. "
            f"Valid canonical codes: {sorted(DDUP_VALID_CODES)}. "
            "Legacy dppl is accepted and normalized to dmd."
        )

# Fallback: auto-detect dedupers from env var set by bin/day_run,
# or from sys.argv for direct snakemake invocations.
_auto_dedup_codes = set()

# Primary: env var from bin/day_run
_auto_dedupers_env = os.environ.get('_DY_AUTO_DEDUPERS', '')
if _auto_dedupers_env:
    _auto_dedup_codes = set(_auto_dedupers_env.split(','))

# Secondary: sys.argv scan (direct snakemake invocation)
if not _auto_dedup_codes:
    _auto_dedup_codes = _target_alias_codes_from_argv("deduper")

if _auto_dedup_codes:
    _had_only_default = (set(DDUP) == {"na"}) and (
        'dedupers' not in config
        or config.get('dedupers') is None
        or len(config.get('dedupers', [])) == 0
    )
    if _had_only_default:
        DDUP = sorted(_auto_dedup_codes)
    else:
        DDUP = sorted(set(DDUP) | _auto_dedup_codes)
    os.system(
        f'''colr "...INFO: Auto-detected dedupers. DDUP updated to: {DDUP}" "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
    )

# PRINT INFO
os.system(
    f"""colr 'deduper (final): {DDUP}' "$DY_WT1" "$DY_B1" "$DY_WS1" 1>&2;"""
)

snv_CALLERS = []
if 'snv_callers' not in config:
     os.system(
        f'''colr "...WARNING: No snv_callers set in the config." "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
     )
else:
    snv_CALLERS = sorted(set([] if 'snv_callers' not in config or config['snv_callers'] == None else config["snv_callers"]))
    ## PRINT INFO
    os.system(
        f"""colr 'SNV Callers:{snv_CALLERS}' "$DY_WT1" "$DY_B1" "$DY_WS1" 1>&2;"""
    )

# Fallback: auto-detect SNV callers from env var set by bin/day_run,
# or from sys.argv for direct snakemake invocations.
if not snv_CALLERS:
    _auto_snv_env = os.environ.get('_DY_AUTO_SNV_CALLERS', '')
    if _auto_snv_env:
        snv_CALLERS = sorted(set(_auto_snv_env.split(',')))
        os.system(
            f'''colr "...INFO: Auto-detected SNV callers from env: {snv_CALLERS}" "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
        )
    else:
        _cli_snv_codes = _target_alias_codes_from_argv("snv_caller")
        if _cli_snv_codes:
            snv_CALLERS = sorted(_cli_snv_codes)
            os.system(
                f'''colr "...INFO: Auto-detected SNV caller targets on CLI. snv_CALLERS set to: {snv_CALLERS}" "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
            )

os.system(
    f"""colr 'SNV Callers (final): {snv_CALLERS}' "$DY_WT1" "$DY_B1" "$DY_WS1" 1>&2;"""
)

somatic_snv_CALLERS = []
if 'snv_callers_somatic' not in config:
    os.system(
        f'''colr "...WARNING: No snv_callers_somatic set in the config." "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
    )
else:
    somatic_snv_CALLERS = sorted(
        set(
            []
            if 'snv_callers_somatic' not in config
            or config['snv_callers_somatic'] is None
            else config["snv_callers_somatic"]
        )
    )
    ## PRINT INFO
    os.system(
        f"""colr 'Somatic SNV Callers:{somatic_snv_CALLERS}' "$DY_WT1" "$DY_B1" "$DY_WS1" 1>&2;"""
    )

sv_CALLERS = []
if 'sv_callers' not in config:

     os.system(
        f'''colr "... WARNING: No sv_callers set in the config." "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
     )
else:
    sv_CALLERS = sorted(set([] if 'sv_callers' not in config or config['sv_callers'] == None else config["sv_callers"]))
    ## PRINT INFO
    os.system(
        f"""colr 'SV Callers:{sv_CALLERS}' "$DY_WT1" "$DY_B1" "$DY_WS1" 1>&2;"""
    )   

if not sv_CALLERS:
    _auto_sv_env = os.environ.get('_DY_AUTO_SV_CALLERS', '')
    if _auto_sv_env:
        sv_CALLERS = sorted(set(_auto_sv_env.split(',')))
        os.system(
            f'''colr "...INFO: Auto-detected SV callers from env: {sv_CALLERS}" "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
        )
    else:
        _cli_sv_codes = _target_alias_codes_from_argv("sv_caller")
        if _cli_sv_codes:
            sv_CALLERS = sorted(_cli_sv_codes)
            os.system(
                f'''colr "...INFO: Auto-detected SV caller targets on CLI. sv_CALLERS set to: {sv_CALLERS}" "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
            )

os.system(
    f"""colr 'SV Callers (final): {sv_CALLERS}' "$DY_WT1" "$DY_B1" "$DY_WS1" 1>&2;"""
)
    


# ####  LOAD SAMPLE DATA FROM ANALYSIS MANIFEST
# ---------------------
# Load sample sheet into pandas dataframe, then validate & if pass
# expose amples as a global  Including to any other rule or called script from a rule  included from the
# main snakefile



def _resolve_table(override_key, default_key, target_filename):
    """Resolve the path to a tabular sample metadata file."""

    override_path = config.get(override_key, "")
    if override_path not in ["", None, "None"]:
        override_path = os.path.abspath(str(override_path))
        if not os.path.exists(override_path):
            raise WorkflowError(
                f"The file specified via --config {override_key}={override_path} was not found."
            )
        return override_path

    dest_path = os.path.abspath(os.path.join("config", target_filename))
    if os.path.exists(dest_path):
        return dest_path

    default_path = config.get(default_key, "")
    if default_path in ["", None, "None"]:
        raise WorkflowError(
            f"No {target_filename} provided. Create config/{target_filename} or set the --config {override_key}=/path/to/{target_filename}."
        )

    default_path = os.path.abspath(str(default_path))
    if not os.path.exists(default_path):
        raise WorkflowError(
            f"The default {target_filename} configured at {default_path} could not be found."
        )

    os.makedirs("config", exist_ok=True)
    shutil.copy(default_path, dest_path)
    print(
        f"     _____ DEFAULT {target_filename} copied to {dest_path}",
        file=sys.stderr,
    )
    return dest_path


samples_table_path = _resolve_table(
    "samples_table",
    f"{config['genome_build']}_samples_table",
    "samples.tsv",
)
units_table_path = _resolve_units_table_path()

config["samples_table"] = samples_table_path
config["units_table"] = units_table_path

print(
    f"A    N   A   L  Y S I S    SAMPLE TABLE DETECTED ::: {samples_table_path}",
    file=sys.stderr,
)
print(
    f"A    N   A   L  Y S I S    UNIT TABLE DETECTED ::: {units_table_path}",
    file=sys.stderr,
)

def load_tsv_as_str(path: str) -> pd.DataFrame:
    # Force *everything* to string; no NA magic.
    df = pd.read_csv(
        path,
        sep="\t",
        dtype=str,
        keep_default_na=False,
        na_values=[],       # ensure nothing gets parsed as NA
        engine="python",    # robust with weird fields/tabs
    )
    return df

def normalize_boolish(df: pd.DataFrame, cols=("IS_POSITIVE_CONTROL", "IS_NEGATIVE_CONTROL")) -> pd.DataFrame:
    for c in cols:
        if c in df.columns:
            df[c] = (
                df[c]
                .astype(str)            # guard if anything slipped in
                .str.strip()
                .str.lower()
            )
            # Optional: clamp to allowed values; pick default you want.
            df[c] = df[c].where(df[c].isin({"true", "false"}), "false")
    return df

sample_records = load_tsv_as_str(samples_table_path)

sample_records.columns = [c.upper() for c in sample_records.columns]

sample_records = normalize_boolish(sample_records)
if "COMMENT" not in sample_records.columns:
    sample_records["COMMENT"] = ""

if sample_records.empty:
    raise WorkflowError("The samples table is empty. Please provide at least one sample entry.")

unit_records = _load_units_table(units_table_path, allow_bootstrap=BCL_BOOTSTRAP_MODE)
bootstrap_unit_context = False
if unit_records is None:
    if not BCL_BOOTSTRAP_MODE:
        raise WorkflowError(
            "The units table is empty. Please provide at least one sequencing unit entry."
        )
    unit_records = _build_bootstrap_unit_records(sample_records)
    bootstrap_unit_context = True

unit_records.columns = [c.upper() for c in unit_records.columns]
if "COMMENT" not in unit_records.columns:
    unit_records["COMMENT"] = ""

validate(sample_records, schema="../schemas/samples.schema.yaml")
validate(unit_records, schema="../schemas/units.schema.yaml")

required_unit_columns = {
    "RUNID",
    "SAMPLEID",
    "EXPERIMENTID",
    "LANEID",
    "BARCODEID",
    "LIBPREP",
    "SEQ_PLATFORM",
}
missing_unit_columns = required_unit_columns - set(unit_records.columns)
if missing_unit_columns:
    raise WorkflowError(
        f"Missing required columns in units table: {sorted(missing_unit_columns)}"
    )

for opt_col in [
    "ILMN_R1_PATH",
    "ILMN_R2_PATH",
    "PACBIO_R1_PATH",
    "PACBIO_R2_PATH",
    "ONT_R1_PATH",
    "ONT_R2_PATH",
    "UG_R1_PATH",
    "UG_R2_PATH",
    "SUBSAMPLE_PCT",
    "ILMN_TRIM_READ_LENGTH",
    "LONGREADTRIM_READ_LENGTH",
    "LONGREADTRIM_MODE",
    "SEQ_VENDOR",
    "AMPLIFICATION_TYPE",
    "ALIGNED_REF_UID",
    "COMMENT",
]:
    if opt_col not in unit_records.columns:
        unit_records[opt_col] = ""

if "SAMPLEID" not in sample_records.columns:
    raise WorkflowError("The samples table must contain a 'SAMPLEID' column.")

sample_records_for_mqc = sample_records.copy()
unit_records_for_mqc = unit_records.copy()

# Drop duplicate metadata columns from the samples table before merging with
# the units table. The units table should be authoritative for run-level
# metadata, and retaining both versions causes pandas to suffix the columns
# (e.g. `RUNID_x`/`RUNID_y`), which later breaks lookups that expect
# canonical names such as `RUNID`.
overlap_columns = (
    set(sample_records.columns)
    & set(unit_records.columns)
    - {"SAMPLEID"}
)
if overlap_columns:
    sample_records = sample_records.drop(columns=sorted(overlap_columns))

metadata = unit_records.merge(
    sample_records,
    on="SAMPLEID",
    how="left",
    validate="many_to_one",
)

if metadata["SAMPLESOURCE"].isna().any():
    missing_samples = metadata[metadata["SAMPLESOURCE"].isna()]["SAMPLEID"].unique()
    raise WorkflowError(
        "The following SampleID entries are missing from samples.tsv: "
        + ", ".join(sorted(missing_samples))
    )

def _clean_component(value):
    value = str(value or "").strip()
    if value.lower() in {"", "na", "none"}:
        return ""
    return re.sub(r"\s+", "", value)


def _load_fastq_path_list_helpers():
    helper_path = os.path.join("workflow", "scripts", "fastq_path_lists.py")
    if not os.path.exists(helper_path):
        raise WorkflowError(f"Missing FASTQ path list helper: {helper_path}")
    spec = importlib.util.spec_from_file_location(
        "dayoa_fastq_path_lists", helper_path
    )
    helper_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper_module)
    return helper_module


_fastq_path_lists = _load_fastq_path_list_helpers()


def _split_fastq_path_list(value):
    try:
        return _fastq_path_lists.split_fastq_path_list(_clean_component(value))
    except ValueError as exc:
        raise WorkflowError(str(exc))


def _paired_fastq_path_lists(r1_value, r2_value, *, context, require_r2=True):
    try:
        r1_paths, r2_paths = _fastq_path_lists.paired_fastq_path_lists(
            _clean_component(r1_value),
            _clean_component(r2_value),
            context=context,
            require_r2=require_r2,
        )
    except ValueError as exc:
        raise WorkflowError(str(exc))
    return r1_paths, r2_paths


def _row_fastq_path_lists(row, *, require_r2=True):
    return _paired_fastq_path_lists(
        row.get("r1_path", ""),
        row.get("r2_path", ""),
        context=f"analysis unit {row.get('analysis_unit_uid', 'unknown')}",
        require_r2=require_r2,
    )


def _row_uses_direct_fastq_list(row):
    return (
        len(_split_fastq_path_list(row.get("r1_path", ""))) > 1
        or len(_split_fastq_path_list(row.get("r2_path", ""))) > 1
    )


def _is_ont_fastq_unit(row):
    ont_r1_path = _clean_component(row.get("ONT_R1_PATH", "")).lower()
    return (
        str(row.get("SEQ_VENDOR", "") or "").strip().upper() == "ONT"
        and ont_r1_path not in {"", "na", "none"}
    )


def _validate_ont_fastq_unit(row):
    if not _is_ont_fastq_unit(row):
        return
    ont_r2_path = _clean_component(row.get("ONT_R2_PATH", "")).lower()
    if ont_r2_path not in {"", "na", "none"}:
        raise WorkflowError(
            "ONT FASTQ units are single-end in DayOA: "
            f"analysis unit {row['analysis_unit_uid']} has ONT_R2_PATH='{ont_r2_path}'. "
            "Set ONT_R2_PATH to 'na' or empty."
        )


def _build_analysis_unit(row):
    parts = [
        _clean_component(row["RUNID"]),
        _clean_component(row["SAMPLEID"]),
        _clean_component(row["EXPERIMENTID"]),
        _clean_component(row["LANEID"]),
        _clean_component(row["BARCODEID"]),
        _clean_component(row.get("LIBPREP", "")),
        _clean_component(row.get("SEQ_VENDOR", "")),
        _clean_component(row.get("SEQ_PLATFORM", "")),
    ]

    parts = [p for p in parts if p]
    if not parts:
        raise WorkflowError(
            "Unable to construct analysis unit identifier; missing RUNID/SAMPLEID/EXPERIMENTID/LANEID/BARCODEID."
        )
    return "-".join(parts)


if "analysis_unit_uid" in metadata.columns:
    metadata["analysis_unit_uid"] = metadata["analysis_unit_uid"].apply(
        _clean_component
    )
    missing_uids = metadata["analysis_unit_uid"] == ""
    if missing_uids.any():
        metadata.loc[missing_uids, "analysis_unit_uid"] = metadata[missing_uids].apply(
            _build_analysis_unit, axis=1
        )
    metadata["analysis_unit_uid"] = metadata["analysis_unit_uid"]
else:
    metadata["analysis_unit_uid"] = metadata.apply(_build_analysis_unit, axis=1)

if bootstrap_unit_context:
    metadata["analysis_unit_uid"] = config["bclconvert_bootstrap_run_id"]

if metadata["analysis_unit_uid"].duplicated().any():
    dupes = metadata[metadata["analysis_unit_uid"].duplicated()]["analysis_unit_uid"].tolist()
    raise WorkflowError(
        f"Duplicate analysis unit identifiers detected: {sorted(set(dupes))}"
    )


def _configured_ont_fastq_hour_window():
    starting_hrs = config.get("use-fq_data-starting-hrs", None)
    up_to_hrs = config.get("use-fq_data-up-to-hrs", None)
    starting_missing = starting_hrs in [None, "", "None"]
    up_to_missing = up_to_hrs in [None, "", "None"]

    if starting_missing and up_to_missing:
        return None
    if starting_missing or up_to_missing:
        raise WorkflowError(
            "use-fq_data-starting-hrs and use-fq_data-up-to-hrs must be "
            "specified together."
        )

    try:
        return _fastq_path_lists.validate_fastq_hour_window(starting_hrs, up_to_hrs)
    except ValueError as exc:
        raise WorkflowError(str(exc)) from exc


ONT_FASTQ_HOUR_WINDOW = _configured_ont_fastq_hour_window()


def _filter_row_ont_fastqs_by_hour_window(row):
    if ONT_FASTQ_HOUR_WINDOW is None:
        return row
    if not _is_ont_fastq_unit(row):
        return row

    original_paths = _split_fastq_path_list(row.get("ONT_R1_PATH", ""))
    if not original_paths:
        return row

    try:
        filtered_paths = _fastq_path_lists.filter_ont_fastq_paths_by_hour_window(
            original_paths,
            ONT_FASTQ_HOUR_WINDOW[0],
            ONT_FASTQ_HOUR_WINDOW[1],
            timestamp_source="chunk-hour",
        )
    except ValueError as exc:
        raise WorkflowError(
            f"analysis unit {row['analysis_unit_uid']} ONT_R1_PATH hour-window "
            f"filter failed: {exc}"
        ) from exc

    if not filtered_paths:
        raise WorkflowError(
            f"analysis unit {row['analysis_unit_uid']} ONT_R1_PATH hour-window "
            "filter kept zero FASTQs."
        )

    if len(filtered_paths) != len(original_paths):
        print(
            "ONT FASTQ hour-window filter for "
            f"{row['analysis_unit_uid']} kept {len(filtered_paths)}/"
            f"{len(original_paths)} FASTQs for elapsed hours "
            f"[{ONT_FASTQ_HOUR_WINDOW[0]}, {ONT_FASTQ_HOUR_WINDOW[1]}).",
            file=sys.stderr,
        )

    row["ONT_R1_PATH"] = ",".join(filtered_paths)
    return row


if ONT_FASTQ_HOUR_WINDOW is not None:
    metadata = metadata.apply(_filter_row_ont_fastqs_by_hour_window, axis=1)

metadata.apply(_validate_ont_fastq_unit, axis=1)

def _select_reads(row):
    if bootstrap_unit_context and str(row.get("analysis_unit_uid", "")) == str(
        config["bclconvert_bootstrap_run_id"]
    ):
        # BCL Convert bootstrap creates FASTQs later; this synthetic row only
        # lets run-level targets parse without requiring pre-existing reads.
        return "na", "na"

    for r1, r2 in [
        ("ILMN_R1_PATH", "ILMN_R2_PATH"),
        ("PACBIO_R1_PATH", "PACBIO_R2_PATH"),
        ("ONT_R1_PATH", "ONT_R2_PATH"),
        ("UG_R1_PATH", "UG_R2_PATH"),
    ]:
        r1_path = _clean_component(row.get(r1, ""))
        r2_path = _clean_component(row.get(r2, ""))
        if r1_path:
            require_r2 = r1 != "ONT_R1_PATH"
            _paired_fastq_path_lists(
                r1_path,
                r2_path,
                context=f"analysis unit {row['analysis_unit_uid']} {r1}/{r2}",
                require_r2=require_r2,
            )
            return r1_path, r2_path if r2_path else "na"

    # Check for CRAM/BAM-only samples (Ultima, ONT, PacBio, Roche)
    for cram_col in ["ULTIMA_CRAM", "ONT_CRAM", "PB_BAM", "ONT_BAM", "ROCHE_BAM"]:
        cram_path = _clean_component(row.get(cram_col, ""))
        if cram_path:
            # Return dummy FASTQ paths for CRAM-only samples
            return "na", "na"

    raise WorkflowError(
        f"No read pairs specified for analysis unit {row['analysis_unit_uid']}."
    )


metadata["r1_path"], metadata["r2_path"] = zip(*metadata.apply(_select_reads, axis=1))
metadata["lib_prep"] = metadata.get("LIBPREP", "").replace("", "na")
metadata["instrument"] = metadata.get("SEQ_PLATFORM", "").replace("", "na")

if "MERGE_SINGLE" not in metadata.columns:
    metadata["MERGE_SINGLE"] = "single"
metadata.loc[metadata["MERGE_SINGLE"].isin(["", None]), "MERGE_SINGLE"] = "single"

metadata["sample"] = metadata["analysis_unit_uid"]
metadata["sample_lane"] = metadata["analysis_unit_uid"]
metadata["RU"] = metadata["RUNID"]
metadata["EX"] = metadata["SAMPLEID"]
metadata["SQ"] = metadata["EXPERIMENTID"]
metadata["LANE"] = metadata["LANEID"]

def _safe_int(x):
    try:
        return int(str(x))
    except Exception:
        return x


metadata["LANE"] = metadata["LANE"].apply(_safe_int)

if "TUM_NRM_SAMPLEID_MATCH" not in metadata.columns:
    metadata["TUM_NRM_SAMPLEID_MATCH"] = "na"
metadata.loc[
    metadata["TUM_NRM_SAMPLEID_MATCH"].isin(["", None, "None"]),
    "TUM_NRM_SAMPLEID_MATCH",
] = "na"

samples = metadata.set_index(["sample", "sample_lane"], drop=False)

for col, default in {
    "BIOLOGICAL_SEX": "na",
    "IDDNA_UID": "na",
    "CONCORDANCE_CONTROL_PATH": "na",
    "IS_POSITIVE_CONTROL": "false",
    "IS_NEGATIVE_CONTROL": "false",
    "SAMPLE_TYPE": "na",
    "MERGE_SINGLE": "single",
    "EXTERNAL_SAMPLE_ID": "na",
    "TRUTH_DATA_DIR": "na",
    "N_X": "na",
    "N_Y": "na",
    "ULTIMA_CRAM": "na",
    "ULTIMA_CRAM_ALIGNER": "na",
    "ULTIMA_CRAM_SNV_CALLER": "na",
    "ONT_CRAM": "na",
    "ONT_CRAM_ALIGNER": "na",
    "ONT_CRAM_SNV_CALLER": "na",
    "ULTIMA_SUBSAMPLE_PCT": "na",
    "ONT_SUBSAMPLE_PCT": "na",
    "PB_BAM": "na",
    "PB_BAM_ALIGNER": "na",
    "PB_BAM_SNV_CALLER": "na",
    "ONT_BAM": "na",
    "ONT_BAM_ALIGNER": "na",
    "ONT_BAM_SNV_CALLER": "na",
    "ROCHE_BAM": "na",
    "ROCHE_BAM_ALIGNER": "na",
    "ROCHE_BAM_SNV_CALLER": "na",
    "ROCHE_DOWNSAMPLE_RATIO": "na",
    "LONGREADTRIM_READ_LENGTH": "na",
    "LONGREADTRIM_MODE": "na",
    "DEEP_MODEL": "WGS",
    "instrument": "na",
    "lib_prep": "na",
    "BWA_KMER": str(config.get("bwa_mem2a_aln_sort", {}).get("k", "19")),
}.items():
    if col not in samples.columns:
        samples[col] = default
    samples[col] = samples[col].replace({None: default, "": default})

# Ensure tum_nrm_sampleid_match exists and treat missing values as 'na'
if "TUM_NRM_SAMPLEID_MATCH" in samples.columns:
    samples["TUM_NRM_SAMPLEID_MATCH"] = samples["TUM_NRM_SAMPLEID_MATCH"].apply(
        lambda x: "na"
        if pd.isna(x) or str(x).strip().lower() in {"", "na"}
        else str(x).strip()
    )
else:
    samples["TUM_NRM_SAMPLEID_MATCH"] = "na"

## validate the analysis_manifest.csv with the appropriate yaml schema
##validate(samples, schema="../schemas/analysis_manifest.schema.yaml")


# TODO: remove the RU/EX usage throughout, unecessary
if len(samples) > 0:
    RU = list(samples.RU)
    EX = list(samples.EX)

# Strip out Unclassified unless directed not to
if "keep_undetermined" in config:
    pass
else:
    new_samples = samples.query("SQ != 'Undetermined'")
    samples = new_samples


# scan the input files and calculate the per sample total fastq size, for use in scaling compute.

pos_samp_vcf_bed = {}

config["samp_fq_size"] = {}

for s in samples["sample"]:
    if s not in config["samp_fq_size"]:
        config["samp_fq_size"][s] = 0.0
        r1_entries = samples.loc[s, ("r1_path")]
        if isinstance(r1_entries, str):
            r1_entries = [r1_entries]
        for r1f_entry in r1_entries:
            for r1f in _split_fastq_path_list(r1f_entry):
                try:
                    config["samp_fq_size"][s] += float(
                        float(os.path.getsize(r1f)) / 1000000000.0
                    )  # Norm to GB
                except Exception as e:
                    print(e, file=sys.stderr)

# added to cluster name to uniquely identify sets of jobs from the same snakemake execution
ri2 = random.randint(0, 999)

sub_user = config["sub_user"]
config["sub_host"] = (
    str(os.environ.get("HOSTNAME"))
    if os.environ.get("HOST") in ["", "None", None]
    else str(os.environ.get("HOST"))
)
config["sub_root"] = str(os.environ.get("PWD"))
config["calling_cli"] = str(os.environ.get("DY_CALLING_CLI"))

#pop out to ipython if set in command line config
if "ipython" in config:
    from IPython import embed

    embed()
    #    Snakefile can be reloaded, to keep this from activating again, remove it
    del config["ipython"]


cluster_config["profile_name"] = config["profile_name"]
cluster_config["cwd"] = os.environ.get("PWD", "./")
cluster_config["sub_user"] = os.environ.get("USER", "na")




# --- Refactored: use explicit column names, no positional access ---

CONCORDANCE_SAMPLES = {}
CRAM_ALIGNERS = []
BAM_ALIGNERS = []
sample_info = {}
sample_lane_seen = set()

# Columns we will read (existence assumed earlier in your pipeline)
#   samp, sample, sample_lane, SQ, RU, EX, LANE, merge_single, biological_sex,
#   ultima_cram, ont_cram, ultima_cram_aligner, ont_cram_aligner, pb_bam_aligner,
#   deep_model, ultima_cram_snv_caller, ont_cram_snv_caller,
#   concordance_control_path, sample_type, is_positive_control, is_negative_control,
#   tum_nrm_sampleid_match, external_sample_id, bwa_kmer, iddna_uid, instrument, lib_prep

for _, row in samples.iterrows():
    # Keys from named columns
    samp_id       = row.get("analysis_unit_uid", "")
    sample        = row.get("sample", "")
    sample_lane   = row.get("sample_lane", "")
    sq_id         = str(row.get("SQ", ""))
    ru_id         = str(row.get("RU", ""))
    ex_id         = str(row.get("EX", ""))
    lane_id       = str(row.get("LANE", ""))
    merge_single  = str(row.get("MERGE_SINGLE", "single")).strip().lower()
    is_bcl_bootstrap_sample = bootstrap_unit_context and str(samp_id) == str(
        config["bclconvert_bootstrap_run_id"]
    )

    # Uniqueness / unsupported mode checks (kept from your original intent)
    if samp_id in sample_info and merge_single == "single":
        raise WorkflowError(
            f"\n\nMANIFEST ERROR:: {samp_id} ... {sample_lane} appears 2+ times in the sample sheet. "
            f"This should only occur if 'merge' has been specified. merge_single is '{merge_single}'."
        )

    if merge_single not in {"single", "merge"}:
        raise WorkflowError(
            f"\n\nMANIFEST ERROR '{sample}, {sample_lane}': MERGE_SINGLE must be 'single' or 'merge',"
            f" but found '{merge_single}'."
        )

    # Legacy constraint about characters (kept; now based on named cols)
    def _bad_token(x: str) -> bool:
        x = str(x)
        return ("." in x) or ("_" in x)

    if not is_bcl_bootstrap_sample and any(_bad_token(t) for t in (sq_id, ru_id, ex_id, lane_id)):
        raise WorkflowError(
            f"\n\nMANIFEST ERROR {sample} ... {sample_lane}: SQ/RU/EX/LANE may not contain '.' or '_' per current constraints."
        )

    # Prevent 'sample_lane' collisions and sample-in-lane name leakage (legacy behavior)
    if not is_bcl_bootstrap_sample and (sample_lane in sample_lane_seen or ("." in sample)):
        raise WorkflowError(
            f"\n\nMANIFEST ERROR {sample} ... {sample_lane}: 'sample_lane' must be unique; "
            f"'sample' must not contain a '.' and must not duplicate 'sample_lane'."
        )
    sample_lane_seen.add(sample_lane)

    # Ensure dict presence
    if samp_id not in sample_info:
        sample_info[samp_id] = {}

    # Copy through selected fields with normalization where you did it before
    # biological_sex normalization
    raw_bsex = str(row.get("BIOLOGICAL_SEX", "na")).strip()
    bsex = raw_bsex.lower()
    if bsex.startswith("m"):
        bsex = "male"
    elif bsex.startswith("f"):
        bsex = "female"
    else:
        bsex = "na"
    sample_info[samp_id]["biological_sex_raw"] = raw_bsex
    sample_info[samp_id]["biological_sex"] = bsex

    # Simple passthroughs
    for col, key in [
        ("ULTIMA_CRAM", "ultima_cram"),
        ("ONT_CRAM", "ont_cram"),
        ("ULTIMA_CRAM_SNV_CALLER", "ultima_cram_snv_caller"),
        ("ONT_CRAM_SNV_CALLER", "ont_cram_snv_caller"),
        ("ROCHE_BAM", "roche_bam"),
        ("ROCHE_BAM_SNV_CALLER", "roche_bam_snv_caller"),
        ("ROCHE_DOWNSAMPLE_RATIO", "roche_downsample_ratio"),
        ("SAMPLE_TYPE", "sample_type"),
        ("IS_POSITIVE_CONTROL", "is_positive_control"),
        ("IS_NEGATIVE_CONTROL", "is_negative_control"),
        ("TUM_NRM_SAMPLEID_MATCH", "tum_nrm_sampleid_match"),
        ("EXTERNAL_SAMPLE_ID", "external_sample_id"),
        ("BWA_KMER", "bwa_kmer"),
    ]:
        sample_info[samp_id][key] = row.get(col, "")
    for derived_col in [
        ("instrument", "instrument"),
        ("lib_prep", "lib_prep"),
    ]:
        sample_info[samp_id][derived_col[1]] = row.get(derived_col[0], "")

    # iddna_uid split (legacy behavior)
    iddna_uid_val = row.get("IDDNA_UID", "")
    if iddna_uid_val not in (None, "", "na", "NA", "None"):
        sample_info[samp_id]["iddna_uid"] = str(iddna_uid_val).split(":")
    else:
        sample_info[samp_id]["iddna_uid"] = iddna_uid_val

    # deep_model validation
    deep_models_ok = {
        "WGS", "WES", "PACBIO", "HYBRID_PACBIO_ILLUMINA", "ONT_R104", "ONT_R941"
    }
    dm = str(row.get("DEEP_MODEL", "") or "").strip().upper()
    if dm not in deep_models_ok:
        print(
            f"\nWARNING::: deep_model '{dm or 'NA'}' not in {sorted(deep_models_ok)}. Using 'WGS'.\n",
            file=sys.stderr,
        )
        dm = "WGS"
    sample_info[samp_id]["deep_model"] = dm

    # Concordance control path
    cpath = row.get("CONCORDANCE_CONTROL_PATH", "")
    sample_info[samp_id]["concordance_control_path"] = cpath
    if cpath not in ["na", "NA", "", None, "None"]:
        CONCORDANCE_SAMPLES[samp_id] = cpath

    # Track CRAM aligners (non-empty values only)
    for aligner_col in ("ULTIMA_CRAM_ALIGNER", "ONT_CRAM_ALIGNER", "PB_BAM_ALIGNER", "ONT_BAM_ALIGNER"):
        aval = str(row.get(aligner_col, "") or "").strip()
        if aval and aval.lower() not in {"na", "none", "hyb"}:
            CRAM_ALIGNERS.append(aval)

    # ONT FASTQ rows align through sentmm2ont and then use the CRAM passthrough
    # into downstream ONT DNAscope rules.
    if _is_ont_fastq_unit(row):
        CRAM_ALIGNERS.append("sentmm2ont")

    # Track BAM-only aligners (Roche stays as BAM, not CRAM)
    for aligner_col in ("ROCHE_BAM_ALIGNER",):
        aval = str(row.get(aligner_col, "") or "").strip()
        if aval and aval.lower() not in {"na", "none", "hyb"}:
            BAM_ALIGNERS.append(aval)

# De-duplicate CRAM and BAM aligners
CRAM_ALIGNERS = sorted(set(CRAM_ALIGNERS))
BAM_ALIGNERS = sorted(set(BAM_ALIGNERS))

config["sample_info"] = sample_info


# --- Positive/Negative control sample lists ---------------------------------
def _truthy(x):
    return str(x or "").strip().lower() in {"true", "t", "1", "yes", "y"}


POSITIVE_CONTROL_SAMPLE_TYPE_TOKENS = {
    "pos_control",
    "poscontrol",
    "positive_control",
    "positivecontrol",
    "control_positive",
}

NEGATIVE_CONTROL_SAMPLE_TYPE_TOKENS = {
    "neg_control",
    "negcontrol",
    "negative_control",
    "negativecontrol",
    "control_negative",
    "ntc",
    "no_template",
    "no_template_control",
    "notemplatecontrol",
}

CONTROL_SAMPLE_TYPE_TOKENS = (
    POSITIVE_CONTROL_SAMPLE_TYPE_TOKENS | NEGATIVE_CONTROL_SAMPLE_TYPE_TOKENS
)


def _metadata_sample_id(wildcards_or_sample):
    return str(getattr(wildcards_or_sample, "sample", wildcards_or_sample))


def sample_metadata(sample):
    sample_id = _metadata_sample_id(sample)
    info = config.get("sample_info", {}).get(sample_id)
    if info is None:
        raise WorkflowError(f"Missing sample_info metadata for sample {sample_id}.")
    return info


def _sample_type_token(info):
    return re.sub(
        r"[^a-z0-9]+",
        "_",
        str(info.get("sample_type", "") or "").strip().lower(),
    ).strip("_")


def is_positive_control_sample(sample):
    info = sample_metadata(sample)
    return _truthy(info.get("is_positive_control")) or (
        _sample_type_token(info) in POSITIVE_CONTROL_SAMPLE_TYPE_TOKENS
    )


def is_negative_control_or_ntc_sample(sample):
    info = sample_metadata(sample)
    return _truthy(info.get("is_negative_control")) or (
        _sample_type_token(info) in NEGATIVE_CONTROL_SAMPLE_TYPE_TOKENS
    )


def is_control_sample(sample):
    info = sample_metadata(sample)
    return (
        is_positive_control_sample(sample)
        or is_negative_control_or_ntc_sample(sample)
        or _sample_type_token(info) in CONTROL_SAMPLE_TYPE_TOKENS
    )


def qc_eligible_sample_ids(sample_ids=None):
    if sample_ids is None:
        sample_ids = globals().get("SSAMPS", [])
    return [
        str(sample)
        for sample in sample_ids
        if not is_negative_control_or_ntc_sample(sample)
    ]


def require_qc_eligible_sample(wildcards_or_sample, tool_name):
    sample = _metadata_sample_id(wildcards_or_sample)
    if is_negative_control_or_ntc_sample(sample):
        info = sample_metadata(sample)
        raise WorkflowError(
            f"{tool_name} excludes negative-control/NTC sample {sample}; "
            f"is_negative_control={info.get('is_negative_control')!r}, "
            f"is_positive_control={info.get('is_positive_control')!r}, "
            f"sample_type={info.get('sample_type')!r}."
        )
    return "ok"


POS_CONTROL_SAMPLES = sorted(
    s for s, info in sample_info.items()
    if is_positive_control_sample(s)
)

NEG_CONTROL_SAMPLES = sorted(
    s for s, info in sample_info.items()
    if is_negative_control_or_ntc_sample(s)
)

_conflicting_control_samples = sorted(
    s
    for s in sample_info
    if is_positive_control_sample(s) and is_negative_control_or_ntc_sample(s)
)
if _conflicting_control_samples:
    raise WorkflowError(
        "Sample metadata marks sample(s) as both positive control and "
        "negative-control/NTC: " + ", ".join(_conflicting_control_samples)
    )

# If you want the concordance control path for just the positive controls:
POS_CONTROL_PATHS = {
    s: p for s, p in CONCORDANCE_SAMPLES.items() if s in POS_CONTROL_SAMPLES
}

# Optional sanity check: a sample is marked positive control but has no path
_missing = [s for s in POS_CONTROL_SAMPLES if s not in CONCORDANCE_SAMPLES]
if _missing:
    raise WorkflowError(
        f"Positive controls missing 'concordance_control_path': {_missing}"
    )


# Build tumor->normal map
def _norm(x):
    return str(x or "").strip().lower()

TN_PAIRS = {}

for tsamp, tinfo in sample_info.items():
    if _norm(tinfo.get("sample_type")) not in {"tumor", "tumour"}:
        continue

    pair_id = str(tinfo.get("tum_nrm_sampleid_match", "")).strip()
    if pair_id.lower() in {"", "na", "nan"}:
        # no pairing label / direct reference; skip
        continue

    # 1) Shared-label pairing: find a normal/blood with same label
    candidates = [
        nsamp2 for nsamp2, ninfo in sample_info.items()
        if str(ninfo.get("tum_nrm_sampleid_match", "")).strip() == pair_id
        and _norm(ninfo.get("sample_type")) in {"normal", "blood"}
    ]

    # 2) If none, treat the value as a direct normal sample ID
    if not candidates:
        ninfo = sample_info.get(pair_id)
        if ninfo and _norm(ninfo.get("sample_type")) in {"normal", "blood"}:
            candidates = [pair_id]

    if len(candidates) == 1:
        TN_PAIRS[tsamp] = candidates[0]
    elif len(candidates) > 1:
        raise WorkflowError(f"Ambiguous normal for tumor '{tsamp}' (pair='{pair_id}') -> {candidates}")
    else:
        raise WorkflowError(f"No normal found for tumor '{tsamp}' (pair='{pair_id}')")

TN_TUMOR_SAMPS = list(TN_PAIRS.keys())

# Optional: restrict rules’ sample wildcard to tumors only
TUMORS_REGEX = "|".join(re.escape(s) for s in TN_TUMOR_SAMPS) or r"^$"

CRAM_ALIGNERS = list(set(CRAM_ALIGNERS))
# Aspirationally hoping to adopt PEPs...
# http://pep.databio.org/en/latest/

instanceid = 'na'
CLUSTER_PRI=""

# #### UTILITY METHODS
# -------------------
# Return just the R1 file for a given sampleid
# note the sort of strange invocation of this method in the rule below
# you specify simply 'get_fastq_rq', without(), and the wildcards
# special variable is inserted.  It holds all of the current pattern
# matching values for the instance of the rule being run.  So for each
# rule being run calling 'get_fastq_r1' (even many at once), the {sample}
# pattern match w/in the rule is passed along in wildcards, which here
# I'm using to get just the R1 read for this sample.
def get_fastq_r1(wildcards):
    file = ""
    for f in samples["r1_path"]:
        if len(f.split(wildcards.sample)) > 1:
            file = os.path.abspath(f)
    return file


# extract the current pattern matching samplePlusR
# from the calling rule wildcards obj passed to the
# method. Since this is matching my sample name AND
# the R1/R2 bit of the file name as well, the
# samplePlusR will be unique with the R1/2 added
# we just return one file path here


def get_raw_R1s(wildcards):
    r1s = []
    for r1_path in samples[samples["sample"] == wildcards.sample]["r1_path"]:
        r1s.extend(_split_fastq_path_list(r1_path))
    return r1s


def get_raw_R2s(wildcards):
    r2s = []
    for r2_path in samples[samples["sample"] == wildcards.sample]["r2_path"]:
        r2s.extend(_split_fastq_path_list(r2_path))
    return r2s


def _fastq_qc_pairs(sample):
    pairs = []
    for _, row in samples[samples["sample"] == sample].iterrows():
        r1_paths = _split_fastq_path_list(row.get("r1_path", ""))
        r2_paths = _split_fastq_path_list(row.get("r2_path", ""))
        if not r1_paths or not r2_paths:
            continue
        if len(r1_paths) != len(r2_paths):
            raise WorkflowError(
                f"analysis unit {row.get('analysis_unit_uid', 'unknown')}: "
                f"R1 and R2 path lists must have the same number of entries "
                f"(R1={len(r1_paths)}, R2={len(r2_paths)})"
            )
        pairs.extend(
            (os.path.abspath(r1), os.path.abspath(r2))
            for r1, r2 in zip(r1_paths, r2_paths)
        )
    return pairs


def sample_has_fastq_qc_inputs(sample):
    return bool(_fastq_qc_pairs(sample))


def get_raw_fastq_qc_R1s(wildcards):
    return [r1 for r1, _r2 in _fastq_qc_pairs(wildcards.sample)]


def get_raw_fastq_qc_R2s(wildcards):
    return [r2 for _r1, r2 in _fastq_qc_pairs(wildcards.sample)]


def get_fastq_r1_r2(wildcards):
    # generate filepaths corresponding to {sample} : {RR} combos
    if wildcards.RR == "R1":
        return None if samples.loc[wildcards.sample, "r1_path"] in ["na","",None] else os.path.abspath(samples.loc[wildcards.sample, "r1_path"])
    elif wildcards.RR == "R2":
        return  None if samples.loc[wildcards.sample, "r1_path"] in ["na","",None] else os.path.abspath(samples.loc[wildcards.sample, "r2_path"])
    else:
        raise ValueError(f"invalid value: {wildcards.RR}")


# Helper method to read the pandas dataframe for the 'sample' IDs
# from the samples.csv spreadsheet.   Used for pattern matching all
# of the expected sample IDs. No wildcards used.
def get_samp_ids():
    samps = {}
    for ii in samples["sample"]:
        if "just_this_sample" in config:
            if config["just_this_sample"] == ii:
                samps[ii] = True
        else:
            samps[ii] = True
    if len(samps.keys()) == 0 and "run_b2fq" not in config and not BCL_BOOTSTRAP_MODE:
        raise Exception(
            "NO SAMPLES HAVE BEEN LOADED TO THE SAMPS ARRAY -or- if running Bcl2FQ, the --config run_b2fq=true and assoc params are not set."
        )
    return samps.keys()


SAMP_SAMPI = []  #  deprecate
for ix in samples.index:
    sample_x = f"{ix[0]}/{ix[1]}"
    SAMP_SAMPI.append(sample_x)


SSI = SAMP_SAMPI  # deprecate
SAMPS = list(get_samp_ids())

# TODO: Revisit if this is still in use
if "remove_samples" in config:
    for rs in config["remove_samples"]:
        SAMPS.remove(rs)
        print(f"SAMPLE REMOVED: {rs}")

FASTQ_QC_SAMPS = [sample for sample in SAMPS if sample_has_fastq_qc_inputs(sample)]

SSAMPS = {}
for sample in samples["sample"].unique():
    row = samples[samples["sample"] == sample]
    ss = first_val(row, "analysis_unit_uid")
    SSAMPS.setdefault(ss, []).append(sample)

QC_ELIGIBLE_SAMPLES = qc_eligible_sample_ids(SSAMPS)


# Tumor-normal pairs
TN_DICT = {}
for match_id, grp in samples.groupby("TUM_NRM_SAMPLEID_MATCH"):
    _match = "" if pd.isna(match_id) else str(match_id).strip().lower()
    if _match in {"", "na"}:
        # skip unpaired entries
        continue
    if len(grp) != 2:
        raise WorkflowError(
            f"tum_nrm_sampleid_match '{match_id}' has {len(grp)} entries; expected exactly 2"
        )
    tumors = grp[grp["SAMPLE_TYPE"].str.lower() == "tumor"]["sample"].tolist()
    normals = grp[grp["SAMPLE_TYPE"].str.lower() == "normal"]["sample"].tolist()
    if len(tumors) != 1 or len(normals) != 1:
        raise WorkflowError(
            f"tum_nrm_sampleid_match '{match_id}' requires one tumor and one normal but found {len(tumors)} tumor(s) and {len(normals)} normal(s)"
        )
    TN_DICT[tumors[0]] = normals[0]
TUMOR_SAMPLES = list(TN_DICT.keys())

def get_normal_sample(wildcards):
    return TN_DICT[wildcards.sample]


SAMP_SAMPI_INDEX = list(samples.index)  # deprecate
RR = ["R1", "R2"]


def _alignment_fastq_inputs(wildcards, mate):
    paths = []
    for _, row in samples[samples["sample"] == wildcards.sample].iterrows():
        r1s, r2s = _row_fastq_path_lists(row, require_r2=False)
        if _row_uses_direct_fastq_list(row):
            paths.extend(r1s if mate == "R1" else r2s)
            continue
        paths.append(
            f"{MDIR}{wildcards.sample}/{row['sample_lane']}.{mate}.fastq.gz"
        )
    return paths


def getR2s(wildcards):
    return _alignment_fastq_inputs(wildcards, "R2")


def getR1s(wildcards):
    return _alignment_fastq_inputs(wildcards, "R1")

def getCRAMs(wildcards):
    crams = []
    for ss_cram in samples.loc[wildcards.sample, "cram"]:
        if ss_cram not in [None, "None", "", "na"]:
            cram = os.path.abspath(cram)
        else:
            pass
    return sorted(crams)

def getR2sS(wildcards):
    fr2s = []
    for r2 in samples[samples["analysis_unit_uid"] == wildcards.sample]["r2_path"]:
        fr2s.extend(_split_fastq_path_list(r2))
    return fr2s


def getR1sS(wildcards):
    fr1s = []
    for r1 in samples[samples["analysis_unit_uid"] == wildcards.sample]["r1_path"]:
        fr1s.extend(_split_fastq_path_list(r1))
    return fr1s


# Call from params block to get sample ID back, without() wildcards (and others ) are added automatically if no () is included.
def ret_sample(wildcards):
    if "analysis_unit_uid" in wildcards.keys():
        return wildcards.analysis_unit_uid # if len(str(wildcards.analysis_unit_uid).split(" ")) < 1 else "sample-len-zero2"
    if "sample" in wildcards.keys():
        return wildcards.sample  #if len(str(wildcards.sample).split(" ")) < 1 else "sample-len-zero1"
    else:
        return "get-sample-ERROR"

def ret_sample_sentD(wildcards):
    return wildcards.sample


def ret_sample_sv(wildcards):
    return f"{wildcards.sample}_{wildcards.s_v_caller}"


def ret_sample_snv(wildcards):
    return f"{wildcards.sample}_{wildcards.snv}"


def ret_sample_alnr(wildcards):
    return f"{wildcards.sample}_{wildcards.alnr}"


def get_bwa_kmer_size(wildcards):
    ret_k = None

    if wildcards.sample in config["sample_info"]:
        if "bwa_kmer" in config["sample_info"][wildcards.sample]:
            ret_k = int(config["sample_info"][wildcards.sample]["bwa_kmer"])
    if ret_k in ["None", None]:
        ret_k = config["bwa_mem2a_aln_sort"]["k"]
    return f" -k {ret_k} "


def ret_mod_chrm(ret_str):

    if ret_str[0] in ['c']:
        if ret_str[3:5] in ['23']:
            ret_str = ret_str[0:3] + "X" + ret_str[5:]
        elif ret_str[3:5] in ['24']:
            ret_str = ret_str[0:3] + "Y" + ret_str[5:]
        elif ret_str[3:5] in ['25']:
            ret_str = ret_str[0:3] + "MT" + ret_str[5:]
    else:
        if ret_str[0:2] in ['23']:
            ret_str =  "X" + ret_str[2:]
        elif ret_str[0:2] in ['24']:
            ret_str =  "Y" + ret_str[2:]
        elif ret_str[0:2] in ['25']:
            ret_str =  "MT" + ret_str[2:]

    return ret_str


## Method to wrap the bwa fastq reader with seqtk to subsample
# if a SUBSAMPLE_PCT column is present in the sample sheet, return the back end of the process substitution
# which will do the subsampling
def get_subsample_head_tail(sample_id):
    ss_head = ss_tail = ""
    row = samples[samples["sample"] == sample_id]
    ss_pct = (first_val(row, "SUBSAMPLE_PCT") or "").strip()
    if ss_pct in {"", "na", "None", "0", "0.0", 0, 100, "100", "100.0", 100.0}:
        return ("", "")
    try:
        f = float(ss_pct)
    except Exception as e:
        raise WorkflowError(f"SUBSAMPLE_PCT must be a float in (0.0,1.0]; got '{ss_pct}'") from e
    if not (0.0 < f <= 1.0):
        raise WorkflowError(f"SUBSAMPLE_PCT must be in (0.0,1.0]; got {f}")
    return (f" <( seqkit sample -j 16 --line-width=0 --quiet --rand-seed=7 --seq-type=dna --proportion={f} ",
            " ) ")



def get_subsample_head(wildcards):
    return get_subsample_head_tail(wildcards.sample)[0]

def get_subsample_tail(wildcards):
    return get_subsample_head_tail(wildcards.sample)[1]


## Method to wrap the fastq reader with seqkit subseq to trim reads to a fixed length
# if ILMN_TRIM_READ_LENGTH column is present in the sample sheet, return the shell fragments
# for process substitution that will truncate reads from the 3' end.
# Uses pipe instead of nested process substitution to avoid seqkit read errors.
def get_ilmn_trim_head_tail(sample_id):
    row = samples[samples["sample"] == sample_id]
    trim_len = (first_val(row, "ILMN_TRIM_READ_LENGTH") or "").strip()
    if trim_len in {"", "na", "None", "0"}:
        return ("", "")
    try:
        length = int(trim_len)
    except Exception as e:
        raise WorkflowError(
            f"ILMN_TRIM_READ_LENGTH must be a positive integer or 'na'; got '{trim_len}'"
        ) from e
    if length <= 0:
        raise WorkflowError(f"ILMN_TRIM_READ_LENGTH must be positive; got {length}")
    return (f" | seqkit subseq -j 16 --line-width=0 --quiet --seq-type=dna -r 1:{length} ", "")
    # seqkit sample -j 16 --line-width=0 --quiet --rand-seed=7 --seq-type=dna --proportion={f}


def get_ilmn_trim_head(wildcards):
    return get_ilmn_trim_head_tail(wildcards.sample)[0]

def get_ilmn_trim_tail(wildcards):
    return get_ilmn_trim_head_tail(wildcards.sample)[1]


## Long-read trimming helpers (ONT / PacBio)
# Controlled by LONGREADTRIM_READ_LENGTH and LONGREADTRIM_MODE columns.
# Modes: 'head' (remove first N bases), 'tail' (remove last N bases),
#        'consecutive' (non-overlapping N-base subreads via seqkit sliding).
def get_longread_trim_head_tail(sample_id):
    row = samples[samples["sample"] == sample_id]
    trim_len = (first_val(row, "LONGREADTRIM_READ_LENGTH") or "").strip()
    trim_mode = (first_val(row, "LONGREADTRIM_MODE") or "").strip().lower()

    if trim_len in {"", "na", "None", "0"} or trim_mode in {"", "na", "None"}:
        return ("", "")

    try:
        length = int(trim_len)
    except Exception as e:
        raise WorkflowError(
            f"LONGREADTRIM_READ_LENGTH must be a positive integer or 'na'; got '{trim_len}'"
        ) from e
    if length <= 0:
        raise WorkflowError(f"LONGREADTRIM_READ_LENGTH must be positive; got {length}")

    if trim_mode == "head":
        # Remove the first N bases from every read
        return (f" | seqkit subseq -j 16 --line-width=0 --quiet --seq-type=dna -r {length + 1}:-1 ", "")
    elif trim_mode == "tail":
        # Remove the last N bases from every read
        return (f" | seqkit subseq -j 16 --line-width=0 --quiet --seq-type=dna -r 1:-{length + 1} ", "")
    elif trim_mode == "consecutive":
        # Split each read into consecutive non-overlapping N-base subreads
        return (f" | seqkit sliding -j 16 --line-width=0 --quiet --seq-type=dna -s {length} -W {length} ", "")
    else:
        raise WorkflowError(
            f"LONGREADTRIM_MODE must be 'head', 'tail', or 'consecutive'; got '{trim_mode}'"
        )


def get_longread_trim_head(wildcards):
    return get_longread_trim_head_tail(wildcards.sample)[0]


def get_longread_trim_tail(wildcards):
    return get_longread_trim_head_tail(wildcards.sample)[1]


def get_samp_name(wildcards):
    return wildcards.sample


def get_instrument(wildcards):
    return samples[samples["analysis_unit_uid"] == wildcards.sample]["instrument"][0]


VALID_REQUIRED_SAMPLE_SEXES = {"male", "female"}


def _sex_sample_id(wildcards_or_sample):
    return str(getattr(wildcards_or_sample, "sample", wildcards_or_sample))


def _sample_info_for_required_sex(sample):
    return config.get("sample_info", {}).get(sample, {})


def sample_sex_for_required_tool(wildcards_or_sample, tool_name):
    """Return a valid sex value for tools that require male/female.

    Unknown, blank, na, none, or otherwise invalid manifest values are treated as
    male by request. Callers should also write sample_sex_assumption_log() to the
    tool log so the assumption is visible in workflow outputs.
    """
    sample = _sex_sample_id(wildcards_or_sample)
    sample_info = _sample_info_for_required_sex(sample)
    sex = str(sample_info.get("biological_sex", "")).strip().lower()
    if sex in VALID_REQUIRED_SAMPLE_SEXES:
        return sex
    return "male"


def sample_sex_assumption_log(wildcards_or_sample, tool_name):
    sample = _sex_sample_id(wildcards_or_sample)
    sample_info = _sample_info_for_required_sex(sample)
    sex = str(sample_info.get("biological_sex", "")).strip().lower()
    if sex in VALID_REQUIRED_SAMPLE_SEXES:
        return ""

    raw_sex = str(sample_info.get("biological_sex_raw", sex)).strip()
    if raw_sex == "":
        raw_sex = "<empty>"
    return (
        f"WARNING: {tool_name} requires biological_sex male/female for sample "
        f"{sample}; observed biological_sex={raw_sex!r}. Assuming male.\n"
    )


def _resolve_sample_sex(wildcards):
    """Resolve biological sex for a sample.

    Priority:
      1. N_X / N_Y columns  (2/0 → female, 1/1 → male)
      2. BIOLOGICAL_SEX column
      3. Default → "male"
    """
    try:
        row = samples[samples["analysis_unit_uid"] == wildcards.sample].iloc[0]

        # --- 1. Try N_X and N_Y columns ---
        n_x = str(row.get("N_X", "na")).strip().lower()
        n_y = str(row.get("N_Y", "na")).strip().lower()
        if n_x not in ("na", "", "none") and n_y not in ("na", "", "none"):
            try:
                n_x_int, n_y_int = int(n_x), int(n_y)
                if n_x_int == 2 and n_y_int == 0:
                    return "female"
                if n_x_int == 1 and n_y_int == 1:
                    return "male"
            except (ValueError, TypeError):
                pass

        # --- 2. Fall back to BIOLOGICAL_SEX ---
        bsex = str(row.get("BIOLOGICAL_SEX", "na")).strip().lower()
        if bsex == "male":
            return "male"
        if bsex == "female":
            return "female"

        # --- 3. Default to male ---
        return "male"
    except Exception as e:
        print(
            f"WARNING::: Unable to resolve sex for sample {wildcards.sample}, defaulting to male -- {e}",
            file=sys.stderr,
        )
        return "male"


def get_diploid_bed_arg(wildcards):
    """Return diploid BED arg for sentieon-cli (-b shorthand)."""
    sex = _resolve_sample_sex(wildcards)
    if sex == "male":
        return f' -b {config["supporting_files"]["files"]["huref"]["male_diploid"]["name"]} '
    return f' -b {config["supporting_files"]["files"]["huref"]["female_diploid"]["name"]} '


def get_diploid_bed_interval_arg(wildcards):
    """Return diploid BED arg for sentieon driver (--interval flag)."""
    sex = _resolve_sample_sex(wildcards)
    if sex == "male":
        return f' --interval {config["supporting_files"]["files"]["huref"]["male_diploid"]["name"]} '
    return f' --interval {config["supporting_files"]["files"]["huref"]["female_diploid"]["name"]} '


def get_diploid_bed_path(wildcards):
    """Return the sample-sex diploid BED path without adding a caller flag."""
    sex = _resolve_sample_sex(wildcards)
    if sex == "male":
        return config["supporting_files"]["files"]["huref"]["male_diploid"]["name"]
    return config["supporting_files"]["files"]["huref"]["female_diploid"]["name"]


def get_haploid_bed_arg(wildcards):
    sex = _resolve_sample_sex(wildcards)
    if sex == "male":
        haploid_path = config["supporting_files"]["files"]["huref"]["male_haploid"]["name"]
        if haploid_path:
            return f' --haploid_bed {haploid_path} '
    return ' '


def print_wildcards_etc(wildcards):
    print("All Wildcards: ", wildcards,  " all snv_CALLERS: ", snv_CALLERS, " all ALIGNERS: ", ALIGNERS, " all CRAM_ALIGNERS: ", CRAM_ALIGNERS, " all samples: ", SSAMPS, " all concordance samples: ", CONCORDANCE_SAMPLES.keys(), file=sys.stderr)

def get_alnr(wildcards):
    return wildcards.alnr


def get_vepchrm(wildcards):
    return _day_chrm_token_to_contig(wildcards.vepchrm)


def get_vep_allowed_contigs(wildcards):
    return ",".join(VEP_CHRMS)


def get_dchrm_day(wildcards):
    pchr = GENOME_CHR_PREFIX
    mito_code = "MT" if "b37" == config['genome_build'] else "M"

    chrm_map = {'23': 'X', '24': 'Y', '25': mito_code}

    def _chrm_name(n):
        """Map numeric chromosome ID to proper name (23=X, 24=Y, 25=MT/M)."""
        s = str(n)
        return pchr + chrm_map.get(s, s)

    raw = wildcards.dchrm.replace('chr', '')
    sl = raw.split("-")
    sl2 = raw.split("~")

    if len(sl2) == 2:
        # Sub-region notation (e.g. "1~100000-200000"), preserved as-is
        ret_str = pchr + wildcards.dchrm
    elif len(sl) == 1:
        ret_str = _chrm_name(sl[0])
    elif len(sl) == 2:
        start = int(sl[0])
        end = int(sl[1])
        ret_str = ','.join(_chrm_name(i) for i in range(start, end + 1))
    else:
        raise Exception(
            "sentD chunks can only be one contiguous range per chunk : ie: 1-4 with the non numerical chrms assigned 23=X, 24=Y, 25=MT"
        )

    return ret_str


def get_gatkchrm(wildcards):
    """Map gatkchrm wildcard to proper chromosome names for Sentieon GATK HaplotypeCaller."""
    pchr = GENOME_CHR_PREFIX
    mito_code = "MT" if "b37" == config['genome_build'] else "M"

    chrm_map = {'23': 'X', '24': 'Y', '25': mito_code}

    def _chrm_name(n):
        s = str(n)
        return pchr + chrm_map.get(s, s)

    raw = wildcards.gatkchrm.replace('chr', '')
    sl = raw.split("-")
    sl2 = raw.split("~")

    if len(sl2) == 2:
        ret_str = pchr + wildcards.gatkchrm
    elif len(sl) == 1:
        ret_str = _chrm_name(sl[0])
    elif len(sl) == 2:
        start = int(sl[0])
        end = int(sl[1])
        ret_str = ','.join(_chrm_name(i) for i in range(start, end + 1))
    else:
        raise Exception(
            "gatk chunks can only be one contiguous range per chunk : ie: 1-4 with 23=X, 24=Y, 25=MT"
        )

    return ret_str


def get_dvchrm_day(wildcards):
    pchr="" #prefix handled already
    ret_str = ""
    sl = wildcards.dvchrm.replace('chr','').split("-")
    sl2 = wildcards.dvchrm.replace('chr','').split("~")
    
    if len(sl2) == 2:
        ret_str = pchr + wildcards.dvchrm
    elif len(sl) == 1:
        ret_str = pchr + sl[0]
    elif len(sl) == 2:
        start = int(sl[0])
        end = int(sl[1])
        while start <= end:
            ret_str = str(ret_str) + " " + pchr + str(start)
            start = start + 1
    else:
        raise Exception(
            "deep chunks can only be one contiguous range per chunk : ie: 1-4 with the non numerical chrms assigned 23=X, 24=Y, 25=MT"
        )

    return ret_mod_chrm(ret_str)


def get_dvsom_chrm_day(wildcards):
    pchr=""  # prefix handled already
    ret_str = ""
    sl = wildcards.dvsomchrm.replace('chr', '').split("-")
    sl2 = wildcards.dvsomchrm.replace('chr', '').split("~")

    if len(sl2) == 2:
        ret_str = pchr + wildcards.dvsomchrm
    elif len(sl) == 1:
        ret_str = pchr + sl[0]
    elif len(sl) == 2:
        start = int(sl[0])
        end = int(sl[1])
        while start <= end:
            ret_str = str(ret_str) + " " + pchr + str(start)
            start = start + 1
    else:
        raise Exception(
            "deep somatic chunks can only be one contiguous range per chunk : ie: 1-4 with the non numerical chrms assigned 23=X, 24=Y,25=MT"
        )

    return ret_mod_chrm(ret_str)


def get_mutect2_chrm_day(wildcards):
    pchr=""  # prefix handled already
    ret_str = ""
    sl = wildcards.m2chrm.replace('chr', '').split("-")
    sl2 = wildcards.m2chrm.replace('chr', '').split("~")

    if len(sl2) == 2:
        ret_str = pchr + wildcards.m2chrm

    elif len(sl) == 1:
        ret_str = pchr + sl[0]
    elif len(sl) == 2:
        start = int(sl[0])
        end = int(sl[1])
        while start <= end:
            ret_str = str(ret_str) + " " + pchr + str(start)
            start = start + 1
    else:
        raise Exception(
            "mutect2 chunks can only be one contiguous range per chunk : ie: 1-4 with the non numerical chrms assigned 23=X, 24=Y,25=MT"

        )

    return ret_mod_chrm(ret_str)


def get_senttn_chrm_day(wildcards):
    pchr=""  # prefix handled already
    ret_str = ""
    sl = wildcards.senttnchrm.replace('chr', '').split("-")
    sl2 = wildcards.senttnchrm.replace('chr', '').split("~")

    if len(sl2) == 2:
        ret_str = pchr + wildcards.senttnchrm
    elif len(sl) == 1:
        ret_str = pchr + sl[0]
    elif len(sl) == 2:
        start = int(sl[0])
        end = int(sl[1])
        while start <= end:
            ret_str = str(ret_str) + " " + pchr + str(start)
            start = start + 1
    else:
        raise Exception(
            "senttn chunks can only be one contiguous range per chunk : ie: 1-4 with the non numerical chrms assigned 23=X, 24=Y,25=MT"
        )

    return ret_mod_chrm(ret_str)


def get_deep_model(wildcards):
    deep_model="WGS"

    try:
        deep_model = samples[samples["analysis_unit_uid"] == wildcards.sample]["DEEP_MODEL"][0]
    except Exception as e:
        print(f"'deep_model' key not found" + str(e), file=sys.stderr)
    
    return deep_model if deep_model not in ["na","",None,"None"] else 'WGS'


def instrument(wildcards):
    instrument = "na"
    try:
        instrument = samples[samples["analysis_unit_uid"] == wildcards.sample]["instrument"][0].lower()
    except Exception as e:
        instrument = "na"
    return instrument


# Known CRAM-producing aligners.  When any of these appear in ALIGNERS
# (e.g. via auto-detection) but are missing from CRAM_ALIGNERS (which is
# populated from samples.tsv), reconcile here so they are never routed
# through the BAM-based no_dedup / markdup rules.
GRAPH_ONLY_PANGENOME_ALIGNERS = {"pangenome_sr", "pangenome_ug"}
PANGENOME_SENTPG_DEDUPER = "spmd"
_KNOWN_CRAM_ALIGNERS = {"sentmm2", "sentmm2ont", "ug", "ont", "pb"}
for _a in ALIGNERS:
    if _a in _KNOWN_CRAM_ALIGNERS and _a not in CRAM_ALIGNERS:
        CRAM_ALIGNERS.append(_a)
CRAM_ALIGNERS = sorted(set(CRAM_ALIGNERS))

_KNOWN_BAM_ALIGNERS = {"roche"}
for _a in ALIGNERS:
    if _a in _KNOWN_BAM_ALIGNERS and _a not in BAM_ALIGNERS:
        BAM_ALIGNERS.append(_a)
BAM_ALIGNERS = sorted(set(BAM_ALIGNERS))

OG_ALIGNERS=list(set(ALIGNERS)-set(CRAM_ALIGNERS)-set(BAM_ALIGNERS))
ALL_ALIGNERS=list(set(ALIGNERS+CRAM_ALIGNERS+BAM_ALIGNERS))
QC_CRAM_ALIGNERS=sorted(set(ALL_ALIGNERS)-set(BAM_ALIGNERS)-GRAPH_ONLY_PANGENOME_ALIGNERS)


# SMN orthogonal callers need stricter routing than generic CRAM QC.  The
# HiOMR wildcard aligner is long-read-facing, but the short-read SMN callers
# must consume the HiOMR SR dedup CRAM produced by sentdhiomr.
SMN_LONG_READ_ALIGNERS = {"ont", "sentmm2ont"}
SMN_SHORT_READ_EXCLUDED_ALIGNERS = (
    SMN_LONG_READ_ALIGNERS | {"sentmm2", "pb"} | GRAPH_ONLY_PANGENOME_ALIGNERS
)
SMN_SHORT_READ_NA_DEDUP_ALIGNERS = {"bwa2a", "sent", "strobe"}


def _smn_hiomr_aligners():
    return set(globals().get("ALIGNERS_DHIOMR", []))


def smn_short_read_aligners():
    short_alnrs = set(QC_CRAM_ALIGNERS) - SMN_SHORT_READ_EXCLUDED_ALIGNERS
    short_alnrs.update(_smn_hiomr_aligners())
    return sorted(short_alnrs)


def smn_long_read_aligners():
    long_alnrs = set(QC_CRAM_ALIGNERS) & SMN_LONG_READ_ALIGNERS
    long_alnrs.update(_smn_hiomr_aligners())
    return sorted(long_alnrs)


def smn_short_read_alnr_ddup_pairs():
    pairs = []
    hiomr_alnrs = _smn_hiomr_aligners()
    for alnr in smn_short_read_aligners():
        if alnr in hiomr_alnrs:
            if "na" in DDUP:
                pairs.append((alnr, "na"))
            continue
        if alnr in SMN_SHORT_READ_EXCLUDED_ALIGNERS:
            continue
        for ddup in DDUP:
            if ddup != "na" or alnr in SMN_SHORT_READ_NA_DEDUP_ALIGNERS:
                pairs.append((alnr, ddup))
    pairs = sorted(set(pairs))
    if not pairs:
        raise WorkflowError(
            "SMN short-read callers require a valid short-read aligner/deduper "
            "pair, such as sent/dmd, or a HiOMR SR evidence pair such as "
            "sentmm2ont/na."
        )
    return pairs


def smn_long_read_alnr_ddup_pairs():
    pairs = []
    for alnr in smn_long_read_aligners():
        if "na" in DDUP:
            pairs.append((alnr, "na"))
    pairs = sorted(set(pairs))
    if not pairs:
        raise WorkflowError(
            "SMN long-read callers require a valid long-read aligner/no-dedup "
            "pair, such as sentmm2ont/na."
        )
    return pairs


def smn_hiomr_alnr_ddup_pairs():
    hiomr_alnrs = sorted(_smn_hiomr_aligners())
    if not hiomr_alnrs:
        return []
    if "na" not in DDUP:
        raise WorkflowError(
            "Sentieon HiOMR SMN segdup evidence requires deduper 'na'."
        )
    return [(alnr, "na") for alnr in hiomr_alnrs]


def expand_smn_alnr_ddup_pairs(patterns, sample_ids=None, pairs=None):
    if sample_ids is None:
        sample_ids = SSAMPS
    if pairs is None:
        pairs = smn_short_read_alnr_ddup_pairs()
    if isinstance(patterns, str):
        patterns = [patterns]
    return [
        pattern.format(sample=sample, alnr=alnr, ddup=ddup)
        for sample in sample_ids
        for alnr, ddup in pairs
        for pattern in patterns
    ]


def smn_short_cram(wildcards):
    if wildcards.alnr in _smn_hiomr_aligners():
        return (
            MDIR
            + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/snv/sentdhiomr/"
            + f"{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.sentdhiomr.sr_dedup.cram"
        )
    if wildcards.alnr in SMN_SHORT_READ_EXCLUDED_ALIGNERS:
        raise WorkflowError(
            "SMN short-read callers must not consume long-read-only or graph-only "
            f"aligner '{wildcards.alnr}'. Use a short-read aligner or HiOMR SR output."
        )
    return (
        MDIR
        + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/"
        + f"{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.cram"
    )


def smn_short_crai(wildcards):
    return smn_short_cram(wildcards) + ".crai"


def smn_long_cram(wildcards):
    if wildcards.alnr in _smn_hiomr_aligners():
        return _sentdhiomr_lr_cram(wildcards)
    if wildcards.alnr == "ont":
        return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.cram"
    if wildcards.alnr == "sentmm2ont":
        return (
            MDIR
            + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/"
            + f"{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.cram"
        )
    raise WorkflowError(
        "SMN long-read callers require ONT evidence from aligner 'ont', "
        f"'sentmm2ont', or HiOMR LR output; observed '{wildcards.alnr}'."
    )


def smn_long_crai(wildcards):
    if wildcards.alnr in _smn_hiomr_aligners():
        return _sentdhiomr_lr_crai(wildcards)
    return smn_long_cram(wildcards) + ".crai"


# ---------------------------------------------------------------------------
# SNV caller → valid output aligners mapping.
#
# Most callers emit VCFs for every aligner in ALL_ALIGNERS.  Platform-specific
# and hybrid callers only produce VCFs for a subset.  This dict is consumed by
# the helper ``valid_snv_alnr_pairs()`` which replaces the blind Cartesian
# expand(alnr=ALL_ALIGNERS, snv=snv_CALLERS) in downstream target rules
# (concordance, peddy, duphold, etc.).
# ---------------------------------------------------------------------------
_SNV_CALLER_VALID_ALIGNERS = {
    # Solo platform callers
    "cgt7p":    ["sentcg"],               # Complete Genomics/MGI DNAscope over MGI-tuned Sentieon BWA MEM
    "sentdont":  ["ont", "sentmm2ont"],   # ONT-only caller
    "sentdug":   ["ug"],                   # Ultima-only caller
    "sentdpb":   ["sentmm2"],             # PacBio-only caller
    "rochehc":   ["roche"],               # Roche SBX Duplex HaplotypeCaller
    "deep19r":   ["roche"],               # DeepVariant 1.9 on Roche BAMs
    # Hybrid CLI callers (ILMN+LR or Ultima+LR)
    "sentdhio":  ["ont"],                  # Hybrid CLI Ilmn+ONT  → emits alnr=ont
    "sentdhuo":  ["ug"],                   # Hybrid CLI Ultima+ONT → emits alnr=ug
    "sentdhip":  ["sentmm2"],             # Hybrid CLI Ilmn+PB   → emits alnr=sentmm2
    "sentdhup":  ["sentmm2"],             # Hybrid CLI Ultima+PB → emits alnr=sentmm2
    # Hybrid modular callers
    "sentdhiom": ["ont"],                  # Modular Hybrid Ilmn+ONT  → emits alnr=ont
    "sentdhuom": ["ug"],                   # Modular Hybrid Ultima+ONT → emits alnr=ug
    "sentdhipm": ["sentmm2"],             # Modular Hybrid Ilmn+PB   → emits alnr=sentmm2
    "sentdhupm": ["sentmm2"],             # Modular Hybrid Ultima+PB → emits alnr=sentmm2
    "sentdhrom": ["roche"],               # Modular Hybrid Roche+ONT → emits alnr=roche
    "sentdhrpm": ["roche"],               # Modular Hybrid Roche+PB  → emits alnr=roche
    # Hybrid modular refactored callers (r-suffix)
    "sentdhiomr": ["sentmm2ont", "ont"],   # Modular Refactored Hybrid Ilmn+ONT  → emits alnr=sentmm2ont for ONT FASTQ/uBAM, ont for ONT CRAM
    "sentdhipmr": ["sentmm2"],            # Modular Refactored Hybrid Ilmn+PB   → emits alnr=sentmm2
    "sentdhuomr": ["ug"],                  # Modular Refactored Hybrid Ultima+ONT → emits alnr=ug
    "sentdhupmr": ["ug"],                  # Modular Refactored Hybrid Ultima+PB  → emits alnr=ug
    # Ensemble callers
    "ensemble":  ["ont", "pb", "sentmm2"],  # Multi-platform ensemble → emits alnr=ont, pb, or sentmm2
    # Pangenome callers
    "sentpg":    ["pangenome_sr", "pangenome_ug"],  # Sentieon pangenome → emits alnr=pangenome_sr or pangenome_ug
    "sentpgs":   ["pangenome_ug"],                   # Sharded Sentieon Ultima pangenome → emits alnr=pangenome_ug
}


def valid_snv_alnr_pairs(all_aligners, callers):
    """Return list of (alnr, snv) tuples restricted to valid combinations.

    For callers listed in _SNV_CALLER_VALID_ALIGNERS, only the declared
    aligners are paired.  All other callers are paired with every aligner
    in *all_aligners*.
    """
    pairs = []
    for snv in callers:
        valid_alnrs = _SNV_CALLER_VALID_ALIGNERS.get(snv, all_aligners)
        for a in valid_alnrs:
            if a in all_aligners:
                pairs.append((a, snv))
    return pairs


_SNV_CALLER_VALID_DEDUPERS = {
    "sentdhiomr": ["na"],
}


def valid_snv_alnr_ddup_tuples(all_aligners, callers, ddups):
    """Return (aligner, deduper, caller) tuples for variant-output paths."""
    tuples = []
    allowed_alnr_ddup = set(valid_alnr_ddup_pairs(all_aligners, ddups))
    for alnr, snv in valid_snv_alnr_pairs(all_aligners, callers):
        if snv in {"sentpg", "sentpgs"} and alnr in GRAPH_ONLY_PANGENOME_ALIGNERS:
            tuples.append((alnr, PANGENOME_SENTPG_DEDUPER, snv))
            continue
        valid_ddups = _SNV_CALLER_VALID_DEDUPERS.get(snv, ddups)
        for ddup in ddups:
            if ddup not in valid_ddups:
                continue
            if (alnr, ddup) in allowed_alnr_ddup:
                tuples.append((alnr, ddup, snv))
    return tuples


def get_somcall_normal_cram(wildcards):
    try:
        nsamp = TN_PAIRS[wildcards.sample]
    except KeyError:
        raise ValueError(f"No matched normal sample for {wildcards.sample}")
    return MDIR + f"{nsamp}/align/{wildcards.alnr}/{wildcards.ddup}/{nsamp}.{wildcards.alnr}.{wildcards.ddup}.cram"


def get_somcall_normal_crai(wildcards):
    try:
        nsamp = TN_PAIRS[wildcards.sample]
    except KeyError:
        raise ValueError(f"No matched normal sample for {wildcards.sample}")
    return MDIR + f"{nsamp}/align/{wildcards.alnr}/{wildcards.ddup}/{nsamp}.{wildcards.alnr}.{wildcards.ddup}.cram.crai"

def get_somcall_tumor_cram(wildcards):
    return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.cram"

def get_somcall_tumor_crai(wildcards):
    return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.cram.crai"
