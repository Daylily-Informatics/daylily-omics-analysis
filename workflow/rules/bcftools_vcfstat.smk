######### BCFTOOLS stats
# ----------------------------
# This is a population agnostic contamination screening tool that can
# operate on single sample or multi sample BAM files.
# github: https://github.com/samtools/bcftools
# paper: http://samtools.github.io/bcftools/howtos/publications.html
# docs: https://samtools.github.io/bcftools/bcftools.html


rule bcftools_vcfstat:
    input:
        snv_vcf=(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/{sample}.{alnr}.{ddup}.{snv_caller}.snv.sort.vcf.gz"
        ),
        snv_vcf_tbi=(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/{sample}.{alnr}.{ddup}.{snv_caller}.snv.sort.vcf.gz.tbi"
        ),
    output:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/bcfstats/{sample}.{alnr}.{ddup}.{snv_caller}.bcfstats.tsv",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/bcfstats/logs/{sample}.{alnr}.{ddup}.{snv_caller}.bcfstats.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv_caller}.bcfstat.bench.tsv",
    conda:
        config["vanilla"]["env_yaml"]
    threads: config["bcftools_vcfstat"]["threads"]
    params:
        cluster_sample=ret_sample,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    shell:
        """
        bcftools stats --threads {threads} {input.snv_vcf} -F {params.huref} > {output};
        ls {output};
        """


localrules:
    produce_bcfvcfstats,

rule produce_bcfvcfstats:  # TARGET:  jusg genvcfstats
    input:
        [
            MDIR
            + f"{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/bcfstats/{sample}.{alnr}.{ddup}.{snv_caller}.bcfstats.tsv"
            for sample in SSAMPS
            for ddup in DDUP
            for alnr, snv_caller in valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)
        ],
