import csv
import os
from pathlib import Path


RELATEDNESS_CFG = config["relatedness"]
RELATEDNESS_REPORT_ROOT = MDIR + "other_reports/relatedness"
RELATEDNESS_SAMPLES = qc_eligible_sample_ids(SSAMPS)


def _relatedness_sample_rows():
    rows = []
    for sample in RELATEDNESS_SAMPLES:
        sample_info = config.get("sample_info", {}).get(sample, {})
        rows.append(
            {
                "sample_id": sample,
                "path": f"{MDIR}{sample}/align/{{alnr}}/{{ddup}}/{sample}.{{alnr}}.{{ddup}}.cram",
                "path_type": "cram",
                "sex": str(sample_info.get("biological_sex", "")),
                "batch_id": "{alnr}.{ddup}",
                "external_sample_id": str(
                    sample_info.get("external_sample_id", sample)
                ),
                "family_id": str(sample_info.get("family_id", "")),
            }
        )
    return rows


def _relatedness_manifest_inputs(wildcards):
    paths = []
    for sample in RELATEDNESS_SAMPLES:
        paths.append(
            MDIR
            + f"{sample}/align/{wildcards.alnr}/{wildcards.ddup}/{sample}.{wildcards.alnr}.{wildcards.ddup}.cram"
        )
        paths.append(
            MDIR
            + f"{sample}/align/{wildcards.alnr}/{wildcards.ddup}/{sample}.{wildcards.alnr}.{wildcards.ddup}.cram.crai"
        )
    return paths


def _relatedness_extract_paths(wildcards):
    return expand(
        MDIR
        + "other_reports/relatedness/{alnr}/{ddup}/somalier/extract/{sample}.somalier",
        sample=RELATEDNESS_SAMPLES,
        alnr=[wildcards.alnr],
        ddup=[wildcards.ddup],
    )


localrules:
    relatedness_batch_manifest,
    relatedness_batch_report,
    relatedness_batch_gather,
    produce_relatedness,


rule relatedness_batch_manifest:
    input:
        _relatedness_manifest_inputs
    output:
        RELATEDNESS_REPORT_ROOT + "/{alnr}/{ddup}/relatedness_manifest.tsv"
    log:
        MDIR + "logs/{alnr}.{ddup}.relatedness_batch_manifest.log"
    run:
        os.makedirs(os.path.dirname(str(output[0])), exist_ok=True)
        with open(output[0], "w", newline="") as handle:
            fieldnames = [
                "sample_id",
                "path",
                "path_type",
                "sex",
                "batch_id",
                "external_sample_id",
                "family_id",
            ]
            writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
            writer.writeheader()
            for row in _relatedness_sample_rows():
                expanded = {
                    key: value.format(alnr=wildcards.alnr, ddup=wildcards.ddup)
                    for key, value in row.items()
                }
                writer.writerow(expanded)


rule relatedness_batch_somalier_extract:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        RELATEDNESS_REPORT_ROOT
        + "/{alnr}/{ddup}/somalier/extract/{sample}.somalier"
    threads: RELATEDNESS_CFG["threads"]
    resources:
        vcpu=RELATEDNESS_CFG["threads"],
        partition=RELATEDNESS_CFG["partition"],
    params:
        sites=RELATEDNESS_CFG["somalier_sites_vcf"],
        ref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        out_dir=RELATEDNESS_REPORT_ROOT + "/{alnr}/{ddup}/somalier/extract",
        sample_ok=lambda wildcards: require_qc_eligible_sample(
            wildcards, "Somalier relatedness"
        ),
        cluster_sample=ret_sample,
    log:
        RELATEDNESS_REPORT_ROOT
        + "/{alnr}/{ddup}/somalier/logs/{sample}.extract.log"
    benchmark:
        MDIR + "{sample}/benchmarks/{alnr}.{ddup}.{sample}.relatedness_batch_somalier_extract.bench.tsv"
    conda:
        RELATEDNESS_CFG["env_yaml"]
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        test {params.sample_ok:q} = ok
        rm -f {output:q}
        tmp_dir="$(mktemp -d "$(dirname {output:q})/.somalier_extract.XXXXXX")"
        cleanup() {{
            rm -rf "$tmp_dir"
        }}
        trap cleanup EXIT
        somalier extract \
          --sites {params.sites:q} \
          --fasta {params.ref:q} \
          --out-dir "$tmp_dir" \
          {input.cram:q} \
          > {log:q} 2>&1
        mapfile -t somalier_outputs < <(find "$tmp_dir" -maxdepth 1 -type f -name "*.somalier" | sort)
        if [ "${{#somalier_outputs[@]}}" -ne 1 ]; then
            echo "ERROR: expected exactly one somalier extract output in $tmp_dir, found ${{#somalier_outputs[@]}}" >> {log:q}
            printf '%s\n' "${{somalier_outputs[@]}}" >> {log:q}
            exit 2
        fi
        mv "${{somalier_outputs[0]}}" {output:q}
        test -s {output:q}
        """


rule relatedness_batch_somalier_relate:
    input:
        _relatedness_extract_paths
    output:
        samples=RELATEDNESS_REPORT_ROOT + "/{alnr}/{ddup}/somalier/cohort.samples.tsv",
        pairs=RELATEDNESS_REPORT_ROOT + "/{alnr}/{ddup}/somalier/cohort.pairs.tsv",
        groups=RELATEDNESS_REPORT_ROOT + "/{alnr}/{ddup}/somalier/cohort.groups.tsv",
        html=RELATEDNESS_REPORT_ROOT + "/{alnr}/{ddup}/somalier/cohort.html",
    params:
        prefix=RELATEDNESS_REPORT_ROOT + "/{alnr}/{ddup}/somalier/cohort",
        sample_count=lambda wildcards: len(RELATEDNESS_SAMPLES),
        cluster_sample="relatedness_batch",
    threads: RELATEDNESS_CFG["threads"]
    resources:
        vcpu=RELATEDNESS_CFG["threads"],
        partition=RELATEDNESS_CFG["partition"],
    log:
        RELATEDNESS_REPORT_ROOT + "/{alnr}/{ddup}/somalier/logs/cohort.log"
    benchmark:
        MDIR + "benchmarks/{alnr}.{ddup}.relatedness_batch_somalier_relate.bench.tsv"
    conda:
        RELATEDNESS_CFG["env_yaml"]
    shell:
        r"""
        set -euo pipefail
        mkdir -p $(dirname {output.pairs:q}) $(dirname {log:q})
        rm -f {output.samples:q} {output.pairs:q} {output.groups:q} {output.html:q}
        if [ {params.sample_count} -lt 2 ]; then
            printf "sample_a\tsample_b\trelatedness\tibs0\n" > {output.pairs:q}
            printf "sample_id\tgroup\n" > {output.samples:q}
            printf "sample_id\tgroup\n" > {output.groups:q}
            printf "<html><body><h1>Relatedness QC</h1><p>No pairs available.</p></body></html>\n" > {output.html:q}
        else
            somalier relate {input:q} -o {params.prefix:q} > {log:q} 2>&1
        fi
        for expected_output in {output.pairs:q} {output.groups:q} {output.samples:q} {output.html:q}; do
            if [[ ! -s "$expected_output" ]]; then
                printf 'ERROR: somalier relate did not create declared cohort output: %s\n' "$expected_output" >> {log:q}
                exit 1
            fi
        done
        """


rule relatedness_batch_report:
    input:
        pairs=RELATEDNESS_REPORT_ROOT + "/{alnr}/{ddup}/somalier/cohort.pairs.tsv",
        groups=RELATEDNESS_REPORT_ROOT + "/{alnr}/{ddup}/somalier/cohort.groups.tsv",
        manifest=RELATEDNESS_REPORT_ROOT + "/{alnr}/{ddup}/relatedness_manifest.tsv",
    output:
        pairs_classified=RELATEDNESS_REPORT_ROOT
        + "/{alnr}/{ddup}/relatedness_pairs_classified.tsv",
        summary=RELATEDNESS_REPORT_ROOT + "/{alnr}/{ddup}/relatedness_summary.tsv",
        html=RELATEDNESS_REPORT_ROOT + "/{alnr}/{ddup}/relatedness_report.html",
    log:
        MDIR + "logs/{alnr}.{ddup}.relatedness_batch_report.log"
    benchmark:
        MDIR + "benchmarks/{alnr}.{ddup}.relatedness_batch_report.bench.tsv"
    params:
        expected=RELATEDNESS_CFG.get("expected_relationships", ""),
        thresholds=RELATEDNESS_CFG.get("relationship_thresholds", {}),
        cluster_sample="relatedness_report",
    conda:
        RELATEDNESS_CFG["report_env_yaml"]
    script:
        "../scripts/relatedness_report.py"


rule relatedness_batch_gather:
    input:
        expand(
            RELATEDNESS_REPORT_ROOT + "/{alnr}/{ddup}/relatedness_summary.tsv",
            alnr=QC_CRAM_ALIGNERS,
            ddup=qc_variant_dedupers(),
        )
    output:
        MDIR + "other_reports/relatedness_mqc.tsv"
    log:
        MDIR + "logs/relatedness_batch_gather.log"
    run:
        os.makedirs(os.path.dirname(str(output[0])), exist_ok=True)
        fieldnames = [
            "Sample",
            "batch_id",
            "aligner",
            "deduper",
            "relationship",
            "status",
            "pair_count",
        ]
        with open(output[0], "w", newline="") as out_handle:
            writer = csv.DictWriter(out_handle, fieldnames=fieldnames, delimiter="\t")
            writer.writeheader()
            for path in input:
                summary_path = Path(path)
                deduper = summary_path.parent.name
                aligner = summary_path.parent.parent.name
                with summary_path.open(newline="") as in_handle:
                    reader = csv.DictReader(in_handle, delimiter="\t")
                    for row in reader:
                        writer.writerow(
                            {
                                "Sample": f"{aligner}.{deduper}",
                                "batch_id": f"{aligner}.{deduper}",
                                "aligner": aligner,
                                "deduper": deduper,
                                "relationship": row.get("relationship", ""),
                                "status": row.get("status", ""),
                                "pair_count": row.get("pair_count", ""),
                            }
                        )


rule produce_relatedness:  # TARGET: produce batch Somalier relatedness QC
    input:
        MDIR + "other_reports/relatedness_mqc.tsv"
    log:
        MDIR + "logs/produce_relatedness.log"
    benchmark:
        "logs/benchmarks/produce_relatedness.bench.tsv"
