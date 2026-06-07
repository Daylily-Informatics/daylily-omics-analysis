"""Rules for running QuicK-mer2 copy-number analysis."""

import os
from collections import defaultdict
from snakemake.exceptions import WorkflowError


class _SafeDict(defaultdict):
    def __missing__(self, key):
        return ""


def _quickmer2_cfg():
    cfg = config.get("quickmer2")
    if not cfg:
        raise WorkflowError(
            "The 'quickmer2' configuration block is missing. Please add it to your rule_config.yaml file."
        )
    return cfg


def _expand_path(template, wildcards=None):
    """Expand environment variables and wildcards inside configuration templates."""
    if template is None:
        return None
    mapping = {"MDIR": MDIR.rstrip("/")}
    if wildcards is not None:
        mapping.update({"sample": wildcards.sample, "alnr": wildcards.alnr})
    formatted = template
    if "{" in template and "}" in template:
        formatted = template.format_map(_SafeDict(str, mapping))
    expanded = os.path.expandvars(os.path.expanduser(formatted))
    return os.path.abspath(expanded)


def _quickmer2_repo_dir():
    cfg = _quickmer2_cfg()
    template = cfg.get("repo_dir", os.path.join("resources", "QuicK-mer2"))
    return _expand_path(template)


def _quickmer2_run_dir(wildcards):
    cfg = _quickmer2_cfg()
    template = cfg.get(
        "work_root",
        os.path.join(MDIR, "{sample}", "align", "{alnr}", "cnv", "quickmer2", "work"),
    )
    return _expand_path(template, wildcards)


def _quickmer2_reference(cfg):
    ref = cfg.get("reference_fasta")
    if ref:
        return os.path.expandvars(os.path.expanduser(ref))
    return config["supporting_files"]["files"]["huref"]["fasta"]["name"]


def _quickmer2_command(wildcards, input, threads):
    cfg = _quickmer2_cfg()
    template = cfg.get("command_template", "").strip()
    if not template:
        raise WorkflowError(
            "quickmer2.command_template is not configured. Please provide a command template in the quickmer2 configuration block."
        )

    repo_dir = _quickmer2_repo_dir()
    run_dir = _quickmer2_run_dir(wildcards)
    reference = _quickmer2_reference(cfg)
    kmer_catalog = cfg.get("kmer_catalog")
    normalization_table = cfg.get("normalization_table")
    additional_args = cfg.get("additional_args", "").strip()

    mapping = _SafeDict(
        str,
        {
            "sample": wildcards.sample,
            "aligner": wildcards.alnr,
            "cram": input.cram,
            "crai": input.crai,
            "threads": threads,
            "repo_dir": repo_dir,
            "run_dir": run_dir,
            "reference": reference,
            "kmer_catalog": kmer_catalog,
            "normalization_table": normalization_table,
            "additional_args": additional_args,
        },
    )

    for key in ("kmer_catalog", "normalization_table"):
        if not mapping[key]:
            raise WorkflowError(
                f"quickmer2 configuration requires '{key}' to be set."
            )

    return template.format_map(mapping)


rule quickmer2:
    """Run QuicK-mer2 against a per-sample CRAM."""
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        archive=MDIR + "{sample}/align/{alnr}/{ddup}/cnv/quickmer2/{sample}.{alnr}.{ddup}.quickmer2.tar.gz",
        done=MDIR + "{sample}/align/{alnr}/{ddup}/cnv/quickmer2/{sample}.{alnr}.{ddup}.quickmer2.done",
    threads: _quickmer2_cfg().get("threads", 8)
    resources:
        threads=lambda wildcards, attempt: _quickmer2_cfg().get("threads", 8),
        mem_mb=lambda wildcards, attempt: _quickmer2_cfg().get("mem_mb", 64000),
        partition=lambda wildcards, attempt: _quickmer2_cfg().get("partition", "i8"),
        time=lambda wildcards, attempt: _quickmer2_cfg().get("time", "24:00:00"),
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.quickmer2.bench.tsv",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/cnv/quickmer2/logs/{sample}.{alnr}.{ddup}.quickmer2.log",
    params:
        cluster_sample=ret_sample,
        repo_dir=lambda wildcards: _quickmer2_repo_dir(),
        repo_url=lambda wildcards: _quickmer2_cfg().get(
            "repo_url", "https://github.com/KiddLab/QuicK-mer2.git"
        ),
        repo_rev=lambda wildcards: _quickmer2_cfg().get("repo_rev", "main"),
        clone_depth=lambda wildcards: str(_quickmer2_cfg().get("clone_depth", 1)),
        update_repo=lambda wildcards: str(_quickmer2_cfg().get("update_repo", True)).lower(),
        run_dir=_quickmer2_run_dir,
        command=lambda wildcards, input, threads: _quickmer2_command(wildcards, input, threads),
        keep_work=lambda wildcards: str(_quickmer2_cfg().get("keep_work", False)).lower(),
    conda:
        _quickmer2_cfg().get("env_yaml", "../envs/quickmer2_v0.1.yaml"),
    shell:
        r"""
        set -euo pipefail

        mkdir -p $(dirname {log})
        mkdir -p $(dirname {output.archive})

        repo_dir="{params.repo_dir}"
        if [ ! -d "$repo_dir/.git" ]; then
            rm -rf "$repo_dir"
            git clone --depth {params.clone_depth} {params.repo_url} "$repo_dir" >> {log} 2>&1
        elif [ "{params.update_repo}" = "true" ]; then
            git -C "$repo_dir" fetch --tags >> {log} 2>&1
        fi

        if [ "{params.repo_rev}" != "" ]; then
            git -C "$repo_dir" checkout {params.repo_rev} >> {log} 2>&1
        fi

        run_dir="{params.run_dir}"
        rm -rf "$run_dir"
        mkdir -p "$run_dir"

        {params.command} >> {log} 2>&1

        if [ -d "$run_dir" ]; then
            tar -C "$run_dir" -czf {output.archive} . >> {log} 2>&1 || true
        fi

        touch {output.done}

        if [ "{params.keep_work}" = "false" ]; then
            rm -rf "$run_dir"
        fi
        """


localrules:
    produce_quickmer2,


rule produce_quickmer2:  # TARGET : Produce QuicK-mer2 copy-number results
    """Target rule to ensure QuicK-mer2 outputs exist for all CRAM alignments."""
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/cnv/quickmer2/{sample}.{alnr}.quickmer2.done",
            sample=SAMPS,
            alnr=CRAM_ALIGNERS,
        ),
    output:
        touch(MDIR + "other_reports/quickmer2_gather.done"),
    log:
        MDIR + "logs/produce_quickmer2.log"
    benchmark:
        "logs/benchmarks/produce_quickmer2.bench.tsv"
    shell:
        "touch {output};"
