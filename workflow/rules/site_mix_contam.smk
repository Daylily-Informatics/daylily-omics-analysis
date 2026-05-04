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


def _parse_contam_path(path):
    parts = str(path).split("/")
    sample = parts[-1].split(".")[0]
    aligner = parts[-1].split(".")[1]
    deduper = parts[-1].split(".")[2]
    external = config.get("sample_info", {}).get(sample, {}).get(
        "external_sample_id", sample
    )
    return sample, str(external), aligner, deduper


def _safe_pct(value):
    try:
        return str(float(value) * 100.0)
    except (TypeError, ValueError):
        return ""

rule site_mix_contam:
    input:
        cram = MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai = MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
        sites_vcf = config["site_mix_contam"]["sites_vcf"],
        sites_vcf_tbi = lambda wildcards: config["site_mix_contam"]["sites_vcf"] + ".tbi",
        ref_fa = config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ref_fai = lambda wildcards: config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
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
        min_af = config["site_mix_contam"]["min_af"],
        max_af = config["site_mix_contam"]["max_af"],
        max_sites = config["site_mix_contam"]["max_sites"],
        min_base_quality = config["site_mix_contam"]["min_base_quality"],
        min_mapping_quality = config["site_mix_contam"]["min_mapping_quality"],
        donor_min_depth = config["site_mix_contam"]["donor_min_depth"],
        max_contamination = config["site_mix_contam"]["max_contamination"],
        grid_step = config["site_mix_contam"]["grid_step"],
        max_candidate_sources = config["site_mix_contam"]["max_candidate_sources"],
    shell:
        r"""
        set -euo pipefail

        outdir="$(dirname {output.tsv})"
        mkdir -p "${{outdir}}" "${{outdir}}/logs"

        candidate_args=()
        if [[ -n "{params.candidate_manifest}" ]]; then
            candidate_args=(--candidate-manifest "{params.candidate_manifest}")
        fi

        bin/util/genotype_free_contam_estimator.py \
          --sample-id "{params.cluster_sample}" \
          --bam {input.cram} \
          --reference {input.ref_fa} \
          --sites-vcf {input.sites_vcf} \
          --output {output.tsv} \
          --donor-output {output.donors} \
          --min-depth {params.min_depth} \
          --max-depth {params.max_depth} \
          --min-sites {params.min_sites} \
          --min-af {params.min_af} \
          --max-af {params.max_af} \
          --max-sites {params.max_sites} \
          --min-base-quality {params.min_base_quality} \
          --min-mapping-quality {params.min_mapping_quality} \
          --donor-min-depth {params.donor_min_depth} \
          --max-contamination {params.max_contamination} \
          --grid-step {params.grid_step} \
          --max-candidate-sources {params.max_candidate_sources} \
          "${{candidate_args[@]}}" \
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
        vb2=_contam_qc_paths("vb2", "vb2.tsv"),
        gatk=_contam_qc_paths("gatk", "gatk.tsv"),
        site_mix=_contam_qc_paths("site_mix", "site_mix.tsv"),
        site_mix_donors=_contam_qc_paths("site_mix", "site_mix_donors.tsv"),
    output:
        contamination=MDIR + "other_reports/contamination_mqc.tsv",
        site_mix=MDIR + "other_reports/site_mix_contam_mqc.tsv",
        donors=MDIR + "other_reports/site_mix_donor_mqc.tsv",
    run:
        os.makedirs(os.path.dirname(str(output.contamination)), exist_ok=True)
        contamination_fields = [
            "sample_id",
            "external_sample_id",
            "aligner",
            "deduper",
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
            "source_path",
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
        with open(output.contamination, "w", newline="") as contam_handle, open(
            output.site_mix, "w", newline=""
        ) as site_handle:
            contam_writer = csv.DictWriter(
                contam_handle, fieldnames=contamination_fields, delimiter="\t"
            )
            site_writer = csv.DictWriter(
                site_handle, fieldnames=contamination_fields, delimiter="\t"
            )
            contam_writer.writeheader()
            site_writer.writeheader()
            for tool, paths in [
                ("verifybamid2", input.vb2),
                ("gatk", input.gatk),
            ]:
                for path in paths:
                    sample, external, aligner, deduper = _parse_contam_path(path)
                    with open(path, newline="") as handle:
                        rows = list(csv.DictReader(handle, delimiter="\t"))
                    row = rows[0] if rows else {}
                    freemix = row.get("FREEMIX", "")
                    contam_writer.writerow(
                        {
                            "sample_id": sample,
                            "external_sample_id": external,
                            "aligner": aligner,
                            "deduper": deduper,
                            "tool": tool,
                            "method": "freemix",
                            "contamination_fraction": freemix,
                            "contamination_pct": _safe_pct(freemix),
                            "ci_low_fraction": "",
                            "ci_high_fraction": "",
                            "unknown_contamination_fraction": "",
                            "unknown_contamination_pct": "",
                            "site_count": row.get("#SNPS", ""),
                            "read_count": row.get("#READS", ""),
                            "mean_depth": row.get("AVG_DP", ""),
                            "source_path": path,
                            "status": "ok" if freemix not in ["", "NA"] else "no_call",
                        }
                    )
            for path in input.site_mix:
                sample, external, aligner, deduper = _parse_contam_path(path)
                with open(path, newline="") as handle:
                    rows = list(csv.DictReader(handle, delimiter="\t"))
                row = rows[0] if rows else {}
                out_row = {
                    "sample_id": sample,
                    "external_sample_id": external,
                    "aligner": aligner,
                    "deduper": deduper,
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
                with open(path, newline="") as handle:
                    for row in csv.DictReader(handle, delimiter="\t"):
                        donor_writer.writerow(
                            {
                                "sample_id": sample,
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
