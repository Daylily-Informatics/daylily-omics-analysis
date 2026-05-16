"""Canonical selector targets backed by the workflow target registry.

The rules in this file do not implement tool logic.  They delegate to the
existing aggregate target inputs recorded in config/workflow_target_aliases.tsv
and write small marker files once those existing outputs are present.
"""


def _workflow_target_alias_rows(kind, target):
    return [
        row
        for row in TARGET_ALIAS_BY_KIND.get(kind, [])
        if row["target"] == target and row["status"] == "current"
    ]


def _workflow_target_delegate_rules(kind, target):
    rows = _workflow_target_alias_rows(kind, target)
    if not rows:
        raise WorkflowError(f"Unknown current {kind} target alias: {target}")
    delegates = []
    for row in rows:
        if row["code"] == "all":
            delegates.extend(_delegate_targets(kind))
        elif row["delegates_to"]:
            delegates.append(row["delegates_to"])
    delegates = sorted(set(delegates))
    if not delegates:
        raise WorkflowError(f"No delegate rule configured for {kind} target alias: {target}")
    return delegates


def _workflow_target_alias_inputs(kind, target):
    inputs = []
    for delegate in _workflow_target_delegate_rules(kind, target):
        try:
            delegate_rule = getattr(rules, delegate)
        except AttributeError:
            raise WorkflowError(
                f"{kind} target alias {target} delegates to missing rule {delegate}."
            )
        delegate_inputs = list(delegate_rule.input)
        if not delegate_inputs:
            raise WorkflowError(
                f"{kind} target alias {target} delegates to {delegate}, "
                "but that rule has no declared inputs to reuse."
            )
        inputs.extend(delegate_inputs)
    return sorted(set(str(path) for path in inputs))


def _workflow_target_alias_marker(target):
    return MDIR + f"logs/target_aliases/{target}.done"


localrules:
    produce_sent_align,
    produce_bwa2a_align,
    produce_strobe_align,
    produce_sentcg_align,
    produce_sentmm2_align,
    produce_sentmm2ont_align,
    produce_all_align,
    produce_dmd_dedup_cram,
    produce_smd_dedup_cram,
    produce_na_dedup_cram,
    produce_all_dedup_cram,
    produce_sentd_snv_vcf,
    produce_cgt7p_snv_vcf,
    produce_sentdpb_snv_vcf,
    produce_sentdont_snv_vcf,
    produce_sentdug_snv_vcf,
    produce_sentdhio_snv_vcf,
    produce_sentdhuo_snv_vcf,
    produce_sentdhip_snv_vcf,
    produce_sentdhup_snv_vcf,
    produce_sentdhiom_snv_vcf,
    produce_sentdhuom_snv_vcf,
    produce_sentdhipm_snv_vcf,
    produce_sentdhupm_snv_vcf,
    produce_sentdhrom_snv_vcf,
    produce_sentdhrpm_snv_vcf,
    produce_sentdhiomr_snv_vcf,
    produce_sentdhipmr_snv_vcf,
    produce_sentdhuomr_snv_vcf,
    produce_sentdhupmr_snv_vcf,
    produce_sentpg_snv_vcf,
    produce_gatk_snv_vcf,
    produce_deep19_snv_vcf,
    produce_deep19r_snv_vcf,
    produce_deep15_snv_vcf,
    produce_oct_snv_vcf,
    produce_clair3_snv_vcf,
    produce_lfq2_snv_vcf,
    produce_varn_snv_vcf,
    produce_aiv_snv_vcf,
    produce_mutect2_snv_vcf,
    produce_dvsom_snv_vcf,
    produce_slk2g_snv_vcf,
    produce_slk2s_snv_vcf,
    produce_senttn_snv_vcf,
    produce_rochehc_snv_vcf,
    produce_all_snv_vcf,
    produce_tiddit_sv_vcf,
    produce_manta_sv_vcf,
    produce_dysgu_sv_vcf,
    produce_all_sv_vcf,


rule produce_sent_align:  # TARGET: canonical Sentieon BWA aligner selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("aligner", "produce_sent_align")
    output:
        _workflow_target_alias_marker("produce_sent_align")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_bwa2a_align:  # TARGET: canonical BWA-MEM2 aligner selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("aligner", "produce_bwa2a_align")
    output:
        _workflow_target_alias_marker("produce_bwa2a_align")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_strobe_align:  # TARGET: canonical Strobealign aligner selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("aligner", "produce_strobe_align")
    output:
        _workflow_target_alias_marker("produce_strobe_align")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentcg_align:  # TARGET: canonical Complete Genomics/MGI aligner selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("aligner", "produce_sentcg_align")
    output:
        _workflow_target_alias_marker("produce_sentcg_align")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentmm2_align:  # TARGET: canonical PacBio minimap2 aligner selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("aligner", "produce_sentmm2_align")
    output:
        _workflow_target_alias_marker("produce_sentmm2_align")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentmm2ont_align:  # TARGET: canonical ONT minimap2 aligner selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("aligner", "produce_sentmm2ont_align")
    output:
        _workflow_target_alias_marker("produce_sentmm2ont_align")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_all_align:  # TARGET: canonical all-aligners selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("aligner", "produce_all_align")
    output:
        _workflow_target_alias_marker("produce_all_align")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_dmd_dedup_cram:  # TARGET: canonical Doppelmark dedup CRAM selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("deduper", "produce_dmd_dedup_cram")
    output:
        _workflow_target_alias_marker("produce_dmd_dedup_cram")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_smd_dedup_cram:  # TARGET: canonical Sentieon dedup CRAM selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("deduper", "produce_smd_dedup_cram")
    output:
        _workflow_target_alias_marker("produce_smd_dedup_cram")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_na_dedup_cram:  # TARGET: canonical no-dedup CRAM selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("deduper", "produce_na_dedup_cram")
    output:
        _workflow_target_alias_marker("produce_na_dedup_cram")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_all_dedup_cram:  # TARGET: canonical all-dedupers CRAM selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("deduper", "produce_all_dedup_cram")
    output:
        _workflow_target_alias_marker("produce_all_dedup_cram")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentd_snv_vcf:  # TARGET: canonical Sentieon DNAscope SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentd_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentd_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_cgt7p_snv_vcf:  # TARGET: canonical Complete Genomics/MGI SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_cgt7p_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_cgt7p_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdpb_snv_vcf:  # TARGET: canonical PacBio Sentieon SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdpb_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdpb_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdont_snv_vcf:  # TARGET: canonical ONT Sentieon SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdont_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdont_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdug_snv_vcf:  # TARGET: canonical Ultima Sentieon SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdug_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdug_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdhio_snv_vcf:  # TARGET: canonical Illumina+ONT hybrid SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdhio_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdhio_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdhuo_snv_vcf:  # TARGET: canonical Ultima+ONT hybrid SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdhuo_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdhuo_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdhip_snv_vcf:  # TARGET: canonical Illumina+PacBio hybrid SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdhip_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdhip_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdhup_snv_vcf:  # TARGET: canonical Ultima+PacBio hybrid SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdhup_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdhup_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdhiom_snv_vcf:  # TARGET: canonical modular Illumina+ONT hybrid SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdhiom_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdhiom_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdhuom_snv_vcf:  # TARGET: canonical modular Ultima+ONT hybrid SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdhuom_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdhuom_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdhipm_snv_vcf:  # TARGET: canonical modular Illumina+PacBio hybrid SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdhipm_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdhipm_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdhupm_snv_vcf:  # TARGET: canonical modular Ultima+PacBio hybrid SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdhupm_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdhupm_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdhrom_snv_vcf:  # TARGET: canonical modular Roche+ONT hybrid SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdhrom_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdhrom_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdhrpm_snv_vcf:  # TARGET: canonical modular Roche+PacBio hybrid SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdhrpm_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdhrpm_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdhiomr_snv_vcf:  # TARGET: canonical refactored Illumina+ONT hybrid SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdhiomr_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdhiomr_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdhipmr_snv_vcf:  # TARGET: canonical refactored Illumina+PacBio hybrid SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdhipmr_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdhipmr_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdhuomr_snv_vcf:  # TARGET: canonical refactored Ultima+ONT hybrid SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdhuomr_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdhuomr_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentdhupmr_snv_vcf:  # TARGET: canonical refactored Ultima+PacBio hybrid SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentdhupmr_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentdhupmr_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_sentpg_snv_vcf:  # TARGET: canonical Sentieon pangenome SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_sentpg_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_sentpg_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_gatk_snv_vcf:  # TARGET: canonical Sentieon GATK SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_gatk_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_gatk_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_deep19_snv_vcf:  # TARGET: canonical DeepVariant 1.9 SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_deep19_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_deep19_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_deep19r_snv_vcf:  # TARGET: canonical DeepVariant 1.9 Roche SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_deep19r_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_deep19r_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_deep15_snv_vcf:  # TARGET: canonical DeepVariant 1.5 SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_deep15_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_deep15_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_oct_snv_vcf:  # TARGET: canonical Octopus SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_oct_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_oct_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_clair3_snv_vcf:  # TARGET: canonical Clair3 SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_clair3_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_clair3_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_lfq2_snv_vcf:  # TARGET: canonical LoFreq2 SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_lfq2_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_lfq2_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_varn_snv_vcf:  # TARGET: canonical VarNet SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_varn_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_varn_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_aiv_snv_vcf:  # TARGET: canonical AIVariant SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_aiv_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_aiv_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_mutect2_snv_vcf:  # TARGET: canonical Mutect2 SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_mutect2_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_mutect2_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_dvsom_snv_vcf:  # TARGET: canonical DeepSomatic SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_dvsom_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_dvsom_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_slk2g_snv_vcf:  # TARGET: canonical Strelka2 germline SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_slk2g_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_slk2g_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_slk2s_snv_vcf:  # TARGET: canonical Strelka2 somatic SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_slk2s_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_slk2s_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_senttn_snv_vcf:  # TARGET: canonical Sentieon TNscope SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_senttn_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_senttn_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_rochehc_snv_vcf:  # TARGET: canonical Roche HaplotypeCaller SNV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_rochehc_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_rochehc_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_all_snv_vcf:  # TARGET: canonical all-SNV-callers selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("snv_caller", "produce_all_snv_vcf")
    output:
        _workflow_target_alias_marker("produce_all_snv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_tiddit_sv_vcf:  # TARGET: canonical TIDDIT SV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("sv_caller", "produce_tiddit_sv_vcf")
    output:
        _workflow_target_alias_marker("produce_tiddit_sv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_manta_sv_vcf:  # TARGET: canonical Manta SV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("sv_caller", "produce_manta_sv_vcf")
    output:
        _workflow_target_alias_marker("produce_manta_sv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_dysgu_sv_vcf:  # TARGET: canonical Dysgu SV selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("sv_caller", "produce_dysgu_sv_vcf")
    output:
        _workflow_target_alias_marker("produce_dysgu_sv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"


rule produce_all_sv_vcf:  # TARGET: canonical all-SV-callers selector
    input:
        lambda wildcards: _workflow_target_alias_inputs("sv_caller", "produce_all_sv_vcf")
    output:
        _workflow_target_alias_marker("produce_all_sv_vcf")
    shell:
        "mkdir -p $(dirname {output:q}); touch {output:q};"
