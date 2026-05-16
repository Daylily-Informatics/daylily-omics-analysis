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
BCL_SAMPLE_SHEET = str(BCLCFG.get("sample_sheet", "SampleSheet.csv") or "SampleSheet.csv")
BCL_RUN_DIR = str(BCLCFG.get("run_dir", "") or "")
BCL_OUTPUT_ROOT = str(BCLCFG.get("output_root", "results/bclconvert") or "results/bclconvert").rstrip(
    "/"
)
BCL_RUN_ID = str(
    config.get("bclconvert_bootstrap_run_id", _derive_bclconvert_run_id(BCL_SAMPLE_SHEET))
)
BCL_ROOT = f"{BCL_OUTPUT_ROOT}/{BCL_RUN_ID}"
BCL_FASTQ_DIR = f"{BCL_ROOT}/fastq"
BCL_REPORT_DIR = f"{BCL_FASTQ_DIR}/Reports"
BCL_TABLE_DIR = f"{BCL_ROOT}/tables"
BCL_METRIC_DIR = f"{BCL_ROOT}/metrics"
BCL_REPORT_OUT_DIR = f"{BCL_ROOT}/reports"
BCL_LOG_DIR = f"{BCL_ROOT}/logs"
BCL_MQC_DIR = f"{MDIR}other_reports"
BCL_MQC_LOG_DIR = f"{BCL_MQC_DIR}/logs"

BCL_VALIDATE_OK = f"{BCL_LOG_DIR}/validated.ok"
BCL_NORMALIZED_SAMPLE_SHEET = f"{BCL_ROOT}/normalized.SampleSheet.csv"
BCL_SAMPLESHEET_ROWS = f"{BCL_TABLE_DIR}/samplesheet_rows.tsv"
BCL_WARNINGS = f"{BCL_LOG_DIR}/bclconvert_validate_inputs.warnings.log"
BCL_DONE = f"{BCL_LOG_DIR}/bclconvert.done"
BCL_FASTQS_COMPLETE = f"{BCL_ROOT}/fastqs.complete"
BCL_BOOTSTRAP_COMPLETE = f"{BCL_ROOT}/bclconvert.bootstrap.complete"
BCL_MQC_COMPLETE = f"{BCL_MQC_DIR}/bclconvert_metrics_mqc.done"

BCL_METRICS_ENV = "../envs/bclconvert_metrics_v0.1.yaml"
MULTIQC_ENV = (
    config.get("multiqc", {})
    .get("bclconvert", {})
    .get("env_yaml", "../envs/multiqc_v0.1.yaml")
)
MULTIQC_CONFIG = (
    config.get("multiqc", {})
    .get("bclconvert", {})
    .get("config_yaml", "config/external_tools/multiqc_config.yaml")
)
SAMPLES_TABLE = str(
    config.get("samples_table", os.path.abspath(os.path.join("config", "samples.tsv")))
)

BCL_THREADS = _intish(BCLCFG.get("threads", 1), 1)
BCL_FORCE = _bool(BCLCFG.get("force", False))
BCL_KEEP_UNDETERMINED = _bool(BCLCFG.get("keep_undetermined_fastqs", True), True)
BCL_SAMPLEPROJECT_SUBDIRS = _bool(BCLCFG.get("sampleproject_subdirectories", False), False)
BCL_STRICT_MODE = _bool(BCLCFG.get("strict_mode", False), False)
BCL_FIRST_TILE_ONLY = _bool(BCLCFG.get("first_tile_only", False), False)
BCL_EXTRA_ARGS = str(BCLCFG.get("extra_args", "") or "").strip()
BCL_LIBPREP = str(BCLCFG.get("libprep", "PCR-FREE") or "PCR-FREE")
BCL_SEQ_VENDOR = str(BCLCFG.get("seq_vendor", "ILMN") or "ILMN")
BCL_SEQ_PLATFORM_OVERRIDE = str(BCLCFG.get("seq_platform_override", "") or "")


localrules:
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
        run_dir=BCL_RUN_DIR,
        runtime_version="4.0.3",
        keep_undetermined_fastqs="true" if BCL_KEEP_UNDETERMINED else "false",
        sampleproject_subdirectories="true" if BCL_SAMPLEPROJECT_SUBDIRS else "false",
        extra_args=BCL_EXTRA_ARGS,
        warnings_out=BCL_WARNINGS,
    log:
        f"{BCL_LOG_DIR}/bclconvert_validate_inputs.log",
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
        if [ -n {params.extra_args:q} ]; then
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
    container:
        "docker://nfcore/bclconvert:4.0.3"
    params:
        run_dir=BCL_RUN_DIR,
        force="-f" if BCL_FORCE else "",
        strict_mode="true" if BCL_STRICT_MODE else "false",
        first_tile_only="true" if BCL_FIRST_TILE_ONLY else "false",
        sampleproject_subdirectories="true" if BCL_SAMPLEPROJECT_SUBDIRS else "false",
    log:
        f"{BCL_LOG_DIR}/run_bclconvert.log",
    shell:
        r"""
        set -euo pipefail
        mkdir -p {BCL_FASTQ_DIR:q} {BCL_LOG_DIR:q}
        : > {log:q}
        bcl-convert --version >> {log:q} 2>&1
        bcl-convert \
          --bcl-input-directory {params.run_dir:q} \
          --output-directory {BCL_FASTQ_DIR:q} \
          --sample-sheet {input.sample_sheet:q} \
          {params.force} \
          --strict-mode {params.strict_mode} \
          --first-tile-only {params.first_tile_only} \
          --bcl-sampleproject-subdirectories {params.sampleproject_subdirectories} \
          >> {log:q} 2>&1
        test -s {output.fastq_list:q}
        test -s {output.demux_stats:q}
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
        run_id=BCL_RUN_ID,
        libprep=BCL_LIBPREP,
        seq_vendor=BCL_SEQ_VENDOR,
        seq_platform_override=BCL_SEQ_PLATFORM_OVERRIDE,
    log:
        f"{BCL_LOG_DIR}/bclconvert_generate_units_tsv.log",
    shell:
        r"""
        set -euo pipefail
        : > {log:q}
        python workflow/scripts/bclconvert_fastq_list_to_units.py \
          --fastq-list {input.fastq_list:q} \
          --sample-sheet-rows {input.sample_sheet_rows:q} \
          --run-id {params.run_id:q} \
          --libprep {params.libprep:q} \
          --seq-vendor {params.seq_vendor:q} \
          --seq-platform-override {params.seq_platform_override:q} \
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
    log:
        f"{BCL_LOG_DIR}/bclconvert_metrics_summary.log",
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
    log:
        f"{BCL_MQC_LOG_DIR}/bclconvert_metrics_multiqc_exports.log",
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
        html=f"{BCL_REPORT_OUT_DIR}/bclconvert.multiqc.html",
    threads:
        1
    conda:
        MULTIQC_ENV
    params:
        multiqc_cfg=MULTIQC_CONFIG,
        multiqc_filename="bclconvert.multiqc.html",
    log:
        f"{BCL_LOG_DIR}/multiqc_bclconvert.log",
    shell:
        r"""
        set -euo pipefail
        mkdir -p {BCL_REPORT_OUT_DIR:q}
        : > {log:q}
        multiqc -f \
          --config {params.multiqc_cfg:q} \
          --template default \
          --filename {params.multiqc_filename:q} \
          --outdir {BCL_REPORT_OUT_DIR:q} \
          {BCL_FASTQ_DIR:q} \
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
        f"{BCL_REPORT_OUT_DIR}/bclconvert.multiqc.html",


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
        f"{BCL_REPORT_OUT_DIR}/bclconvert.multiqc.html",
    output:
        touch(BCL_BOOTSTRAP_COMPLETE),
    shell:
        "touch {output}"
