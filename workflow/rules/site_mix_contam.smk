######### GENOTYPE-FREE SITE MIX CONTAMINATION SCREEN
# - Estimates same-species contamination without target genotype.
# - Optional donor attribution uses a candidate BAM/CRAM/VCF manifest.

import csv
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
        ddup=qc_alignment_dedupers(),
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
        ddup=qc_alignment_dedupers(),
        vb2panel=VERIFYBAMID2_PANELS,
    )


def _verifybamid2_benchmark_paths():
    return expand(
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{vb2panel}.vb2.bench.tsv",
        sample=SSAMPS,
        alnr=QC_CRAM_ALIGNERS,
        ddup=qc_alignment_dedupers(),
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
        for ddup in qc_alignment_dedupers():
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
            for ddup in qc_alignment_dedupers():
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
          --sample-id "{params.cluster_sample}" \
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
        gatk=lambda wildcards: _enabled_contam_qc_paths("gatk_contam", "gatk", "contam.tsv"),
        site_mix=lambda wildcards: _enabled_contam_qc_paths(
            "site_mix", "site_mix", "site_mix.tsv"
        ),
        site_mix_donors=lambda wildcards: _enabled_contam_qc_paths(
            "site_mix", "site_mix", "site_mix_donors.tsv"
        ),
    output:
        contamination=MDIR + "other_reports/contamination_mqc.tsv",
        gatk=MDIR + "other_reports/gatk_contam_mqc.tsv",
        vb2_comparison=MDIR + "other_reports/verifybamid2_panel_comparison_mqc.tsv",
        site_mix=MDIR + "other_reports/site_mix_contam_mqc.tsv",
        donors=MDIR + "other_reports/site_mix_donor_mqc.tsv",
    run:
        os.makedirs(os.path.dirname(str(output.contamination)), exist_ok=True)
        contamination_fields = [
            "sample_id",
            "external_sample_id",
            "aligner",
            "deduper",
            "panel_id",
            "panel_label",
            "tool",
            "method",
            "contamination_fraction",
            "contamination_pct",
            "ci_low_fraction",
            "ci_high_fraction",
            "unknown_contamination_fraction",
            "unknown_contamination_pct",
            "site_count",
            "read_count",
            "mean_depth",
            "svd_prefix",
            "source_path",
            "status",
        ]
        vb2_fields = [
            "sample_id",
            "external_sample_id",
            "aligner",
            "deduper",
            "panel_id",
            "panel_label",
            "snp_count",
            "svd_prefix",
            "freemix_fraction",
            "contamination_pct",
            "site_count",
            "read_count",
            "mean_depth",
            "runtime_seconds",
            "runtime_minutes",
            "task_cost",
            "source_path",
            "benchmark_path",
            "status",
        ]
        donor_fields = [
            "sample_id",
            "external_sample_id",
            "aligner",
            "deduper",
            "source_rank",
            "source_sample_id",
            "is_unknown_source",
            "contamination_fraction",
            "contamination_pct",
            "single_source_delta_log_likelihood",
            "source_path",
        ]
        gatk_fields = contamination_fields + [
            "gatk_sample_id",
            "gatk_error_fraction",
        ]
        with open(output.contamination, "w", newline="") as contam_handle, open(
            output.site_mix, "w", newline=""
        ) as site_handle, open(output.vb2_comparison, "w", newline="") as vb2_handle, open(
            output.gatk, "w", newline=""
        ) as gatk_handle:
            contam_writer = csv.DictWriter(
                contam_handle, fieldnames=contamination_fields, delimiter="\t"
            )
            site_writer = csv.DictWriter(
                site_handle, fieldnames=contamination_fields, delimiter="\t"
            )
            vb2_writer = csv.DictWriter(
                vb2_handle, fieldnames=vb2_fields, delimiter="\t"
            )
            gatk_writer = csv.DictWriter(
                gatk_handle, fieldnames=gatk_fields, delimiter="\t"
            )
            contam_writer.writeheader()
            site_writer.writeheader()
            vb2_writer.writeheader()
            gatk_writer.writeheader()
            vb2_benchmarks = _benchmark_by_vb2_key(input.vb2_bench)
            for path in input.vb2:
                sample, external, aligner, deduper, panel_id = _parse_vb2_panel_path(path)
                sample_id = day_stage_sample_id(sample, aligner, deduper)
                with open(path, newline="") as handle:
                    rows = list(csv.DictReader(handle, delimiter="\t"))
                row = rows[0] if rows else {}
                freemix = row.get("FREEMIX", "")
                panel_cfg = _verifybamid2_panel_config(panel_id)
                benchmark_path = vb2_benchmarks.get((sample, aligner, deduper, panel_id), "")
                benchmark = _read_benchmark_row(benchmark_path)
                runtime_seconds = benchmark.get("s", "")
                panel_label = str(panel_cfg.get("label", panel_id))
                snp_count = str(panel_cfg.get("snp_count", row.get("#SNPS", "")))
                svd_prefix = _supporting_file_name(panel_cfg["svd_prefix"])
                contam_row = {
                    "sample_id": sample_id,
                    "external_sample_id": external,
                    "aligner": aligner,
                    "deduper": deduper,
                    "panel_id": panel_id,
                    "panel_label": panel_label,
                    "tool": "verifybamid2",
                    "method": "freemix",
                    "contamination_fraction": freemix,
                    "contamination_pct": _safe_pct(freemix),
                    "ci_low_fraction": "",
                    "ci_high_fraction": "",
                    "unknown_contamination_fraction": "",
                    "unknown_contamination_pct": "",
                    "site_count": row.get("#SNPS", snp_count),
                    "read_count": row.get("#READS", ""),
                    "mean_depth": row.get("AVG_DP", ""),
                    "svd_prefix": svd_prefix,
                    "source_path": path,
                    "status": "ok" if freemix not in ["", "NA"] else "no_call",
                }
                contam_writer.writerow(contam_row)
                vb2_writer.writerow(
                    {
                        "sample_id": sample_id,
                        "external_sample_id": external,
                        "aligner": aligner,
                        "deduper": deduper,
                        "panel_id": panel_id,
                        "panel_label": panel_label,
                        "snp_count": snp_count,
                        "svd_prefix": svd_prefix,
                        "freemix_fraction": freemix,
                        "contamination_pct": _safe_pct(freemix),
                        "site_count": row.get("#SNPS", snp_count),
                        "read_count": row.get("#READS", ""),
                        "mean_depth": row.get("AVG_DP", ""),
                        "runtime_seconds": runtime_seconds,
                        "runtime_minutes": _seconds_to_minutes(runtime_seconds),
                        "task_cost": benchmark.get("task_cost", ""),
                        "source_path": path,
                        "benchmark_path": benchmark_path,
                        "status": contam_row["status"],
                    }
                )
            for path in input.gatk:
                sample, external, aligner, deduper = _parse_contam_path(path)
                sample_id = day_stage_sample_id(sample, aligner, deduper)
                with open(path, newline="") as handle:
                    rows = list(csv.DictReader(handle, delimiter="\t"))
                row = rows[0] if rows else {}
                if "contamination" not in row:
                    raise ValueError(
                        f"GATK contamination table missing contamination column: {path}"
                    )
                contamination = row.get("contamination", "")
                out_row = {
                    "sample_id": sample_id,
                    "external_sample_id": external,
                    "aligner": aligner,
                    "deduper": deduper,
                    "panel_id": "",
                    "panel_label": "",
                    "tool": "gatk",
                    "method": "calculate_contamination",
                    "contamination_fraction": contamination,
                    "contamination_pct": _safe_pct(contamination),
                    "ci_low_fraction": "",
                    "ci_high_fraction": "",
                    "unknown_contamination_fraction": "",
                    "unknown_contamination_pct": "",
                    "site_count": "",
                    "read_count": "",
                    "mean_depth": "",
                    "svd_prefix": "",
                    "source_path": path,
                    "status": "ok" if contamination not in ["", "NA"] else "no_call",
                }
                contam_writer.writerow(out_row)
                gatk_writer.writerow(
                    {
                        **out_row,
                        "gatk_sample_id": row.get("sample", ""),
                        "gatk_error_fraction": row.get("error", ""),
                    }
                )
            for path in input.site_mix:
                sample, external, aligner, deduper = _parse_contam_path(path)
                sample_id = day_stage_sample_id(sample, aligner, deduper)
                with open(path, newline="") as handle:
                    rows = list(csv.DictReader(handle, delimiter="\t"))
                row = rows[0] if rows else {}
                out_row = {
                    "sample_id": sample_id,
                    "external_sample_id": external,
                    "aligner": aligner,
                    "deduper": deduper,
                    "panel_id": "",
                    "panel_label": "",
                    "tool": "site_mix",
                    "method": row.get("method", "genotype_free_site_mix"),
                    "contamination_fraction": row.get("contamination_fraction", ""),
                    "contamination_pct": row.get("contamination_pct", ""),
                    "ci_low_fraction": row.get("ci_low_fraction", ""),
                    "ci_high_fraction": row.get("ci_high_fraction", ""),
                    "unknown_contamination_fraction": row.get(
                        "unknown_contamination_fraction", ""
                    ),
                    "unknown_contamination_pct": row.get("unknown_contamination_pct", ""),
                    "site_count": row.get("site_count", ""),
                    "read_count": row.get("read_count", ""),
                    "mean_depth": row.get("mean_depth", ""),
                    "svd_prefix": "",
                    "source_path": path,
                    "status": "ok"
                    if row.get("contamination_fraction", "") not in ["", "NA"]
                    else "no_call",
                }
                contam_writer.writerow(out_row)
                site_writer.writerow(out_row)
        with open(output.donors, "w", newline="") as donor_handle:
            donor_writer = csv.DictWriter(
                donor_handle, fieldnames=donor_fields, delimiter="\t"
            )
            donor_writer.writeheader()
            for path in input.site_mix_donors:
                sample, external, aligner, deduper = _parse_contam_path(path)
                sample_id = day_stage_sample_id(sample, aligner, deduper)
                with open(path, newline="") as handle:
                    for row in csv.DictReader(handle, delimiter="\t"):
                        donor_writer.writerow(
                            {
                                "sample_id": sample_id,
                                "external_sample_id": external,
                                "aligner": aligner,
                                "deduper": deduper,
                                "source_rank": row.get("source_rank", ""),
                                "source_sample_id": row.get("source_sample_id", ""),
                                "is_unknown_source": row.get("is_unknown_source", ""),
                                "contamination_fraction": row.get(
                                    "contamination_fraction", ""
                                ),
                                "contamination_pct": row.get("contamination_pct", ""),
                                "single_source_delta_log_likelihood": row.get(
                                    "single_source_delta_log_likelihood", ""
                                ),
                                "source_path": path,
                            }
                        )


rule produce_site_mix_contam_estimate:  # TARGET: Produce genotype-free site-mix contamination estimates
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/contam/site_mix/{sample}.{alnr}.{ddup}.site_mix.tsv",
            sample=SSAMPS,
            alnr=QC_CRAM_ALIGNERS,
            ddup=qc_alignment_dedupers(),
        ),
        MDIR + "other_reports/site_mix_contam_mqc.tsv",
