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


def _alignstats_input(wildcards):
    """Return alignment file + index, choosing BAM for BAM_ALIGNERS else CRAM."""
    base = MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}"
    if wildcards.alnr in BAM_ALIGNERS:
        return {"aln": base + ".bam", "idx": base + ".bam.bai"}
    return {"aln": base + ".cram", "idx": base + ".cram.crai"}


def _alignstats_format(wildcards):
    """Return 'bam' or 'cram' for the alignstats -j flag."""
    return "bam" if wildcards.alnr in BAM_ALIGNERS else "cram"


rule alignstats:
    input:
        unpack(_alignstats_input),
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
        aln_format=_alignstats_format,
        ld_preload=" "
        if "ld_preload" not in config["malloc_alt"]
        else config["malloc_alt"]["ld_preload"],
        ld_pre=" "
        if "ld_preload" not in config["alignstats"]        else config["alignstats"]["ld_preload"],
    conda:
        config["alignstats"]["env_yaml"]
    shell:
        "alignstats  -C -U  -i {input.aln} -T {params.huref} -o {output.json}  -j {params.aln_format} -v -P {threads} -p {threads} > {log};"


localrules:
    finish_align_stats,

rule finish_align_stats:
    input:
        json=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/alignstats/{sample}.{alnr}.{ddup}.alignstats.json",
    output:
        tsv=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/alignstats/{sample}.{alnr}.{ddup}.alignstats.tsv",
    threads: 2
    params:
        P=50,
        n=config["alignstats"]["num_reads_in_mem"],
        cluster_sample=ret_sample,
        alnr_f=fetch_alnr,
        ld_preload=" "
        if "ld_preload" not in config["malloc_alt"]
        else config["malloc_alt"]["ld_preload"],
        ld_pre=" "
        if "ld_preload" not in config["alignstats"]
        else config["alignstats"]["ld_preload"],
    run:
        import os
        import sys
        import json

        j = json.load(open(f"{input.json}", "r"))
        aa = "sample\taligner\t" + "\t".join([str(x) for x in sorted(j)])
        bb = f"{params.cluster_sample}.{params.alnr_f}\t{params.alnr_f}\t" + "\t".join(
            [str(j[x]) for x in sorted(j)]
        )
        os.system(f"echo {aa} > {output.tsv} ; echo {bb} >> {output.tsv}")

