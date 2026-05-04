import os

import pandas as pd
from snakemake.exceptions import WorkflowError


configfile: "config/relatedness.yaml"


def _required_config(name):
    value = config.get(name, "")
    if value in ["", None, "None"]:
        raise WorkflowError(f"config/relatedness.yaml must define '{name}'.")
    return value


def _load_samples():
    manifest = config.get("samples_manifest", "")
    if manifest in ["", None, "None"]:
        raise WorkflowError(
            "config/relatedness.yaml must define samples_manifest; "
            "expected columns: sample_id, path, path_type, optional sex, batch_id, family_id."
        )

    if not os.path.exists(manifest):
        raise WorkflowError(f"Relatedness samples_manifest not found: {manifest}")

    frame = pd.read_csv(
        manifest,
        sep="\t",
        dtype=str,
        keep_default_na=False,
        na_values=[],
    )
    required = {"sample_id", "path", "path_type"}
    missing = required - set(frame.columns)
    if missing:
        raise WorkflowError(
            f"Relatedness samples_manifest missing required columns: {sorted(missing)}"
        )
    if frame["sample_id"].duplicated().any():
        duplicated = sorted(frame.loc[frame["sample_id"].duplicated(), "sample_id"].unique())
        raise WorkflowError(f"Duplicate relatedness sample_id values: {duplicated}")

    valid_types = {"bam", "cram", "vcf"}
    bad_types = sorted(set(frame["path_type"]) - valid_types)
    if bad_types:
        raise WorkflowError(
            f"Invalid relatedness path_type values: {bad_types}; expected {sorted(valid_types)}"
        )

    missing_paths = frame.loc[~frame["path"].map(os.path.exists), ["sample_id", "path"]]
    if not missing_paths.empty:
        details = ", ".join(
            f"{row.sample_id}:{row.path}" for row in missing_paths.itertuples(index=False)
        )
        raise WorkflowError(f"Relatedness input paths do not exist: {details}")

    return frame.set_index("sample_id", drop=False)


SAMPLES_MANIFEST = _required_config("samples_manifest")
REF = _required_config("ref_fasta")
SOM_SITES = _required_config("somalier_sites_vcf")
GENOME_BUILD = config.get("genome_build", "GRCh38")
SAMPLE_TABLE = _load_samples()
SAMPLES = SAMPLE_TABLE["sample_id"].tolist()

SOMALIER_DIR = "results/relatedness/somalier"
REPORT_DIR = "results/relatedness"
SomExtract = expand(
    SOMALIER_DIR + "/extract/{sample}.somalier",
    sample=SAMPLES,
)


def sample_path(wildcards):
    return SAMPLE_TABLE.loc[wildcards.sample, "path"]


def sample_type(wildcards):
    return SAMPLE_TABLE.loc[wildcards.sample, "path_type"]


rule relatedness_all:
    input:
        REPORT_DIR + "/relatedness_pairs_classified.tsv",
        REPORT_DIR + "/relatedness_summary.tsv",
        REPORT_DIR + "/relatedness_report.html",


rule somalier_extract:
    output:
        SOMALIER_DIR + "/extract/{sample}.somalier"
    params:
        input_path=sample_path,
        input_type=sample_type,
        sites=SOM_SITES,
        ref=REF,
        build=GENOME_BUILD,
        prefix=lambda wildcards: f"{SOMALIER_DIR}/extract/{wildcards.sample}",
    threads: 4
    conda:
        "../envs/somalier.yaml"
    shell:
        r"""
        set -euo pipefail
        mkdir -p {SOMALIER_DIR}/extract
        if [[ "{params.input_type}" == "bam" || "{params.input_type}" == "cram" ]]; then
            somalier extract \
              --sites {params.sites} \
              --fasta {params.ref} \
              --out-dir {SOMALIER_DIR}/extract \
              --sample-prefix {wildcards.sample} \
              {params.input_path}
        elif [[ "{params.input_type}" == "vcf" ]]; then
            somalier extract \
              --sites {params.sites} \
              --unknown \
              --out-dir {SOMALIER_DIR}/extract \
              --sample-prefix {wildcards.sample} \
              {params.input_path}
        else
            echo "unsupported path_type: {params.input_type}" >&2
            exit 2
        fi
        test -s {output}
        """


rule somalier_relate:
    input:
        SomExtract
    output:
        pairs=SOMALIER_DIR + "/cohort_pairs.tsv",
        groups=SOMALIER_DIR + "/cohort_groups.tsv",
        html=SOMALIER_DIR + "/cohort.html",
    conda:
        "../envs/somalier.yaml"
    shell:
        r"""
        set -euo pipefail
        mkdir -p {SOMALIER_DIR}
        somalier relate {SOMALIER_DIR}/extract/*.somalier -o {SOMALIER_DIR}/cohort
        test -s {output.pairs}
        test -s {output.groups}
        test -s {output.html}
        """


rule relatedness_report:
    input:
        pairs=SOMALIER_DIR + "/cohort_pairs.tsv",
        groups=SOMALIER_DIR + "/cohort_groups.tsv",
        manifest=SAMPLES_MANIFEST,
    output:
        pairs_classified=REPORT_DIR + "/relatedness_pairs_classified.tsv",
        summary=REPORT_DIR + "/relatedness_summary.tsv",
        html=REPORT_DIR + "/relatedness_report.html",
    params:
        expected=config.get("expected_relationships", ""),
        thresholds=config.get("relationship_thresholds", {}),
    conda:
        "../envs/report.yaml"
    script:
        "../scripts/relatedness_report.py"


rule produce_relatedness:
    input:
        REPORT_DIR + "/relatedness_pairs_classified.tsv",
        REPORT_DIR + "/relatedness_summary.tsv",
        REPORT_DIR + "/relatedness_report.html",
