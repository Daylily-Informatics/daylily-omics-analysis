"""Aggregate selected hard-to-detect-region callers."""


def htd_call_outputs(*, require_non_empty=False):
    callers = htd_callers_selected(require_non_empty=require_non_empty)
    outputs = []
    alnrs = QC_CRAM_ALIGNERS
    ddups = DDUP

    if "gauchian" in callers:
        outputs.extend(
            expand(
                MDIR + "{sample}/align/{alnr}/{ddup}/htd/gauchian/{sample}.{alnr}.{ddup}.gauchian.done",
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
            expand(
                MDIR + "{sample}/align/{alnr}/{ddup}/htd/smn12/{sample}.{alnr}.{ddup}.smn12.summary.json",
                sample=SSAMPS,
                alnr=alnrs,
                ddup=ddups,
            )
        )
    if "parascopy" in callers:
        outputs.extend(
            expand(
                MDIR + "{sample}/align/{alnr}/{ddup}/htd/parascopy/{sample}.{alnr}.{ddup}.parascopy.done",
                sample=SSAMPS,
                alnr=alnrs,
                ddup=ddups,
            )
        )
    if "smaca" in callers:
        outputs.extend(
            expand(
                [
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/smaca/{sample}.{alnr}.{ddup}.smaca.summary.tsv",
                    MDIR + "{sample}/align/{alnr}/{ddup}/htd/smaca/{sample}.{alnr}.{ddup}.smaca.done",
                ],
                sample=SSAMPS,
                alnr=alnrs,
                ddup=ddups,
            )
        )
    if "genetocn" in callers:
        outputs.extend(
            expand(
                MDIR + "{sample}/align/{alnr}/{ddup}/htd/genetocn/{sample}.{alnr}.{ddup}.genetocn.done",
                sample=SSAMPS,
                alnr=alnrs,
                ddup=ddups,
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
        MDIR + "other_reports/logs/htd_calls_mqc.log"
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
        mqc=MDIR + "other_reports/htd_calls_mqc.tsv",
    output:
        "logs/htd_calls.done"
    shell:
        "mkdir -p $(dirname {output}); touch {output}"
