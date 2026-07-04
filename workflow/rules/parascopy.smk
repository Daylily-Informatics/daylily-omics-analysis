"""Rules for running Parascopy copy number analysis."""

from snakemake.exceptions import WorkflowError

_PARASCOPY_CONFIG = config.get("parascopy", {})
_GO_LEFT_CONF = config.get("go_left", {})


def _parascopy_threads():
    return _PARASCOPY_CONFIG.get("threads", _GO_LEFT_CONF.get("threads", 1))


def _parascopy_partition():
    return _PARASCOPY_CONFIG.get("partition", _GO_LEFT_CONF.get("partition", ""))


def _parascopy_mem_mb():
    return _PARASCOPY_CONFIG.get("mem_mb", 50000)


def _parascopy_locus_config():
    locus_config = _PARASCOPY_CONFIG.get("locus_config")
    if not locus_config:
        raise WorkflowError(
            "Missing configuration value: set config['parascopy']['locus_config'] to the Parascopy locus configuration file."
        )
    return locus_config


def _parascopy_extra_args():
    return _PARASCOPY_CONFIG.get("extra_args", "")


def _parascopy_targets():
    return _PARASCOPY_CONFIG.get("targets", "")


def _parascopy_reference():
    return _PARASCOPY_CONFIG.get(
        "reference",
        config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    )


rule parascopy:
    """Run Parascopy on the CRAM alignment for a sample/aligner pair."""
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        results_dir=directory(MDIR + "{sample}/align/{alnr}/{ddup}/htd/parascopy/results/{sample}.{alnr}.{ddup}.parascopy"),
        done=MDIR + "{sample}/align/{alnr}/{ddup}/htd/parascopy/{sample}.{alnr}.{ddup}.parascopy.done",
    params:
        cluster_sample=ret_sample,
        reference=lambda wildcards: _parascopy_reference(),
        locus_config=lambda wildcards: _parascopy_locus_config(),
        extra_args=lambda wildcards: _parascopy_extra_args(),
        targets=lambda wildcards: _parascopy_targets(),
        prefix=lambda wildcards: f"{wildcards.sample}.{wildcards.alnr}.parascopy",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.parascopy.benchmark.tsv",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/htd/parascopy/logs/{sample}.{alnr}.{ddup}.parascopy.log",
    threads: _parascopy_threads()
    resources:
        vcpu=_parascopy_threads(),
        threads=_parascopy_threads(),
        partition=_parascopy_partition(),
        mem_mb=_parascopy_mem_mb(),
    conda:
        "../envs/parascopy_v0.1.yaml"
    shell:
        """
        set -euo pipefail

        mkdir -p $(dirname {log})

        tmp_dir=$(mktemp -d)
        trap 'rm -rf "${{tmp_dir}}"' EXIT

        target_args=()
        if [[ -n "{params.targets}" ]]; then
            target_args=("--targets" "{params.targets}")
        fi

        extra_args=()
        if [[ -n "{params.extra_args}" ]]; then
            read -r -a extra_args <<<"{params.extra_args}"
        fi

        parascopy call \
            --bam {input.cram} \
            --reference {params.reference} \
            --locus-config {params.locus_config} \
            --output-prefix "${{tmp_dir}}/{params.prefix}" \
            --sample {wildcards.sample} \
            --threads {threads} \
            "${{target_args[@]}}" \
            "${{extra_args[@]}}" \
            &> {log}

        mkdir -p $(dirname {output.results_dir})
        mkdir -p $(dirname {output.done})
        rm -rf {output.results_dir}
        mv "${{tmp_dir}}" {output.results_dir}
        trap - EXIT

        touch {output.done}
        """


localrules: produce_parascopy


rule produce_parascopy:  # TARGET : Produce Parascopy results
    """Aggregate completion of all Parascopy runs."""
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/htd/parascopy/{sample}.{alnr}.{ddup}.parascopy.done",
            sample=SSAMPS,
            alnr=QC_CRAM_ALIGNERS,
            ddup=DDUP,
        )
    output:
        "./logs/parascopy.done"
    shell:
        "touch {output}"
