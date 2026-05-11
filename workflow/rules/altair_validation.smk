import csv
import shlex

from snakemake.exceptions import WorkflowError


ALTAIR_VALIDATION_CONFIG = config.get("altair_validation", {})
ALTAIR_VALIDATION_OUTPUT_DIR = str(
    ALTAIR_VALIDATION_CONFIG.get("output_dir", "validation_artifacts")
).rstrip("/")
ALTAIR_VALIDATION_FORBIDDEN_RR_PATH_TOKENS = (
    "altair_rr_v1_x_giab",
    "benchmark_accuracy_region",
    "bar",
    "giabhc",
    "giab_hc",
    "giab-hc",
    "highconfidence",
    "high_confidence",
    "clinvar",
    "wgs",
    "core",
    "whole_genome",
    "whole-genome",
)


def _altair_required_config_path(key):
    value = str(ALTAIR_VALIDATION_CONFIG.get(key, "")).strip()
    if value == "":
        raise WorkflowError(
            f"produce_altair_validation_artifacts requires altair_validation.{key}."
        )
    return value


def _altair_optional_config_path(key):
    value = str(ALTAIR_VALIDATION_CONFIG.get(key, "")).strip()
    return value if value else ""


def _altair_required_nested_path(section, key):
    section_value = ALTAIR_VALIDATION_CONFIG.get(section, {})
    if isinstance(section_value, dict):
        value = str(section_value.get(key, "")).strip()
    else:
        value = str(section_value).strip()
    if value == "":
        raise WorkflowError(
            f"produce_altair_validation_artifacts requires "
            f"altair_validation.{section}.{key}."
        )
    return value


def _altair_optional_nested_path(section, key):
    section_value = ALTAIR_VALIDATION_CONFIG.get(section, {})
    if isinstance(section_value, dict):
        return str(section_value.get(key, "")).strip()
    return ""


def _altair_rr_full_bed(wildcards=None):
    rr_bed = _altair_required_nested_path("coverage", "full_rr_bed")
    normalized = rr_bed.lower().replace("/", "_").replace(".", "_").replace("-", "_")
    rejected = [
        token
        for token in ALTAIR_VALIDATION_FORBIDDEN_RR_PATH_TOKENS
        if token in normalized
    ]
    if rejected:
        raise WorkflowError(
            "altair_validation.coverage.full_rr_bed must be the full controlled "
            "Altair RR BED. BAR, GIAB HC, ClinVar-only, WGS, and core-scope "
            f"paths are rejected. Rejected token(s): {', '.join(rejected)} in {rr_bed}"
        )
    return rr_bed


def _altair_coverage_param(key, default):
    coverage = ALTAIR_VALIDATION_CONFIG.get("coverage", {})
    if isinstance(coverage, dict):
        return coverage.get(key, default)
    return default


def _altair_rr_manifest_value(field):
    manifest = _altair_required_config_path("rr_manifest")
    with open(manifest, newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    if len(rows) != 1:
        raise WorkflowError(
            "Altair validation expects rr_manifest.tsv to contain exactly one "
            f"controlled RR row; found {len(rows)} rows in {manifest}."
        )
    value = str(rows[0].get(field, "")).strip()
    if value in ["", "NA", "None"]:
        raise WorkflowError(f"rr_manifest.tsv is missing required field {field}.")
    return value


def _altair_boundary_verification_input(wildcards=None):
    configured = _altair_optional_config_path("boundary_verification")
    if configured:
        return configured
    return ALTAIR_VALIDATION_OUTPUT_DIR + "/rr_boundary_verification.tsv"


def _altair_release_vcfs(wildcards=None):
    boundary = ALTAIR_VALIDATION_CONFIG.get("boundary", {})
    values = []
    if isinstance(boundary, dict):
        values = boundary.get("released_vcfs", [])
    if isinstance(values, str):
        values = [item.strip() for item in values.split(",") if item.strip()]
    if not values:
        raise WorkflowError(
            "Altair boundary verification requires "
            "altair_validation.boundary.released_vcfs or "
            "altair_validation.boundary_verification."
        )
    return values


def _altair_report_args():
    template = _altair_optional_config_path("report_template_docx")
    if not template:
        return ""
    report_docx = _altair_optional_config_path("report_docx")
    args = ["--report-template-docx", template]
    if report_docx:
        args.extend(["--report-docx", report_docx])
    return " ".join(shlex.quote(str(item)) for item in args)


localrules:
    altair_validation_rr_coverage_callability,
    altair_rr_boundary_verification,
    produce_altair_validation_artifacts,


rule altair_rr_mosdepth:
    """Generate one per-sample mosdepth RR coverage/callability row."""
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
        full_rr_bed=_altair_rr_full_bed,
        rr_manifest=lambda wildcards: _altair_required_config_path("rr_manifest"),
    output:
        tsv=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/altair_rr/"
        + "{sample}.{alnr}.{ddup}.rr_coverage_callability.tsv",
        regions=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/altair_rr/mosdepth/"
        + "{sample}.{alnr}.{ddup}.Altair_RR_v1.regions.bed.gz",
        thresholds=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/altair_rr/mosdepth/"
        + "{sample}.{alnr}.{ddup}.Altair_RR_v1.thresholds.bed.gz",
        summary=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/altair_rr/mosdepth/"
        + "{sample}.{alnr}.{ddup}.Altair_RR_v1.mosdepth.summary.txt",
    threads: config["mosdepth"]["threads"]
    resources:
        threads=config["mosdepth"]["threads"],
        partition=config["mosdepth"]["partition"],
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.altair_rr_mosdepth.bench.tsv"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/altair_rr/logs/"
        + "{sample}.{alnr}.{ddup}.altair_rr_mosdepth.log",
    conda:
        config["mosdepth"]["env_yaml"]
    params:
        prefix=lambda wildcards, output: str(output.summary).removesuffix(
            ".mosdepth.summary.txt"
        ),
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mapq=lambda wildcards: _altair_coverage_param("min_mapq", 0),
        depth_bins=lambda wildcards: _altair_coverage_param("depth_bins", "0,10,20"),
        rr_bed_name=lambda wildcards: _altair_rr_manifest_value("rr_bed_name"),
        rr_bed_sha256=lambda wildcards: _altair_rr_manifest_value("rr_bed_sha256"),
        rr_total_bases=lambda wildcards: _altair_rr_manifest_value("rr_total_bases"),
        callable_definition=lambda wildcards: _altair_coverage_param(
            "callable_definition",
            "mosdepth DP>=20x over full Altair_RR_v1",
        ),
    shell:
        """
        mkdir -p "$(dirname {output.tsv})" "$(dirname {output.summary})" "$(dirname {log})"
        rm -f {params.prefix}.mosdepth.* {params.prefix}.regions.bed.gz {params.prefix}.thresholds.bed.gz
        mosdepth --threads {threads} \
            --by {input.full_rr_bed:q} \
            --use-median \
            -n \
            --fast-mode \
            --mapq {params.mapq} \
            -f {params.huref:q} \
            -T {params.depth_bins:q} \
            {params.prefix:q} \
            {input.cram:q} \
            > {log:q} 2>&1
        mosdepth_version=$(mosdepth --version 2>&1 | head -n 1 | tr ' ' '_')
        python -m daylily_omics_analysis.altair_validation coverage-from-mosdepth \
            --sample-id {wildcards.sample:q} \
            --run-id {wildcards.alnr:q} \
            --library-id {wildcards.ddup:q} \
            --rr-bed {input.full_rr_bed:q} \
            --rr-bed-name {params.rr_bed_name:q} \
            --rr-bed-sha256 {params.rr_bed_sha256:q} \
            --rr-total-bases {params.rr_total_bases:q} \
            --regions-bed-gz {output.regions:q} \
            --thresholds-bed-gz {output.thresholds:q} \
            --coverage-tool-version "$mosdepth_version" \
            --callable-definition {params.callable_definition:q} \
            --output {output.tsv:q} \
            >> {log:q} 2>&1
        """


rule altair_validation_rr_coverage_callability:
    """Aggregate RR-specific coverage/callability across samples."""
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/alignqc/altair_rr/"
            + "{sample}.{alnr}.{ddup}.rr_coverage_callability.tsv",
            sample=SSAMPS,
            alnr=CRAM_ALIGNERS,
            ddup=DDUP,
        ),
    output:
        ALTAIR_VALIDATION_OUTPUT_DIR + "/rr_coverage_callability_by_sample.tsv",
    log:
        ALTAIR_VALIDATION_OUTPUT_DIR + "/logs/rr_coverage_callability_by_sample.log",
    conda:
        "../envs/vanilla_v0.1.yaml"
    shell:
        """
        mkdir -p "$(dirname {output})" "$(dirname {log})"
        python -m daylily_omics_analysis.altair_validation merge-coverage \
            --output {output:q} \
            {input:q} \
            > {log:q} 2>&1
        """


rule altair_rr_boundary_verification:
    """Verify released VCFs have zero calls outside RR and no released indels >50 bp."""
    input:
        rr_bed=_altair_rr_full_bed,
        vcfs=_altair_release_vcfs,
    output:
        ALTAIR_VALIDATION_OUTPUT_DIR + "/rr_boundary_verification.tsv",
    params:
        rr_bed_name=lambda wildcards: _altair_rr_manifest_value("rr_bed_name"),
        rr_bed_sha256=lambda wildcards: _altair_rr_manifest_value("rr_bed_sha256"),
    log:
        ALTAIR_VALIDATION_OUTPUT_DIR + "/logs/rr_boundary_verification.log",
    conda:
        "../envs/vanilla_v0.1.yaml"
    shell:
        """
        mkdir -p "$(dirname {output})" "$(dirname {log})"
        python -m daylily_omics_analysis.altair_validation boundary-from-vcf \
            --rr-bed {input.rr_bed:q} \
            --rr-bed-name {params.rr_bed_name:q} \
            --rr-bed-sha256 {params.rr_bed_sha256:q} \
            --output {output:q} \
            {input.vcfs:q} \
            > {log:q} 2>&1
        """


rule produce_altair_validation_artifacts:
    """TARGET: Produce audit-ready Altair validation_artifacts."""
    input:
        rr_manifest=lambda wildcards: _altair_required_config_path("rr_manifest"),
        bar_manifest=lambda wildcards: _altair_required_config_path("bar_manifest"),
        giab_concordance=lambda wildcards: _altair_required_config_path("giab_concordance"),
        rr_callability=rules.altair_validation_rr_coverage_callability.output,
        boundary_verification=_altair_boundary_verification_input,
    output:
        rr_manifest=ALTAIR_VALIDATION_OUTPUT_DIR + "/rr_manifest.tsv",
        bar_manifest=ALTAIR_VALIDATION_OUTPUT_DIR + "/bar_manifest.tsv",
        accuracy_by_sample=ALTAIR_VALIDATION_OUTPUT_DIR
        + "/accuracy_metrics_by_sample.tsv",
        accuracy_pooled=ALTAIR_VALIDATION_OUTPUT_DIR + "/accuracy_metrics_pooled.tsv",
        coverage=ALTAIR_VALIDATION_OUTPUT_DIR
        + "/rr_coverage_callability_by_sample.tsv",
        boundary=ALTAIR_VALIDATION_OUTPUT_DIR + "/rr_boundary_verification.tsv",
        summary=ALTAIR_VALIDATION_OUTPUT_DIR + "/validation_summary.json",
        sentinel=ALTAIR_VALIDATION_OUTPUT_DIR + "/altair_validation_artifacts.done",
    params:
        output_dir=ALTAIR_VALIDATION_OUTPUT_DIR,
        report_args=lambda wildcards: _altair_report_args(),
    log:
        ALTAIR_VALIDATION_OUTPUT_DIR + "/logs/produce_altair_validation_artifacts.log",
    conda:
        "../envs/vanilla_v0.1.yaml"
    shell:
        """
        mkdir -p {params.output_dir:q} "$(dirname {log})"
        python -m daylily_omics_analysis.altair_validation build \
            --rr-manifest {input.rr_manifest:q} \
            --bar-manifest {input.bar_manifest:q} \
            --giab-concordance {input.giab_concordance:q} \
            --rr-coverage-callability {input.rr_callability:q} \
            --boundary-verification {input.boundary_verification:q} \
            --output-dir {params.output_dir:q} \
            {params.report_args} \
            > {log:q} 2>&1
        touch {output.sentinel}
        """
