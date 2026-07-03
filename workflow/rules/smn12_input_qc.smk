"""Preflight BAM/CRAM inputs for SMN12 caller compatibility."""


SMN12_INPUT_QC_GENOME_ARG = "37" if config["genome_build"] == "b37" else "38"


def smn12_input_qc_dir(wildcards):
    return (
        MDIR
        + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/htd/smn12_input_qc"
    )


def smn12_input_qc_done(wildcards):
    return (
        smn12_input_qc_dir(wildcards)
        + f"/{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.smn12_input_qc.done"
    )


def smn12_input_qc_mqc_path(wildcards):
    return (
        smn12_input_qc_dir(wildcards)
        + f"/{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.smn12_preflight_mqc.tsv"
    )


def smn12_input_qc_outputs(wildcards=None):
    return expand_smn_alnr_ddup_pairs(
        [
            MDIR
            + "{sample}/align/{alnr}/{ddup}/htd/smn12_input_qc/"
            + "{sample}.{alnr}.{ddup}.smn12_input_qc.tsv",
            MDIR
            + "{sample}/align/{alnr}/{ddup}/htd/smn12_input_qc/"
            + "{sample}.{alnr}.{ddup}.smn12_region_depth.tsv",
            MDIR
            + "{sample}/align/{alnr}/{ddup}/htd/smn12_input_qc/"
            + "{sample}.{alnr}.{ddup}.smn12_required_regions_status.tsv",
            MDIR
            + "{sample}/align/{alnr}/{ddup}/htd/smn12_input_qc/"
            + "{sample}.{alnr}.{ddup}.smn12_alignment_flags.tsv",
            MDIR
            + "{sample}/align/{alnr}/{ddup}/htd/smn12_input_qc/"
            + "{sample}.{alnr}.{ddup}.smn12_preflight_mqc.tsv",
            MDIR
            + "{sample}/align/{alnr}/{ddup}/htd/smn12_input_qc/"
            + "{sample}.{alnr}.{ddup}.smn12_input_qc.done",
        ],
        pairs=smn_short_read_alnr_ddup_pairs(),
    )


def smn12_input_qc_mqc_outputs(wildcards=None):
    return expand_smn_alnr_ddup_pairs(
        MDIR
        + "{sample}/align/{alnr}/{ddup}/htd/smn12_input_qc/"
        + "{sample}.{alnr}.{ddup}.smn12_preflight_mqc.tsv",
        pairs=smn_short_read_alnr_ddup_pairs(),
    )


rule smn12_input_qc:
    """Validate a whole-genome BAM/CRAM before SMN12 callers consume it."""
    input:
        cram=smn_short_cram,
        crai=smn_short_crai,
    output:
        input_qc=MDIR
        + "{sample}/align/{alnr}/{ddup}/htd/smn12_input_qc/"
        + "{sample}.{alnr}.{ddup}.smn12_input_qc.tsv",
        region_depth=MDIR
        + "{sample}/align/{alnr}/{ddup}/htd/smn12_input_qc/"
        + "{sample}.{alnr}.{ddup}.smn12_region_depth.tsv",
        required_status=MDIR
        + "{sample}/align/{alnr}/{ddup}/htd/smn12_input_qc/"
        + "{sample}.{alnr}.{ddup}.smn12_required_regions_status.tsv",
        alignment_flags=MDIR
        + "{sample}/align/{alnr}/{ddup}/htd/smn12_input_qc/"
        + "{sample}.{alnr}.{ddup}.smn12_alignment_flags.tsv",
        mqc=MDIR
        + "{sample}/align/{alnr}/{ddup}/htd/smn12_input_qc/"
        + "{sample}.{alnr}.{ddup}.smn12_preflight_mqc.tsv",
        done=MDIR
        + "{sample}/align/{alnr}/{ddup}/htd/smn12_input_qc/"
        + "{sample}.{alnr}.{ddup}.smn12_input_qc.done",
    params:
        cluster_sample=ret_sample,
        reference=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        data_dir="workflow/resources/smn12",
        genome=SMN12_INPUT_QC_GENOME_ARG,
        max_sample_records=lambda wildcards: config.get("smn12_input_qc", {}).get(
            "max_sample_records", 200000
        ),
        min_norm_bin_present_fraction=lambda wildcards: config.get(
            "smn12_input_qc", {}
        ).get("min_norm_bin_present_fraction", 0.95),
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/htd/smn12_input_qc/logs/"
        + "{sample}.{alnr}.{ddup}.smn12_input_qc.log",
    benchmark:
        MDIR + "benchmarks/smn12_input_qc.{alnr}.{ddup}.{sample}.bench.tsv"
    threads: config["smn12_input_qc"]["threads"]
    resources:
        partition=config["smn12_input_qc"]["partition"],
        threads=config["smn12_input_qc"]["threads"],
        vcpu=config["smn12_input_qc"]["threads"],
        mem_mb=config["smn12_input_qc"]["mem_mb"],
    conda:
        "../envs/smn12_v0.1.yaml"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.input_qc:q}) $(dirname {log:q})
        rm -f {output.input_qc:q} {output.region_depth:q} {output.required_status:q} \
              {output.alignment_flags:q} {output.mqc:q} {output.done:q}
        python workflow/scripts/smn12_input_qc.py \
          --input {input.cram:q} \
          --reference {params.reference:q} \
          --regions-bed {params.data_dir:q}/SMN_region_{params.genome}.bed \
          --snp-file {params.data_dir:q}/SMN_SNP_{params.genome}.txt \
          --target-variant-file {params.data_dir:q}/SMN_target_variant_{params.genome}.txt \
          --sample {wildcards.sample:q} \
          --aligner {wildcards.alnr:q} \
          --deduper {wildcards.ddup:q} \
          --input-qc {output.input_qc:q} \
          --region-depth {output.region_depth:q} \
          --required-status {output.required_status:q} \
          --alignment-flags {output.alignment_flags:q} \
          --mqc {output.mqc:q} \
          --max-sample-records {params.max_sample_records:q} \
          --min-norm-bin-present-fraction {params.min_norm_bin_present_fraction:q} \
          > {log:q} 2>&1
        touch {output.done:q}
        """


localrules:
    smn12_input_qc_mqc,
    produce_smn12_input_qc,


rule smn12_input_qc_mqc:
    input:
        smn12_input_qc_mqc_outputs
    output:
        MDIR + "other_reports/smn12_preflight_mqc.tsv"
    log:
        MDIR + "other_reports/logs/smn12_preflight_mqc.log"
    benchmark:
        MDIR + "benchmarks/smn12_preflight_mqc.bench.tsv"
    container: None
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        first=1
        : > {output:q}
        for tsv in {input:q}; do
          if [ "$first" -eq 1 ]; then
            cat "$tsv" >> {output:q}
            first=0
          else
            tail -n +2 "$tsv" >> {output:q}
          fi
        done > {log:q} 2>&1
        """


rule produce_smn12_input_qc:  # TARGET : Produce SMN12 caller input preflight QC
    input:
        qc=smn12_input_qc_outputs,
        mqc=MDIR + "other_reports/smn12_preflight_mqc.tsv",
    output:
        "logs/smn12_input_qc.done"
    log:
        MDIR + "logs/produce_smn12_input_qc.log"
    benchmark:
        "logs/benchmarks/produce_smn12_input_qc.bench.tsv"
    shell:
        "mkdir -p $(dirname {output}); touch {output}"
