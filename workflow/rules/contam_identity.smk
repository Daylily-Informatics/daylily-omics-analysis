######### GLOBAL CONTAMINATION / IDENTITY EVIDENCE BUNDLE
# DayOA emits evidence only. R2 owns interpretation, disposition, and release.

from snakemake.exceptions import WorkflowError


CONTAM_IDENTITY_ROOT = MDIR + "other_reports/contam_identity"
CONTAM_IDENTITY_SAMPLES = qc_eligible_sample_ids(SSAMPS)
CONTAM_IDENTITY_TARGETS = {
    "produce_global_contam_check",
    "produce_haplocheck_contam_identity",
    "produce_read_haps_contam_identity",
}


def contam_identity_enabled_for_multiqc():
    return bool(CONTAM_IDENTITY_TARGETS & _requested_targets()) or qc_tool_enabled(
        "contam_identity", long_running=True, default=False
    )


def _contam_identity_config():
    cfg = config.get("contam_identity")
    if not isinstance(cfg, dict):
        raise WorkflowError(
            "Global contamination/identity requires an explicit contam_identity "
            "config block."
        )
    return cfg


def contam_identity_primary_snv_caller():
    cfg = _contam_identity_config()
    caller = str(cfg.get("primary_snv_caller", "") or "").strip()
    if not caller:
        raise WorkflowError(
            "Global contamination/identity requires explicit "
            "contam_identity.primary_snv_caller."
        )
    configured_callers = config.get("snv_callers")
    if not isinstance(configured_callers, list) or not configured_callers:
        raise WorkflowError(
            "Global contamination/identity requires explicit snv_callers config; "
            "contam_identity.primary_snv_caller must not rely on auto-detected "
            "caller state."
        )
    if caller not in configured_callers:
        raise WorkflowError(
            "contam_identity.primary_snv_caller must be present in the explicit "
            f"snv_callers config; observed primary_snv_caller={caller!r}, "
            f"snv_callers={configured_callers!r}."
        )
    if caller not in snv_CALLERS:
        raise WorkflowError(
            "contam_identity.primary_snv_caller is explicit, but it is not active "
            f"in the parsed Snakemake caller set; observed primary_snv_caller={caller!r}, "
            f"snv_CALLERS={snv_CALLERS!r}."
        )
    return caller


def _contam_identity_required_cfg(section, keys, allow_empty=()):
    cfg = config.get(section)
    if not isinstance(cfg, dict):
        raise WorkflowError(f"Global contamination/identity requires config block {section}.")
    missing = [
        key
        for key in keys
        if key not in allow_empty
        and str(cfg.get(key, "") or "").strip() in {"", "None", "none", "NA", "na"}
    ]
    missing.extend(key for key in allow_empty if key not in cfg)
    if missing:
        raise WorkflowError(
            "Global contamination/identity is missing explicit config value(s): "
            + ", ".join(f"{section}.{key}" for key in missing)
        )
    return cfg


def _contam_identity_alignment_pairs():
    pairs = [
        (alnr, ddup)
        for alnr in QC_CRAM_ALIGNERS
        for ddup in qc_contamination_dedupers()
    ]
    if not pairs:
        raise WorkflowError(
            "Global contamination/identity requires at least one CRAM-capable "
            "alignment/deduper pair."
        )
    return pairs


def _contam_identity_primary_snv_pairs():
    caller = contam_identity_primary_snv_caller()
    pairs = [
        (alnr, caller)
        for alnr, caller in valid_snv_alnr_pairs(QC_CRAM_ALIGNERS, [caller])
    ]
    if not pairs:
        raise WorkflowError(
            "Global contamination/identity primary SNV caller produced no valid "
            f"CRAM-capable aligner pairs: {caller!r}."
        )
    return pairs


def _contam_identity_primary_snv_vcf(wildcards):
    caller = contam_identity_primary_snv_caller()
    if str(wildcards.snv) != caller:
        raise WorkflowError(
            f"Contam identity requested snv={wildcards.snv!r}, but "
            f"contam_identity.primary_snv_caller={caller!r}."
        )
    return (
        MDIR
        + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/snv/{caller}/"
        + f"{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.{caller}.snv.sort.vcf.gz"
    )


def _contam_identity_primary_snv_tbi(wildcards):
    return _contam_identity_primary_snv_vcf(wildcards) + ".tbi"


def _haplocheck_modes():
    cfg = _contam_identity_required_cfg(
        "haplocheck",
        (
            "env_yaml",
            "threads",
            "mem_mb",
            "partition",
            "haplocheck_command",
            "cloudgene_command",
            "cloudgene_app",
        ),
    )
    modes = _as_config_list(cfg.get("input_modes", []))
    unsupported = sorted(set(modes) - {"bam", "vcf"})
    if unsupported:
        raise WorkflowError(
            "haplocheck.input_modes supports only 'bam' and 'vcf'; observed "
            + ", ".join(unsupported)
        )
    if not modes:
        raise WorkflowError("haplocheck.input_modes must include 'bam', 'vcf', or both.")
    return modes


def _haplocheck_bam_outputs(suffix):
    if "bam" not in _haplocheck_modes():
        return []
    return expand(
        MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/contam_identity/haplocheck/bam/"
        + "{sample}.{alnr}.{ddup}.haplocheck."
        + suffix,
        sample=CONTAM_IDENTITY_SAMPLES,
        alnr=QC_CRAM_ALIGNERS,
        ddup=qc_contamination_dedupers(),
    )


def _haplocheck_vcf_outputs(suffix):
    if "vcf" not in _haplocheck_modes():
        return []
    pairs = _contam_identity_primary_snv_pairs()
    return expand(
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/contam_identity/haplocheck/vcf/"
        + "{sample}.{alnr}.{ddup}.{snv}.haplocheck."
        + suffix,
        sample=CONTAM_IDENTITY_SAMPLES,
        alnr=[pair[0] for pair in pairs],
        snv=[pair[1] for pair in pairs],
        ddup=qc_variant_dedupers(),
    )


def _haplocheck_outputs(suffix):
    return _haplocheck_bam_outputs(suffix) + _haplocheck_vcf_outputs(suffix)


def _read_haps_outputs(suffix):
    # Explicit required config: read_haps.reliable_snp_file
    _contam_identity_required_cfg(
        "read_haps",
        (
            "env_yaml",
            "threads",
            "mem_mb",
            "partition",
            "read_haps_command",
            "reliable_snp_file",
            "extra_args",
        ),
        allow_empty=("extra_args",),
    )
    pairs = _contam_identity_primary_snv_pairs()
    return expand(
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/contam_identity/read_haps/"
        + "{sample}.{alnr}.{ddup}.{snv}."
        + suffix,
        sample=CONTAM_IDENTITY_SAMPLES,
        alnr=[pair[0] for pair in pairs],
        snv=[pair[1] for pair in pairs],
        ddup=qc_variant_dedupers(),
    )


def contam_identity_multiqc_inputs(wildcards=None):
    if not contam_identity_enabled_for_multiqc():
        return []
    return [
        MDIR + "other_reports/contam_identity_mqc.tsv",
        MDIR + "other_reports/haplocheck_mtdna_mqc.tsv",
        MDIR + "other_reports/read_haps_mqc.tsv",
    ]


def _contam_identity_native_inputs(wildcards=None):
    if not contam_identity_enabled_for_multiqc():
        return []
    return (
        _haplocheck_outputs("contamination.txt")
        + _haplocheck_outputs("contamination.raw.txt")
        + _haplocheck_outputs("report.html")
        + _read_haps_outputs("read_haps.txt")
    )


localrules:
    contam_identity_mqc_gather,
    produce_global_contam_check,
    produce_haplocheck_contam_identity,
    produce_read_haps_contam_identity,


rule haplocheck_bam_contam_identity:
    input:
        bam=rules.legacy_cram_compat_bam.output.bam,
        bai=rules.legacy_cram_compat_bam.output.bai,
    output:
        contamination=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam_identity/haplocheck/bam/{sample}.{alnr}.{ddup}.haplocheck.contamination.txt",
        raw=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam_identity/haplocheck/bam/{sample}.{alnr}.{ddup}.haplocheck.contamination.raw.txt",
        html=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam_identity/haplocheck/bam/{sample}.{alnr}.{ddup}.haplocheck.report.html",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam_identity/haplocheck/bam/logs/{sample}.{alnr}.{ddup}.haplocheck.bam.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.haplocheck_bam.bench.tsv"
    conda:
        config["haplocheck"]["env_yaml"]
    threads: config["haplocheck"]["threads"]
    resources:
        vcpu=config["haplocheck"]["threads"],
        mem_mb=config["haplocheck"]["mem_mb"],
        partition=config["haplocheck"]["partition"],
    params:
        cloudgene=config["haplocheck"]["cloudgene_command"],
        app=config["haplocheck"]["cloudgene_app"],
        sample_ok=lambda wildcards: require_qc_eligible_sample(
            wildcards, "Haplocheck BAM"
        ),
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail
        test {params.sample_ok:q} = ok
        outdir="$(dirname {output.contamination:q})"
        mkdir -p "$outdir" "$(dirname {log:q})"
        command -v {params.cloudgene:q} > /dev/null
        input_dir="$(mktemp -d "$outdir/.haplocheck_bam_input.XXXXXX")"
        result_dir="$(mktemp -d "$outdir/.haplocheck_bam_output.XXXXXX")"
        cleanup() {{
            rm -rf "$input_dir" "$result_dir"
        }}
        trap cleanup EXIT
        ln -s "$(readlink -f {input.bam:q})" "$input_dir/$(basename {input.bam:q})"
        ln -s "$(readlink -f {input.bai:q})" "$input_dir/$(basename {input.bai:q})"
        {params.cloudgene:q} run {params.app:q} --files "$input_dir" --format bam --output "$result_dir" --threads {threads} > {log:q} 2>&1
        test -s "$result_dir/report/contamination.txt"
        test -s "$result_dir/report/contamination.raw.txt"
        test -s "$result_dir/report/report.html"
        cp "$result_dir/report/contamination.txt" {output.contamination:q}
        cp "$result_dir/report/contamination.raw.txt" {output.raw:q}
        cp "$result_dir/report/report.html" {output.html:q}
        """


rule haplocheck_vcf_contam_identity:
    input:
        vcf=_contam_identity_primary_snv_vcf,
        tbi=_contam_identity_primary_snv_tbi,
    output:
        contamination=MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/contam_identity/haplocheck/vcf/{sample}.{alnr}.{ddup}.{snv}.haplocheck.contamination.txt",
        raw=MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/contam_identity/haplocheck/vcf/{sample}.{alnr}.{ddup}.{snv}.haplocheck.contamination.raw.txt",
        html=MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/contam_identity/haplocheck/vcf/{sample}.{alnr}.{ddup}.{snv}.haplocheck.report.html",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/contam_identity/haplocheck/vcf/logs/{sample}.{alnr}.{ddup}.{snv}.haplocheck.vcf.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.haplocheck_vcf.bench.tsv"
    conda:
        config["haplocheck"]["env_yaml"]
    threads: config["haplocheck"]["threads"]
    resources:
        vcpu=config["haplocheck"]["threads"],
        mem_mb=config["haplocheck"]["mem_mb"],
        partition=config["haplocheck"]["partition"],
    params:
        command=config["haplocheck"]["haplocheck_command"],
        sample_ok=lambda wildcards: require_qc_eligible_sample(
            wildcards, "Haplocheck VCF"
        ),
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail
        test {params.sample_ok:q} = ok
        outdir="$(dirname {output.contamination:q})"
        mkdir -p "$outdir" "$(dirname {log:q})"
        command -v {params.command:q} > /dev/null
        result_dir="$(mktemp -d "$outdir/.haplocheck_vcf_output.XXXXXX")"
        result_prefix="$result_dir/contamination.txt"
        cleanup() {{
            rm -rf "$result_dir"
        }}
        trap cleanup EXIT
        {params.command:q} --out "$result_prefix" --raw {input.vcf:q} > {log:q} 2>&1
        test -s "$result_dir/contamination.txt"
        test -s "$result_dir/contamination.raw.txt"
        test -s "$result_dir/contamination.html"
        cp "$result_dir/contamination.txt" {output.contamination:q}
        cp "$result_dir/contamination.raw.txt" {output.raw:q}
        cp "$result_dir/contamination.html" {output.html:q}
        """


rule read_haps_contam_identity:
    input:
        bam=rules.legacy_cram_compat_bam.output.bam,
        bai=rules.legacy_cram_compat_bam.output.bai,
        vcf=_contam_identity_primary_snv_vcf,
        tbi=_contam_identity_primary_snv_tbi,
    output:
        txt=MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/contam_identity/read_haps/{sample}.{alnr}.{ddup}.{snv}.read_haps.txt",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/contam_identity/read_haps/logs/{sample}.{alnr}.{ddup}.{snv}.read_haps.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.read_haps.bench.tsv"
    conda:
        config["read_haps"]["env_yaml"]
    threads: config["read_haps"]["threads"]
    resources:
        vcpu=config["read_haps"]["threads"],
        mem_mb=config["read_haps"]["mem_mb"],
        partition=config["read_haps"]["partition"],
    params:
        command=config["read_haps"]["read_haps_command"],
        reliable_snp_file=config["read_haps"]["reliable_snp_file"],
        extra_args=config["read_haps"]["extra_args"],
        ref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        sample_ok=lambda wildcards: require_qc_eligible_sample(
            wildcards, "read_haps"
        ),
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail
        test {params.sample_ok:q} = ok
        mkdir -p "$(dirname {output.txt:q})" "$(dirname {log:q})"
        command -v {params.command:q} > /dev/null
        test -s {params.reliable_snp_file:q}
        {params.command:q} {params.extra_args} -fa {params.ref:q} {input.bam:q} {params.reliable_snp_file:q} {input.vcf:q} > {output.txt:q} 2> {log:q}
        test -s {output.txt:q}
        grep -q 'PASS_FAIL' {output.txt:q}
        grep -q 'REASON' {output.txt:q}
        """


rule contam_identity_mqc_gather:
    input:
        contamination=MDIR + "other_reports/contamination_mqc.tsv",
        haplocheck=lambda wildcards: _haplocheck_outputs("contamination.txt"),
        read_haps=lambda wildcards: _read_haps_outputs("read_haps.txt"),
    output:
        identity=MDIR + "other_reports/contam_identity_mqc.tsv",
        haplocheck=MDIR + "other_reports/haplocheck_mtdna_mqc.tsv",
        read_haps=MDIR + "other_reports/read_haps_mqc.tsv",
    params:
        sample_map=_sample_external_ids_json,
    log:
        MDIR + "other_reports/logs/contam_identity_custom_data.log",
    benchmark:
        MDIR + "benchmarks/contam_identity_mqc_gather.bench.tsv"
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output.identity:q})" "$(dirname {log:q})"
        python workflow/scripts/compile_contam_identity_mqc.py \
          --sample-map-json {params.sample_map:q} \
          --contam-identity-output {output.identity:q} \
          --haplocheck-output {output.haplocheck:q} \
          --read-haps-output {output.read_haps:q} \
          --contamination {input.contamination:q} \
          --haplocheck {input.haplocheck:q} \
          --read-haps {input.read_haps:q} \
          > {log:q} 2>&1
        """


rule produce_haplocheck_contam_identity:  # TARGET: run Haplocheck mtDNA contamination proxy evidence
    input:
        lambda wildcards: _haplocheck_outputs("contamination.txt"),


    log:
        MDIR + "logs/produce_haplocheck_contam_identity.log"
    benchmark:
        MDIR + "benchmarks/produce_haplocheck_contam_identity.bench.tsv"
rule produce_read_haps_contam_identity:  # TARGET: run read_haps haplotype contamination evidence
    input:
        lambda wildcards: _read_haps_outputs("read_haps.txt"),


    log:
        MDIR + "logs/produce_read_haps_contam_identity.log"
    benchmark:
        MDIR + "benchmarks/produce_read_haps_contam_identity.bench.tsv"
rule produce_global_contam_check:  # TARGET: run global contamination and identity evidence bundle
    input:
        MDIR + "other_reports/contamination_mqc.tsv",
        MDIR + "other_reports/site_mix_contam_mqc.tsv",
        MDIR + "other_reports/site_mix_donor_mqc.tsv",
        MDIR + "other_reports/peddy_sample_qc_mqc.tsv",
        MDIR + "other_reports/relatedness_mqc.tsv",
        MDIR + "other_reports/contam_identity_mqc.tsv",
        MDIR + "other_reports/haplocheck_mtdna_mqc.tsv",
        MDIR + "other_reports/read_haps_mqc.tsv",
    log:
        MDIR + "logs/produce_global_contam_check.log"
    benchmark:
        MDIR + "benchmarks/produce_global_contam_check.bench.tsv"
