import os
import sys


def _requested_targets():
    return {arg for arg in sys.argv[1:] if not arg.startswith('-')}


BCL_BOOTSTRAP_TARGETS = {
    "produce_bclconvert_fastqs_and_metrics",
    "produce_bclconvert_fastqs",
}

BCL_BOOTSTRAP_MODE = bool(_requested_targets() & BCL_BOOTSTRAP_TARGETS) or str(
    config.get("bootstrap_bclconvert", False)
).lower() in {"1", "true", "yes"}

BCLCFG = config.get("bclconvert", {})
BCL_EXEC = BCLCFG.get("executable", "bcl-convert")
BCL_RUN_DIR = BCLCFG.get("run_dir", "")
BCL_SAMPLE_SHEET = BCLCFG.get("sample_sheet", "config/SampleSheet.csv")
BCL_RUN_ID = BCLCFG.get("run_id", "")
BCL_OUTPUT_ROOT = BCLCFG.get("output_root", "results/bclconvert")

if not BCL_RUN_ID:
    BCL_RUN_ID = os.path.splitext(os.path.basename(BCL_SAMPLE_SHEET))[0]

BCL_ROOT = f"{BCL_OUTPUT_ROOT.rstrip('/')}/{BCL_RUN_ID}"
BCL_FASTQ_DIR = f"{BCL_ROOT}/fastq"
BCL_REPORT_DIR = f"{BCL_FASTQ_DIR}/Reports"
BCL_TABLE_DIR = f"{BCL_ROOT}/tables"
BCL_METRIC_DIR = f"{BCL_ROOT}/metrics"
BCL_LOG_DIR = f"{BCL_ROOT}/logs"
BCL_REPORT_OUT_DIR = f"{BCL_ROOT}/reports"


rule bclconvert_validate_inputs:
    input:
        sample_sheet=BCL_SAMPLE_SHEET,
        samples=config["samples_table"],
    output:
        validated=f"{BCL_LOG_DIR}/validated.ok",
        normalized_sample_sheet=f"{BCL_ROOT}/normalized.SampleSheet.csv",
        parsed_samplesheet_tsv=f"{BCL_TABLE_DIR}/samplesheet_rows.tsv",
    conda:
        "../envs/bclconvert_metrics_v0.1.yaml"
    shell:
        r"""
        set -euo pipefail
        mkdir -p {BCL_LOG_DIR} {BCL_TABLE_DIR}
        python workflow/scripts/parse_bclconvert_samplesheet.py \
          --sample-sheet {input.sample_sheet} \
          --samples-tsv {input.samples} \
          --normalized-out {output.normalized_sample_sheet} \
          --rows-out {output.parsed_samplesheet_tsv}
        touch {output.validated}
        """


rule run_bclconvert:
    input:
        validated=f"{BCL_LOG_DIR}/validated.ok",
        sample_sheet=f"{BCL_ROOT}/normalized.SampleSheet.csv",
    output:
        done=f"{BCL_LOG_DIR}/bclconvert.done",
        fastq_list=f"{BCL_REPORT_DIR}/fastq_list.csv",
        demux_stats=f"{BCL_REPORT_DIR}/Demultiplex_Stats.csv",
    params:
        exe=BCL_EXEC,
        run_dir=BCL_RUN_DIR,
        outdir=BCL_FASTQ_DIR,
        force="-f" if str(BCLCFG.get("force", False)).lower() in {"1", "true", "yes"} else "",
    log:
        f"{BCL_LOG_DIR}/run_bclconvert.log",
    shell:
        r"""
        set -euo pipefail
        mkdir -p {BCL_LOG_DIR}
        {params.exe} \
          --bcl-input-directory {params.run_dir} \
          --output-directory {params.outdir} \
          --sample-sheet {input.sample_sheet} \
          {params.force} \
          > {log} 2>&1
        test -s {output.fastq_list}
        test -s {output.demux_stats}
        touch {output.done}
        """


rule bclconvert_generate_units_tsv:
    input:
        done=f"{BCL_LOG_DIR}/bclconvert.done",
        fastq_list=f"{BCL_REPORT_DIR}/fastq_list.csv",
        sample_sheet_rows=f"{BCL_TABLE_DIR}/samplesheet_rows.tsv",
    output:
        units=f"{BCL_TABLE_DIR}/generated.units.tsv",
    conda:
        "../envs/bclconvert_metrics_v0.1.yaml"
    shell:
        r"""
        set -euo pipefail
        python workflow/scripts/bclconvert_fastq_list_to_units.py \
          --fastq-list {input.fastq_list} \
          --sample-sheet-rows {input.sample_sheet_rows} \
          --run-id {BCL_RUN_ID} \
          --libprep "{BCLCFG.get('libprep', 'PCR-FREE')}" \
          --seq-vendor "{BCLCFG.get('seq_vendor', 'ILMN')}" \
          --seq-platform-override "{BCLCFG.get('seq_platform_override', '')}" \
          --units-out {output.units}
        """


rule bclconvert_metrics_summary:
    input:
        done=f"{BCL_LOG_DIR}/bclconvert.done",
        demux=f"{BCL_REPORT_DIR}/Demultiplex_Stats.csv",
        fastq_list=f"{BCL_REPORT_DIR}/fastq_list.csv",
    output:
        demux_tsv=f"{BCL_METRIC_DIR}/demultiplex_stats.tsv",
        unknown_tsv=f"{BCL_METRIC_DIR}/unknown_barcodes.tsv",
        hopping_tsv=f"{BCL_METRIC_DIR}/index_hopping.tsv",
        fastq_manifest_tsv=f"{BCL_METRIC_DIR}/fastq_manifest.tsv",
        rollup_json=f"{BCL_METRIC_DIR}/rollup.json",
    conda:
        "../envs/bclconvert_metrics_v0.1.yaml"
    shell:
        r"""
        set -euo pipefail
        mkdir -p {BCL_METRIC_DIR}
        python workflow/scripts/bclconvert_metrics_summary.py \
          --report-dir {BCL_REPORT_DIR} \
          --demux-out {output.demux_tsv} \
          --unknown-out {output.unknown_tsv} \
          --hopping-out {output.hopping_tsv} \
          --fastq-manifest-out {output.fastq_manifest_tsv} \
          --rollup-json-out {output.rollup_json}
        """


rule multiqc_bclconvert:
    input:
        done=f"{BCL_LOG_DIR}/bclconvert.done",
        demux=f"{BCL_REPORT_DIR}/Demultiplex_Stats.csv",
    output:
        html=f"{BCL_REPORT_OUT_DIR}/bclconvert.multiqc.html",
    conda:
        config["multiqc"]["bcl2fq"]["env_yaml"]
    log:
        f"{BCL_LOG_DIR}/multiqc_bclconvert.log",
    shell:
        r"""
        set -euo pipefail
        mkdir -p {BCL_REPORT_OUT_DIR}
        multiqc \
          --interactive \
          --force \
          --outdir {BCL_REPORT_OUT_DIR} \
          --filename $(basename {output.html}) \
          {BCL_FASTQ_DIR} \
          > {log} 2>&1
        test -s {output.html}
        """


rule produce_bclconvert_fastqs_and_metrics:  # TARGET : Run bcl-convert bootstrap demultiplexing and emit generated units TSV plus metrics
    input:
        f"{BCL_LOG_DIR}/bclconvert.done",
        f"{BCL_TABLE_DIR}/generated.units.tsv",
        f"{BCL_METRIC_DIR}/demultiplex_stats.tsv",
        f"{BCL_METRIC_DIR}/unknown_barcodes.tsv",
        f"{BCL_METRIC_DIR}/index_hopping.tsv",
        f"{BCL_METRIC_DIR}/fastq_manifest.tsv",
        f"{BCL_METRIC_DIR}/rollup.json",
        f"{BCL_REPORT_OUT_DIR}/bclconvert.multiqc.html",
    output:
        touch(f"{BCL_ROOT}/bclconvert.bootstrap.complete"),
    shell:
        "touch {output}"
