import os

##### facets-suite somatic variant caller
# ---------------------------

rule facets_suite:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_cram=get_somcall_tumor_cram,
        tumor_crai=get_somcall_tumor_crai,
        normal_cram=get_somcall_normal_cram,
        normal_crai=get_somcall_normal_crai,
        ref_fa=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ref_fai=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        cncf=MDIR + "{sample}/align/{alnr}/snv/facets/{sample}.{alnr}.facets.cncf.txt",
        seg=MDIR + "{sample}/align/{alnr}/snv/facets/{sample}.{alnr}.facets.seg",
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/facets/{sample}.{alnr}.facets.vcf.gz",
        vcftbi=MDIR + "{sample}/align/{alnr}/snv/facets/{sample}.{alnr}.facets.vcf.gz.tbi",
    log:
        MDIR + "{sample}/align/{alnr}/snv/facets/log/{sample}.{alnr}.facets.log",
    threads: config['facets']['threads']
    container:
        config['facets']['container']
    resources:
        vcpu=config['facets']['threads'],
        threads=config['facets']['threads'],
        partition=config['facets']['partition'],
        mem_mb=config['facets']['mem_mb'],
    params:
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output.cncf})"

        run_facets_wrapper.R \
            --tumor {input.tumor_cram} \
            --normal {input.normal_cram} \
            --reference {input.ref_fa} \
            --outdir $(dirname {output.cncf}) \
            --name {wildcards.sample}.{wildcards.alnr} \
            --vcf {output.vcfgz} \
            --cncf {output.cncf} \
            --seg {output.seg} >> {log} 2>&1

        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1
        """


rule produce_facets_suite_vcf:  # Target rule to gather facets outputs
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcftb=expand(
            MDIR + "{sample}/align/{alnr}/snv/facets/{sample}.{alnr}.facets.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        vcftbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/facets/{sample}.{alnr}.facets.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
    output:
        "gatheredall.facets",
    threads: 1
    log:
        "gatheredall.facets.log",
    params:
        cluster_sample=ret_sample,
    shell:
        "touch {output}"
