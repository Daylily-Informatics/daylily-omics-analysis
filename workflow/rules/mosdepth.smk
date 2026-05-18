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
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.mosdepth.bench.tsv"
    log:
        a=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/{sample}.{alnr}.{ddup}.mosdepth.log",
        b=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/{sample}.{alnr}.{ddup}",
    conda:
        config["mosdepth"]["env_yaml"]
    params:
        win_size=1000,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        core_bed=config["supporting_files"]["files"]["huref"]["fasta"]["bed"],
        mapq=0,
        T="0,10,20,30"
        if "depth_bins" not in config["mosdepth"]
        else config["mosdepth"]["depth_bins"],
        cluster_sample=ret_sample,
    shell:
        "(rm -rf {log.b}* || echo rmlogFailedMosDepth );"
        "mosdepth --threads {threads} --by {params.core_bed} --use-median  -n --fast-mode --mapq {params.mapq} -f {params.huref} -T {params.T} {log.b} {input.cram} > {log.a} 2>&1; "
        "(rm  {log.b}*per-base* || echo 'rm perbase failed' >> {log.a} 2>&1);"
        "ls {output.summary};"

localrules:
    produce_mosdepth,

rule produce_mosdepth:  # TARGET:  jusg gen mosdepth
    input:
        expand(MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/{sample}.{alnr}.{ddup}.mosdepth.summary.txt", sample=SSAMPS, alnr=CRAM_ALIGNERS, ddup=DDUP),
