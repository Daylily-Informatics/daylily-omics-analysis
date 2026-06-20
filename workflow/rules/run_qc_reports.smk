import re


def _runqc_text(section, key):
    value = section.get(key, "")
    if value is None:
        return ""
    return str(value).strip()


def _runqc_safe_token(value, default):
    text = _runqc_text({"value": value}, "value")
    if not text:
        return default
    text = re.sub(r"[\\/]+", "_", text)
    text = re.sub(r"[^A-Za-z0-9._-]+", "_", text)
    text = re.sub(r"_+", "_", text)
    return text.strip("._-") or default


RUNQC_CFG = config.get("run_qc", {})
RUNQC_ILMN_CFG = RUNQC_CFG.get("illumina", {})
RUNQC_ONT_CFG = RUNQC_CFG.get("ont", {})
RUNQC_UG_CFG = RUNQC_CFG.get("ultima", {})
RUNQC_ENV = _runqc_text(RUNQC_CFG, "env_yaml") or "../envs/run_qc_reports_v0.1.yaml"
RUNQC_FASTQC_ENV = _runqc_text(RUNQC_CFG, "fastqc_env_yaml") or "../envs/fastqc_v0.1.yaml"
RUNQC_MULTIQC_ENV = "../envs/multiqc_v0.1.yaml"

RUNQC_ILMN_TARGET_REQUESTED = bool(
    _requested_targets()
    & {
        "produce_illumina_run_qc",
        "produce_illumina_run_qc_and_bclconvert",
        "produce_read_fate_river",
        "produce_run_qc_reports",
    }
)
RUNQC_ONT_TARGET_REQUESTED = bool(
    _requested_targets()
    & {
        "produce_ont_run_qc",
        "produce_ont_demux_fastq_qc",
        "produce_ont_run_qc_and_demux_multiqc",
        "produce_run_qc_reports",
    }
)
RUNQC_UG_TARGET_REQUESTED = bool(
    _requested_targets()
    & {
        "produce_ultima_run_qc",
        "produce_ultima_demux_fastq_qc",
        "produce_ultima_run_qc_and_demux_multiqc",
        "produce_run_qc_reports",
    }
)

RUNQC_ILMN_CONTEXT = run_context_for_platform(
    "ILMN", require=RUNQC_ILMN_TARGET_REQUESTED
)
RUNQC_ONT_CONTEXT = run_context_for_platform(
    "ONT", require=RUNQC_ONT_TARGET_REQUESTED
)
RUNQC_UG_CONTEXT = run_context_for_platform(
    "ULTIMA", require=RUNQC_UG_TARGET_REQUESTED
)


def _runqc_root(context, platform_dir):
    if context is None:
        return f"results/runs/_run_context_required/run_qc/{platform_dir}"
    return f"{context['OUTPUT_ROOT_RESOLVED'].rstrip('/')}/run_qc/{platform_dir}"


def _runqc_mounted_run_dir(context, platform_name, target_requested):
    if context is None:
        return ""
    if not _filled(context.get("RUN_DIR", "")):
        raise WorkflowError(
            f"RUNID={context['RUNID']} must populate RUN_DIR for mounted {platform_name} run QC."
        )
    return context["RUN_DIR"]


def _runqc_optional_input(path):
    return path if _filled(path) else []


def _runqc_illumina_mode(context):
    if context is None:
        return ""
    if _filled(context.get("RUN_DIR", "")):
        return "mounted"
    if _filled(context.get("SOURCE_S3_URI", "")):
        return "s3"
    raise WorkflowError(
        f"RUNID={context['RUNID']} must populate RUN_DIR for mounted Illumina run QC or SOURCE_S3_URI for S3 mode."
    )


RUNQC_ILMN_MODE = _runqc_illumina_mode(RUNQC_ILMN_CONTEXT)
RUNQC_ILMN_ROOT = _runqc_root(RUNQC_ILMN_CONTEXT, "illumina")
RUNQC_ILMN_SOURCE_RUN = RUNQC_ILMN_ROOT + "/source_run_subset"
RUNQC_ILMN_INTEROP_DIR = RUNQC_ILMN_SOURCE_RUN + "/InterOp"
RUNQC_ILMN_REPORT_DIR = RUNQC_ILMN_ROOT
RUNQC_ILMN_TABLE_DIR = RUNQC_ILMN_ROOT
RUNQC_ILMN_MQC_DIR = RUNQC_ILMN_ROOT + "/multiqc_inputs"
RUNQC_ILMN_LOG_DIR = RUNQC_ILMN_ROOT + "/logs"
RUNQC_ILMN_BENCH_DIR = RUNQC_ILMN_ROOT + "/benchmarks"
RUNQC_ILMN_REPORT_PREFIX = _runqc_safe_token(
    RUNQC_ILMN_CFG.get("report_prefix", "illumina_read_fate_river"),
    "illumina_read_fate_river",
)
RUNQC_ILMN_REPORT_TITLE = (
    _runqc_text(RUNQC_ILMN_CFG, "report_title") or "Illumina Read-Fate River"
)
RUNQC_ILMN_RIVER_HTML = RUNQC_ILMN_REPORT_DIR + "/" + RUNQC_ILMN_REPORT_PREFIX + ".html"
RUNQC_ILMN_RIVER_TSV = RUNQC_ILMN_REPORT_DIR + "/" + RUNQC_ILMN_REPORT_PREFIX + ".tsv"
RUNQC_ILMN_RIVER_MD = RUNQC_ILMN_REPORT_DIR + "/" + RUNQC_ILMN_REPORT_PREFIX + ".md"
RUNQC_ILMN_RIVER_INVENTORY = (
    RUNQC_ILMN_REPORT_DIR
    + "/raw_illumina_metrics_inventory_"
    + RUNQC_ILMN_REPORT_PREFIX
    + ".md"
)

RUNQC_ONT_ROOT = _runqc_root(RUNQC_ONT_CONTEXT, "ont")
RUNQC_UG_ROOT = _runqc_root(RUNQC_UG_CONTEXT, "ultima")
RUNQC_ONT_RUN_DIR = _runqc_mounted_run_dir(
    RUNQC_ONT_CONTEXT, "ONT", RUNQC_ONT_TARGET_REQUESTED
)
RUNQC_UG_RUN_DIR = _runqc_mounted_run_dir(
    RUNQC_UG_CONTEXT, "Ultima", RUNQC_UG_TARGET_REQUESTED
)
RUNQC_ONT_RUN_S3_URI = (
    _runqc_text(RUNQC_ONT_CFG, "run_s3_uri")
    if RUNQC_ONT_CONTEXT is None
    else RUNQC_ONT_CONTEXT["SOURCE_S3_URI"]
)
RUNQC_UG_RUN_S3_URI = (
    _runqc_text(RUNQC_UG_CFG, "run_s3_uri")
    if RUNQC_UG_CONTEXT is None
    else RUNQC_UG_CONTEXT["SOURCE_S3_URI"]
)
RUNQC_ONT_TABLE_DIR = RUNQC_ONT_ROOT + "/tables"
RUNQC_ONT_LOG_DIR = RUNQC_ONT_ROOT + "/logs"
RUNQC_ONT_BENCH_DIR = RUNQC_ONT_ROOT + "/benchmarks"
RUNQC_ONT_PYCOQC_DIR = RUNQC_ONT_ROOT + "/pycoqc"
RUNQC_ONT_NANOPLOT_DIR = RUNQC_ONT_ROOT + "/nanoplot"
RUNQC_ONT_SUMMARY_LIST = RUNQC_ONT_TABLE_DIR + "/sequencing_summary_files.txt"
RUNQC_ONT_PYCOQC_HTML = RUNQC_ONT_PYCOQC_DIR + "/pycoQC.html"
RUNQC_ONT_PYCOQC_JSON = RUNQC_ONT_PYCOQC_DIR + "/pycoQC.json"
RUNQC_ONT_NANOPLOT_DONE = RUNQC_ONT_NANOPLOT_DIR + "/nanoplot.done"
RUNQC_ONT_MULTIQC_HTML = RUNQC_ONT_ROOT + "/multiqc_report.html"
RUNQC_ONT_DEMUX_ROOT = RUNQC_ONT_ROOT + "/demux_fastq_qc"
RUNQC_ONT_DEMUX_GROUP_LIST = RUNQC_ONT_DEMUX_ROOT + "/fastq_group_dirs.txt"
RUNQC_ONT_DEMUX_DONE = RUNQC_ONT_DEMUX_ROOT + "/ont_demux_fastq_qc.done"
RUNQC_ONT_DEMUX_MULTIQC_HTML = RUNQC_ONT_ROOT + "/ont_demux_fastq.multiqc.html"
RUNQC_ONT_METRICS_PATH = (
    RUNQC_ONT_PYCOQC_JSON
    if RUNQC_ONT_CONTEXT is not None
    else _runqc_text(RUNQC_ONT_CFG, "metrics_path")
)
RUNQC_ONT_TARGET_INPUTS = [RUNQC_ONT_ROOT + "/logs/ont_run_qc_report.done"]
if RUNQC_ONT_CONTEXT is not None:
    RUNQC_ONT_TARGET_INPUTS.append(RUNQC_ONT_MULTIQC_HTML)
    RUNQC_ONT_TARGET_INPUTS.append(RUNQC_ONT_DEMUX_MULTIQC_HTML)

RUNQC_UG_LOG_DIR = RUNQC_UG_ROOT + "/logs"
RUNQC_UG_BENCH_DIR = RUNQC_UG_ROOT + "/benchmarks"
RUNQC_UG_DEMUX_ROOT = RUNQC_UG_ROOT + "/demux_fastq_qc"
RUNQC_UG_DEMUX_GROUP_LIST = RUNQC_UG_DEMUX_ROOT + "/fastq_group_dirs.txt"
RUNQC_UG_DEMUX_DONE = RUNQC_UG_DEMUX_ROOT + "/ultima_demux_fastq_qc.done"
RUNQC_UG_DEMUX_MULTIQC_HTML = RUNQC_UG_ROOT + "/ultima_demux_fastq.multiqc.html"
RUNQC_UG_TARGET_INPUTS = [RUNQC_UG_LOG_DIR + "/ultima_run_qc_report.done"]
if RUNQC_UG_CONTEXT is not None:
    RUNQC_UG_TARGET_INPUTS.append(RUNQC_UG_DEMUX_MULTIQC_HTML)


localrules:
    illumina_run_qc_fetch_metric_subset,
    illumina_run_qc_interop_summary,
    illumina_run_qc_json,
    illumina_run_qc_report,
    illumina_run_qc_multiqc,
    illumina_run_qc_read_fate_river,
    produce_illumina_run_qc_and_bclconvert,
    ont_run_qc_collect_summaries,
    ont_run_qc_pycoqc,
    ont_run_qc_nanoplot,
    ont_run_qc_multiqc,
    ont_demux_fastq_group_list,
    ont_demux_fastq_qc,
    ont_demux_fastq_multiqc,
    ont_run_qc_report,
    ultima_demux_fastq_group_list,
    ultima_demux_fastq_qc,
    ultima_demux_fastq_multiqc,
    ultima_run_qc_report,
    produce_illumina_run_qc,
    produce_ont_run_qc,
    produce_ont_demux_fastq_qc,
    produce_ont_run_qc_and_demux_multiqc,
    produce_ultima_run_qc,
    produce_ultima_demux_fastq_qc,
    produce_ultima_run_qc_and_demux_multiqc,
    produce_read_fate_river,
    produce_run_qc_reports,


rule illumina_run_qc_fetch_metric_subset:
    output:
        done=RUNQC_ILMN_LOG_DIR + "/metric_subset_fetched.done",
    params:
        mode=RUNQC_ILMN_MODE,
        run_dir="" if RUNQC_ILMN_CONTEXT is None else RUNQC_ILMN_CONTEXT["RUN_DIR"],
        source_s3_uri="" if RUNQC_ILMN_CONTEXT is None else RUNQC_ILMN_CONTEXT["SOURCE_S3_URI"],
        profile="" if RUNQC_ILMN_CONTEXT is None else RUNQC_ILMN_CONTEXT["PROFILE"],
        region="" if RUNQC_ILMN_CONTEXT is None else RUNQC_ILMN_CONTEXT["REGION"],
        source_run=RUNQC_ILMN_SOURCE_RUN,
        cluster_sample="illumina_run_qc_fetch_metric_subset",
    log:
        RUNQC_ILMN_LOG_DIR + "/metric_subset_fetched.log",
    benchmark:
        RUNQC_ILMN_BENCH_DIR + "/metric_subset_fetched.bench.tsv",
    conda:
        RUNQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.done:q}) $(dirname {log:q}) {params.source_run:q}
        : > {log:q}
        if [ -z {params.mode:q} ]; then
            echo "config/runs.tsv is required for Illumina run QC" >> {log:q}
            exit 2
        fi
        link_or_copy_required () {{
            rel="$1"
            dest="{params.source_run}/$rel"
            src="$(printf "%s" {params.run_dir:q} | sed 's:/*$::')/$rel"
            mkdir -p "$(dirname "$dest")"
            test -s "$src"
            ln -sf "$src" "$dest"
            test -s "$dest"
        }}
        link_or_copy_optional () {{
            rel="$1"
            src="$(printf "%s" {params.run_dir:q} | sed 's:/*$::')/$rel"
            if [ -s "$src" ]; then
                dest="{params.source_run}/$rel"
                mkdir -p "$(dirname "$dest")"
                ln -sf "$src" "$dest"
            fi
        }}
        s3_copy_required () {{
            rel="$1"
            dest="{params.source_run}/$rel"
            mkdir -p "$(dirname "$dest")"
            AWS_PROFILE={params.profile:q} AWS_REGION={params.region:q} \
              aws s3 cp "$run_uri/$rel" "$dest" >> {log:q} 2>&1
            test -s "$dest"
        }}
        s3_copy_optional () {{
            rel="$1"
            dest="{params.source_run}/$rel"
            mkdir -p "$(dirname "$dest")"
            AWS_PROFILE={params.profile:q} AWS_REGION={params.region:q} \
              aws s3 cp "$run_uri/$rel" "$dest" >> {log:q} 2>&1 || true
            if [ -e "$dest" ]; then
                test -s "$dest"
            fi
        }}
        required_rels="RunInfo.xml
          InterOp/CorrectedIntMetricsOut.bin \
          InterOp/EmpiricalPhasingMetricsOut.bin \
          InterOp/ExtendedTileMetricsOut.bin \
          InterOp/ExtractionMetricsOut.bin \
          InterOp/ImageMetricsOut.bin \
          InterOp/QMetricsOut.bin \
          InterOp/SummaryRunMetricsOut.bin \
          InterOp/TileMetricsOut.bin"
        optional_rels="RunParameters.xml
          runParameters.xml
          SampleSheet.csv
          RunCompletionStatus.xml
          Analysis/1/Data/BCLConvert/SampleSheet.csv
          Analysis/1/Data/BCLConvert/fastq/Reports/fastq_list.csv
          Analysis/1/Data/BCLConvert/fastq/Reports/Quality_Metrics.csv
          Analysis/1/Data/BCLConvert/fastq/Reports/Adapter_Metrics.csv"
        if [ {params.mode:q} = "mounted" ]; then
            test -d {params.run_dir:q}
            for rel in $required_rels; do
                link_or_copy_required "$rel"
            done
            for rel in $optional_rels; do
                link_or_copy_optional "$rel"
            done
        elif [ {params.mode:q} = "s3" ]; then
            if [ -z {params.source_s3_uri:q} ]; then
                echo "SOURCE_S3_URI is required for Illumina run QC S3 mode" >> {log:q}
                exit 2
            fi
            if [ -z {params.profile:q} ]; then
                echo "PROFILE is required for Illumina run QC S3 mode" >> {log:q}
                exit 2
            fi
            if [ {params.profile:q} = "default" ]; then
                echo "PROFILE must not be default for Illumina run QC S3 mode" >> {log:q}
                exit 2
            fi
            if [ -z {params.region:q} ]; then
                echo "REGION is required for Illumina run QC S3 mode" >> {log:q}
                exit 2
            fi
            command -v aws >> {log:q} 2>&1
            run_uri=$(printf "%s" {params.source_s3_uri:q} | sed 's:/*$::')
            for rel in $required_rels; do
                s3_copy_required "$rel"
            done
            for rel in $optional_rels; do
                s3_copy_optional "$rel"
            done
        else
            echo "Unsupported Illumina run QC mode: {params.mode}" >> {log:q}
            exit 2
        fi
        for rel in $required_rels; do
            test -s "{params.source_run}/$rel"
        done
        touch {output.done:q}
        """


rule illumina_run_qc_interop_summary:
    input:
        done=RUNQC_ILMN_LOG_DIR + "/metric_subset_fetched.done",
    output:
        summary=RUNQC_ILMN_TABLE_DIR + "/interop_summary.csv",
        index_summary=RUNQC_ILMN_TABLE_DIR + "/interop_index_summary.csv",
    params:
        source_run=RUNQC_ILMN_SOURCE_RUN,
        interop_dir=RUNQC_ILMN_INTEROP_DIR,
        cluster_sample="illumina_run_qc_interop_summary",
    log:
        RUNQC_ILMN_LOG_DIR + "/interop_summary.log",
    benchmark:
        RUNQC_ILMN_BENCH_DIR + "/interop_summary.bench.tsv",
    conda:
        RUNQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.summary:q}) $(dirname {log:q})
        : > {log:q}
        test -d {params.interop_dir:q}
        if [ -z "${{CONDA_PREFIX:-}}" ]; then
            echo "CONDA_PREFIX is required for illumina_run_qc_interop_summary" >> {log:q}
            exit 2
        fi
        "$CONDA_PREFIX/bin/python" workflow/scripts/write_interop_summary_csv.py \
          --run-folder {params.source_run:q} \
          --summary-out {output.summary:q} \
          --index-summary-out {output.index_summary:q} \
          >> {log:q} 2>&1
        test -s {output.summary:q}
        test -s {output.index_summary:q}
        """


rule illumina_run_qc_json:
    input:
        done=RUNQC_ILMN_LOG_DIR + "/metric_subset_fetched.done",
        interop_summary=RUNQC_ILMN_TABLE_DIR + "/interop_summary.csv",
        interop_index_summary=RUNQC_ILMN_TABLE_DIR + "/interop_index_summary.csv",
    output:
        json=RUNQC_ILMN_TABLE_DIR + "/illumina_run_qc.json",
    params:
        source_run=RUNQC_ILMN_SOURCE_RUN,
        cluster_sample="illumina_run_qc_json",
    log:
        RUNQC_ILMN_LOG_DIR + "/illumina_run_qc_json.log",
    benchmark:
        RUNQC_ILMN_BENCH_DIR + "/illumina_run_qc_json.bench.tsv",
    conda:
        RUNQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.json:q}) $(dirname {log:q})
        : > {log:q}
        test -s {params.source_run:q}/RunInfo.xml
        if [ -z "${{CONDA_PREFIX:-}}" ]; then
            echo "CONDA_PREFIX is required for illumina_run_qc_json" >> {log:q}
            exit 2
        fi
        "$CONDA_PREFIX/bin/python" workflow/scripts/write_illumina_run_qc_json.py \
          --run-info {params.source_run:q}/RunInfo.xml \
          --interop-summary {input.interop_summary:q} \
          --interop-index-summary {input.interop_index_summary:q} \
          --output-json {output.json:q} \
          >> {log:q} 2>&1
        python -m json.tool {output.json:q} > {output.json:q}.pretty
        mv {output.json:q}.pretty {output.json:q}
        """


rule illumina_run_qc_report:
    input:
        interop_summary=RUNQC_ILMN_TABLE_DIR + "/interop_summary.csv",
        interop_index_summary=RUNQC_ILMN_TABLE_DIR + "/interop_index_summary.csv",
        illumina_qc_json=RUNQC_ILMN_TABLE_DIR + "/illumina_run_qc.json",
    output:
        html=RUNQC_ILMN_REPORT_DIR + "/summary.html",
        tsv=RUNQC_ILMN_TABLE_DIR + "/summary.tsv",
        done=RUNQC_ILMN_LOG_DIR + "/illumina_run_qc_report.done",
    params:
        run_s3_uri="" if RUNQC_ILMN_CONTEXT is None else RUNQC_ILMN_CONTEXT["SOURCE_S3_URI"],
        cluster_sample="illumina_run_qc_report",
    log:
        RUNQC_ILMN_LOG_DIR + "/illumina_run_qc_report.log",
    benchmark:
        RUNQC_ILMN_BENCH_DIR + "/illumina_run_qc_report.bench.tsv",
    conda:
        RUNQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.html:q}) $(dirname {output.tsv:q}) $(dirname {log:q})
        python workflow/scripts/summarize_run_qc_report.py \
          --platform ILMN \
          --run-s3-uri {params.run_s3_uri:q} \
          --interop-summary {input.interop_summary:q} \
          --interop-index-summary {input.interop_index_summary:q} \
          --illumina-qc-json {input.illumina_qc_json:q} \
          --output-html {output.html:q} \
          --output-tsv {output.tsv:q} \
          --done {output.done:q} > {log:q} 2>&1
        """


rule illumina_run_qc_multiqc:
    input:
        interop_summary=RUNQC_ILMN_TABLE_DIR + "/interop_summary.csv",
        interop_index_summary=RUNQC_ILMN_TABLE_DIR + "/interop_index_summary.csv",
        illumina_qc_json=RUNQC_ILMN_TABLE_DIR + "/illumina_run_qc.json",
        summary_tsv=RUNQC_ILMN_TABLE_DIR + "/summary.tsv",
        report_done=RUNQC_ILMN_LOG_DIR + "/illumina_run_qc_report.done",
    output:
        html=RUNQC_ILMN_REPORT_DIR + "/multiqc_report.html",
        mqc_tsv=RUNQC_ILMN_MQC_DIR + "/illumina_run_qc_summary_mqc.tsv",
        multiqc_config=RUNQC_ILMN_MQC_DIR + "/illumina_run_qc_multiqc_config.yaml",
    params:
        mqc_dir=RUNQC_ILMN_MQC_DIR,
        cluster_sample="illumina_run_qc_multiqc",
    log:
        RUNQC_ILMN_LOG_DIR + "/illumina_run_qc_multiqc.log",
    benchmark:
        RUNQC_ILMN_BENCH_DIR + "/illumina_run_qc_multiqc.bench.tsv",
    conda:
        RUNQC_MULTIQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.html:q}) $(dirname {log:q}) {params.mqc_dir:q}
        out={output.html:q}
        multiqc --version > {log:q} 2>&1 || true
        python workflow/scripts/illumina_run_qc_to_multiqc.py \
          --summary-tsv {input.summary_tsv:q} \
          --illumina-qc-json {input.illumina_qc_json:q} \
          --summary-out {output.mqc_tsv:q} \
          --config-out {output.multiqc_config:q} \
          >> {log:q} 2>&1
        multiqc -f \
          -m custom_content \
          --config {output.multiqc_config:q} \
          --filename "$(basename "$out")" \
          --outdir "$(dirname "$out")" \
          {params.mqc_dir:q} >> {log:q} 2>&1
        test -s {output.html:q}
        """


rule illumina_run_qc_read_fate_river:
    input:
        alignstats=MDIR + "other_reports/alignstats_combo_mqc.tsv",
        fetched=RUNQC_ILMN_LOG_DIR + "/metric_subset_fetched.done",
    output:
        html=RUNQC_ILMN_RIVER_HTML,
        tsv=RUNQC_ILMN_RIVER_TSV,
        markdown=RUNQC_ILMN_RIVER_MD,
        inventory=RUNQC_ILMN_RIVER_INVENTORY,
    params:
        out_dir=RUNQC_ILMN_REPORT_DIR,
        source_run=RUNQC_ILMN_SOURCE_RUN,
        run_s3_uri="" if RUNQC_ILMN_CONTEXT is None else RUNQC_ILMN_CONTEXT["SOURCE_S3_URI"],
        report_prefix=RUNQC_ILMN_REPORT_PREFIX,
        report_title=RUNQC_ILMN_REPORT_TITLE,
        cluster_sample="illumina_run_qc_read_fate_river",
    log:
        RUNQC_ILMN_LOG_DIR + "/illumina_read_fate_river.log",
    benchmark:
        RUNQC_ILMN_BENCH_DIR + "/illumina_read_fate_river.bench.tsv",
    conda:
        RUNQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p {params.out_dir:q} $(dirname {log:q})
        python bin/build_illumina_read_fate_river.py \
          --alignstats-combo {input.alignstats:q} \
          --output-dir {params.out_dir:q} \
          --run-s3-uri {params.run_s3_uri:q} \
          --local-run-dir {params.source_run:q} \
          --skip-fetch \
          --report-prefix {params.report_prefix:q} \
          --report-title {params.report_title:q} > {log:q} 2>&1
        test -s {output.html:q}
        test -s {output.tsv:q}
        test -s {output.markdown:q}
        test -s {output.inventory:q}
        """


rule produce_illumina_run_qc_and_bclconvert:  # TARGET: mounted Illumina run QC plus BCL Convert demux and demux MultiQC
    input:
        RUNQC_ILMN_REPORT_DIR + "/summary.html",
        RUNQC_ILMN_REPORT_DIR + "/multiqc_report.html",
        BCL_BOOTSTRAP_COMPLETE,


    log:
        MDIR + "logs/produce_illumina_run_qc_and_bclconvert.log"
    benchmark:
        "logs/benchmarks/produce_illumina_run_qc_and_bclconvert.bench.tsv"
    shell:
        r"""
        set -euo pipefail
        mkdir -p logs/benchmarks $(dirname {log:q})
        : > {log:q}
        """
rule ont_run_qc_collect_summaries:
    output:
        summary_list=RUNQC_ONT_SUMMARY_LIST,
    params:
        run_dir=RUNQC_ONT_RUN_DIR,
        cluster_sample="ont_run_qc_collect_summaries",
    log:
        RUNQC_ONT_LOG_DIR + "/collect_summaries.log",
    benchmark:
        RUNQC_ONT_BENCH_DIR + "/collect_summaries.bench.tsv",
    conda:
        RUNQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.summary_list:q}) $(dirname {log:q})
        : > {log:q}
        if [ -z {params.run_dir:q} ]; then
            echo "config/runs.tsv with PLATFORM=ONT and RUN_DIR is required for mounted ONT run QC" >> {log:q}
            exit 2
        fi
        test -d {params.run_dir:q}
        find {params.run_dir:q} -type f \( -name 'sequencing_summary*.txt' -o -name 'sequencing_summary*.txt.gz' \) \
          | sort > {output.summary_list:q}
        if [ ! -s {output.summary_list:q} ]; then
            echo "No sequencing_summary*.txt files found under {params.run_dir}" >> {log:q}
            exit 2
        fi
        """


rule ont_run_qc_pycoqc:
    input:
        summary_list=RUNQC_ONT_SUMMARY_LIST,
    output:
        html=RUNQC_ONT_PYCOQC_HTML,
        json=RUNQC_ONT_PYCOQC_JSON,
    params:
        run_id="" if RUNQC_ONT_CONTEXT is None else RUNQC_ONT_CONTEXT["RUNID"],
        cluster_sample="ont_run_qc_pycoqc",
    log:
        RUNQC_ONT_LOG_DIR + "/pycoqc.log",
    benchmark:
        RUNQC_ONT_BENCH_DIR + "/pycoqc.bench.tsv",
    conda:
        RUNQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p {RUNQC_ONT_PYCOQC_DIR:q} $(dirname {log:q})
        : > {log:q}
        command -v pycoQC >> {log:q} 2>&1
        mapfile -t summary_files < {input.summary_list:q}
        python workflow/scripts/run_pycoqc_compat.py \
          --summary-file "${{summary_files[@]}}" \
          --html-outfile {output.html:q} \
          --json-outfile {output.json:q} \
          --report-title {params.run_id:q} \
          >> {log:q} 2>&1
        test -s {output.html:q}
        test -s {output.json:q}
        """


rule ont_run_qc_nanoplot:
    input:
        summary_list=RUNQC_ONT_SUMMARY_LIST,
    output:
        done=touch(RUNQC_ONT_NANOPLOT_DONE),
    threads:
        8
    params:
        run_id="" if RUNQC_ONT_CONTEXT is None else RUNQC_ONT_CONTEXT["RUNID"],
        out_dir=RUNQC_ONT_NANOPLOT_DIR,
        cluster_sample="ont_run_qc_nanoplot",
    log:
        RUNQC_ONT_LOG_DIR + "/nanoplot.log",
    benchmark:
        RUNQC_ONT_BENCH_DIR + "/nanoplot.bench.tsv",
    conda:
        RUNQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p {params.out_dir:q} $(dirname {log:q})
        : > {log:q}
        command -v NanoPlot >> {log:q} 2>&1
        mapfile -t summary_files < {input.summary_list:q}
        NanoPlot \
          --summary "${{summary_files[@]}}" \
          --loglength \
          --tsv_stats \
          --info_in_report \
          -t {threads} \
          -o {params.out_dir:q} \
          -p {params.run_id:q}. \
          >> {log:q} 2>&1
        """


rule ont_run_qc_multiqc:
    input:
        pycoqc_html=RUNQC_ONT_PYCOQC_HTML,
        pycoqc_json=RUNQC_ONT_PYCOQC_JSON,
        nanoplot_done=RUNQC_ONT_NANOPLOT_DONE,
    output:
        html=RUNQC_ONT_MULTIQC_HTML,
    params:
        root=RUNQC_ONT_ROOT,
        cluster_sample="ont_run_qc_multiqc",
    log:
        RUNQC_ONT_LOG_DIR + "/multiqc.log",
    benchmark:
        RUNQC_ONT_BENCH_DIR + "/multiqc.bench.tsv",
    conda:
        RUNQC_MULTIQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.html:q}) $(dirname {log:q})
        multiqc --version > {log:q} 2>&1 || true
        multiqc -f \
          -m pycoqc \
          -m nanostat \
          --filename "$(basename {output.html:q})" \
          --outdir "$(dirname {output.html:q})" \
          {params.root:q} >> {log:q} 2>&1
        test -s {output.html:q}
        """


rule ont_demux_fastq_group_list:
    output:
        group_list=RUNQC_ONT_DEMUX_GROUP_LIST,
    params:
        run_dir=RUNQC_ONT_RUN_DIR,
        cluster_sample="ont_demux_fastq_group_list",
    log:
        RUNQC_ONT_LOG_DIR + "/demux_fastq_group_list.log",
    benchmark:
        RUNQC_ONT_BENCH_DIR + "/demux_fastq_group_list.bench.tsv",
    conda:
        RUNQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.group_list:q}) $(dirname {log:q})
        : > {log:q}
        if [ -z {params.run_dir:q} ]; then
            echo "config/runs.tsv with PLATFORM=ONT and RUN_DIR is required for ONT demux FASTQ QC" >> {log:q}
            exit 2
        fi
        test -d {params.run_dir:q}
        find {params.run_dir:q} -type f \( -name '*.fastq.gz' -o -name '*.fq.gz' \) \
          | sed 's#/[^/]*$##' \
          | sort -u > {output.group_list:q}
        if [ ! -s {output.group_list:q} ]; then
            echo "No demux FASTQ groups found under {params.run_dir}" >> {log:q}
            exit 2
        fi
        """


rule ont_demux_fastq_qc:
    input:
        group_list=RUNQC_ONT_DEMUX_GROUP_LIST,
    output:
        done=touch(RUNQC_ONT_DEMUX_DONE),
    threads:
        8
    params:
        out_root=RUNQC_ONT_DEMUX_ROOT,
        run_dir=RUNQC_ONT_RUN_DIR,
        run_id="" if RUNQC_ONT_CONTEXT is None else RUNQC_ONT_CONTEXT["RUNID"],
        cluster_sample="ont_demux_fastq_qc",
    log:
        RUNQC_ONT_LOG_DIR + "/demux_fastq_qc.log",
    benchmark:
        RUNQC_ONT_BENCH_DIR + "/demux_fastq_qc.bench.tsv",
    conda:
        RUNQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p {params.out_root:q} $(dirname {log:q})
        : > {log:q}
        command -v seqkit >> {log:q} 2>&1
        command -v nanoq >> {log:q} 2>&1
        command -v NanoStat >> {log:q} 2>&1
        command -v NanoPlot >> {log:q} 2>&1
        run_dir="$(printf "%s" {params.run_dir:q} | sed 's:/*$::')"
        seen_ids="{params.out_root}/.ont_demux_fastq_qc_seen_ids"
        find {params.out_root:q} -mindepth 1 -maxdepth 1 -type d -exec rm -rf {{}} +
        : > "$seen_ids"
        while IFS= read -r fastq_dir; do
            rel="${{fastq_dir#"$run_dir"/}}"
            if [ "$rel" = "$fastq_dir" ]; then
                echo "ONT demux FASTQ group is not under RUN_DIR: $fastq_dir" >> {log:q}
                exit 2
            fi
            group_token="$(printf "%s" "$rel" | sed 's#[^A-Za-z0-9._+-]#-#g; s#--*#-#g; s#^-##; s#-$##')"
            if [ -z "$group_token" ]; then
                echo "Could not derive ONT demux FASTQ sample identifier from $fastq_dir" >> {log:q}
                exit 2
            fi
            sample="{params.run_id}-${{group_token}}"
            if grep -Fxq "$sample" "$seen_ids"; then
                echo "Duplicate ONT demux FASTQ sample identifier $sample from $fastq_dir" >> {log:q}
                exit 2
            fi
            printf "%s\n" "$sample" >> "$seen_ids"
            sample_out="{params.out_root}/$sample"
            file_list="$sample_out/$sample.fastq_files.txt"
            mkdir -p "$sample_out/nanoplot"
            find "$fastq_dir" -maxdepth 1 -type f \( -name '*.fastq.gz' -o -name '*.fq.gz' \) \
              | sort > "$file_list"
            if [ ! -s "$file_list" ]; then
                echo "No FASTQs found for $sample under $fastq_dir" >> {log:q}
                exit 2
            fi
            mapfile -t fastqs < "$file_list"
            seqkit stats --tabular "${{fastqs[@]}}" \
              > "$sample_out/$sample.seqkit_stats.tsv" \
              2>> {log:q}
            gzip -dc "${{fastqs[@]}}" \
              | nanoq --stats --header \
              > "$sample_out/$sample.nanoq.txt" \
              2>> {log:q}
            NanoStat --fastq "${{fastqs[@]}}" \
              > "$sample_out/$sample.NanoStat.fastq.txt" \
              2>> {log:q}
            NanoPlot \
              --fastq "${{fastqs[@]}}" \
              --loglength \
              --tsv_stats \
              --info_in_report \
              -t {threads} \
              -o "$sample_out/nanoplot" \
              -p "$sample." \
              >> {log:q} 2>&1
        done < {input.group_list:q}
        """


rule ont_demux_fastq_multiqc:
    input:
        done=RUNQC_ONT_DEMUX_DONE,
    output:
        html=RUNQC_ONT_DEMUX_MULTIQC_HTML,
    params:
        root=RUNQC_ONT_DEMUX_ROOT,
        cluster_sample="ont_demux_fastq_multiqc",
    log:
        RUNQC_ONT_LOG_DIR + "/demux_fastq_multiqc.log",
    benchmark:
        RUNQC_ONT_BENCH_DIR + "/demux_fastq_multiqc.bench.tsv",
    conda:
        RUNQC_MULTIQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.html:q}) $(dirname {log:q})
        multiqc --version > {log:q} 2>&1 || true
        multiqc -f \
          -m nanostat \
          -m seqkit \
          -m nanoq \
          --filename "$(basename {output.html:q})" \
          --outdir "$(dirname {output.html:q})" \
          {params.root:q} >> {log:q} 2>&1
        test -s {output.html:q}
        """


rule ultima_demux_fastq_group_list:
    output:
        group_list=RUNQC_UG_DEMUX_GROUP_LIST,
    params:
        run_dir=RUNQC_UG_RUN_DIR,
        cluster_sample="ultima_demux_fastq_group_list",
    log:
        RUNQC_UG_LOG_DIR + "/demux_fastq_group_list.log",
    benchmark:
        RUNQC_UG_BENCH_DIR + "/demux_fastq_group_list.bench.tsv",
    conda:
        RUNQC_FASTQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.group_list:q}) $(dirname {log:q})
        : > {log:q}
        if [ -z {params.run_dir:q} ]; then
            echo "config/runs.tsv with PLATFORM=ULTIMA and RUN_DIR is required for Ultima demux FASTQ QC" >> {log:q}
            exit 2
        fi
        test -d {params.run_dir:q}
        find {params.run_dir:q} -type f \( -name '*.fastq.gz' -o -name '*.fq.gz' \) \
          | sed 's#/[^/]*$##' \
          | sort -u > {output.group_list:q}
        if [ ! -s {output.group_list:q} ]; then
            echo "No demux FASTQ groups found under {params.run_dir}" >> {log:q}
            exit 2
        fi
        """


rule ultima_demux_fastq_qc:
    input:
        group_list=RUNQC_UG_DEMUX_GROUP_LIST,
    output:
        done=touch(RUNQC_UG_DEMUX_DONE),
    threads:
        8
    params:
        out_root=RUNQC_UG_DEMUX_ROOT,
        run_dir=RUNQC_UG_RUN_DIR,
        run_id="" if RUNQC_UG_CONTEXT is None else RUNQC_UG_CONTEXT["RUNID"],
        cluster_sample="ultima_demux_fastq_qc",
    log:
        RUNQC_UG_LOG_DIR + "/demux_fastq_qc.log",
    benchmark:
        RUNQC_UG_BENCH_DIR + "/demux_fastq_qc.bench.tsv",
    conda:
        RUNQC_FASTQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p {params.out_root:q} $(dirname {log:q})
        : > {log:q}
        command -v fastqc >> {log:q} 2>&1
        command -v seqkit >> {log:q} 2>&1
        run_dir="$(printf "%s" {params.run_dir:q} | sed 's:/*$::')"
        seen_ids="{params.out_root}/.ultima_demux_fastq_qc_seen_ids"
        find {params.out_root:q} -mindepth 1 -maxdepth 1 -type d -exec rm -rf {{}} +
        : > "$seen_ids"
        while IFS= read -r fastq_dir; do
            rel="${{fastq_dir#"$run_dir"/}}"
            if [ "$rel" = "$fastq_dir" ]; then
                echo "Ultima demux FASTQ group is not under RUN_DIR: $fastq_dir" >> {log:q}
                exit 2
            fi
            group_token="$(printf "%s" "$rel" | sed 's#[^A-Za-z0-9._+-]#-#g; s#--*#-#g; s#^-##; s#-$##')"
            if [ -z "$group_token" ]; then
                echo "Could not derive Ultima demux FASTQ sample identifier from $fastq_dir" >> {log:q}
                exit 2
            fi
            sample="{params.run_id}-${{group_token}}"
            if grep -Fxq "$sample" "$seen_ids"; then
                echo "Duplicate Ultima demux FASTQ sample identifier $sample from $fastq_dir" >> {log:q}
                exit 2
            fi
            printf "%s\n" "$sample" >> "$seen_ids"
            sample_out="{params.out_root}/$sample"
            input_dir="$sample_out/inputs"
            fastqc_dir="$sample_out/fastqc"
            file_list="$sample_out/$sample.fastq_files.txt"
            mkdir -p "$input_dir" "$fastqc_dir"
            find "$fastq_dir" -maxdepth 1 -type f \( -name '*.fastq.gz' -o -name '*.fq.gz' \) \
              | sort > "$file_list"
            if [ ! -s "$file_list" ]; then
                echo "No FASTQs found for $sample under $fastq_dir" >> {log:q}
                exit 2
            fi
            mapfile -t fastqs < "$file_list"
            seqkit stats --tabular "${{fastqs[@]}}" \
              > "$sample_out/$sample.seqkit_stats.tsv" \
              2>> {log:q}
            fastqc_inputs=()
            idx=0
            for fastq in "${{fastqs[@]}}"; do
                idx="$((idx + 1))"
                base_token="$(basename "$fastq" | sed 's#[^A-Za-z0-9._+-]#-#g; s#--*#-#g; s#^-##; s#-$##')"
                link_path="$input_dir/$sample.$(printf '%03d' "$idx").$base_token"
                ln -sfn "$(realpath "$fastq")" "$link_path"
                fastqc_inputs+=("$link_path")
            done
            fastqc \
              -o "$fastqc_dir" \
              -t {threads} \
              "${{fastqc_inputs[@]}}" \
              >> {log:q} 2>&1
        done < {input.group_list:q}
        """


rule ultima_demux_fastq_multiqc:
    input:
        done=RUNQC_UG_DEMUX_DONE,
    output:
        html=RUNQC_UG_DEMUX_MULTIQC_HTML,
    params:
        root=RUNQC_UG_DEMUX_ROOT,
        cluster_sample="ultima_demux_fastq_multiqc",
    log:
        RUNQC_UG_LOG_DIR + "/demux_fastq_multiqc.log",
    benchmark:
        RUNQC_UG_BENCH_DIR + "/demux_fastq_multiqc.bench.tsv",
    conda:
        RUNQC_MULTIQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.html:q}) $(dirname {log:q})
        multiqc --version > {log:q} 2>&1 || true
        multiqc -f \
          -m fastqc \
          -m seqkit \
          --filename "$(basename {output.html:q})" \
          --outdir "$(dirname {output.html:q})" \
          {params.root:q} >> {log:q} 2>&1
        test -s {output.html:q}
        """


rule ont_run_qc_report:
    input:
        metrics=lambda wildcards: _runqc_optional_input(RUNQC_ONT_METRICS_PATH),
    output:
        html=RUNQC_ONT_ROOT + "/summary.html",
        tsv=RUNQC_ONT_ROOT + "/summary.tsv",
        done=RUNQC_ONT_ROOT + "/logs/ont_run_qc_report.done",
    params:
        metrics_path=RUNQC_ONT_METRICS_PATH,
        run_s3_uri=RUNQC_ONT_RUN_S3_URI,
        cluster_sample="ont_run_qc_report",
    log:
        RUNQC_ONT_ROOT + "/logs/ont_run_qc_report.log",
    benchmark:
        RUNQC_ONT_BENCH_DIR + "/ont_run_qc_report.bench.tsv",
    conda:
        RUNQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.html:q}) $(dirname {output.tsv:q}) $(dirname {log:q})
        python workflow/scripts/summarize_run_qc_report.py \
          --platform ONT \
          --run-s3-uri {params.run_s3_uri:q} \
          --metrics-path {params.metrics_path:q} \
          --output-html {output.html:q} \
          --output-tsv {output.tsv:q} \
          --done {output.done:q} > {log:q} 2>&1
        """


rule ultima_run_qc_report:
    output:
        html=RUNQC_UG_ROOT + "/summary.html",
        tsv=RUNQC_UG_ROOT + "/summary.tsv",
        done=RUNQC_UG_ROOT + "/logs/ultima_run_qc_report.done",
    params:
        metrics_path=_runqc_text(RUNQC_UG_CFG, "metrics_path"),
        run_s3_uri=RUNQC_UG_RUN_S3_URI,
        cluster_sample="ultima_run_qc_report",
    log:
        RUNQC_UG_ROOT + "/logs/ultima_run_qc_report.log",
    benchmark:
        RUNQC_UG_BENCH_DIR + "/ultima_run_qc_report.bench.tsv",
    conda:
        RUNQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.html:q}) $(dirname {output.tsv:q}) $(dirname {log:q})
        python workflow/scripts/summarize_run_qc_report.py \
          --platform UG \
          --run-s3-uri {params.run_s3_uri:q} \
          --metrics-path {params.metrics_path:q} \
          --output-html {output.html:q} \
          --output-tsv {output.tsv:q} \
          --done {output.done:q} > {log:q} 2>&1
        """


rule produce_illumina_run_qc:  # TARGET: separate Illumina run-level QC report
    input:
        RUNQC_ILMN_REPORT_DIR + "/summary.html",
        RUNQC_ILMN_REPORT_DIR + "/multiqc_report.html",


    log:
        MDIR + "logs/produce_illumina_run_qc.log"
    benchmark:
        "logs/benchmarks/produce_illumina_run_qc.bench.tsv"
    shell:
        r"""
        set -euo pipefail
        mkdir -p logs/benchmarks $(dirname {log:q})
        : > {log:q}
        """
rule produce_ont_run_qc:  # TARGET: mounted ONT run-level QC plus demux FASTQ QC
    input:
        RUNQC_ONT_TARGET_INPUTS,


    log:
        MDIR + "logs/produce_ont_run_qc.log"
    benchmark:
        "logs/benchmarks/produce_ont_run_qc.bench.tsv"
    shell:
        r"""
        set -euo pipefail
        mkdir -p logs/benchmarks $(dirname {log:q})
        : > {log:q}
        """
rule produce_ont_demux_fastq_qc:  # TARGET: mounted ONT demux FASTQ QC and focused MultiQC report
    input:
        RUNQC_ONT_DEMUX_MULTIQC_HTML,


    log:
        MDIR + "logs/produce_ont_demux_fastq_qc.log"
    benchmark:
        "logs/benchmarks/produce_ont_demux_fastq_qc.bench.tsv"
    shell:
        r"""
        set -euo pipefail
        mkdir -p logs/benchmarks $(dirname {log:q})
        : > {log:q}
        """
rule produce_ont_run_qc_and_demux_multiqc:  # TARGET: mounted ONT run QC plus demux FASTQ MultiQC
    input:
        RUNQC_ONT_TARGET_INPUTS,


    log:
        MDIR + "logs/produce_ont_run_qc_and_demux_multiqc.log"
    benchmark:
        "logs/benchmarks/produce_ont_run_qc_and_demux_multiqc.bench.tsv"
    shell:
        r"""
        set -euo pipefail
        mkdir -p logs/benchmarks $(dirname {log:q})
        : > {log:q}
        """
rule produce_ultima_run_qc:  # TARGET: mounted Ultima run-level QC plus demux FASTQ QC
    input:
        RUNQC_UG_TARGET_INPUTS,


    log:
        MDIR + "logs/produce_ultima_run_qc.log"
    benchmark:
        "logs/benchmarks/produce_ultima_run_qc.bench.tsv"
    shell:
        r"""
        set -euo pipefail
        mkdir -p logs/benchmarks $(dirname {log:q})
        : > {log:q}
        """
rule produce_ultima_demux_fastq_qc:  # TARGET: mounted Ultima demux FASTQ QC and focused MultiQC report
    input:
        RUNQC_UG_DEMUX_MULTIQC_HTML,


    log:
        MDIR + "logs/produce_ultima_demux_fastq_qc.log"
    benchmark:
        "logs/benchmarks/produce_ultima_demux_fastq_qc.bench.tsv"
    shell:
        r"""
        set -euo pipefail
        mkdir -p logs/benchmarks $(dirname {log:q})
        : > {log:q}
        """
rule produce_ultima_run_qc_and_demux_multiqc:  # TARGET: mounted Ultima run QC plus demux FASTQ MultiQC
    input:
        RUNQC_UG_TARGET_INPUTS,


    log:
        MDIR + "logs/produce_ultima_run_qc_and_demux_multiqc.log"
    benchmark:
        "logs/benchmarks/produce_ultima_run_qc_and_demux_multiqc.bench.tsv"
    shell:
        r"""
        set -euo pipefail
        mkdir -p logs/benchmarks $(dirname {log:q})
        : > {log:q}
        """
rule produce_read_fate_river:  # TARGET: Illumina read-fate RIVER report
    input:
        RUNQC_ILMN_RIVER_HTML,


    log:
        MDIR + "logs/produce_read_fate_river.log"
    benchmark:
        "logs/benchmarks/produce_read_fate_river.bench.tsv"
    shell:
        r"""
        set -euo pipefail
        mkdir -p logs/benchmarks $(dirname {log:q})
        : > {log:q}
        """
rule produce_run_qc_reports:  # TARGET: all run-level QC reports, separate from final WGS MultiQC
    input:
        RUNQC_ILMN_REPORT_DIR + "/summary.html",
        RUNQC_ILMN_REPORT_DIR + "/multiqc_report.html",
        RUNQC_ONT_TARGET_INPUTS,
        RUNQC_UG_TARGET_INPUTS,
    log:
        MDIR + "logs/produce_run_qc_reports.log"
    benchmark:
        "logs/benchmarks/produce_run_qc_reports.bench.tsv"
    shell:
        r"""
        set -euo pipefail
        mkdir -p logs/benchmarks $(dirname {log:q})
        : > {log:q}
        """
