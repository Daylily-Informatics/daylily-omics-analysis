"""Rules for running the GeneToCN copy-number caller."""

import re

GENETOCN_CFG = config.get("genetocn", {})
GENETOCN_ENV = GENETOCN_CFG.get("env_yaml", "workflow/envs/genetocn_v0.1.yaml")
GENETOCN_THREADS = GENETOCN_CFG.get("threads", config["go_left"]["threads"])
GENETOCN_MEM_MB = GENETOCN_CFG.get("mem_mb", 32000)


def genetocn_cram(wildcards):
    """Return the CRAM input for GeneToCN."""
    return MDIR + (
        f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/"
        f"{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.cram"
    )


def genetocn_crai(wildcards):
    """Return the CRAI input for GeneToCN."""
    return f"{genetocn_cram(wildcards)}.crai"


def _genetocn_config_path(*keys):
    for key in keys:
        value = GENETOCN_CFG.get(key)
        if value:
            return value
    return []


def _genetocn_input_value(value):
    if isinstance(value, str):
        return value
    if not value:
        return ""
    return value[0]


def genetocn_command(wildcards, input, output, threads):
    """Build the GeneToCN command, allowing overrides from the config."""
    cfg = GENETOCN_CFG
    reference = cfg.get(
        "reference",
        config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    )
    panel = _genetocn_input_value(getattr(input, "panel", ""))
    intervals = _genetocn_input_value(getattr(input, "intervals", ""))
    annotation = _genetocn_input_value(getattr(input, "annotation", ""))
    extra_args = cfg.get("extra_args", "").strip()

    template = cfg.get("command_template")
    values = {
        "sample": wildcards.sample,
        "aligner": wildcards.alnr,
        "cram": input.cram,
        "bam": input.cram,
        "crai": input.crai,
        "bai": input.crai,
        "reference": reference,
        "panel": panel or "",
        "intervals": intervals or "",
        "annotation": annotation or "",
        "outdir": output.results_dir,
        "results_dir": output.results_dir,
        "threads": threads,
        "extra_args": extra_args,
        "panel_flag": "" if not panel else f"--panel {panel}",
        "interval_flag": "" if not intervals else f"--intervals {intervals}",
        "annotation_flag": "" if not annotation else f"--annotation {annotation}",
    }

    if template:
        command = template.format(**values).strip()
        return re.sub(r"\s+", " ", command)

    cmd_parts = [
        "GeneToCN",
        f"--sample {wildcards.sample}",
        f"--bam {input.cram}",
        f"--reference {reference}",
        f"--outdir {output.results_dir}",
        f"--threads {threads}",
    ]

    if panel:
        cmd_parts.append(f"--panel {panel}")
    if intervals:
        cmd_parts.append(f"--intervals {intervals}")
    if annotation:
        cmd_parts.append(f"--annotation {annotation}")
    if extra_args:
        cmd_parts.append(extra_args)

    return " ".join(cmd_parts)


rule genetocn:
    """Run GeneToCN on an input CRAM/CRAI pair."""
    input:
        cram=genetocn_cram,
        crai=genetocn_crai,
        panel=lambda wildcards: _genetocn_config_path("panel", "targets"),
        intervals=lambda wildcards: _genetocn_config_path("intervals"),
        annotation=lambda wildcards: _genetocn_config_path("annotation"),
    output:
        results_dir=directory(MDIR + "{sample}/align/{alnr}/{ddup}/htd/genetocn/results/{sample}.{alnr}"),
        done=MDIR + "{sample}/align/{alnr}/{ddup}/htd/genetocn/{sample}.{alnr}.{ddup}.genetocn.done",
    params:
        cluster_sample=ret_sample,
        command=genetocn_command,
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/htd/genetocn/logs/{sample}.{alnr}.{ddup}.genetocn.log",
    threads: GENETOCN_THREADS
    resources:
        mem_mb=GENETOCN_MEM_MB
    conda:
        GENETOCN_ENV
    shell:
        """
        set -euo pipefail

        out_dir={output.results_dir}
        mkdir -p "$(dirname {log})"
        rm -rf "${{out_dir}}"
        mkdir -p "${{out_dir}}"

        {params.command} > {log} 2>&1

        touch {output.done}
        """


localrules: produce_genetocn


rule produce_genetocn:  # TARGET : Produce GeneToCN copy-number results
    """Aggregate completion for all GeneToCN runs."""
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/htd/genetocn/{sample}.{alnr}.{ddup}.genetocn.done",
            sample=SSAMPS,
            alnr=QC_CRAM_ALIGNERS,
            ddup=DDUP,
        )
    output:
        "./logs/genetocn.done"
    shell:
        "touch {output}"
