import os
# ###### MOSDEPTH
#
# mosdepth
# github: https://github.com/brentp/mosdepth
# paper: https://academic.oup.com/bioinformatics/article/34/5/867/4583630


rule mosdepth:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        summary=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/{sample}.{alnr}.{ddup}.mosdepth.summary.txt",
        global_dist=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/{sample}.{alnr}.{ddup}.mosdepth.global.dist.txt",
        region_dist=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/{sample}.{alnr}.{ddup}.mosdepth.region.dist.txt",
    threads: config["mosdepth"]["threads"]
    resources:
        threads=config["mosdepth"]["threads"],
        partition=config["mosdepth"]["partition"],
        mem_mb=config["mosdepth"]["mem_mb"],
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.mosdepth.bench.tsv"
    log:
        a=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/{sample}.{alnr}.{ddup}.mosdepth.log",
    conda:
        config["mosdepth"]["env_yaml"]
    params:
        prefix=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/{sample}.{alnr}.{ddup}",
        win_size=1000,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        core_bed=config["supporting_files"]["files"]["huref"]["fasta"]["bed"],
        mapq=0,
        T="0,10,20,30"
        if "depth_bins" not in config["mosdepth"]
        else config["mosdepth"]["depth_bins"],
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output.summary:q})"
        rm -f {log.a:q} {params.prefix:q} {output.summary:q} {output.global_dist:q} {output.region_dist:q}
        mosdepth --threads {threads} --by {params.core_bed:q} --use-median -n --fast-mode --mapq {params.mapq} -f {params.huref:q} -T {params.T:q} {params.prefix:q} {input.cram:q} > {log.a:q} 2>&1
        rm -f {params.prefix:q}.per-base.bed.gz {params.prefix:q}.per-base.bed.gz.csi
        test -s {output.summary:q} || (printf 'ERROR: mosdepth summary output is missing or empty: %s\n' {output.summary:q} | tee -a {log.a:q} >&2; exit 1)
        test -s {output.global_dist:q} || (printf 'ERROR: mosdepth global_dist output is missing or empty: %s\n' {output.global_dist:q} | tee -a {log.a:q} >&2; exit 1)
        test -s {output.region_dist:q} || (printf 'ERROR: mosdepth region_dist output is missing or empty: %s\n' {output.region_dist:q} | tee -a {log.a:q} >&2; exit 1)
        """

localrules:
    produce_mosdepth,

rule produce_mosdepth:  # TARGET:  jusg gen mosdepth
    input:
        expand(MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/{sample}.{alnr}.{ddup}.mosdepth.summary.txt", sample=SSAMPS, alnr=QC_CRAM_ALIGNERS, ddup=qc_alignment_dedupers()),
        expand(MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/{sample}.{alnr}.{ddup}.mosdepth.global.dist.txt", sample=SSAMPS, alnr=QC_CRAM_ALIGNERS, ddup=qc_alignment_dedupers()),
        expand(MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/{sample}.{alnr}.{ddup}.mosdepth.region.dist.txt", sample=SSAMPS, alnr=QC_CRAM_ALIGNERS, ddup=qc_alignment_dedupers()),
    log:
        MDIR + "logs/produce_mosdepth.log"
    benchmark:
        "logs/benchmarks/produce_mosdepth.bench.tsv"
