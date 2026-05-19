import os

from snakemake.exceptions import WorkflowError

# This rule set gathers staged QC outputs and produces the public MultiQC
# reports.  Runtime-gated tools are still available as first-class rules, but
# they are kept out of routine MultiQC targets unless explicitly enabled.

RPT_TITLE = os.environ.get("RPT_TITLE", "Final")


def _seq_data_component_inputs(wildcards):
    paths = _sequence_qc_native_inputs(wildcards)
    if qc_tool_enabled("bclconvert", default=False):
        paths.append(MDIR + "other_reports/bclconvert_metrics_mqc.done")
    paths.append(MDIR + "other_reports/sequence_qc_outputs_mqc.tsv")
    return paths


def _sequence_qc_native_inputs(wildcards):
    paths = []
    if qc_tool_enabled("fastqc"):
        paths.extend(
            expand(
                MDIR + "{sample}/seqqc/fastqc/{sample}.fastqc.done",
                sample=FASTQ_QC_SAMPS,
            )
        )
    if qc_tool_enabled("seqfu"):
        paths.append(MDIR + "other_reports/seqfu_mqc.tsv")
    if qc_tool_enabled("fastv", long_running=True):
        paths.extend(
            expand(
                [
                    MDIR + "{sample}/seqqc/fastv/{sample}.fastv.json",
                    MDIR + "{sample}/seqqc/fastv/{sample}.fastv.html",
                ],
                sample=FASTQ_QC_SAMPS,
            )
        )
    return paths


def _alignment_component_inputs(wildcards):
    paths = list(_seq_data_component_inputs(wildcards))
    paths.extend(_alignment_qc_native_inputs(wildcards))
    paths.extend(_unmapped_metagenomics_component_inputs(wildcards))
    paths.append(MDIR + "other_reports/alignment_qc_outputs_mqc.tsv")
    if (
        qc_tool_enabled("verifybamid2")
        or qc_tool_enabled("gatk_contam")
        or qc_tool_enabled("site_mix")
    ):
        paths.append(MDIR + "other_reports/contamination_mqc.tsv")
    if qc_tool_enabled("verifybamid2"):
        paths.append(MDIR + "other_reports/verifybamid2_panel_comparison_mqc.tsv")
    if qc_tool_enabled("site_mix"):
        paths.extend(
            [
                MDIR + "other_reports/site_mix_contam_mqc.tsv",
                MDIR + "other_reports/site_mix_donor_mqc.tsv",
            ]
        )
    if qc_tool_enabled("relatedness"):
        paths.append(MDIR + "other_reports/relatedness_mqc.tsv")
        paths.extend(_relatedness_native_inputs(wildcards))
    return paths


def _unmapped_metagenomics_enabled_for_multiqc():
    return qc_tool_enabled(
        "unmapped_metagenomics", long_running=True, default=False
    )


def _validate_unmapped_metagenomics_multiqc_config():
    cfg = config.get("unmapped_metagenomics")
    if not isinstance(cfg, dict):
        raise WorkflowError(
            "Final MultiQC includes unmapped metagenomics only when explicitly "
            "enabled with multiqc_qc.enable_tools=['unmapped_metagenomics'] "
            "and configured with unmapped_metagenomics.kraken2_db, threads, "
            "mem_mb, and partition."
        )
    missing = [
        key
        for key in ("kraken2_db", "threads", "mem_mb", "partition")
        if str(cfg.get(key, "")).strip() in {"", "None", "none", "na", "NA"}
    ]
    if missing:
        raise WorkflowError(
            "Final MultiQC unmapped metagenomics is enabled but missing "
            "explicit config value(s): "
            + ", ".join(f"unmapped_metagenomics.{key}" for key in missing)
        )
    read_limit = str(cfg.get("read_limit", "all")).strip()
    if read_limit != "all":
        raise WorkflowError(
            "Final MultiQC unmapped metagenomics requires "
            "unmapped_metagenomics.read_limit='all'."
        )


def _unmapped_metagenomics_component_inputs(wildcards):
    if not _unmapped_metagenomics_enabled_for_multiqc():
        return []
    _validate_unmapped_metagenomics_multiqc_config()
    aligners = sorted(ALL_ALIGNERS)
    dedupers = qc_contamination_dedupers()
    if not aligners:
        raise WorkflowError(
            "Final MultiQC unmapped metagenomics requires at least one active aligner."
        )
    if not dedupers:
        raise WorkflowError(
            "Final MultiQC unmapped metagenomics requires at least one real deduper."
        )
    paths = [MDIR + "other_reports/unmapped_metagenomics_mqc.tsv"]
    paths.extend(
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
            + "{sample}.{alnr}.{ddup}.kraken2.quick.report.txt",
            sample=SSAMPS,
            alnr=aligners,
            ddup=dedupers,
        )
    )
    return paths


def _alignment_qc_native_inputs(wildcards):
    paths = []
    qddups = qc_alignment_dedupers()
    contam_ddups = qc_contamination_dedupers()
    alnrs = QC_CRAM_ALIGNERS
    paths.append(MDIR + "other_reports/alignstats_combo_mqc.tsv")
    paths.append(MDIR + "other_reports/norm_cov_evenness_combo_mqc.tsv")
    paths.extend(
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/alignqc/samtmetrics/{sample}.{alnr}.{ddup}.complete",
            sample=SSAMPS,
            alnr=alnrs,
            ddup=qddups,
        )
    )
    paths.append(MDIR + "other_reports/samtools_metrics_gather.done")
    paths.extend(
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/{sample}.{alnr}.{ddup}.mosdepth.summary.txt",
            sample=SSAMPS,
            alnr=alnrs,
            ddup=qddups,
        )
    )
    paths.extend(
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/goleft.done",
            sample=SSAMPS,
            alnr=alnrs,
            ddup=qddups,
        )
    )
    paths.extend(
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/alignqc/norm_cov_eveness/{sample}.{alnr}.{ddup}.md",
            sample=SSAMPS,
            alnr=alnrs,
            ddup=qddups,
        )
    )
    if qc_tool_enabled("verifybamid2"):
        paths.extend(
            expand(
                MDIR
                + "{sample}/align/{alnr}/{ddup}/alignqc/contam/vb2/{vb2panel}/{sample}.{alnr}.{ddup}.{vb2panel}.vb2.tsv",
                sample=SSAMPS,
                alnr=alnrs,
                ddup=contam_ddups,
                vb2panel=VERIFYBAMID2_PANELS,
            )
        )
    if qc_tool_enabled("gatk_contam"):
        paths.extend(
            expand(
                MDIR
                + "{sample}/align/{alnr}/{ddup}/alignqc/contam/gatk/{sample}.{alnr}.{ddup}.gatk.tsv",
                sample=SSAMPS,
                alnr=alnrs,
                ddup=contam_ddups,
            )
        )
    return paths


def _relatedness_native_inputs(wildcards):
    paths = []
    qddups = qc_variant_dedupers()
    alnrs = QC_CRAM_ALIGNERS
    paths.extend(
        expand(
            MDIR
            + "other_reports/relatedness/{alnr}/{ddup}/somalier/cohort.samples.tsv",
            alnr=alnrs,
            ddup=qddups,
        )
    )
    paths.extend(
        expand(
            MDIR
            + "other_reports/relatedness/{alnr}/{ddup}/somalier/cohort.pairs.tsv",
            alnr=alnrs,
            ddup=qddups,
        )
    )
    return paths


def _variant_component_inputs(wildcards):
    paths = list(_alignment_component_inputs(wildcards))
    pairs = valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)
    paths.append(MDIR + "other_reports/bcftools_variant_stats_mqc.tsv")
    paths.append(MDIR + "other_reports/rtg_vcfstats_mqc.tsv")
    paths.extend(_sv_component_inputs(wildcards))
    if qc_tool_enabled("peddy"):
        paths.extend(["logs/peddy_gathered.done", MDIR + "other_reports/peddy_sample_qc_mqc.tsv"])
    if (
        qc_tool_enabled("expansionhunter")
        and set(ALIGNERS) & EXPANSIONHUNTER_ALIGNERS
        and expansionhunter_report_targets_available()
    ):
        paths.append(MDIR + "other_reports/expansionhunter_mqc.tsv")
    if qc_tool_enabled("vep", long_running=True):
        paths.append(MDIR + "other_reports/vep_annotation_mqc.tsv")
    if HTD_CALLERS:
        paths.append(MDIR + "other_reports/htd_calls_mqc.tsv")
    if len(CONCORDANCE_SAMPLES.keys()) > 0 and pairs:
        paths.append(MDIR + "other_reports/giab_concordance_mqc.tsv")
    return paths


def _sv_component_inputs(wildcards):
    paths = []
    if "tiddit" in sv_CALLERS:
        paths.append(MDIR + "other_reports/tiddit_sv_mqc.tsv")
    if (
        config.get("truvari_sv_benchmark", {}).get("truthsets")
        and set(sv_CALLERS) & {"dysgu", "manta", "tiddit"}
    ):
        paths.append(MDIR + "other_reports/giab_sv_concordance_mqc.tsv")
    return paths


def _final_component_inputs(wildcards):
    return _variant_component_inputs(wildcards)


def _multiqc_stage_component_inputs(wildcards):
    stage = wildcards.report_stage
    if stage == "seq_data":
        return _seq_data_component_inputs(wildcards)
    if stage == "alignment":
        return _alignment_component_inputs(wildcards)
    if stage == "variants":
        return _variant_component_inputs(wildcards)
    if stage == "final":
        return _final_component_inputs(wildcards) + [
            MDIR + "other_reports/rules_benchmark_data_mqc.tsv"
        ]
    raise ValueError(f"Unknown MultiQC report stage: {stage}")


localrules:
    collect_rules_benchmark_data,
    collect_rules_benchmark_data_singleton,
    sequence_qc_outputs_custom_data,
    alignment_qc_outputs_custom_data,
    stage_multiqc_inputs,
    aggregate_report_components,
    produce_multiqc_input_data,
    produce_multiqc_cram,
    produce_multiqc_snv,
    produce_multiqc_sv,
    produce_multiqc_sample_qc,
    produce_multiqc_variant_annotation,
    produce_multiqc_all,
    produce_multiqc_stage_final,
    produce_multiqc_seq_data,
    produce_multiqc_alignment,
    produce_multiqc_variants,
    produce_multiqc_final,
    produce_multiqc_final_wgs,


rule collect_rules_benchmark_data:
    input:
        f"{MDIR}logs/report_components_aggregated.done",
    output:
        f"{MDIR}other_reports/rules_benchmark_data_mqc.tsv",
    params:
        cluster_sample="rules_benchmark_collect",
        working_file=f"{MDIR}reports/benchmarks_summary.tsv",
        ref_code=config["genome_build"],
    log:
        f"{MDIR}other_reports/logs/rules_benchmarks_summary.log",
    container: None
    shell:
        "bin/util/benchmarks/collect_day_benchmark_data.sh {params.ref_code} > {log};"
        "python bin/util/benchmarks/split_bench_rule_col.py {params.working_file} {output} > {log};"
        "sed -i -E 's/\t$/\tNA/' {output};"


rule collect_rules_benchmark_data_singleton:  # TARGET: collect benchmarks
    output:
        f"{MDIR}other_reports/rules_benchmark_data_singleton.tsv",
    params:
        cluster_sample="rules_benchmark_collect",
        working_file=f"{MDIR}reports/benchmarks_summary.tsv",
        ref_code=config["genome_build"],
    log:
        f"{MDIR}other_reports/logs/rules_benchmarks_singleton_summary.log",
    container: None
    shell:
        "bin/util/benchmarks/collect_day_benchmark_data.sh {params.ref_code} > {log};"
        "python bin/util/benchmarks/split_bench_rule_col.py {params.working_file} {output} > {log};"
        "sed -i -E 's/\t$/\tNA/' {output};"


rule sequence_qc_outputs_custom_data:
    input:
        _sequence_qc_native_inputs
    output:
        MDIR + "other_reports/sequence_qc_outputs_mqc.tsv"
    log:
        MDIR + "other_reports/logs/sequence_qc_outputs_custom_data.log"
    container: None
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        python workflow/scripts/multiqc_custom_output_inventory.py \
          --stage sequence_qc \
          --output {output:q} \
          {input:q} > {log:q} 2>&1
        """


rule alignment_qc_outputs_custom_data:
    input:
        _alignment_qc_native_inputs
    output:
        MDIR + "other_reports/alignment_qc_outputs_mqc.tsv"
    log:
        MDIR + "other_reports/logs/alignment_qc_outputs_custom_data.log"
    container: None
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        python workflow/scripts/multiqc_custom_output_inventory.py \
          --stage alignment_qc \
          --output {output:q} \
          {input:q} > {log:q} 2>&1
        """


rule aggregate_report_components:
    input:
        _final_component_inputs
    threads: 2
    output:
        f"{MDIR}logs/report_components_aggregated.done",
    shell:
        "mkdir -p $(dirname {output}); touch {output};"


rule stage_multiqc_inputs:
    input:
        _multiqc_stage_component_inputs
    output:
        done=touch(MDIR + "reports/multiqc_inputs/{report_stage}/.stage.done"),
        manifest=MDIR + "reports/multiqc_inputs/{report_stage}/manifest.tsv",
    log:
        MDIR + "reports/logs/{report_stage}_multiqc_input_staging.log"
    params:
        input_root=MDIR,
        stage_dir=MDIR + "reports/multiqc_inputs/{report_stage}",
        cluster_sample="stage_multiqc_inputs",
    container: None
    conda:
        "../envs/vanilla_v0.1.yaml"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {log:q})
        python workflow/scripts/stage_multiqc_inputs.py \
          --input-root {params.input_root:q} \
          --output-dir {params.stage_dir:q} \
          --manifest {output.manifest:q} \
          {input:q} > {log:q} 2>&1
        """


rule multiqc_seq_data:  # TARGET: sequence-data QC MultiQC report
    input:
        stage_done=MDIR + "reports/multiqc_inputs/seq_data/.stage.done",
        stage_manifest=MDIR + "reports/multiqc_inputs/seq_data/manifest.tsv",
        module_exclude_config="config/multiqc_module_exclude.txt",
    output:
        f"{MDIR}reports/DAY_seq_data_multiqc.html",
    benchmark:
        f"{MDIR}benchmarks/DAY_all.seq_data_multiqc.bench.tsv"
    threads: config["multiqc"]["threads"]
    resources:
        threads=config["multiqc"]["threads"],
        partition=config["multiqc"]["partition"],
    log:
        f"{MDIR}reports/logs/seq_data_multiqc.log",
    params:
        ghash=config["githash"],
        gbranch=config["gitbranch"],
        gtag=config["gittag"],
        cluster_sample="multiqc_seq_data",
        stage_dir=MDIR + "reports/multiqc_inputs/seq_data",
        data_json=MDIR + "reports/DAY_seq_data_multiqc_data/multiqc_data.json",
    container:
        "docker://multiqc/multiqc:v1.35"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        python workflow/scripts/multiqc_log_guard.py --log-dir {MDIR:q}other_reports/logs > {log:q} 2>&1
        multiqc --version >> {log:q} 2>&1 || true
        module_excludes="$(python workflow/scripts/multiqc_module_exclude_args.py {input.module_exclude_config:q})"
        multiqc -f \
          $module_excludes \
          --config ./config/external_tools/multiqc_config.yaml \
          --custom-css-file ./config/external_tools/multiqc.css \
          --ignore "*/other_reports/logs/*" \
          --ignore "other_reports/logs/*" \
          --ignore "*_mqc.log" \
          --template default \
          --filename {output:q} \
          -i 'Sequence Data MultiQC Report' \
          -b 'https://github.com/Daylily-Informatics/daylily-omics-analysis (BRANCH:{params.gbranch}) (TAG:{params.gtag}) (HASH:{params.ghash})' \
          {params.stage_dir:q} > {log:q} 2>&1
        python workflow/scripts/validate_multiqc_sample_ids.py \
          --manifest {input.stage_manifest:q} \
          --multiqc-data {params.data_json:q} >> {log:q} 2>&1
        """


rule multiqc_alignment:  # TARGET: sequence plus alignment QC MultiQC report
    input:
        stage_done=MDIR + "reports/multiqc_inputs/alignment/.stage.done",
        stage_manifest=MDIR + "reports/multiqc_inputs/alignment/manifest.tsv",
        module_exclude_config="config/multiqc_module_exclude.txt",
    output:
        f"{MDIR}reports/DAY_alignment_multiqc.html",
    benchmark:
        f"{MDIR}benchmarks/DAY_all.alignment_multiqc.bench.tsv"
    threads: config["multiqc"]["threads"]
    resources:
        threads=config["multiqc"]["threads"],
        partition=config["multiqc"]["partition"],
    log:
        f"{MDIR}reports/logs/alignment_multiqc.log",
    params:
        ghash=config["githash"],
        gbranch=config["gitbranch"],
        gtag=config["gittag"],
        cluster_sample="multiqc_alignment",
        stage_dir=MDIR + "reports/multiqc_inputs/alignment",
        data_json=MDIR + "reports/DAY_alignment_multiqc_data/multiqc_data.json",
    container:
        "docker://multiqc/multiqc:v1.35"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        python workflow/scripts/multiqc_log_guard.py --log-dir {MDIR:q}other_reports/logs > {log:q} 2>&1
        multiqc --version >> {log:q} 2>&1 || true
        module_excludes="$(python workflow/scripts/multiqc_module_exclude_args.py {input.module_exclude_config:q})"
        multiqc -f \
          $module_excludes \
          --config ./config/external_tools/multiqc_config.yaml \
          --custom-css-file ./config/external_tools/multiqc.css \
          --ignore "*/other_reports/logs/*" \
          --ignore "other_reports/logs/*" \
          --ignore "*_mqc.log" \
          --template default \
          --filename {output:q} \
          -i 'Alignment MultiQC Report' \
          -b 'https://github.com/Daylily-Informatics/daylily-omics-analysis (BRANCH:{params.gbranch}) (TAG:{params.gtag}) (HASH:{params.ghash})' \
          {params.stage_dir:q} > {log:q} 2>&1
        python workflow/scripts/validate_multiqc_sample_ids.py \
          --manifest {input.stage_manifest:q} \
          --multiqc-data {params.data_json:q} >> {log:q} 2>&1
        """


rule multiqc_variants:  # TARGET: sequence, alignment, and variant QC MultiQC report
    input:
        stage_done=MDIR + "reports/multiqc_inputs/variants/.stage.done",
        stage_manifest=MDIR + "reports/multiqc_inputs/variants/manifest.tsv",
        module_exclude_config="config/multiqc_module_exclude.txt",
    output:
        f"{MDIR}reports/DAY_variants_multiqc.html",
    benchmark:
        f"{MDIR}benchmarks/DAY_all.variants_multiqc.bench.tsv"
    threads: config["multiqc"]["threads"]
    resources:
        threads=config["multiqc"]["threads"],
        partition=config["multiqc"]["partition"],
    log:
        f"{MDIR}reports/logs/variants_multiqc.log",
    params:
        ghash=config["githash"],
        gbranch=config["gitbranch"],
        gtag=config["gittag"],
        cluster_sample="multiqc_variants",
        stage_dir=MDIR + "reports/multiqc_inputs/variants",
        data_json=MDIR + "reports/DAY_variants_multiqc_data/multiqc_data.json",
    container:
        "docker://multiqc/multiqc:v1.35"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        python workflow/scripts/multiqc_log_guard.py --log-dir {MDIR:q}other_reports/logs > {log:q} 2>&1
        multiqc --version >> {log:q} 2>&1 || true
        module_excludes="$(python workflow/scripts/multiqc_module_exclude_args.py {input.module_exclude_config:q})"
        multiqc -f \
          $module_excludes \
          --config ./config/external_tools/multiqc_config.yaml \
          --custom-css-file ./config/external_tools/multiqc.css \
          --ignore "*/other_reports/logs/*" \
          --ignore "other_reports/logs/*" \
          --ignore "*_mqc.log" \
          --template default \
          --filename {output:q} \
          -i 'Variant QC MultiQC Report' \
          -b 'https://github.com/Daylily-Informatics/daylily-omics-analysis (BRANCH:{params.gbranch}) (TAG:{params.gtag}) (HASH:{params.ghash})' \
          {params.stage_dir:q} > {log:q} 2>&1
        python workflow/scripts/validate_multiqc_sample_ids.py \
          --manifest {input.stage_manifest:q} \
          --multiqc-data {params.data_json:q} >> {log:q} 2>&1
        """


rule multiqc_final_wgs:  # TARGET: the big report
    input:
        components=f"{MDIR}logs/report_components_aggregated.done",
        benchmark=f"{MDIR}other_reports/rules_benchmark_data_mqc.tsv",
        stage_done=MDIR + "reports/multiqc_inputs/final/.stage.done",
        stage_manifest=MDIR + "reports/multiqc_inputs/final/manifest.tsv",
        module_exclude_config="config/multiqc_module_exclude.txt",
    output:
        html=f"{MDIR}reports/DAY_final_multiqc.html",
        html_original=f"{MDIR}reports/DAY_final_multiqc.original.html",
        header=f"{MDIR}reports/multiqc_header.yaml",
    benchmark:
        f"{MDIR}benchmarks/DAY_all.final_multiqc.bench.tsv"
    threads: config["multiqc"]["threads"]
    resources:
        threads=config["multiqc"]["threads"],
        partition=config["multiqc"]["partition"],
    priority: 50
    params:
        fnamef="DAY_final_multiqc.html",
        ghash=config["githash"],
        gbranch=config["gitbranch"],
        gtag=config["gittag"],
        cluster_sample="multiqc_final",
        cemail=config["day_contact_email"],
        rtitle=RPT_TITLE,
        stage_dir=MDIR + "reports/multiqc_inputs/final",
        data_json=MDIR + "reports/DAY_final_multiqc_data/multiqc_data.json",
    log:
        f"{MDIR}reports/logs/all__mqc_fin_a.log",
    container:
        "docker://multiqc/multiqc:v1.35"
    shell:
        """
        dbill='$';
        mkdir -p $(dirname {output.html:q}) $(dirname {log:q})
        python workflow/scripts/multiqc_log_guard.py --log-dir {MDIR:q}other_reports/logs > {log:q} 2>&1
        multiqc --version >> {log:q} 2>&1 || true
        echo '''
report_header_info:
  - Project/Budget: "REGSUB_PROJECT"
  - Budget @ Runtime: "REGSUB_BUDGET"
  - Spot Instances: "REGSUB_SPOTINSTANCES"
  - Spot Costs per hr: "REGSUB_SPOTCOST"
  - FQ->BAM.sort avg Costs: "REGSUB_TOTALCOST"
  - BAM mrkdup avg Cost: "REGSUB_MRKDUPCOST"
  - Results Dir (GB): "REGSUB_TOTALSIZE"
  ''' > {output.header:q} 2>> {log:q};

        perl -pi -e "s/REGSUB_PROJECT/$DAY_PROJECT/g;"  {output.header:q} >> {log:q} 2>&1;
        perl -pi -e "s/REGSUB_BUDGET/\\\$dbill$USED_BUDGET of \\\$dbill$TOTAL_BUDGET spent ( $PERCENT_USED\%)/g;" {output.header:q} >> {log:q} 2>&1;

        size=$(du -hs results | cut -f1) >> {log:q} 2>&1;
        perl -pi -e "s/REGSUB_TOTALSIZE/$size/g;" {output.header:q} >> {log:q} 2>&1;

        source bin/proc_spot_price_logs.sh >> {log:q} 2>&1;
        perl -pi -e "s/REGSUB_SPOTCOST/median: \\\$dbill$MEDIAN_SPOT_PRICE  mean: \\\$dbill$AVERAGE_SPOT_PRICE ( avg cost per vcpu,per min: \\\$dbill$VCPU_COST_PER_MIN ) /g;"  {output.header:q} >> {log:q} 2>&1;
        perl -pi -e "s/REGSUB_SPOTINSTANCES/ $INSTANCE_TYPES_LINE /g;" {output.header:q} >> {log:q} 2>&1;

        source bin/proc_aligner_costs.sh {input.benchmark:q} $VCPU_COST_PER_MIN >> {log:q} 2>&1;
        perl -pi -e "s/REGSUB_TOTALCOST/$ALNR_SUMMARY_COST/g;" {output.header:q} >> {log:q} 2>&1;

        source bin/proc_mrkdup_costs.sh {input.benchmark:q} $VCPU_COST_PER_MIN  >> {log:q} 2>&1;
        perl -pi -e "s/REGSUB_MRKDUPCOST/$MRKDUP_AVG_MINUTES min, costing \\\$dbill$MRKDUP_AVG_COST/g;" {output.header:q} >> {log:q} 2>&1;

        module_excludes="$(python workflow/scripts/multiqc_module_exclude_args.py {input.module_exclude_config:q})"
        multiqc -f  \
        $module_excludes \
        --config {output.header:q} \
        --config ./config/external_tools/multiqc_config.yaml  \
        --custom-css-file ./config/external_tools/multiqc.css \
        --ignore "*/other_reports/logs/*" \
        --ignore "other_reports/logs/*" \
        --ignore "*_mqc.log" \
        --template default \
        --filename {output.html:q} \
        -i '{params.rtitle} Multiqc Report ' \
        -b 'https://github.com/Daylily-Informatics/daylily-omics-analysis (BRANCH:{params.gbranch}) (TAG:{params.gtag}) (HASH:{params.ghash}) ' \
        {params.stage_dir:q} >> {log:q} 2>&1;
        python workflow/scripts/force_multiqc_dark_mode.py \
          --html {output.html:q} \
          --backup {output.html_original:q} >> {log:q} 2>&1;
        python workflow/scripts/validate_multiqc_sample_ids.py \
          --manifest {input.stage_manifest:q} \
          --multiqc-data {params.data_json:q} >> {log:q} 2>&1;
        ls -lt {output.html:q} {output.html_original:q} {output.header:q} >> {log:q} 2>&1;
        """


rule produce_multiqc_input_data:  # TARGET: canonical input sequence-data QC report
    input:
        MDIR + "reports/DAY_seq_data_multiqc.html"


rule produce_multiqc_cram:  # TARGET: canonical CRAM/alignment QC report
    input:
        MDIR + "reports/DAY_alignment_multiqc.html"


rule produce_multiqc_snv:  # TARGET: canonical SNV QC report
    input:
        MDIR + "reports/DAY_variants_multiqc.html"


rule produce_multiqc_sv:  # TARGET: canonical SV QC report
    input:
        MDIR + "reports/DAY_variants_multiqc.html"


rule produce_multiqc_sample_qc:  # TARGET: canonical sample-level QC report
    input:
        MDIR + "reports/DAY_alignment_multiqc.html"


rule produce_multiqc_variant_annotation:  # TARGET: canonical variant annotation QC report
    input:
        MDIR + "reports/DAY_variants_multiqc.html"


rule produce_multiqc_all:  # TARGET: canonical all-routine-QC report
    input:
        MDIR + "reports/DAY_final_multiqc.html"


rule produce_multiqc_stage_final:  # TARGET: stage final MultiQC input tree
    input:
        MDIR + "reports/multiqc_inputs/final/.stage.done"


rule produce_multiqc_seq_data:  # DEPRECATED TARGET: use produce_multiqc_input_data
    input:
        MDIR + "reports/DAY_seq_data_multiqc.html"


rule produce_multiqc_alignment:  # DEPRECATED TARGET: use produce_multiqc_cram
    input:
        MDIR + "reports/DAY_alignment_multiqc.html"


rule produce_multiqc_variants:  # DEPRECATED TARGET: use produce_multiqc_snv / produce_multiqc_variant_annotation
    input:
        MDIR + "reports/DAY_variants_multiqc.html"


rule produce_multiqc_final:  # DEPRECATED TARGET: use produce_multiqc_all
    input:
        MDIR + "reports/DAY_final_multiqc.html"


rule produce_multiqc_final_wgs:  # DEPRECATED TARGET: use produce_multiqc_all
    input:
        MDIR + "reports/DAY_final_multiqc.html"
