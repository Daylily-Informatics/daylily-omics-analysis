import os
# ###### SAMTOOLS METIRCS
# ------------------------
# BAM Metrics From samtools
#

rule gen_samstats:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        stats=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/samtmetrics/{sample}.{alnr}.{ddup}.stats.tsv",
        flagstats=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/samtmetrics/{sample}.{alnr}.{ddup}.flagstat.tsv",
        idxstats=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/samtmetrics/{sample}.{alnr}.{ddup}.idxstat.tsv",
        sent=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/samtmetrics/{sample}.{alnr}.{ddup}.complete",
    threads: config["gen_samstats"]["threads"]
    conda:
        config["samtools_markdups"]["env_yaml"]
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.samt.bench.tsv"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/samtmetrics/logs/{sample}.{alnr}.{ddup}.samt.log"
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
        run_threads_a=config["gen_samstats"]["run_threadsa"],
        run_threads_b=config["gen_samstats"]["run_threadsb"],
    shell:
        "samtools stats -@  {params.run_threads_a} --reference {params.huref} {input.cram} > {output.stats} 2> {log};"
        "samtools flagstats -@  {params.run_threads_b} {input.cram} > {output.flagstats}  2> {log}.2;"
        "samtools idxstats -@  {params.run_threads_b} {input.cram} > {output.idxstats} 2> {log}.3;"
        "touch {log}.waitdone;"
        "touch {output.sent};"
        

localrules: produce_samtools_metrics

rule produce_samtools_metrics:  # TARGET : Produce samtools BAM metrics
    input:
        expand(MDIR + "{sample}/align/{alnr}/alignqc/samtmetrics/{sample}.{alnr}.complete",
            sample=SAMPS,
            alnr=CRAM_ALIGNERS
            )
    output:
        touch(MDIR + "other_reports/samtools_metrics_gather.done"),
