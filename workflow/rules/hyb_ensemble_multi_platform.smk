
#############################################
# hyb_ensemble_multi_platform.smk
#
# Multi-platform (ILMN + ONT), multi-caller
# VCF-level ensemble with provenance tags.
#
# Integrates with daylily concordance workflow:
# - Reads VCF paths from units.tsv (SR_VCF_PATH, LR_VCF_PATH columns)
# - Outputs to standard path: results/day/{genome_build}/{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/
# - Compatible with produce_snv_concordances target
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
# Units.tsv columns (optional):
#   SR_VCF_PATH: Path to short-read VCF (ILMN/Ultima)
#   LR_VCF_PATH: Path to long-read VCF (ONT/PacBio)
#
#############################################

import os
import sys

# Aligner constraint for ensemble workflow
# Ensemble outputs are associated with the long-read aligner
ALIGNERS_ENSEMBLE = ["ont", "pb"]

# Get config or use defaults
cfg = config.get("hyb_ensemble", {})
mode = cfg.get("mode", "A")
pad_bp = cfg.get("pad_bp", 50)
thresholds = cfg.get("thresholds", {
    "A": {"ont_qual_min_snv": 60, "ont_qual_min_indel": 80, "allow_ont_snv": False},
    "D": {"ont_qual_min_snv": 30, "ont_qual_min_indel": 50, "allow_ont_snv": True}
})[mode]


#############################################
# Helper functions
#############################################

def get_sr_vcf(wildcards):
    """Get short-read VCF path from SR_VCF_PATH column (same pattern as getR1sS/getR2sS)."""
    row = samples[samples["analysis_unit_uid"] == wildcards.sample]
    if row.empty:
        raise WorkflowError(f"No units found for sample {wildcards.sample}")

    sr_vcf = str(row.iloc[0].get("SR_VCF_PATH", ""))
    if not sr_vcf or sr_vcf in ["", "na", "NA", "None"]:
        raise WorkflowError(f"SR_VCF_PATH not set for sample {wildcards.sample}")

    return sr_vcf


def get_lr_vcf(wildcards):
    """Get long-read VCF path from LR_VCF_PATH column (same pattern as getR1sS/getR2sS)."""
    row = samples[samples["analysis_unit_uid"] == wildcards.sample]
    if row.empty:
        raise WorkflowError(f"No units found for sample {wildcards.sample}")

    lr_vcf = str(row.iloc[0].get("LR_VCF_PATH", ""))
    if not lr_vcf or lr_vcf in ["", "na", "NA", "None"]:
        raise WorkflowError(f"LR_VCF_PATH not set for sample {wildcards.sample}")

    return lr_vcf


#############################################
# Normalize input VCFs
#############################################

rule hyb_norm_vcfs:
    input:
        sr_vcf = get_sr_vcf,
        lr_vcf = get_lr_vcf
    output:
        sr_norm = MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/tmp/sr.norm.vcf.gz",
        sr_norm_tbi = MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/tmp/sr.norm.vcf.gz.tbi",
        lr_norm = MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/tmp/lr.norm.vcf.gz",
        lr_norm_tbi = MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/tmp/lr.norm.vcf.gz.tbi"
    wildcard_constraints:
        alnr="|".join(ALIGNERS_ENSEMBLE)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/log/{sample}.{alnr}.{ddup}.norm.log"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.ensemble.norm.bench.tsv"
    threads: 2
    resources:
        vcpu=2,
        threads=2,
        partition="i384nvme,i192nvme,i192,i128"
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample
    conda:
        "../envs/bcftools_v0.1.yaml"
    shell:
        r"""
        mkdir -p $(dirname {output.sr_norm})

        # Normalize short-read VCF
        bcftools norm -f {params.huref} -m -any {input.sr_vcf} \
          -Oz -o {output.sr_norm} >> {log} 2>&1
        bcftools index -f -t {output.sr_norm} >> {log} 2>&1

        # Normalize long-read VCF
        bcftools norm -f {params.huref} -m -any {input.lr_vcf} \
          -Oz -o {output.lr_norm} >> {log} 2>&1
        bcftools index -f -t {output.lr_norm} >> {log} 2>&1
        """


#############################################
# Define rescue regions (discordant between platforms)
#############################################

rule hyb_rescue_regions:
    input:
        sr_vcf = MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/tmp/sr.norm.vcf.gz",
        lr_vcf = MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/tmp/lr.norm.vcf.gz"
    output:
        bed = MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/tmp/rescue_regions.bed"
    wildcard_constraints:
        alnr="|".join(ALIGNERS_ENSEMBLE)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/log/{sample}.{alnr}.{ddup}.rescue.log"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.ensemble.rescue.bench.tsv"
    threads: 2
    resources:
        vcpu=2,
        threads=2,
        partition="i384nvme,i192nvme,i192,i128"
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        pad_bp=pad_bp,
        cluster_sample=ret_sample
    conda:
        "../envs/bcftools_v0.1.yaml"
    shell:
        r"""
        # Remove any stale .csi indexes so bcftools uses the .tbi we create
        rm -f {input.sr_vcf}.csi {input.lr_vcf}.csi

        # Find variants private to short-read platform
        bcftools isec -n=1 -w1 {input.sr_vcf} {input.lr_vcf} \
          -Oz -o {output.bed}.tmp.vcf.gz >> {log} 2>&1

        # Convert to BED with padding
        bcftools query -f '%CHROM\t%POS0\t%END\n' {output.bed}.tmp.vcf.gz \
          | bedtools slop -b {params.pad_bp} \
            -g <(cut -f1,2 {params.huref}.fai) \
          > {output.bed} 2>> {log}

        rm -f {output.bed}.tmp.vcf.gz
        """


#############################################
# Ensemble merge (SR backbone + LR rescue)
#############################################

rule hyb_ensemble_merge:
    input:
        sr_vcf = MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/tmp/sr.norm.vcf.gz",
        lr_vcf = MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/tmp/lr.norm.vcf.gz",
        rescue_bed = MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/tmp/rescue_regions.bed"
    output:
        vcf = temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/{sample}.{alnr}.{ddup}.ensemble.snv.vcf.gz"),
        tbi = temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/{sample}.{alnr}.{ddup}.ensemble.snv.vcf.gz.tbi")
    wildcard_constraints:
        alnr="|".join(ALIGNERS_ENSEMBLE)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/log/{sample}.{alnr}.{ddup}.merge.log"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.ensemble.merge.bench.tsv"
    threads: 4
    resources:
        vcpu=4,
        threads=4,
        partition="i384nvme,i192nvme,i192,i128"
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mode=mode,
        ont_qual_min_snv=thresholds["ont_qual_min_snv"],
        ont_qual_min_indel=thresholds["ont_qual_min_indel"],
        allow_ont_snv=thresholds.get("allow_ont_snv", False),
        cluster_sample=ret_sample
    conda:
        "../envs/bcftools_v0.1.yaml"
    shell:
        r"""
        tmpdir=$(dirname {output.vcf})/tmp_merge
        mkdir -p $tmpdir

        # Shared calls (intersection)
        bcftools isec -n=2 -w1 {input.sr_vcf} {input.lr_vcf} \
          -Oz -o $tmpdir/shared.vcf.gz >> {log} 2>&1
        bcftools index -f $tmpdir/shared.vcf.gz >> {log} 2>&1

        # Long-read rescue in discordant regions
        if [ "{params.mode}" = "A" ]; then
            # Mode A: conservative - only indels
            bcftools view -R {input.rescue_bed} {input.lr_vcf} \
              | bcftools filter -i 'TYPE="indel" && QUAL>={params.ont_qual_min_indel}' \
              -Oz -o $tmpdir/lr_rescue.vcf.gz >> {log} 2>&1
        else
            # Mode D: sensitive - indels + SNVs
            bcftools view -R {input.rescue_bed} {input.lr_vcf} \
              | bcftools filter -i '(TYPE="indel" && QUAL>={params.ont_qual_min_indel}) || (TYPE="snp" && QUAL>={params.ont_qual_min_snv})' \
              -Oz -o $tmpdir/lr_rescue.vcf.gz >> {log} 2>&1
        fi
        bcftools index -f $tmpdir/lr_rescue.vcf.gz >> {log} 2>&1

        # Rename LR rescue sample to match SR sample name (required for bcftools concat)
        bcftools query -l $tmpdir/shared.vcf.gz > $tmpdir/sample_names.txt
        bcftools reheader -s $tmpdir/sample_names.txt $tmpdir/lr_rescue.vcf.gz \
          -o $tmpdir/lr_rescue.reheadered.vcf.gz >> {log} 2>&1
        mv $tmpdir/lr_rescue.reheadered.vcf.gz $tmpdir/lr_rescue.vcf.gz
        bcftools index -f $tmpdir/lr_rescue.vcf.gz >> {log} 2>&1

        # Concatenate shared + rescued variants
        bcftools concat -a -D $tmpdir/shared.vcf.gz $tmpdir/lr_rescue.vcf.gz \
          -Oz -o {output.vcf} >> {log} 2>&1
        bcftools index -f -t {output.vcf} >> {log} 2>&1

        rm -rf $tmpdir
        """


#############################################
# Sort and finalize ensemble VCF
#############################################

rule hyb_ensemble_sort:
    input:
        vcf = MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/{sample}.{alnr}.{ddup}.ensemble.snv.vcf.gz"
    output:
        vcf = MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/{sample}.{alnr}.{ddup}.ensemble.snv.sort.vcf.gz",
        tbi = MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/{sample}.{alnr}.{ddup}.ensemble.snv.sort.vcf.gz.tbi"
    wildcard_constraints:
        alnr="|".join(ALIGNERS_ENSEMBLE)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/ensemble/log/{sample}.{alnr}.{ddup}.sort.log"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.ensemble.sort.bench.tsv"
    threads: 4
    resources:
        vcpu=4,
        threads=4,
        partition="i384nvme,i192nvme,i192,i128"
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample
    conda:
        "../envs/bcftools_v0.1.yaml"
    shell:
        r"""
        # Sort and normalize final VCF
        bcftools sort {input.vcf} \
          | bcftools norm -f {params.huref} -d all \
          -Oz -o {output.vcf} >> {log} 2>&1

        bcftools index -t {output.vcf} >> {log} 2>&1
        """


#############################################
# Target rule: produce ensemble VCFs
#############################################

localrules: produce_ensemble_vcf

rule produce_ensemble_vcf:  # TARGET: ensemble VCF generation
    input:
        [
            MDIR + f"{sample}/align/{alnr}/{ddup}/snv/ensemble/{sample}.{alnr}.{ddup}.ensemble.snv.sort.vcf.gz"
            for sample in SSAMPS
            for ddup in DDUP
            for alnr in ALIGNERS_ENSEMBLE
            if alnr in ALL_ALIGNERS
        ]
    output:
        touch(MDIR + "other_reports/ensemble_vcf.done")
    log:
        MDIR + "logs/produce_ensemble_vcf.log"
    benchmark:
        "logs/benchmarks/produce_ensemble_vcf.bench.tsv"
    params:
        cluster_sample="aggregate"
    conda:
        "../envs/vanilla_v0.1.yaml"
    shell:
        """
        echo "Ensemble VCF generation complete" > {output}
        """


#############################################
# Target rule: produce ensemble VCFs + concordance
#############################################

localrules: produce_ensemble_concordances

rule produce_ensemble_concordances:  # TARGET: ensemble VCF + concordance
    input:
        [
            MDIR + f"{sample}/align/{alnr}/{ddup}/snv/ensemble/concordance/concordance.done"
            for sample in SSAMPS
            for ddup in DDUP
            for alnr in ALIGNERS_ENSEMBLE
            if alnr in ALL_ALIGNERS and sample in CONCORDANCE_SAMPLES
        ]
    output:
        touch(MDIR + "other_reports/ensemble_concordance.done")
    log:
        MDIR + "logs/produce_ensemble_concordances.log"
    benchmark:
        "logs/benchmarks/produce_ensemble_concordances.bench.tsv"
    params:
        cluster_sample="aggregate"
    conda:
        "../envs/vanilla_v0.1.yaml"
    shell:
        """
        echo "Ensemble concordance complete" > {output}
        """
