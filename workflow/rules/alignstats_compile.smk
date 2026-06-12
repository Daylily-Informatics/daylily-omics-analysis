import os

# This rule is actually gathering up all of the sub rules completed states
# so it can generate a final QC report, and that report will satisfy the input
# requirement of all to run



localrules:
    alignstats_gather,

rule alignstats_gather:
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/alignqc/alignstats/{sample}.{alnr}.{ddup}.alignstats.tsv",
            sample=SSAMPS,
            alnr=QC_CRAM_ALIGNERS,
            ddup=qc_alignment_dedupers(),
        ),
    output:
        f"{MDIR}other_reports/alignstats_summary_gather.done",
        bm=MDIR + "benchmarks/all.alignstats_summary.bench.tsv",
    benchmark:
        MDIR + "benchmarks/all.alignstats_summary.bench.tsv"
    threads: 1
    log:
        MDIR + "logs/alignstats_summary_gather.log",
    conda:
        config["alignstats"]["env_yaml"]
    shell:
        " touch {output[0]}; touch {output.bm}"



localrules:
    alignstats_compile,


rule alignstats_compile:
    input:
        f"{MDIR}other_reports/alignstats_summary_gather.done",
    output:
        temp(f"{MDIR}other_reports/alignstats_bsummary.tsv"),
        temp(f"{MDIR}other_reports/alignstats_csummary.tsv"),
        f"{MDIR}other_reports/alignstats_combo_mqc.tsv",
        f"{MDIR}other_reports/alignstats_gs_mqc.tsv",        
    benchmark:
        MDIR + "benchmarks/all.alignstats_smmary_compile.bench.tsv"
    threads: 2
    params:
        l="{",
        r="}",
        cluster_sample="na",
    log:
        MDIR + "logs/alignstats_summary_compile.log",
    shell:
        """
        set -euo pipefail
        python workflow/scripts/compile_alignstats.py \
          --mdir {MDIR:q} \
          --log {log:q} \
          --bsummary {output[0]:q} \
          --csummary {output[1]:q} \
          --combo {output[2]:q} \
          --generalstats {output[3]:q}
        """


localrules:
    produce_alignstats,


rule produce_alignstats:  # TARGET - only takes path to produce alignstats
    input:
        f"{MDIR}other_reports/alignstats_bsummary.tsv",
    output:
        done=f"{MDIR}logs/produce_alignstats.done",
    log:
        MDIR + "logs/produce_alignstats.log"
    benchmark:
        "logs/benchmarks/produce_alignstats.bench.tsv"
    shell:
        "touch {log}; touch {output.done}"
