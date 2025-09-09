import os

##### neusomatic
# ---------------------------


def get_neusom_ensemble_callers(wildcards):
    vcfs = []
    base = MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/snv"
    mapping = {
        "mutect2": f"{base}/mutect2/{wildcards.sample}.{wildcards.alnr}.mutect2.vcf",
        "strelka2": f"{base}/strelka2/{wildcards.sample}.{wildcards.alnr}.strelka2.vcf",
        "vardict": f"{base}/vardict/{wildcards.sample}.{wildcards.alnr}.vardict.vcf",
        "varscan2": f"{base}/varscan2/{wildcards.sample}.{wildcards.alnr}.varscan2.vcf",
    }
    for caller in ["mutect2", "strelka2", "vardict", "varscan2"]:
        if caller in somatic_snv_CALLERS:
            vcfs.append(mapping[caller])
    return vcfs


rule neusomatic:
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
        vcf=MDIR + "{sample}/align/{alnr}/snv/neusomatic/{sample}.{alnr}.neusomatic.snv.vcf",
    log:
        MDIR + "{sample}/align/{alnr}/snv/neusomatic/log/{sample}.{alnr}.neusomatic.snv.log",
    threads: config['neusomatic']['threads']
    container:
        config['neusomatic']['container']
    resources:
        vcpu=config['neusomatic']['threads'],
        threads=config['neusomatic']['threads'],
        partition=config['neusomatic']['partition'],
        mem_mb=config['neusomatic']['mem_mb'],
    params:
        cluster_sample=ret_sample,
        numa=config['neusomatic']['numa'],
    shell:
        r"""
        set -euo pipefail
        {params.numa} neusomatic.py call \
            --output {output.vcf} \
            --tumor {input.tumor_cram} \
            --normal {input.normal_cram} \
            --ref {input.ref_fa} \
            --threads {threads} >> {log} 2>&1
        """


rule neusomatic_ensemble:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_cram=get_somcall_tumor_cram,
        tumor_crai=get_somcall_tumor_crai,
        normal_cram=get_somcall_normal_cram,
        normal_crai=get_somcall_normal_crai,
        ref_fa=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ref_fai=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
        callers=get_neusom_ensemble_callers,
    output:
        vcf=MDIR + "{sample}/align/{alnr}/snv/neusomatic/{sample}.{alnr}.neusomatic_ensemble.snv.vcf",
    log:
        MDIR + "{sample}/align/{alnr}/snv/neusomatic/log/{sample}.{alnr}.neusomatic_ensemble.snv.log",
    threads: config['neusomatic']['threads']
    container:
        config['neusomatic']['container']
    resources:
        vcpu=config['neusomatic']['threads'],
        threads=config['neusomatic']['threads'],
        partition=config['neusomatic']['partition'],
        mem_mb=config['neusomatic']['mem_mb'],
    params:
        cluster_sample=ret_sample,
        numa=config['neusomatic']['numa'],
        caller_vcfs=lambda wildcards: " ".join(get_neusom_ensemble_callers(wildcards)),
    shell:
        r"""
        set -euo pipefail
        {params.numa} neusomatic.py ensemble \
            --output {output.vcf} \
            --tumor {input.tumor_cram} \
            --normal {input.normal_cram} \
            --ref {input.ref_fa} \
            --callers {params.caller_vcfs} \
            --threads {threads} >> {log} 2>&1
        """
