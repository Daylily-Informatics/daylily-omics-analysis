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
RUNQC_MULTIQC_ENV = (
    config.get("multiqc", {})
    .get("run_qc", {})
    .get("env_yaml", "../envs/multiqc_v0.1.yaml")
)

RUNQC_ILMN_TARGET_REQUESTED = bool(
    _requested_targets()
    & {"produce_illumina_run_qc", "produce_read_fate_river", "produce_run_qc_reports"}
)
RUNQC_ONT_TARGET_REQUESTED = bool(
    _requested_targets() & {"produce_ont_run_qc", "produce_run_qc_reports"}
)
RUNQC_UG_TARGET_REQUESTED = bool(
    _requested_targets() & {"produce_ultima_run_qc", "produce_run_qc_reports"}
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
RUNQC_ILMN_LOG_DIR = RUNQC_ILMN_ROOT + "/logs"
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


localrules:
    illumina_run_qc_fetch_metric_subset,
    illumina_run_qc_interop_summary,
    illumina_run_qc_checkqc_json,
    illumina_run_qc_report,
    illumina_run_qc_multiqc,
    illumina_run_qc_read_fate_river,
    ont_run_qc_report,
    ultima_run_qc_report,
    produce_illumina_run_qc,
    produce_ont_run_qc,
    produce_ultima_run_qc,
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
    conda:
        RUNQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.summary:q}) $(dirname {log:q})
        : > {log:q}
        test -d {params.interop_dir:q}
        command -v interop_summary >> {log:q} 2>&1
        command -v interop_index-summary >> {log:q} 2>&1
        interop_summary {params.source_run:q} --csv=1 > {output.summary:q} 2>> {log:q}
        interop_index-summary {params.source_run:q} --csv=1 > {output.index_summary:q} 2>> {log:q}
        test -s {output.summary:q}
        test -s {output.index_summary:q}
        """


rule illumina_run_qc_checkqc_json:
    input:
        done=RUNQC_ILMN_LOG_DIR + "/metric_subset_fetched.done",
    output:
        json=RUNQC_ILMN_TABLE_DIR + "/checkqc.json",
    params:
        source_run=RUNQC_ILMN_SOURCE_RUN,
        config_file=_runqc_text(RUNQC_ILMN_CFG, "checkqc_config_file"),
        cluster_sample="illumina_run_qc_checkqc_json",
    log:
        RUNQC_ILMN_LOG_DIR + "/checkqc.log",
    conda:
        RUNQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.json:q}) $(dirname {log:q})
        : > {log:q}
        test -s {params.source_run:q}/RunInfo.xml
        command -v checkqc >> {log:q} 2>&1
        if [ -n {params.config_file:q} ]; then
            test -s {params.config_file:q}
            checkqc --config_file {params.config_file:q} --json {params.source_run:q} > {output.json:q} 2>> {log:q}
        else
            checkqc --json {params.source_run:q} > {output.json:q} 2>> {log:q}
        fi
        python -m json.tool {output.json:q} > {output.json:q}.pretty
        mv {output.json:q}.pretty {output.json:q}
        """


rule illumina_run_qc_report:
    input:
        interop_summary=RUNQC_ILMN_TABLE_DIR + "/interop_summary.csv",
        interop_index_summary=RUNQC_ILMN_TABLE_DIR + "/interop_index_summary.csv",
        checkqc_json=RUNQC_ILMN_TABLE_DIR + "/checkqc.json",
    output:
        html=RUNQC_ILMN_REPORT_DIR + "/summary.html",
        tsv=RUNQC_ILMN_TABLE_DIR + "/summary.tsv",
        done=RUNQC_ILMN_LOG_DIR + "/illumina_run_qc_report.done",
    params:
        run_s3_uri="" if RUNQC_ILMN_CONTEXT is None else RUNQC_ILMN_CONTEXT["SOURCE_S3_URI"],
        cluster_sample="illumina_run_qc_report",
    log:
        RUNQC_ILMN_LOG_DIR + "/illumina_run_qc_report.log",
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
          --checkqc-json {input.checkqc_json:q} \
          --output-html {output.html:q} \
          --output-tsv {output.tsv:q} \
          --done {output.done:q} > {log:q} 2>&1
        """


rule illumina_run_qc_multiqc:
    input:
        interop_summary=RUNQC_ILMN_TABLE_DIR + "/interop_summary.csv",
        interop_index_summary=RUNQC_ILMN_TABLE_DIR + "/interop_index_summary.csv",
        checkqc_json=RUNQC_ILMN_TABLE_DIR + "/checkqc.json",
        report_done=RUNQC_ILMN_LOG_DIR + "/illumina_run_qc_report.done",
    output:
        html=RUNQC_ILMN_REPORT_DIR + "/multiqc_report.html",
    params:
        root=RUNQC_ILMN_ROOT,
        cluster_sample="illumina_run_qc_multiqc",
    log:
        RUNQC_ILMN_LOG_DIR + "/illumina_run_qc_multiqc.log",
    conda:
        RUNQC_MULTIQC_ENV
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.html:q}) $(dirname {log:q})
        out={output.html:q}
        multiqc --version > {log:q} 2>&1 || true
        multiqc -f \
          -m interop \
          -m checkqc \
          --filename "$(basename "$out")" \
          --outdir "$(dirname "$out")" \
          {params.root:q} >> {log:q} 2>&1
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


rule ont_run_qc_report:
    output:
        html=RUNQC_ONT_ROOT + "/summary.html",
        tsv=RUNQC_ONT_ROOT + "/summary.tsv",
        done=RUNQC_ONT_ROOT + "/logs/ont_run_qc_report.done",
    params:
        metrics_path=_runqc_text(RUNQC_ONT_CFG, "metrics_path"),
        run_s3_uri=_runqc_text(RUNQC_ONT_CFG, "run_s3_uri"),
        cluster_sample="ont_run_qc_report",
    log:
        RUNQC_ONT_ROOT + "/logs/ont_run_qc_report.log",
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
        run_s3_uri=_runqc_text(RUNQC_UG_CFG, "run_s3_uri"),
        cluster_sample="ultima_run_qc_report",
    log:
        RUNQC_UG_ROOT + "/logs/ultima_run_qc_report.log",
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


rule produce_ont_run_qc:  # TARGET: explicit ONT run-level QC placeholder report
    input:
        RUNQC_ONT_ROOT + "/logs/ont_run_qc_report.done",


rule produce_ultima_run_qc:  # TARGET: explicit Ultima run-level QC placeholder report
    input:
        RUNQC_UG_ROOT + "/logs/ultima_run_qc_report.done",


rule produce_read_fate_river:  # TARGET: Illumina read-fate RIVER report
    input:
        RUNQC_ILMN_RIVER_HTML,


rule produce_run_qc_reports:  # TARGET: all run-level QC reports, separate from final WGS MultiQC
    input:
        RUNQC_ILMN_REPORT_DIR + "/summary.html",
        RUNQC_ILMN_REPORT_DIR + "/multiqc_report.html",
        RUNQC_ONT_ROOT + "/logs/ont_run_qc_report.done",
        RUNQC_UG_ROOT + "/logs/ultima_run_qc_report.done",
