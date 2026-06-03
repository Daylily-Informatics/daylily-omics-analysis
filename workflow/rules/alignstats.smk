import os
##### ALIGNSTATS
# --------------
#
# It blows my mind this tool is not uniformly adopted.
# It calculates 300+ metrices relevant to monitoring NGS
# quality, and does it all in one place, often with more detail
# included than the standard tooling.  I rely on it
# for a ton of QC work. The Baylor Genome Center developed it
# github: https://github.com/jfarek/alignstat


def fetch_alnr(wildcards):
    return wildcards.alnr

ruleorder: alignstats_bam > alignstats


rule alignstats_bam:
    """Run alignstats on BAM input (Roche SBX Duplex BAMs that stay as BAM, not CRAM)."""
    input:
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.bam",
        bai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.bam.bai",
    output:
        json=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/alignstats/{sample}.{alnr}.{ddup}.alignstats.json",
    wildcard_constraints:
        alnr="roche",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.alignstats_bam.bench.tsv"
    threads: config["alignstats"]["threads"]
    resources:
        attempt_n=lambda wildcards, attempt:  (attempt + 0),
        partition=config["alignstats"]["partition"],
        threads=config["alignstats"]["threads"],
        vcpu=config["alignstats"]["threads"]
    log:  MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/alignstats/logs/{sample}.{alnr}.{ddup}.alignstats.log",
    params:
        P=50,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        n=config["alignstats"]["num_reads_in_mem"],
        cluster_sample=ret_sample,
        ld_preload=" "
        if "ld_preload" not in config["malloc_alt"]
        else config["malloc_alt"]["ld_preload"],
        ld_pre=" "
        if "ld_preload" not in config["alignstats"]
        else config["alignstats"]["ld_preload"],
    conda:
        config["alignstats"]["env_yaml"]
    shell:
        "resources/alignstats/alignstats  -C -U  -i {input.bam} -T {params.huref} -o {output.json}  -j bam -v -P {threads} -p {threads} > {log};"


rule alignstats:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        json=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/alignstats/{sample}.{alnr}.{ddup}.alignstats.json",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.alignstats.bench.tsv"
    threads: config["alignstats"]["threads"]
    resources:
        attempt_n=lambda wildcards, attempt:  (attempt + 0),
        partition=config["alignstats"]["partition"],
        threads=config["alignstats"]["threads"],
        vcpu=config["alignstats"]["threads"]
    log:  MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/alignstats/logs/{sample}.{alnr}.{ddup}.alignstats.log",
    params:
        P=50,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        n=config["alignstats"]["num_reads_in_mem"],
        cluster_sample=ret_sample,
        ld_preload=" "
        if "ld_preload" not in config["malloc_alt"]
        else config["malloc_alt"]["ld_preload"],
        ld_pre=" "
        if "ld_preload" not in config["alignstats"]        else config["alignstats"]["ld_preload"],
    conda:
        config["alignstats"]["env_yaml"]
    shell:
        "resources/alignstats/alignstats  -C -U  -i {input.cram} -T {params.huref} -o {output.json}  -j cram -v -P {threads} -p {threads} > {log};"


localrules:
    finish_align_stats,

rule finish_align_stats:
    input:
        json=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/alignstats/{sample}.{alnr}.{ddup}.alignstats.json",
    output:
        tsv=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/alignstats/{sample}.{alnr}.{ddup}.alignstats.tsv",
    log:
        MDIR + "{sample}/logs/{sample}.{alnr}.{ddup}.finish_align_stats.log"
    threads: 2
    params:
        P=50,
        n=config["alignstats"]["num_reads_in_mem"],
        cluster_sample=ret_sample,
        alnr_f=fetch_alnr,
        ddup=lambda wildcards: wildcards.ddup,
        ld_preload=" "
        if "ld_preload" not in config["malloc_alt"]
        else config["malloc_alt"]["ld_preload"],
        ld_pre=" "
        if "ld_preload" not in config["alignstats"]
        else config["alignstats"]["ld_preload"],
    run:
        import csv
        import json

        j = json.load(open(f"{input.json}", "r"))
        metric_fields = [str(x) for x in sorted(j)]
        fieldnames = ["Sample", "base_sample", "aligner", "deduper"] + metric_fields
        row = {
            "Sample": day_stage_sample_id(
                params.cluster_sample, params.alnr_f, params.ddup
            ),
            "base_sample": params.cluster_sample,
            "aligner": params.alnr_f,
            "deduper": params.ddup,
        }
        row.update({field: str(j[field]) for field in metric_fields})
        with open(output.tsv, "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
            writer.writeheader()
            writer.writerow(row)
