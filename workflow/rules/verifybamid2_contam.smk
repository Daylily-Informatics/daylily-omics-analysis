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
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
        svd_ud=lambda wildcards: verifybamid2_panel_svd_prefix(wildcards) + ".UD",
        svd_v=lambda wildcards: verifybamid2_panel_svd_prefix(wildcards) + ".V",
        svd_mu=lambda wildcards: verifybamid2_panel_svd_prefix(wildcards) + ".mu",
        svd_bed=lambda wildcards: verifybamid2_panel_svd_prefix(wildcards) + ".bed",
    output:
        vb_prefix=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/vb2/{vb2panel}/{sample}.{alnr}.{ddup}.{vb2panel}.vb2",
        vb_tsv=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/vb2/{vb2panel}/{sample}.{alnr}.{ddup}.{vb2panel}.vb2.tsv",
        contam=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/vb2/{vb2panel}/{sample}.{alnr}.{ddup}.{vb2panel}.contam.tsv",
        selfSM=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/vb2/{vb2panel}/{sample}.{alnr}.{ddup}.{vb2panel}.vb2.selfSM",
        mqc=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/vb2/{vb2panel}/{sample}.{alnr}.{ddup}.{vb2panel}.vb2_mqc.tsv",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/vb2/{vb2panel}/logs/{sample}.{alnr}.{ddup}.{vb2panel}.vb2.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{vb2panel}.vb2.bench.tsv"
    conda:
        config["verifybamid2_contam"]["env_yaml"]
    threads: verifybamid2_panel_threads
    resources:
        vcpu=verifybamid2_panel_threads,
        mem_mb=verifybamid2_panel_mem_mb,
        partition=verifybamid2_panel_partition,
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        db_prefix=verifybamid2_panel_svd_prefix,
        panel_label=verifybamid2_panel_label,
        snp_count=verifybamid2_panel_snp_count,
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail

        outdir=$(dirname {output.vb_tsv})
        mkdir -p "${{outdir}}" "${{outdir}}/logs"

        rm -f {output.vb_prefix}.selfSM {output.vb_prefix}.selfRG {output.vb_prefix}.depthSM \
            {output.vb_tsv} {output.selfSM} {output.mqc} {output.contam}

        printf 'VerifyBamID2 panel\t%s\t%s SNPs\n' "{params.panel_label}" "{params.snp_count}" > {log}

        verifybamid2 \
            --BamFile {input.cram} \
            --Output {output.vb_prefix} \
            --DisableSanityCheck \
            --SVDPrefix {params.db_prefix} \
            --NumThread {threads} \
            --Reference {params.huref} \
            --min-BQ 20 --min-MQ 20 --adjust-MQ 50 --max-depth 500 \
            >> {log} 2>&1

        cp {output.selfSM} {output.vb_tsv}
        cp {output.selfSM} {output.mqc}
        touch {output.vb_prefix}

        awk 'NR<=2 {{print}}' {output.selfSM} > {output.contam}
        """

localrules:
    produce_contam_estimate,
    produce_verifybamid2_panel_comparison,

rule produce_contam_estimate:  # TARGET:  jusg gen contam
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/vb2/{vb2panel}/{sample}.{alnr}.{ddup}.{vb2panel}.vb2.tsv",
            sample=SSAMPS,
            alnr=QC_CRAM_ALIGNERS,
            ddup=qc_alignment_dedupers(),
            vb2panel=VERIFYBAMID2_PANELS,
        ),


rule produce_verifybamid2_panel_comparison:  # TARGET: compare selected VerifyBamID2 SNP panels
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/vb2/{vb2panel}/{sample}.{alnr}.{ddup}.{vb2panel}.vb2.tsv",
            sample=SSAMPS,
            alnr=QC_CRAM_ALIGNERS,
            ddup=qc_alignment_dedupers(),
            vb2panel=VERIFYBAMID2_PANELS,
        ),
        MDIR + "other_reports/verifybamid2_panel_comparison_mqc.tsv",
