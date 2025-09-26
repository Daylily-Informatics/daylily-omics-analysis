######### CONTAMINATION SCREEN
# ----------------------------
# This is a population agnostic contamination screening tool that can
# operate on single sample or multi sample BAM files.
# github: http://griffan.github.io/VerifyBamID/
# paper: https://doi.org/10.1101/gr.246934.118
#   2020. “Ancestry-agnostic estimation of DNA sample
#   contamination from sequence reads.” Genome Research.


rule verifybamid2_contam:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        vb_prefix=MDIR + "{sample}/align/{alnr}/alignqc/contam/vb2/{sample}.{alnr}.vb2",
        vb_tsv=MDIR + "{sample}/align/{alnr}/alignqc/contam/vb2/{sample}.{alnr}.vb2.tsv",
        contam=MDIR + "{sample}/align/{alnr}/alignqc/contam/vb2/{sample}.{alnr}.contam.tsv",
        selfSM=MDIR + "{sample}/align/{alnr}/alignqc/contam/vb2/{sample}.{alnr}.vb2.selfSM",
        mqc=MDIR + "{sample}/align/{alnr}/alignqc/contam/vb2/{sample}.{alnr}.vb2_mqc.tsv",
    log:
        MDIR + "{sample}/align/{alnr}/alignqc/contam/vb2/logs/{sample}.{alnr}.vb2.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.vb2.bench.tsv"
    conda:
        config["verifybamid2_contam"]["env_yaml"]
    threads: config["verifybamid2_contam"]["threads"]
    resources:
        vcpu=config["verifybamid2_contam"]["threads"],
        partition=config["verifybamid2_contam"]["partition"],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        db_prefix=config["supporting_files"]["files"]["verifybam2"]["dat_files"]["name"],
        site_vcf=config["supporting_files"]["files"]["verifybam2"]["oneM_snps_vcf"]["name"],
    shell:
        r"""
        set -euo pipefail

        outdir=$(dirname {output.vb_tsv})
        mkdir -p "${{outdir}}" "${{outdir}}/logs"

        rm -f {output.vb_prefix}.selfSM {output.vb_prefix}.selfRG {output.vb_prefix}.depthSM \
            {output.vb_tsv} {output.selfSM} {output.mqc} {output.contam}

        verifybamid2 \
            --WithinAncestry \
            --BamFile {input.cram} \
            --Output {output.vb_prefix} \
            --DisableSanityCheck \
            --SiteVCF {params.site_vcf} \
            --SVDPrefix {params.db_prefix} \
            --NumThread {threads} \
            --Reference {params.huref} \
            > {log} 2>&1

        cp {output.selfSM} {output.vb_tsv}
        cp {output.selfSM} {output.mqc}
        touch {output.vb_prefix}

        awk 'NR<=2 {{print}}' {output.selfSM} > {output.contam}
        """

localrules:
    produce_contam_estimate,

rule produce_contam_estimate:  # TARGET:  jusg gen contam
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/alignqc/contam/vb2/{sample}.{alnr}.vb2.tsv",
            sample=SSAMPS,
            alnr=ALL_ALIGNERS,
        ),
