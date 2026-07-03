"""Aggregate selected hard-to-detect-region callers."""


def htd_smn12_preflight_needed(*, require_non_empty=False):
    callers = htd_callers_selected(require_non_empty=require_non_empty)
    return bool({"smn12", "smaca", "sma_finder"} & set(callers))


def htd_call_outputs(*, require_non_empty=False):
    callers = htd_callers_selected(require_non_empty=require_non_empty)
    outputs = []
    alnrs = QC_CRAM_ALIGNERS
    ddups = DDUP
    smn_short_pairs = smn_short_read_alnr_ddup_pairs()

    if "gauchian" in callers:
        outputs.extend(
            expand(
                [
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/gauchian/{sample}.{alnr}.{ddup}.gauchian.done",
                ],
                sample=SSAMPS,
                alnr=alnrs,
                ddup=ddups,
            )
        )
    if "cyrius" in callers:
        outputs.extend(
            expand(
                [
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/cyrius/{sample}.{alnr}.{ddup}.cyrius.tsv",
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/cyrius/{sample}.{alnr}.{ddup}.cyrius.json",
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/cyrius/{sample}.{alnr}.{ddup}.cyrius.done",
                ],
                sample=SSAMPS,
                alnr=alnrs,
                ddup=ddups,
            )
        )
    if "smn12" in callers:
        outputs.extend(
            expand_smn_alnr_ddup_pairs(
                [
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/smn12/{sample}.{alnr}.{ddup}.smn12.summary.json",
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/smn12/{sample}.{alnr}.{ddup}.smn12.done",
                ],
                pairs=smn_short_pairs,
            )
        )
    if "smaca" in callers:
        outputs.extend(
            expand_smn_alnr_ddup_pairs(
                [
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/smaca/{sample}.{alnr}.{ddup}.smaca.summary.tsv",
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/smaca/{sample}.{alnr}.{ddup}.smaca.done",
                ],
                pairs=smn_short_pairs,
            )
        )
    if "sma_finder" in callers:
        outputs.extend(
            expand_smn_alnr_ddup_pairs(
                [
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/sma_finder/{sample}.{alnr}.{ddup}.sma_finder.summary.tsv",
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/sma_finder/{sample}.{alnr}.{ddup}.sma_finder.summary.json",
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/sma_finder/{sample}.{alnr}.{ddup}.sma_finder.done",
                ],
                pairs=smn_short_pairs,
            )
        )
    if "hapsma" in callers:
        smn_long_pairs = smn_long_read_alnr_ddup_pairs()
        outputs.extend(
            expand_smn_alnr_ddup_pairs(
                [
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/{sample}.{alnr}.{ddup}.hapsma.summary.tsv",
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/{sample}.{alnr}.{ddup}.hapsma.done",
                ],
                pairs=smn_long_pairs,
            )
        )
    return outputs


def selected_htd_call_outputs(wildcards):
    return htd_call_outputs()


def required_htd_call_outputs(wildcards):
    return htd_call_outputs(require_non_empty=True)


localrules:
    htd_calls_mqc,
    produce_htd_calls,


rule htd_calls_mqc:
    input:
        selected_htd_call_outputs
    output:
        MDIR + "other_reports/htd_calls_mqc.tsv"
    log:
        MDIR + "other_reports/logs/htd_calls_custom_data.log"
    benchmark:
        MDIR + "benchmarks/htd_calls_mqc.bench.tsv"
    container: None
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        python workflow/scripts/htd_calls_mqc.py \
          --output {output:q} \
          {input:q} > {log:q} 2>&1
        """


rule produce_htd_calls:  # TARGET : Produce selected HTD caller outputs
    input:
        calls=required_htd_call_outputs,
        smn12_preflight=lambda wildcards: (
            MDIR + "other_reports/smn12_preflight_mqc.tsv"
            if htd_smn12_preflight_needed(require_non_empty=True)
            else []
        ),
        mqc=MDIR + "other_reports/htd_calls_mqc.tsv",
    output:
        "logs/htd_calls.done"
    log:
        MDIR + "logs/produce_htd_calls.log"
    benchmark:
        "logs/benchmarks/produce_htd_calls.bench.tsv"
    shell:
        "mkdir -p $(dirname {output}); touch {output}"
