import os

##### bcbio-variation-recall ensemble
# -----------------------------------
# https://github.com/bcbio/bcbio.variation.recall

rule bcbio_variation_recall_ensemble:
    input:
        vcfs=lambda wildcards: expand(
            MDIR + "{sample}/align/{alnr}/snv/{caller}/{sample}.{alnr}.{caller}.snv.sort.vcf.gz",
            caller=config["bcbio_variation_recall"]["callers"],
            sample=wildcards.sample,
            alnr=wildcards.alnr,
        ),
        vcfs_tbi=lambda wildcards: expand(
            MDIR + "{sample}/align/{alnr}/snv/{caller}/{sample}.{alnr}.{caller}.snv.sort.vcf.gz.tbi",
            caller=config["bcbio_variation_recall"]["callers"],
            sample=wildcards.sample,
            alnr=wildcards.alnr,
        ),
        ref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    output:
        vcf=MDIR + "{sample}/align/{alnr}/snv/bcbio_ensemble/{sample}.{alnr}.bcbio_ensemble.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/snv/bcbio_ensemble/{sample}.{alnr}.bcbio_ensemble.vcf.gz.tbi",
    log:
        MDIR + "{sample}/align/{alnr}/snv/bcbio_ensemble/log/{sample}.{alnr}.bcbio_ensemble.log",
    threads: config["bcbio_variation_recall"]["threads"]
    conda:
        config["bcbio_variation_recall"]["env_yaml"]
    params:
        names=lambda wildcards: ",".join(config["bcbio_variation_recall"]["callers"]),
        numpass=config["bcbio_variation_recall"].get("numpass", 1),
    shell:
        """
        bcbio-variation-recall ensemble \
            --cores {threads} \
            --numpass {params.numpass} \
            --names {params.names} \
            --out {output.vcf} \
            --ref {input.ref} \
            {input.vcfs} >> {log} 2>&1;
        tabix -f -p vcf {output.vcf} >> {log} 2>&1;
        {latency_wait};
        ls {output.vcf};
        """


localrules:
    produce_bcbio_variation_recall,

rule produce_bcbio_variation_recall:
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/snv/bcbio_ensemble/{sample}.{alnr}.bcbio_ensemble.vcf.gz",
            sample=SSAMPS,
            alnr=ALIGNERS,
        )
