import os


TRUVARI_SV_SUPPORTED_CALLERS = {"dysgu", "manta", "tiddit"}
TRUVARI_SV_TRUTH_REQUIRED_KEYS = ("truth_vcf", "truth_tbi", "truth_bed")


def _truvari_sv_config():
    cfg = config.get("truvari_sv_benchmark")
    if not isinstance(cfg, dict):
        raise WorkflowError(
            "Truvari SV benchmarking requires config['truvari_sv_benchmark'] with "
            "explicit per-sample truthsets."
        )
    return cfg


def _truvari_sv_truthsets():
    truthsets = _truvari_sv_config().get("truthsets")
    if not isinstance(truthsets, dict) or not truthsets:
        raise WorkflowError(
            "Truvari SV benchmarking requires non-empty "
            "config['truvari_sv_benchmark']['truthsets']."
        )
    return truthsets


def _truvari_sv_enabled_callers():
    unknown = sorted(set(sv_CALLERS) - TRUVARI_SV_SUPPORTED_CALLERS)
    if unknown:
        raise WorkflowError(
            "Truvari SV benchmarking only supports callers "
            f"{sorted(TRUVARI_SV_SUPPORTED_CALLERS)}; unsupported sv_callers: {unknown}"
        )
    return sorted(caller for caller in sv_CALLERS if caller in TRUVARI_SV_SUPPORTED_CALLERS)


def _truvari_sv_truth_sample_entry(sample):
    return _truvari_sv_truthsets().get(str(sample), {})


def _truvari_sv_truth_regions(sample):
    sample_entry = _truvari_sv_truth_sample_entry(sample)
    if not sample_entry:
        return {}
    regions = sample_entry.get("regions")
    if not isinstance(regions, dict) or not regions:
        raise WorkflowError(
            "Truvari SV benchmarking truthset for sample "
            f"{sample} requires a non-empty 'regions' mapping."
        )
    return regions


def _truvari_sv_truth_region_entry(sample, roi):
    regions = _truvari_sv_truth_regions(sample)
    if str(roi) not in regions:
        raise WorkflowError(
            f"Truvari SV truth ROI '{roi}' is not configured for sample {sample}."
        )
    entry = regions[str(roi)]
    if not isinstance(entry, dict):
        raise WorkflowError(
            f"Truvari SV truth ROI '{roi}' for sample {sample} must be a mapping."
        )
    missing = [
        key
        for key in TRUVARI_SV_TRUTH_REQUIRED_KEYS
        if not str(entry.get(key, "")).strip()
    ]
    if missing:
        raise WorkflowError(
            f"Truvari SV truth ROI '{roi}' for sample {sample} is missing: {missing}."
        )
    return entry


def _truvari_sv_samples():
    truth_samples = sorted(str(sample) for sample in _truvari_sv_truthsets())
    unknown = sorted(set(truth_samples) - set(SAMPS))
    if unknown:
        raise WorkflowError(
            "Truvari SV truthsets are configured for sample IDs not present in "
            f"config/samples.tsv: {unknown}"
        )
    return truth_samples


def _truvari_sv_alt_id(wildcards):
    sample_entry = _truvari_sv_truth_sample_entry(wildcards.sample)
    alt_id = str(sample_entry.get("alt_id", "")).strip()
    if not alt_id:
        raise WorkflowError(
            f"Truvari SV truthset for sample {wildcards.sample} requires explicit alt_id."
        )
    return alt_id


def _truvari_sv_stage_sample(wildcards):
    return day_stage_sample_id(
        wildcards.sample,
        wildcards.alnr,
        wildcards.ddup,
        wildcards.svcaller,
    )


def _truvari_sv_query_vcf(wildcards):
    return (
        MDIR
        + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/sv/"
        + f"{wildcards.svcaller}/{wildcards.sample}.{wildcards.alnr}."
        + f"{wildcards.svcaller}.sv.sort.vcf.gz"
    )


def _truvari_sv_query_tbi(wildcards):
    return _truvari_sv_query_vcf(wildcards) + ".tbi"


def _truvari_sv_truth_vcf(wildcards):
    return str(
        _truvari_sv_truth_region_entry(wildcards.sample, wildcards.roi)["truth_vcf"]
    )


def _truvari_sv_truth_tbi(wildcards):
    return str(
        _truvari_sv_truth_region_entry(wildcards.sample, wildcards.roi)["truth_tbi"]
    )


def _truvari_sv_truth_bed(wildcards):
    return str(
        _truvari_sv_truth_region_entry(wildcards.sample, wildcards.roi)["truth_bed"]
    )


def _truvari_sv_extra_args(wildcards):
    return str(_truvari_sv_config().get("extra_args", "")).strip()


def _truvari_sv_thread_count(wildcards):
    return int(_truvari_sv_config().get("threads", 8))


def _truvari_sv_mem_mb(wildcards):
    return int(_truvari_sv_config().get("mem_mb", 32000))


def _truvari_sv_partition(wildcards):
    return str(_truvari_sv_config().get("partition", "i192mem,i192bigmem"))


def _truvari_sv_jobs():
    truth_samples = _truvari_sv_samples()
    callers = _truvari_sv_enabled_callers()
    if not callers:
        raise WorkflowError(
            "Truvari SV benchmarking requires at least one supported sv_caller "
            f"from {sorted(TRUVARI_SV_SUPPORTED_CALLERS)}."
        )
    jobs = []
    for sample in truth_samples:
        regions = _truvari_sv_truth_regions(sample)
        for ddup in DDUP:
            for alnr in QC_CRAM_ALIGNERS:
                for svcaller in callers:
                    for roi in sorted(regions):
                        jobs.append(
                            {
                                "sample": sample,
                                "alnr": alnr,
                                "ddup": ddup,
                                "svcaller": svcaller,
                                "roi": roi,
                            }
                        )
    if not jobs:
        raise WorkflowError(
            "Truvari SV benchmarking selected no jobs; check aligners, dedupers, "
            "sv_callers, and truvari_sv_benchmark.truthsets."
        )
    return jobs


def _truvari_sv_mqc_path(sample, alnr, ddup, svcaller, roi):
    return (
        MDIR
        + f"{sample}/align/{alnr}/{ddup}/sv/{svcaller}/concordance/_{roi}/"
        + f"sv_{sample}_{roi}_{svcaller}_concordance.mqc.tsv"
    )


def _truvari_sv_done_path(sample, alnr, ddup, svcaller):
    return (
        MDIR
        + f"{sample}/align/{alnr}/{ddup}/sv/{svcaller}/concordance/"
        + "truvari_sv_concordance.done"
    )


def truvari_sv_mqc_outputs(wildcards):
    regions = _truvari_sv_truth_regions(wildcards.sample)
    return [
        _truvari_sv_mqc_path(
            wildcards.sample,
            wildcards.alnr,
            wildcards.ddup,
            wildcards.svcaller,
            roi,
        )
        for roi in sorted(regions)
    ]


def all_truvari_sv_mqc_outputs():
    return sorted(
        _truvari_sv_mqc_path(
            job["sample"],
            job["alnr"],
            job["ddup"],
            job["svcaller"],
            job["roi"],
        )
        for job in _truvari_sv_jobs()
    )


def all_truvari_sv_done_outputs():
    seen = set()
    paths = []
    for job in _truvari_sv_jobs():
        key = (job["sample"], job["alnr"], job["ddup"], job["svcaller"])
        if key in seen:
            continue
        seen.add(key)
        paths.append(_truvari_sv_done_path(*key))
    return sorted(paths)


rule truvari_sv_benchmark_roi:
    input:
        query_vcf=_truvari_sv_query_vcf,
        query_tbi=_truvari_sv_query_tbi,
        truth_vcf=_truvari_sv_truth_vcf,
        truth_tbi=_truvari_sv_truth_tbi,
        truth_bed=_truvari_sv_truth_bed,
    output:
        summary=MDIR
        + "{sample}/align/{alnr}/{ddup}/sv/{svcaller}/concordance/_{roi}/summary.json",
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/sv/{svcaller}/concordance/logs/"
        + "{sample}.{alnr}.{ddup}.{svcaller}.{roi}.truvari_sv_benchmark.log",
    benchmark:
        MDIR
        + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{svcaller}.{roi}.truvari_sv_benchmark.bench.tsv",
    threads:
        _truvari_sv_thread_count
    resources:
        vcpu=_truvari_sv_thread_count,
        threads=_truvari_sv_thread_count,
        mem_mb=_truvari_sv_mem_mb,
        partition=_truvari_sv_partition,
    conda:
        config.get("truvari_sv_benchmark", {}).get("env_yaml", "../envs/truvari_v0.1.yaml")
    params:
        reference=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        extra_args=_truvari_sv_extra_args,
        alt_id=_truvari_sv_alt_id,
        stage_sample=_truvari_sv_stage_sample,
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail

        outdir="$(dirname {output.summary:q})"
        rm -rf "$outdir"
        mkdir -p "$outdir" "$(dirname {log:q})"

        truvari bench \
          -b {input.truth_vcf:q} \
          -c {input.query_vcf:q} \
          -f {params.reference:q} \
          -o "$outdir" \
          --includebed {input.truth_bed:q} \
          --bSample {params.alt_id:q} \
          --cSample {wildcards.sample:q} \
          {params.extra_args} \
          > {log:q} 2>&1

        test -s {output.summary:q}
        """


rule parse_truvari_sv_summary_roi:
    input:
        summary=rules.truvari_sv_benchmark_roi.output.summary,
    output:
        mqc=MDIR
        + "{sample}/align/{alnr}/{ddup}/sv/{svcaller}/concordance/_{roi}/"
        + "sv_{sample}_{roi}_{svcaller}_concordance.mqc.tsv",
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/sv/{svcaller}/concordance/logs/"
        + "{sample}.{alnr}.{ddup}.{svcaller}.{roi}.parse_truvari_summary.log",
    benchmark:
        MDIR
        + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{svcaller}.{roi}.parse_truvari_summary.bench.tsv",
    conda:
        config.get("truvari_sv_benchmark", {}).get("env_yaml", "../envs/truvari_v0.1.yaml")
    params:
        stage_sample=_truvari_sv_stage_sample,
        alt_id=_truvari_sv_alt_id,
        truth_vcf=_truvari_sv_truth_vcf,
        query_vcf=_truvari_sv_query_vcf,
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output.mqc:q})" "$(dirname {log:q})"
        python workflow/scripts/parse_truvari_summary.py one \
          --summary {input.summary:q} \
          --output {output.mqc:q} \
          --sample {wildcards.sample:q} \
          --stage-sample {params.stage_sample:q} \
          --roi {wildcards.roi:q} \
          --alt-id {params.alt_id:q} \
          --aligner {wildcards.alnr:q} \
          --deduper {wildcards.ddup:q} \
          --sv-caller {wildcards.svcaller:q} \
          --truth-vcf {params.truth_vcf:q} \
          --query-vcf {params.query_vcf:q} \
          > {log:q} 2>&1
        test -s {output.mqc:q}
        """


rule prep_for_truvari_sv_concordance:
    input:
        query_vcf=_truvari_sv_query_vcf,
        query_tbi=_truvari_sv_query_tbi,
        mqcs=truvari_sv_mqc_outputs,
    output:
        done=touch(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/sv/{svcaller}/concordance/truvari_sv_concordance.done"
        ),
        fofn=touch(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/sv/{svcaller}/concordance/truvari_sv_concordance.fofn"
        ),
        fin_cmds=touch(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/sv/{svcaller}/concordance/truvari_sv_concordance.fin.cmds"
        ),
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/sv/{svcaller}/concordance/logs/"
        + "{sample}.{alnr}.{ddup}.{svcaller}.truvari_sv_concordance.log",
    benchmark:
        MDIR
        + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{svcaller}.truvari_sv_concordance.bench.tsv",
    conda:
        config.get("truvari_sv_benchmark", {}).get("env_yaml", "../envs/truvari_v0.1.yaml")
    params:
        regions=lambda wildcards: ",".join(
            sorted(_truvari_sv_truth_regions(wildcards.sample))
        ),
        nmqcs=lambda wildcards, input: len(input.mqcs),
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail

        mkdir -p "$(dirname {output.done:q})" "$(dirname {log:q})"
        utc_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

        {{
            echo "# Truvari SV per-ROI jobs are scheduled by Snakemake; this file is informational."
            echo "# generated_at_utc=$utc_ts"
            echo "# regions={params.regions}"
            for mqc in {input.mqcs:q}; do
                echo "$mqc"
            done
        }} > {output.fofn:q}

        {{
            echo "# See Snakemake DAG for exact Truvari commands."
            echo "# generated_at_utc=$utc_ts"
        }} > {output.fin_cmds:q}

        echo "Truvari SV concordance sentinel complete. regions={params.regions} mqcs={params.nmqcs}" >> {log:q}
        """


localrules: produce_sv_concordances
rule produce_sv_concordances:  # TARGET: produce Truvari SV concordances
    input:
        dones=lambda wildcards: all_truvari_sv_done_outputs(),
        mqcs=lambda wildcards: all_truvari_sv_mqc_outputs(),
    priority: 48
    output:
        mqc=MDIR + "other_reports/giab_sv_concordance_mqc.tsv",
    params:
        cluster_sample="aggregate",
    shell:
        r"""
        set -euo pipefail
        mkdir -p "$(dirname {output.mqc:q})"
        python workflow/scripts/parse_truvari_summary.py aggregate \
          --output {output.mqc:q} \
          {input.mqcs:q}
        """
