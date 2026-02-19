
#############################################
# hyb_ensemble_multi_platform.smk
#
# Multi-platform (ILMN + ONT), multi-caller
# VCF-level ensemble with provenance tags.
#
# Supports modes:
#   A = maximize F1 (conservative ONT rescue)
#   D = sensitivity-focused ONT rescue
#
# Requires config block:
#
# hyb_ensemble:
#   ref_fa: /path/to/hg38.fa
#   mode: "A"
#   pad_bp: 50
#   platforms:
#     ILMN:
#       callers:
#         DV:   "path/to/ilmn_dv.vcf.gz"
#         SENT: "path/to/ilmn_sent.vcf.gz"
#     ONT:
#       callers:
#         DV:   "path/to/ont_dv.vcf.gz"
#         SENT: "path/to/ont_sent.vcf.gz"
#   thresholds:
#     A:
#       ont_qual_min_snv: 60
#       ont_qual_min_indel: 80
#       allow_ont_snv: false
#     D:
#       ont_qual_min_snv: 30
#       ont_qual_min_indel: 50
#       allow_ont_snv: true
#
#############################################

import os

cfg = config["hyb_ensemble"]
ref = cfg["ref_fa"]
mode = cfg["mode"]
pad_bp = cfg["pad_bp"]
thresholds = cfg["thresholds"][mode]
platforms = cfg["platforms"]


#############################################
# Helper functions
#############################################

def get_all_vcfs(wildcards):
    vcfs = []
    for platform in platforms:
        for caller in platforms[platform]["callers"]:
            path_template = platforms[platform]["callers"][caller]
            vcfs.append(path_template.format(sample=wildcards.sample))
    return vcfs


#############################################
# Normalize all input VCFs
#############################################

rule hyb_norm_all:
    input:
        get_all_vcfs
    output:
        directory("results/day/hg38/{sample}/hyb/norm")
    conda:
        "../envs/bcftools_v0.1.yaml"
    shell:
        r"""
        mkdir -p {output}
        for v in {input}; do
            base=$(basename $v .vcf.gz)
            bcftools norm -f {ref} -m -any $v -Oz -o {output}/$base.norm.vcf.gz
            bcftools index -f {output}/$base.norm.vcf.gz
        done
        """


#############################################
# Platform consensus (>=2 callers per platform)
#############################################

rule hyb_platform_consensus:
    input:
        norm_dir = "results/day/hg38/{sample}/hyb/norm"
    output:
        ilmn = "results/day/hg38/{sample}/hyb/consensus/ILMN.vcf.gz",
        ont  = "results/day/hg38/{sample}/hyb/consensus/ONT.vcf.gz"
    conda:
        "../envs/bcftools_v0.1.yaml"
    shell:
        r"""
        mkdir -p results/day/hg38/{wildcards.sample}/hyb/consensus

        # ILMN consensus
        bcftools isec -n=2 -w1 \
          {input.norm_dir}/*ILMN*norm.vcf.gz \
          -Oz -o {output.ilmn}
        bcftools index -f {output.ilmn}

        # ONT consensus
        bcftools isec -n=2 -w1 \
          {input.norm_dir}/*ONT*norm.vcf.gz \
          -Oz -o {output.ont}
        bcftools index -f {output.ont}
        """


#############################################
# Define rescue regions (discordant between platforms)
#############################################

rule hyb_rescue_regions:
    input:
        ilmn = "results/day/hg38/{sample}/hyb/consensus/ILMN.vcf.gz",
        ont  = "results/day/hg38/{sample}/hyb/consensus/ONT.vcf.gz"
    output:
        bed = "results/day/hg38/{sample}/hyb/rescue_regions.bed"
    conda:
        "../envs/bcftools_v0.1.yaml"
    shell:
        r"""
        bcftools isec -n=1 -w1 {input.ilmn} {input.ont} -Oz -o tmp.private.vcf.gz
        bcftools query -f '%CHROM\t%POS0\t%END\n' tmp.private.vcf.gz \
          | bedtools slop -b {pad_bp} -g <(samtools faidx {ref} | cut -f1,2) \
          > {output.bed}
        """


#############################################
# Ensemble merge (ILMN backbone + ONT rescue)
#############################################

rule hyb_ensemble_core:
    input:
        ilmn = "results/day/hg38/{sample}/hyb/consensus/ILMN.vcf.gz",
        ont  = "results/day/hg38/{sample}/hyb/consensus/ONT.vcf.gz",
        rescue = "results/day/hg38/{sample}/hyb/rescue_regions.bed"
    output:
        core = "results/day/hg38/{sample}/hyb/ensemble/{sample}.ensemble.{mode}.core.vcf.gz"
    conda:
        "../envs/bcftools_v0.1.yaml"
    shell:
        r"""
        mkdir -p results/day/hg38/{wildcards.sample}/hyb/ensemble

        # Shared calls
        bcftools isec -n=2 -w1 {input.ilmn} {input.ont} -Oz -o shared.vcf.gz

        # ONT rescue
        if [ "{mode}" = "A" ]; then
            bcftools view -R {input.rescue} {input.ont} \
              | bcftools filter -i 'TYPE="indel" && QUAL>{thresholds[ont_qual_min_indel]}' \
              -Oz -o ont_rescue.vcf.gz
        else
            bcftools view -R {input.rescue} {input.ont} \
              | bcftools filter -i '(TYPE="indel" && QUAL>{thresholds[ont_qual_min_indel]}) || (TYPE="snp" && QUAL>{thresholds[ont_qual_min_snv]})' \
              -Oz -o ont_rescue.vcf.gz
        fi

        bcftools concat -a shared.vcf.gz ont_rescue.vcf.gz \
          -Oz -o {output.core}
        bcftools index -f {output.core}
        """


#############################################
# Add provenance INFO fields
#############################################

rule hyb_add_provenance:
    input:
        core = rules.hyb_ensemble_core.output.core
    output:
        final = "results/day/hg38/{sample}/hyb/ensemble/{sample}.ensemble.{mode}.prov.vcf.gz"
    conda:
        "../envs/bcftools_v0.1.yaml"
    shell:
        r"""
        bcftools annotate \
          -h <(cat <<EOF
##INFO=<ID=PLATFORM_SUPPORT,Number=.,Type=String,Description="Platforms supporting this variant">
##INFO=<ID=CALLER_SUPPORT,Number=.,Type=String,Description="Platform:Caller pairs supporting this variant">
##INFO=<ID=ENSEMBLE_DECISION,Number=1,Type=String,Description="Decision class">
EOF
          ) \
          {input.core} \
          -Oz -o {output.final}

        bcftools index -f {output.final}
        """
