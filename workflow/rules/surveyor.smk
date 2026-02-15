"""Rules for running the SurVeyor structural variant caller."""

config.setdefault("surveyor", {})
config["surveyor"].setdefault("threads", 4)
config["surveyor"].setdefault("partition", "i8")
config["surveyor"].setdefault("env_yaml", "../envs/surveyor_v0.1.yaml")
config["surveyor"].setdefault("extra_args", "")
config["surveyor"].setdefault("ld_preload", "  ")

config.setdefault("surveyor_sort_index", {})
config["surveyor_sort_index"].setdefault("threads", 2)
config["surveyor_sort_index"].setdefault("partition", "i8")


rule surveyor:
    """https://github.com/Mesh89/SurVeyor"""
    input:
        bam=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.mrkdup.sort.bam",
        bai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.mrkdup.sort.bam.bai",
        reference=lambda wildcards: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/sv/surveyor/{sample}.{alnr}.surveyor.sv.vcf",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/sv/surveyor/logs/{sample}.{alnr}.surveyor.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.surveyor.sv.vcf.bench.tsv",
    threads: config["surveyor"]["threads"]
    resources:
        vcpu=config["surveyor"]["threads"],
        partition=config["surveyor"]["partition"],
        threads=config["surveyor"]["threads"],
    params:
        extra=config["surveyor"].get("extra_args", ""),
        cluster_sample=ret_sample_alnr,
    conda:
        config["surveyor"]["env_yaml"]
    shell:
        """
        set +euo pipefail;
        mkdir -p $(dirname {output.vcf}) $(dirname {log});
        rm -f {output.vcf};
        surveyor call \
            --bam {input.bam} \
            --reference {input.reference} \
            --threads {threads} \
            --output {output.vcf} \
            {params.extra} >> {log} 2>&1;
        ls {output.vcf};
        """


rule surveyor_sort_index:
    input:
        MDIR + "{sample}/align/{alnr}/{ddup}/sv/surveyor/{sample}.{alnr}.surveyor.sv.vcf",
    output:
        sortvcf=MDIR + "{sample}/align/{alnr}/{ddup}/sv/surveyor/{sample}.{alnr}.surveyor.sv.sort.vcf",
        sortgz=MDIR + "{sample}/align/{alnr}/{ddup}/sv/surveyor/{sample}.{alnr}.surveyor.sv.sort.vcf.gz",
        sorttbi=MDIR + "{sample}/align/{alnr}/{ddup}/sv/surveyor/{sample}.{alnr}.surveyor.sv.sort.vcf.gz.tbi",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/sv/surveyor/logs/{sample}.{alnr}.surveyor.sv.sort.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.surveyor.sv.sort.bench.tsv",
    threads: config["surveyor_sort_index"]["threads"]
    resources:
        vcpu=config["surveyor_sort_index"]["threads"],
        partition=config["surveyor_sort_index"]["partition"],
        threads=config["surveyor_sort_index"]["threads"],
    conda:
        "../envs/vanilla_v0.1.yaml"
    params:
        cluster_sample=ret_sample,
    shell:
        """
        set +euo pipefail;
        (bedtools sort -header -i {input} > {output.sortvcf};
        bgzip -f -@ {threads} {output.sortvcf};
        touch {output.sortvcf};
        tabix -p vcf -f {output.sortgz};
        ls {output.sortgz} {output.sorttbi};) > {log} 2>&1;
        """


localrules: produce_surveyor,


rule produce_surveyor:  # TARGET : Produce SurVeyor SV VCFs
    """Ensure all SurVeyor VCFs are generated."""
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/sv/surveyor/{sample}.{alnr}.surveyor.sv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS,
            ddup=DDUP,
        )
