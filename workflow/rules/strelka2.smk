import sys
import os

##### strelka2
# ---------------------------

rule strelka2_germline:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
        ref_fa=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.germline.vcf.gz",
        vcftbi=MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.germline.vcf.gz.tbi",
    log:
        MDIR + "{sample}/align/{alnr}/snv/strelka2/log/{sample}.{alnr}.strelka2.germline.log",
    threads: config['strelka2']['threads']
    container:
        config['strelka2']['container']
    resources:
        vcpu=config['strelka2']['threads'],
        threads=config['strelka2']['threads'],
        partition=config['strelka2']['partition'],
        mem_mb=config['strelka2']['mem_mb'],
    params:
        run_dir=MDIR + "{sample}/align/{alnr}/snv/strelka2/work/{sample}.germline",
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail
        mkdir -p {params.run_dir}
        configureStrelkaGermlineWorkflow.py \
            --bam {input.cram} \
            --referenceFasta {input.ref_fa} \
            --runDir {params.run_dir} >> {log} 2>&1
        {params.run_dir}/runWorkflow.py -m local -j {threads} >> {log} 2>&1
        cp {params.run_dir}/results/variants/variants.vcf.gz {output.vcfgz}
        cp {params.run_dir}/results/variants/variants.vcf.gz.tbi {output.vcftbi}
        """


rule strelka2_somatic:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_cram=get_somcall_tumor_cram,
        tumor_crai=get_somcall_tumor_crai,
        normal_cram=get_somcall_normal_cram,
        normal_crai=get_somcall_normal_crai,
        ref_fa=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    output:
        snv=MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.snvs.vcf.gz",
        snvtbi=MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.snvs.vcf.gz.tbi",
        indel=MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.indels.vcf.gz",
        indeltbi=MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.indels.vcf.gz.tbi",
    log:
        MDIR + "{sample}/align/{alnr}/snv/strelka2/log/{sample}.{alnr}.strelka2.somatic.log",
    threads: config['strelka2']['threads']
    container:
        config['strelka2']['container']
    resources:
        vcpu=config['strelka2']['threads'],
        threads=config['strelka2']['threads'],
        partition=config['strelka2']['partition'],
        mem_mb=config['strelka2']['mem_mb'],
    params:
        run_dir=MDIR + "{sample}/align/{alnr}/snv/strelka2/work/{sample}.somatic",
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail
        mkdir -p {params.run_dir}
        configureStrelkaSomaticWorkflow.py \
            --tumorBam {input.tumor_cram} \
            --normalBam {input.normal_cram} \
            --referenceFasta {input.ref_fa} \
            --runDir {params.run_dir} >> {log} 2>&1
        {params.run_dir}/runWorkflow.py -m local -j {threads} >> {log} 2>&1
        cp {params.run_dir}/results/variants/somatic.snvs.vcf.gz {output.snv}
        cp {params.run_dir}/results/variants/somatic.snvs.vcf.gz.tbi {output.snvtbi}
        cp {params.run_dir}/results/variants/somatic.indels.vcf.gz {output.indel}
        cp {params.run_dir}/results/variants/somatic.indels.vcf.gz.tbi {output.indeltbi}
        """


rule produce_strelka2_germline_vcf:
    input:
        vcftb=expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.germline.vcf.gz",
            sample=SSAMPS,
            alnr=ALIGNERS,
        ),
        vcftbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.germline.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS,
        ),
    output:
        "gatheredall.strelka2.germline",
    threads: 4
    log:
        "gatheredall.strelka2.germline.log",
    params:
        cluster_sample=ret_sample,
    resources:
        vcpu=4,
        threads=4,
        partition=config['strelka2']['partition'],
        mem_mb=config['strelka2']['mem_mb'],


rule produce_strelka2_somatic_vcf:
    input:
        snv=expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.snvs.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        snvtbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.snvs.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        indel=expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.indels.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        indeltbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.indels.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
    output:
        "gatheredall.strelka2.somatic",
    threads: 4
    log:
        "gatheredall.strelka2.somatic.log",
    params:
        cluster_sample=ret_sample,
    resources:
        vcpu=4,
        threads=4,
        partition=config['strelka2']['partition'],
        mem_mb=config['strelka2']['mem_mb'],
