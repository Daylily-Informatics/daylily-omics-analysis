import os

# This rule set gathers staged QC outputs and produces the public MultiQC
# reports.  Runtime-gated tools are still available as first-class rules, but
# they are kept out of routine MultiQC targets unless explicitly enabled.

RPT_TITLE = os.environ.get("RPT_TITLE", "Final")


def _seq_data_component_inputs(wildcards):
    paths = _sequence_qc_native_inputs(wildcards)
    paths.append(MDIR + "other_reports/sequence_qc_outputs_mqc.tsv")
    return paths


def _sequence_qc_native_inputs(wildcards):
    paths = []
    if qc_tool_enabled("fastqc"):
        paths.extend(
            expand(MDIR + "{sample}/seqqc/fastqc/{sample}.fastqc.done", sample=SAMPS)
        )
    if qc_tool_enabled("seqfu"):
        paths.append(MDIR + "other_reports/seqfu_mqc.tsv")
    if qc_tool_enabled("kat", long_running=True):
        paths.extend(expand(MDIR + "{sample}/seqqc/kat/{sample}.kat.done", sample=SAMPS))
    if qc_tool_enabled("fastv", long_running=True):
        paths.extend(
            expand(
                [
                    MDIR + "{sample}/seqqc/fastv/{sample}.fastv.json",
                    MDIR + "{sample}/seqqc/fastv/{sample}.fastv.html",
                ],
                sample=SAMPS,
            )
        )
    return paths


def _alignment_component_inputs(wildcards):
    paths = list(_seq_data_component_inputs(wildcards))
    paths.extend(_alignment_qc_native_inputs(wildcards))
    paths.append(MDIR + "other_reports/alignment_qc_outputs_mqc.tsv")
    if (
        qc_tool_enabled("verifybamid2")
        or qc_tool_enabled("gatk_contam")
        or qc_tool_enabled("site_mix")
    ):
        paths.append(MDIR + "other_reports/contamination_mqc.tsv")
    if qc_tool_enabled("verifybamid2"):
        paths.append(MDIR + "other_reports/verifybamid2_panel_comparison_mqc.tsv")
    if qc_tool_enabled("gatk_contam"):
        paths.append(MDIR + "other_reports/gatk_contam_mqc.tsv")
    if qc_tool_enabled("site_mix"):
        paths.extend(
            [
                MDIR + "other_reports/site_mix_contam_mqc.tsv",
                MDIR + "other_reports/site_mix_donor_mqc.tsv",
            ]
        )
    if qc_tool_enabled("relatedness"):
        paths.append(MDIR + "other_reports/relatedness_mqc.tsv")
    return paths


def _alignment_qc_native_inputs(wildcards):
    paths = []
    qddups = qc_alignment_dedupers()
    alnrs = QC_CRAM_ALIGNERS
    paths.append(MDIR + "other_reports/alignstats_combo_mqc.tsv")
    paths.append(MDIR + "other_reports/normcovevenness_combo_mqc.tsv")
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
            + "{sample}/align/{alnr}/{ddup}/alignqc/picard/picard/{sample}.{alnr}.{ddup}.done",
            sample=SSAMPS,
            alnr=alnrs,
            ddup=qddups,
        )
    )
    paths.extend(
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/alignqc/qmap/{sample}.{alnr}/{ddup}/{sample}.{alnr}.{ddup}.qmap.done",
            sample=SSAMPS,
            alnr=alnrs,
            ddup=qddups,
        )
    )
    paths.extend(
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/alignqc/mosdepth/{sample}.{alnr}.{ddup}.mosdepth.summary.sort.bed",
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
                ddup=qddups,
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
                ddup=qddups,
            )
        )
    return paths


def _variant_component_inputs(wildcards):
    paths = list(_alignment_component_inputs(wildcards))
    pairs = valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)
    paths.append(MDIR + "other_reports/bcftools_variant_stats_mqc.tsv")
    paths.append(MDIR + "other_reports/rtg_vcfstats_mqc.tsv")
    if qc_tool_enabled("peddy"):
        paths.extend(["logs/peddy_gathered.done", MDIR + "other_reports/peddy_sample_qc_mqc.tsv"])
    if qc_tool_enabled("expansionhunter") and set(ALIGNERS) & EXPANSIONHUNTER_ALIGNERS:
        paths.append(MDIR + "other_reports/expansionhunter_mqc.tsv")
    if qc_tool_enabled("vep", long_running=True):
        paths.append(MDIR + "other_reports/vep_annotation_mqc.tsv")
    if qc_tool_enabled("snpeff", long_running=True):
        paths.append(MDIR + "other_reports/snpeff_annotation_mqc.tsv")
    if HTD_CALLERS:
        paths.append(MDIR + "other_reports/htd_calls_mqc.tsv")
    if len(CONCORDANCE_SAMPLES.keys()) > 0 and pairs:
        paths.append(MDIR + "other_reports/giab_concordance_mqc.tsv")
    return paths


def _final_component_inputs(wildcards):
    return _variant_component_inputs(wildcards)


localrules:
    collect_rules_benchmark_data,
    collect_rules_benchmark_data_singleton,
    sequence_qc_outputs_custom_data,
    alignment_qc_outputs_custom_data,
    aggregate_report_components,
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
        MDIR + "other_reports/logs/sequence_qc_outputs.log"
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
        MDIR + "other_reports/logs/alignment_qc_outputs.log"
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


rule multiqc_seq_data:  # TARGET: sequence-data QC MultiQC report
    input:
        _seq_data_component_inputs
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
    container:
        "docker://daylilyinformatics/daylily_multiqc:0.2"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        multiqc -f \
          --config ./config/external_tools/multiqc_config.yaml \
          --custom-css-file ./config/external_tools/multiqc.css \
          --ignore "*/alignqc/contam/gatk/*_mqc.tsv" \
          --ignore "*/alignqc/contam/vb2/*/*_mqc.tsv" \
          --template default \
          --filename {output:q} \
          -i 'Sequence Data MultiQC Report' \
          -b 'https://github.com/lsmc-bio/daylily-omics-analysis (BRANCH:{params.gbranch}) (TAG:{params.gtag}) (HASH:{params.ghash})' \
          {MDIR} > {log:q} 2>&1
        """


rule multiqc_alignment:  # TARGET: sequence plus alignment QC MultiQC report
    input:
        _alignment_component_inputs
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
    container:
        "docker://daylilyinformatics/daylily_multiqc:0.2"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        multiqc -f \
          --config ./config/external_tools/multiqc_config.yaml \
          --custom-css-file ./config/external_tools/multiqc.css \
          --ignore "*/alignqc/contam/gatk/*_mqc.tsv" \
          --ignore "*/alignqc/contam/vb2/*/*_mqc.tsv" \
          --template default \
          --filename {output:q} \
          -i 'Alignment MultiQC Report' \
          -b 'https://github.com/lsmc-bio/daylily-omics-analysis (BRANCH:{params.gbranch}) (TAG:{params.gtag}) (HASH:{params.ghash})' \
          {MDIR} > {log:q} 2>&1
        """


rule multiqc_variants:  # TARGET: sequence, alignment, and variant QC MultiQC report
    input:
        _variant_component_inputs
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
    container:
        "docker://daylilyinformatics/daylily_multiqc:0.2"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        multiqc -f \
          --config ./config/external_tools/multiqc_config.yaml \
          --custom-css-file ./config/external_tools/multiqc.css \
          --ignore "*/alignqc/contam/gatk/*_mqc.tsv" \
          --ignore "*/alignqc/contam/vb2/*/*_mqc.tsv" \
          --template default \
          --filename {output:q} \
          -i 'Variant QC MultiQC Report' \
          -b 'https://github.com/lsmc-bio/daylily-omics-analysis (BRANCH:{params.gbranch}) (TAG:{params.gtag}) (HASH:{params.ghash})' \
          {MDIR} > {log:q} 2>&1
        """


rule multiqc_final_wgs:  # TARGET: the big report
    input:
        components=f"{MDIR}logs/report_components_aggregated.done",
        benchmark=f"{MDIR}other_reports/rules_benchmark_data_mqc.tsv",
    output:
        html=f"{MDIR}reports/DAY_final_multiqc.html",
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
    log:
        f"{MDIR}reports/logs/all__mqc_fin_a.log",
    container:
        "docker://daylilyinformatics/daylily_multiqc:0.2"
    shell:
        """
        dbill='$';
        mkdir -p $(dirname {output.html:q}) $(dirname {log:q})
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

        multiqc -f  \
        --config {output.header:q} \
        --config ./config/external_tools/multiqc_config.yaml  \
        --custom-css-file ./config/external_tools/multiqc.css \
        --ignore "*/alignqc/contam/gatk/*_mqc.tsv" \
        --ignore "*/alignqc/contam/vb2/*/*_mqc.tsv" \
        --ignore "*/norm_cov_eveness/*" \
        --ignore "*/other_reports/logs/*" \
        --ignore "*sort_metrics/*" \
        --template default \
        --filename {output.html:q} \
        -i '{params.rtitle} Multiqc Report ' \
        -b 'https://github.com/lsmc-bio/daylily-omics-analysis (BRANCH:{params.gbranch}) (TAG:{params.gtag}) (HASH:{params.ghash}) ' \
        {MDIR} >> {log:q} 2>&1;
        ls -lt {output.html:q} {output.header:q} >> {log:q} 2>&1;
        """


rule produce_multiqc_seq_data:  # TARGET: Generated sequence-data QC report
    input:
        MDIR + "reports/DAY_seq_data_multiqc.html"


rule produce_multiqc_alignment:  # TARGET: Generated sequence and alignment QC report
    input:
        MDIR + "reports/DAY_alignment_multiqc.html"


rule produce_multiqc_variants:  # TARGET: Generated sequence, alignment, and variant QC report
    input:
        MDIR + "reports/DAY_variants_multiqc.html"


rule produce_multiqc_final:  # TARGET: Generated All Routine WGS QC Reports
    input:
        MDIR + "reports/DAY_final_multiqc.html"


rule produce_multiqc_final_wgs:  # TARGET: Generated All WGS Reports
    input:
        MDIR + "reports/DAY_final_multiqc.html"
