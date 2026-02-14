# #### Terminal Rule to end processing at generating DDUPED BAMS



localrules:
    produce_deduplicated_crams,


rule produce_deduplicated_crams:  # TARGET : Generate Just BAMs with Dups Marked .
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
