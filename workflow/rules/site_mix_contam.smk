######### GENOTYPE-FREE SITE MIX CONTAMINATION SCREEN
# - Estimates same-species contamination without target genotype.
# - Optional donor attribution uses a candidate BAM/CRAM/VCF manifest.

import csv
import json
import os


def _contam_qc_paths(tool, suffix):
    return expand(
        MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/contam/"
        + tool
        + "/{sample}.{alnr}.{ddup}."
        + suffix,
        sample=SSAMPS,
        alnr=QC_CRAM_ALIGNERS,
        ddup=qc_contamination_dedupers(),
    )


def _enabled_contam_qc_paths(enabled_tool, tool, suffix):
    if qc_tool_enabled(enabled_tool):
        return _contam_qc_paths(tool, suffix)
    return []


def _verifybamid2_qc_paths(suffix):
    return expand(
        MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/contam/vb2/{vb2panel}/"
        + "{sample}.{alnr}.{ddup}.{vb2panel}."
        + suffix,
        sample=SSAMPS,
        alnr=QC_CRAM_ALIGNERS,
        ddup=qc_contamination_dedupers(),
        vb2panel=VERIFYBAMID2_PANELS,
    )


def _verifybamid2_benchmark_paths():
    return expand(
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{vb2panel}.vb2.bench.tsv",
        sample=SSAMPS,
        alnr=QC_CRAM_ALIGNERS,
        ddup=qc_contamination_dedupers(),
        vb2panel=VERIFYBAMID2_PANELS,
    )


def _enabled_verifybamid2_qc_paths(suffix):
    if qc_tool_enabled("verifybamid2"):
        return _verifybamid2_qc_paths(suffix)
    return []


def _enabled_verifybamid2_benchmarks():
    if qc_tool_enabled("verifybamid2"):
        return _verifybamid2_benchmark_paths()
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


def _parse_vb2_panel_path(path):
    sample, external, aligner, deduper = _parse_contam_path(path)
    marker = f".{aligner}.{deduper}."
    tail = os.path.basename(str(path)).split(marker, 1)
    if len(tail) != 2 or "." not in tail[1]:
        raise ValueError(f"Malformed panel-aware VerifyBamID2 path: {path}")
    return sample, external, aligner, deduper, tail[1].split(".", 1)[0]


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


def _benchmark_by_vb2_key(paths):
    benchmarks = {}
    for path in paths:
        name = os.path.basename(str(path))
        for alnr in QC_CRAM_ALIGNERS:
            for ddup in qc_contamination_dedupers():
                marker = f".{alnr}.{ddup}."
                if marker not in name:
                    continue
                sample = name.split(marker, 1)[0]
                tail = name.split(marker, 1)[1]
                panel = tail.split(".", 1)[0]
                benchmarks[(sample, alnr, ddup, panel)] = path
                break
    return benchmarks


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


def _verifybamid2_panel_metadata_json(wildcards=None):
    metadata = {}
    for panel_id in VERIFYBAMID2_PANELS:
        panel_cfg = _verifybamid2_panel_config(panel_id)
        metadata[panel_id] = {
            "label": str(panel_cfg.get("label", panel_id)),
            "snp_count": str(panel_cfg.get("snp_count", "")),
            "svd_prefix": _supporting_file_name(panel_cfg.get("svd_prefix", "")),
        }
    return json.dumps(metadata)

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

        if [[ -n "{params.candidate_manifest}" ]]; then
            echo "ERROR: site_mix_contam production rule uses GATK pileup tables and does not support candidate_manifest donor attribution. Use the estimator CLI BAM/CRAM mode for donor attribution." >&2
            exit 2
        fi

        bin/util/genotype_free_contam_estimator.py \
          --sample-id "{params.stage_sample}" \
          --counts-tsv {input.pileups} \
          --output {output.tsv} \
          --donor-output {output.donors} \
          --min-depth {params.min_depth} \
          --max-depth {params.max_depth} \
          --min-sites {params.min_sites} \
          --max-contamination {params.max_contamination} \
          --grid-step {params.grid_step} \
          > {log} 2>&1

        test -s {output.tsv}
        test -s {output.donors}
        touch {output.stamp}
        """


localrules:
    contamination_mqc_gather,
    produce_site_mix_contam_estimate,


rule contamination_mqc_gather:
    input:
        vb2=lambda wildcards: _enabled_verifybamid2_qc_paths("vb2.tsv"),
        vb2_bench=lambda wildcards: _enabled_verifybamid2_benchmarks(),
        gatk=lambda wildcards: _enabled_contam_qc_paths("gatk_contam", "gatk", "gatk.tsv"),
        site_mix=lambda wildcards: _enabled_contam_qc_paths(
            "site_mix", "site_mix", "site_mix.tsv"
        ),
        site_mix_donors=lambda wildcards: _enabled_contam_qc_paths(
            "site_mix", "site_mix", "site_mix_donors.tsv"
        ),
    output:
        contamination=MDIR + "other_reports/contamination_mqc.tsv",
        vb2_comparison=MDIR + "other_reports/verifybamid2_panel_comparison_mqc.tsv",
        site_mix=MDIR + "other_reports/site_mix_contam_mqc.tsv",
        donors=MDIR + "other_reports/site_mix_donor_mqc.tsv",
    params:
        sample_map=_sample_external_ids_json,
        panel_metadata=_verifybamid2_panel_metadata_json,
    log:
        MDIR + "other_reports/logs/contamination_custom_data.log",
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.contamination:q}) $(dirname {log:q})
        python workflow/scripts/compile_contamination_mqc.py \
          --sample-map-json {params.sample_map:q} \
          --panel-metadata-json {params.panel_metadata:q} \
          --contamination-output {output.contamination:q} \
          --vb2-comparison-output {output.vb2_comparison:q} \
          --site-mix-output {output.site_mix:q} \
          --donor-output {output.donors:q} \
          --vb2 {input.vb2:q} \
          --vb2-bench {input.vb2_bench:q} \
          --gatk {input.gatk:q} \
          --site-mix {input.site_mix:q} \
          --site-mix-donors {input.site_mix_donors:q} \
          > {log:q} 2>&1
        """


rule produce_site_mix_contam_estimate:  # TARGET: Produce genotype-free site-mix contamination estimates
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/site_mix/{sample}.{alnr}.{ddup}.site_mix.tsv",
            sample=SSAMPS,
            alnr=QC_CRAM_ALIGNERS,
            ddup=qc_contamination_dedupers(),
        ),
        MDIR + "other_reports/site_mix_contam_mqc.tsv",
