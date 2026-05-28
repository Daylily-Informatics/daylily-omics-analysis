######### GENOTYPE-FREE SITE MIX CONTAMINATION SCREEN
# - Estimates same-species contamination without target genotype.
# - Optional donor attribution uses a candidate BAM/CRAM/VCF manifest.

import csv
import json
import os


def _site_mix_qc_samples():
    return qc_eligible_sample_ids(SSAMPS)


def _contam_qc_paths(tool, suffix, sample_ids=None):
    if sample_ids is None:
        sample_ids = SSAMPS
    return expand(
        MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/contam/"
        + tool
        + "/{sample}.{alnr}.{ddup}."
        + suffix,
        sample=sample_ids,
        alnr=QC_CRAM_ALIGNERS,
        ddup=qc_contamination_dedupers(),
    )


def _enabled_contam_qc_paths(enabled_tool, tool, suffix, sample_ids=None):
    if qc_tool_enabled(enabled_tool) or "produce_global_contam_check" in _requested_targets():
        return _contam_qc_paths(tool, suffix, sample_ids=sample_ids)
    return []


def _parse_contam_path(path):
    name = os.path.basename(str(path))
    sample = aligner = deduper = None
    for alnr in QC_CRAM_ALIGNERS:
        for ddup in qc_contamination_dedupers():
            marker = f".{alnr}.{ddup}."
            if marker in name:
                sample = name.split(marker, 1)[0]
                aligner = alnr
                deduper = ddup
                break
        if sample is not None:
            break
    if sample is None:
        raise ValueError(f"Malformed contamination path: {path}")
    external = config.get("sample_info", {}).get(sample, {}).get(
        "external_sample_id", sample
    )
    return sample, str(external), aligner, deduper


def _contam_stage_sample_id(sample, aligner, deduper):
    return day_stage_sample_id(sample, aligner, deduper)


def _safe_pct(value):
    try:
        return str(float(value) * 100.0)
    except (TypeError, ValueError):
        return ""


def _read_benchmark_row(path):
    if not path:
        return {}
    try:
        with open(path, newline="") as handle:
            rows = list(csv.DictReader(handle, delimiter="\t"))
    except OSError:
        return {}
    return rows[0] if rows else {}


def _seconds_to_minutes(value):
    try:
        return str(float(value) / 60.0)
    except (TypeError, ValueError):
        return ""


def _sample_external_ids_json(wildcards=None):
    sample_info = config.get("sample_info", {})
    return json.dumps(
        {
            sample: str(sample_info.get(sample, {}).get("external_sample_id", sample))
            for sample in SSAMPS
        }
    )


rule site_mix_contam:
    input:
        pileups = MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/gatk/{sample}.{alnr}.{ddup}.pileups.table",
    output:
        tsv = MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/site_mix/{sample}.{alnr}.{ddup}.site_mix.tsv",
        donors = MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/site_mix/{sample}.{alnr}.{ddup}.site_mix_donors.tsv",
        stamp = MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/site_mix/{sample}.{alnr}.{ddup}.site_mix.done",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/site_mix/logs/{sample}.{alnr}.{ddup}.site_mix.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.site_mix_contam.bench.tsv"
    conda:
        config["site_mix_contam"]["env_yaml"]
    threads: config["site_mix_contam"]["threads"]
    resources:
        vcpu = config["site_mix_contam"]["threads"],
        partition = config["site_mix_contam"]["partition"],
    params:
        cluster_sample = ret_sample,
        stage_sample=lambda wildcards: _contam_stage_sample_id(
            wildcards.sample, wildcards.alnr, wildcards.ddup
        ),
        sample_ok=lambda wildcards: require_qc_eligible_sample(
            wildcards, "site_mix_contam"
        ),
        candidate_manifest = config["site_mix_contam"]["candidate_manifest"],
        min_depth = config["site_mix_contam"]["min_depth"],
        max_depth = config["site_mix_contam"]["max_depth"],
        min_sites = config["site_mix_contam"]["min_sites"],
        max_contamination = config["site_mix_contam"]["max_contamination"],
        grid_step = config["site_mix_contam"]["grid_step"],
    shell:
        r"""
        set -euo pipefail

        outdir="$(dirname {output.tsv})"
        mkdir -p "${{outdir}}" "${{outdir}}/logs"
        test {params.sample_ok:q} = ok

        if [[ -n "{params.candidate_manifest}" ]]; then
            echo "ERROR: site_mix_contam production rule uses GATK pileup tables and does not support candidate_manifest donor attribution. Use the estimator CLI BAM/CRAM mode for donor attribution." >&2
            exit 2
        fi

        if ! bin/util/genotype_free_contam_estimator.py \
            --sample-id "{params.stage_sample}" \
            --counts-tsv {input.pileups} \
            --output {output.tsv} \
            --donor-output {output.donors} \
            --min-depth {params.min_depth} \
            --max-depth {params.max_depth} \
            --min-sites {params.min_sites} \
            --max-contamination {params.max_contamination} \
            --grid-step {params.grid_step} \
            > {log} 2>&1; then
            if grep -Eq '^ERROR: Only [0-9]+ usable sites after depth filters; need at least [0-9]+' {log:q}; then
                printf 'sample_id\tmethod\tcontamination_fraction\tcontamination_pct\tci_low_fraction\tci_high_fraction\tunknown_contamination_fraction\tunknown_contamination_pct\tsite_count\tread_count\tmean_depth\tlog_likelihood\tnull_log_likelihood\tdelta_log_likelihood\tsource_delta_log_likelihood\tstatus\n' > {output.tsv:q}
                printf '{params.stage_sample}\tgenotype_free_site_mix\tNA\tNA\t\t\tNA\tNA\t0\t0\t0\t\t\t\t\tno_usable_sites\n' >> {output.tsv:q}
                printf 'sample_id\tsource_rank\tsource_sample_id\tis_unknown_source\tcontamination_fraction\tcontamination_pct\tsingle_source_delta_log_likelihood\n' > {output.donors:q}
            else
                exit 1
            fi
        fi

        test -s {output.tsv}
        test -s {output.donors}
        touch {output.stamp}
        """


localrules:
    contamination_mqc_gather,
    produce_site_mix_contam_estimate,


rule contamination_mqc_gather:
    input:
        gatk=lambda wildcards: _enabled_contam_qc_paths("gatk_contam", "gatk", "gatk.tsv"),
        site_mix=lambda wildcards: _enabled_contam_qc_paths(
            "site_mix", "site_mix", "site_mix.tsv", sample_ids=_site_mix_qc_samples()
        ),
        site_mix_donors=lambda wildcards: _enabled_contam_qc_paths(
            "site_mix",
            "site_mix",
            "site_mix_donors.tsv",
            sample_ids=_site_mix_qc_samples(),
        ),
    output:
        contamination=MDIR + "other_reports/contamination_mqc.tsv",
        site_mix=MDIR + "other_reports/site_mix_contam_mqc.tsv",
        donors=MDIR + "other_reports/site_mix_donor_mqc.tsv",
    params:
        sample_map=_sample_external_ids_json,
    log:
        MDIR + "other_reports/logs/contamination_custom_data.log",
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.contamination:q}) $(dirname {log:q})
        python workflow/scripts/compile_contamination_mqc.py \
          --sample-map-json {params.sample_map:q} \
          --contamination-output {output.contamination:q} \
          --site-mix-output {output.site_mix:q} \
          --donor-output {output.donors:q} \
          --gatk {input.gatk:q} \
          --site-mix {input.site_mix:q} \
          --site-mix-donors {input.site_mix_donors:q} \
          > {log:q} 2>&1
        """


rule produce_site_mix_contam_estimate:  # TARGET: Produce genotype-free site-mix contamination estimates
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/site_mix/{sample}.{alnr}.{ddup}.site_mix.tsv",
            sample=_site_mix_qc_samples(),
            alnr=QC_CRAM_ALIGNERS,
            ddup=qc_contamination_dedupers(),
        ),
        MDIR + "other_reports/site_mix_contam_mqc.tsv",
