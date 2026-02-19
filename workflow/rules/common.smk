from snakemake.utils import validate
from snakemake.exceptions import WorkflowError
import re
import os
import pandas as pd
import sys
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


# ##### Generate the day top level directories
if "conda_prefix" not in config:
    config["conda_prefix"] = "etc/"


config["jem_dot"] = os.environ["DAY_ROOT"] + "/.jemalloc_loc"
os.system(f"touch {config['jem_dot']}")


# ##### A place to track failed samples so they can be tallied up at the end.
# NOT REALLY IMPLEMENTED YET
config["failed_samples"] = {}  ### USE SAMPLE SHEET FOR THIS


# ##### Safety sort of the yaml defined crms
config["glimpse"] = {"impute_chrms": "2"}

def first_val(df, col):
    if df.empty:
        return None
    return df.iloc[0].get(col)

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

# SNV caller chunk arrays
SENTD_CHRMS = config["sentD"][f"{config['genome_build']}_sentD_chrms"].split(",")
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
_ALIGNER_TARGET_MAP = {
    "produce_bwa_mem2_sort_bam": "bwa2a",
    "produce_sentieon_bwa_sort_bam": "sent",
    "produce_strobe_align_sort_bam": "strobe",
    "produce_sentmm2_align_sort": "sentmm2",
    "produce_sentmm2ont_align_sort": "sentmm2ont",
}
if not ALIGNERS:
    _auto_aligners_env = os.environ.get('_DY_AUTO_ALIGNERS', '')
    if _auto_aligners_env:
        ALIGNERS = sorted(set(_auto_aligners_env.split(',')))
        os.system(
            f'''colr "...INFO: Auto-detected aligners from env: {ALIGNERS}" "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
        )
    else:
        _cli_aligner_codes = set()
        for _arg in sys.argv:
            if _arg in _ALIGNER_TARGET_MAP:
                _cli_aligner_codes.add(_ALIGNER_TARGET_MAP[_arg])
        if _cli_aligner_codes:
            ALIGNERS = sorted(_cli_aligner_codes)
            os.system(
                f'''colr "...INFO: Auto-detected aligner targets on CLI. ALIGNERS set to: {ALIGNERS}" "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
            )

os.system(
    f"""colr 'aligners (final): {ALIGNERS}' "$DY_WT1" "$DY_B1" "$DY_WS1" 1>&2;"""
)

# Handle dedupers
# Valid dedup codes: dmd (doppelmark), smd (sentieon markdup), na (no dedup / skip)
# Legacy codes dppl and dppl_sent are mapped to dmd and smd respectively.
# If no dedupers specified, defaults to ['na'] (no dedup).
DDUP_LEGACY_MAP = {"dppl": "dmd", "dppl_sent": "smd"}
DDUP_VALID_CODES = {"dmd", "smd", "na"}

DDUP = []
if 'dedupers' not in config or config.get('dedupers') is None or len(config.get('dedupers', [])) == 0:
    DDUP = ["na"]
    os.system(
        f'''colr "...INFO: No dedupers set in config. Defaulting to na (no dedup)." "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
    )
else:
    _raw_ddup = sorted(set(config["dedupers"]))
    DDUP = sorted(set(DDUP_LEGACY_MAP.get(d, d) for d in _raw_ddup))
    _unknown = set(DDUP) - DDUP_VALID_CODES
    if _unknown:
        os.system(
            f'''colr "...WARNING: Unknown deduper codes: {_unknown}. Valid: {DDUP_VALID_CODES}" "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
        )

# Fallback: auto-detect dedupers from env var set by bin/day_run,
# or from sys.argv for direct snakemake invocations.
_DEDUP_TARGET_MAP = {
    "dedup_doppelmark": "dmd",
    "dedup_sentieon": "smd",
    "dedup_none": "na",
}
_auto_dedup_codes = set()

# Primary: env var from bin/day_run
_auto_dedupers_env = os.environ.get('_DY_AUTO_DEDUPERS', '')
if _auto_dedupers_env:
    _auto_dedup_codes = set(_auto_dedupers_env.split(','))

# Secondary: sys.argv scan (direct snakemake invocation)
if not _auto_dedup_codes:
    for _arg in sys.argv:
        if _arg in _DEDUP_TARGET_MAP:
            _auto_dedup_codes.add(_DEDUP_TARGET_MAP[_arg])

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
_SNV_CALLER_TARGET_MAP = {
    "produce_sentD_vcf": "sentd",
    "produce_sentdpb_vcf": "sentdpb",
    "produce_sentdont_vcf": "sentdont",
    "produce_sentdug_vcf": "sentdug",
    "produce_sentdhio_vcf": "sentdhio",
    "produce_sentdhuo_vcf": "sentdhuo",
    "produce_sentpg_vcf": "sentpg",
    "produce_deep19_vcf": "deep19",
    "produce_deep15_vcf": "deep15",
    "produce_oct_vcf": "oct",
    "produce_clair3_vcf": "clair3",
    "produce_lofreq2_vcf": "lfq2",
    "produce_varn_vcf": "varn",
    "produce_aiv_vcf": "aiv",
    "produce_mutect2_vcf": "mutect2",
    "produce_dvsom_vcf": "dvsom",
    "produce_strelka2_germline_vcf": "slk2g",
    "produce_strelka2_somatic_vcf": "slk2s",
    "produce_sent_TNscope_vcf": "senttn",
    "produce_rochehc_vcf": "rochehc",
    "produce_deep19_r_vcf": "deep19r",
}
if not snv_CALLERS:
    _auto_snv_env = os.environ.get('_DY_AUTO_SNV_CALLERS', '')
    if _auto_snv_env:
        snv_CALLERS = sorted(set(_auto_snv_env.split(',')))
        os.system(
            f'''colr "...INFO: Auto-detected SNV callers from env: {snv_CALLERS}" "$DY_WT1" "$DY_WB1" "$DY_WS1" 1>&2'''
        )
    else:
        _cli_snv_codes = set()
        for _arg in sys.argv:
            if _arg in _SNV_CALLER_TARGET_MAP:
                _cli_snv_codes.add(_SNV_CALLER_TARGET_MAP[_arg])
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
units_table_path = _resolve_table(
    "units_table",
    f"{config['genome_build']}_units_table",
    "units.tsv",
)

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

import pandas as pd

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
unit_records   = load_tsv_as_str(units_table_path)

sample_records.columns = [c.upper() for c in sample_records.columns]
unit_records.columns   = [c.upper() for c in unit_records.columns]

sample_records = normalize_boolish(sample_records)

if sample_records.empty:
    raise WorkflowError("The samples table is empty. Please provide at least one sample entry.")

if unit_records.empty:
    raise WorkflowError("The units table is empty. Please provide at least one sequencing unit entry.")

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
]:
    if opt_col not in unit_records.columns:
        unit_records[opt_col] = ""

if "SAMPLEID" not in sample_records.columns:
    raise WorkflowError("The samples table must contain a 'SAMPLEID' column.")

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

if metadata["analysis_unit_uid"].duplicated().any():
    dupes = metadata[metadata["analysis_unit_uid"].duplicated()]["analysis_unit_uid"].tolist()
    raise WorkflowError(
        f"Duplicate analysis unit identifiers detected: {sorted(set(dupes))}"
    )

def _select_reads(row):
    for r1, r2 in [
        ("ILMN_R1_PATH", "ILMN_R2_PATH"),
        ("PACBIO_R1_PATH", "PACBIO_R2_PATH"),
        ("ONT_R1_PATH", "ONT_R2_PATH"),
        ("UG_R1_PATH", "UG_R2_PATH"),
    ]:
        r1_path = _clean_component(row.get(r1, ""))
        r2_path = _clean_component(row.get(r2, ""))
        if r1_path:
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
        for r1f in samples.loc[s, ("r1_path")]:
            if r1f in ["","na", None]:
                pass
            else:
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

    if any(_bad_token(t) for t in (sq_id, ru_id, ex_id, lane_id)):
        raise WorkflowError(
            f"\n\nMANIFEST ERROR {sample} ... {sample_lane}: SQ/RU/EX/LANE may not contain '.' or '_' per current constraints."
        )

    # Prevent 'sample_lane' collisions and sample-in-lane name leakage (legacy behavior)
    if sample_lane in sample_lane_seen or ("." in sample):
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
    bsex = str(row.get("BIOLOGICAL_SEX", "na")).strip().lower()
    if bsex.startswith("m"):
        bsex = "male"
    elif bsex.startswith("f"):
        bsex = "female"
    else:
        bsex = "na"
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

POS_CONTROL_SAMPLES = sorted(
    s for s, info in sample_info.items()
    if _truthy(info.get("is_positive_control"))
)

NEG_CONTROL_SAMPLES = sorted(
    s for s, info in sample_info.items()
    if _truthy(info.get("is_negative_control"))
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
    for i in samples[samples["sample"] == wildcards.sample][
        "r1_path"
    ]:  # .loc[wildcards.sample, "sample_lane"]['sample_lane']:
        r1s.append(i)
    return sorted(r1s)


def get_raw_R2s(wildcards):
    r2s = []
    for i in samples[samples["sample"] == wildcards.sample][
        "r2_path"
    ]:  # .loc[wildcards.sample, "sample_lane"]:
        r2s.append(i)
    return sorted(r2s)


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
    if len(samps.keys()) == 0 and "run_b2fq" not in config:
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

SSAMPS = {}
for sample in samples["sample"].unique():
    row = samples[samples["sample"] == sample]
    ss = first_val(row, "analysis_unit_uid")
    SSAMPS.setdefault(ss, []).append(sample)


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

def getR2s(wildcards):
    fr2s = []
    for sample_lane in samples.loc[wildcards.sample, "sample_lane"]:
        r2 = f"{MDIR}{wildcards.sample}/{sample_lane}.R2.fastq.gz"
        fr2s.append(r2)
    return sorted(fr2s)


def getR1s(wildcards):
    fr1s = []
    for sample_lane in samples.loc[wildcards.sample, "sample_lane"]:
        r1 = f"{MDIR}{wildcards.sample}/{sample_lane}.R1.fastq.gz"
        fr1s.append(r1)
    return sorted(fr1s)

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
        fr2s.append(r2)
    return sorted(fr2s)


def getR1sS(wildcards):
    fr1s = []
    for r1 in samples[samples["analysis_unit_uid"] == wildcards.sample]["r1_path"]:
        fr1s.append(r1)
    return sorted(fr1s)


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
    # Ensemble callers
    "ensemble":  ["ont", "pb", "sentmm2"],  # Multi-platform ensemble → emits alnr=ont, pb, or sentmm2
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
