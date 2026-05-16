# #### Terminal Rules for generating deduplicated (or passthrough) CRAMs



localrules:
    produce_deduplicated_crams,
    dedup_doppelmark,
    dedup_sentieon,
    dedup_none,


rule produce_deduplicated_crams:  # TARGET : Generate CRAMs with all configured dedupers
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
            sample=SSAMPS,
            alnr=ALIGNERS,
            ddup=DDUP,
        ),
    output:
        expand(MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.ddupgen.complete",sample=SAMPS, alnr=ALIGNERS, ddup=DDUP)
    threads: 1
    shell:
        "touch {output};"


rule dedup_doppelmark:  # DEPRECATED TARGET: use produce_dmd_dedup_cram
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/dmd/{sample}.{alnr}.dmd.cram",
            sample=SSAMPS,
            alnr=ALIGNERS,
        ),
    output:
        expand(MDIR + "{sample}/align/{alnr}/dmd/{sample}.{alnr}.dmd.ddupgen.complete", sample=SAMPS, alnr=ALIGNERS)
    threads: 1
    shell:
        "touch {output};"


rule dedup_sentieon:  # DEPRECATED TARGET: use produce_smd_dedup_cram
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/smd/{sample}.{alnr}.smd.cram",
            sample=SSAMPS,
            alnr=ALIGNERS,
        ),
    output:
        expand(MDIR + "{sample}/align/{alnr}/smd/{sample}.{alnr}.smd.ddupgen.complete", sample=SAMPS, alnr=ALIGNERS)
    threads: 1
    shell:
        "touch {output};"


rule dedup_none:  # DEPRECATED TARGET: use produce_na_dedup_cram
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/na/{sample}.{alnr}.na.cram",
            sample=SSAMPS,
            alnr=ALIGNERS,
        ),
    output:
        expand(MDIR + "{sample}/align/{alnr}/na/{sample}.{alnr}.na.ddupgen.complete", sample=SAMPS, alnr=ALIGNERS)
    threads: 1
    shell:
        "touch {output};"
