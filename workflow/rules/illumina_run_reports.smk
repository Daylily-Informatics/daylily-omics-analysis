import os

from snakemake.exceptions import WorkflowError


ILLUMINA_RUN_METRICS_CFG = config.get("illumina_run_metrics", {})
ILLUMINA_RUN_DIR = str(ILLUMINA_RUN_METRICS_CFG.get("run_dir", "") or "").strip()
ILLUMINA_AWS_PROFILE = str(
    ILLUMINA_RUN_METRICS_CFG.get("aws_profile", "") or ""
).strip()
ILLUMINA_AWS_REGION = str(
    ILLUMINA_RUN_METRICS_CFG.get("aws_region", "") or ""
).strip()

ILLUMINA_RUN_METRICS_DIR = MDIR + "reports/illumina_run_metrics"
ILLUMINA_RUN_METRICS_RAW_DIR = ILLUMINA_RUN_METRICS_DIR + "/raw_metric_tables"
READ_DISPOSITIONS_DIR = MDIR + "reports/read_dispositions"
ILLUMINA_REPORT_ENV = "../envs/illumina_run_metrics.yaml"
ILLUMINA_SAMPLES_TABLE = str(
    config.get("samples_table", os.path.abspath(os.path.join("config", "samples.tsv")))
)
ILLUMINA_UNITS_TABLE = str(
    config.get("units_table", os.path.abspath(os.path.join("config", "units.tsv")))
)


def validate_illumina_run_metrics_config():
    if ILLUMINA_RUN_DIR == "":
        raise WorkflowError("illumina_run_metrics.run_dir is required")
    if ILLUMINA_RUN_DIR.startswith("s3://") and ILLUMINA_AWS_PROFILE == "":
        raise WorkflowError(
            "illumina_run_metrics.aws_profile is required when illumina_run_metrics.run_dir starts with s3://"
        )
    if ILLUMINA_RUN_DIR.startswith("s3://") and ILLUMINA_AWS_REGION == "":
        raise WorkflowError(
            "illumina_run_metrics.aws_region is required when illumina_run_metrics.run_dir starts with s3://"
        )
    return True


localrules:
    produce_illumina_run_metrics,
    produce_read_dispositions,


rule illumina_run_metrics:
    output:
        html=ILLUMINA_RUN_METRICS_DIR + "/illumina_run_metrics.html",
        markdown=ILLUMINA_RUN_METRICS_DIR + "/illumina_run_metrics.md",
        artifact_status=ILLUMINA_RUN_METRICS_RAW_DIR + "/artifact_status.tsv",
        source_objects=ILLUMINA_RUN_METRICS_RAW_DIR + "/source_objects.tsv",
        run_metadata=ILLUMINA_RUN_METRICS_RAW_DIR + "/run_metadata.tsv",
        fastq_list=ILLUMINA_RUN_METRICS_RAW_DIR + "/bclconvert_fastq_list.tsv",
        quality_metrics=ILLUMINA_RUN_METRICS_RAW_DIR + "/bclconvert_quality_metrics_with_read_equivalents.tsv",
        sample_lanes=ILLUMINA_RUN_METRICS_RAW_DIR + "/bclconvert_quality_metrics_by_analyzed_sample_lane.tsv",
        demux_summary=ILLUMINA_RUN_METRICS_RAW_DIR + "/bclconvert_demux_summary.tsv",
        mqc=MDIR + "other_reports/illumina_run_metrics_mqc.tsv",
    benchmark:
        MDIR + "benchmarks/illumina_run_metrics.bench.tsv"
    threads: 1
    params:
        run_dir=ILLUMINA_RUN_DIR,
        aws_profile=ILLUMINA_AWS_PROFILE,
        aws_region=ILLUMINA_AWS_REGION,
        validated=lambda wildcards: validate_illumina_run_metrics_config(),
        cluster_sample="illumina_run_metrics",
    log:
        MDIR + "reports/logs/illumina_run_metrics.log",
    conda:
        ILLUMINA_REPORT_ENV
    container: None
    shell:
        """
        set -euo pipefail
        : {params.validated:q}
        mkdir -p {ILLUMINA_RUN_METRICS_DIR:q} {ILLUMINA_RUN_METRICS_RAW_DIR:q} $(dirname {output.mqc:q}) $(dirname {log:q})
        python workflow/scripts/illumina_run_metrics.py \
          --run-dir {params.run_dir:q} \
          --output-dir {ILLUMINA_RUN_METRICS_DIR:q} \
          --mqc-out {output.mqc:q} \
          --aws-profile {params.aws_profile:q} \
          --aws-region {params.aws_region:q} > {log:q} 2>&1
        """


rule read_dispositions_report:
    input:
        metrics=ILLUMINA_RUN_METRICS_RAW_DIR + "/bclconvert_quality_metrics_by_analyzed_sample_lane.tsv",
        alignstats=MDIR + "other_reports/alignstats_combo_mqc.tsv",
        samples=ILLUMINA_SAMPLES_TABLE,
        units=ILLUMINA_UNITS_TABLE,
    output:
        html=READ_DISPOSITIONS_DIR + "/read_dispositions.html",
        markdown=READ_DISPOSITIONS_DIR + "/read_dispositions.md",
        sample_lanes=READ_DISPOSITIONS_DIR + "/sample_lane_dispositions.tsv",
        cohort=READ_DISPOSITIONS_DIR + "/cohort_dispositions.tsv",
        mqc=MDIR + "other_reports/read_dispositions_mqc.tsv",
    benchmark:
        MDIR + "benchmarks/read_dispositions.bench.tsv"
    threads: 1
    params:
        metrics_dir=ILLUMINA_RUN_METRICS_RAW_DIR,
        cluster_sample="read_dispositions",
    log:
        MDIR + "reports/logs/read_dispositions.log",
    conda:
        ILLUMINA_REPORT_ENV
    container: None
    shell:
        """
        set -euo pipefail
        mkdir -p {READ_DISPOSITIONS_DIR:q} $(dirname {output.mqc:q}) $(dirname {log:q})
        python workflow/scripts/read_dispositions_report.py \
          --metrics-dir {params.metrics_dir:q} \
          --alignstats-combo {input.alignstats:q} \
          --samples-tsv {input.samples:q} \
          --units-tsv {input.units:q} \
          --output-dir {READ_DISPOSITIONS_DIR:q} \
          --mqc-out {output.mqc:q} > {log:q} 2>&1
        """


rule produce_illumina_run_metrics:  # TARGET: Build Illumina run metrics from a local or S3 run folder
    input:
        ILLUMINA_RUN_METRICS_DIR + "/illumina_run_metrics.html",
        ILLUMINA_RUN_METRICS_DIR + "/illumina_run_metrics.md",
        MDIR + "other_reports/illumina_run_metrics_mqc.tsv",


rule produce_read_dispositions:  # TARGET: Build read disposition report from Illumina metrics and alignstats
    input:
        READ_DISPOSITIONS_DIR + "/read_dispositions.html",
        READ_DISPOSITIONS_DIR + "/read_dispositions.md",
        READ_DISPOSITIONS_DIR + "/sample_lane_dispositions.tsv",
        READ_DISPOSITIONS_DIR + "/cohort_dispositions.tsv",
        MDIR + "other_reports/read_dispositions_mqc.tsv",
