"""Aggregate orthogonal SMN12 caller evidence."""


def smn12_orthogonal_call_outputs(wildcards=None):
    outputs = []
    short_alnrs = smn_short_read_aligners()
    long_alnrs = smn_long_read_aligners()
    outputs.extend(
        expand(
            [
                MDIR + "{sample}/align/{alnr}/{ddup}/htd/smn12/{sample}.{alnr}.{ddup}.smn12.summary.json",
                MDIR + "{sample}/align/{alnr}/{ddup}/htd/smn12/{sample}.{alnr}.{ddup}.smn12.done",
                MDIR + "{sample}/align/{alnr}/{ddup}/htd/smaca/{sample}.{alnr}.{ddup}.smaca.summary.tsv",
                MDIR + "{sample}/align/{alnr}/{ddup}/htd/smaca/{sample}.{alnr}.{ddup}.smaca.done",
                MDIR + "{sample}/align/{alnr}/{ddup}/htd/sma_finder/{sample}.{alnr}.{ddup}.sma_finder.summary.tsv",
                MDIR + "{sample}/align/{alnr}/{ddup}/htd/sma_finder/{sample}.{alnr}.{ddup}.sma_finder.summary.json",
                MDIR + "{sample}/align/{alnr}/{ddup}/htd/sma_finder/{sample}.{alnr}.{ddup}.sma_finder.done",
            ],
            sample=SSAMPS,
            alnr=short_alnrs,
            ddup=DDUP,
        )
    )
    outputs.extend(
        expand(
            [
                MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/{sample}.{alnr}.{ddup}.hapsma.summary.tsv",
                MDIR + "{sample}/align/{alnr}/{ddup}/htd/hapsma/{sample}.{alnr}.{ddup}.hapsma.done",
            ],
            sample=SSAMPS,
            alnr=long_alnrs,
            ddup=DDUP,
        )
    )
    hiomr_alnrs = sorted(_smn_hiomr_aligners())
    if hiomr_alnrs:
        if "SMN1" not in globals().get("SEGDUP_GENES", []):
            raise WorkflowError(
                "produce_smn12_orthogonal_calls requires Sentieon HiOMR segdup_genes "
                "to include SMN1 when HiOMR aligners are configured."
            )
        outputs.extend(
            expand(
                [
                    MDIR + "{sample}/align/{alnr}/{ddup}/segdup/sentdhiomr/results/SMN1/{sample}.SMN1.result.vcf.gz",
                    MDIR + "{sample}/align/{alnr}/{ddup}/segdup/sentdhiomr/results/SMN1/{sample}.SMN1.result.vcf.gz.tbi",
                    MDIR + "{sample}/align/{alnr}/{ddup}/segdup/sentdhiomr/results/SMN1/{sample}.SMN1.yaml",
                    MDIR + "{sample}/align/{alnr}/{ddup}/segdup/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.segdup.SMN1.done",
                ],
                sample=SSAMPS,
                alnr=hiomr_alnrs,
                ddup=DDUP,
            )
        )
    return outputs


localrules:
    smn12_orthogonal_calls_mqc,
    produce_smn12_orthogonal_calls,


rule smn12_orthogonal_calls_mqc:
    input:
        smn12_orthogonal_call_outputs
    output:
        MDIR + "other_reports/smn12_orthogonal_calls_mqc.tsv"
    log:
        MDIR + "other_reports/logs/smn12_orthogonal_calls_mqc.log"
    benchmark:
        MDIR + "benchmarks/smn12_orthogonal_calls_mqc.bench.tsv"
    container: None
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output:q}) $(dirname {log:q})
        python workflow/scripts/smn12_orthogonal_calls_mqc.py \
          --output {output:q} \
          {input:q} > {log:q} 2>&1
        """


rule produce_smn12_orthogonal_calls:  # TARGET : Produce orthogonal SMN1/SMN2 caller evidence
    input:
        calls=smn12_orthogonal_call_outputs,
        mqc=MDIR + "other_reports/smn12_orthogonal_calls_mqc.tsv",
    output:
        "logs/smn12_orthogonal_calls.done"
    log:
        MDIR + "logs/produce_smn12_orthogonal_calls.log"
    benchmark:
        "logs/benchmarks/produce_smn12_orthogonal_calls.bench.tsv"
    shell:
        "mkdir -p $(dirname {output}); touch {output}"
