# noqa
from snakemake.exceptions import WorkflowError

# #### BBSplit contamination removal
# ----------------------------------
# https://jgi.doe.gov/data-and-tools/bbtools/bb-tools-user-guide/bbsplit-guide/


def _collect_bbsplit_refs():
    """Return a comma separated list of reference fasta paths for BBSplit."""
    refs_cfg = (
        config
        .get("supporting_files", {})
        .get("files", {})
        .get("bbsplit", {})
        .get("references", {})
    )

    refs = []
    if isinstance(refs_cfg, dict):
        for value in refs_cfg.values():
            if isinstance(value, dict):
                ref_path = value.get("name", "")
            else:
                ref_path = value
            if ref_path not in [None, "", "na"]:
                refs.append(ref_path)
    elif isinstance(refs_cfg, (list, tuple)):
        for value in refs_cfg:
            if isinstance(value, dict):
                ref_path = value.get("name", "")
            else:
                ref_path = value
            if ref_path not in [None, "", "na"]:
                refs.append(ref_path)

    if not refs:
        raise WorkflowError(
            "No reference FASTA files configured for BBSplit. "
            "Set config['supporting_files']['files']['bbsplit']['references'] "
            "with one or more valid paths."
        )

    return ",".join(refs)


rule bbsplit_contam:
    input:
        r1=get_raw_R1s,
        r2=get_raw_R2s,
    output:
        clean_r1=MDIR + "{sample}/seqqc/bbsplit/{sample}.bbsplit.clean.R1.fastq.gz",
        clean_r2=MDIR + "{sample}/seqqc/bbsplit/{sample}.bbsplit.clean.R2.fastq.gz",
        clean_single=MDIR + "{sample}/seqqc/bbsplit/{sample}.bbsplit.clean.single.fastq.gz",
        summary=MDIR + "{sample}/seqqc/bbsplit/{sample}.bbsplit.summary.txt",
        refstats=MDIR + "{sample}/seqqc/bbsplit/{sample}.bbsplit.refstats.txt",
        scafstats=MDIR + "{sample}/seqqc/bbsplit/{sample}.bbsplit.scafstats.txt",
        done=MDIR + "{sample}/seqqc/bbsplit/{sample}.bbsplit.done",
    log:
        MDIR + "{sample}/logs/seqqc/bbsplit/{sample}.bbsplit.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.bbsplit.bench.tsv",
    threads: config["bbsplit_contam"]["threads"]
    resources:
        vcpu=config["bbsplit_contam"]["threads"],
        partition=config["bbsplit_contam"]["partition"],
        mem_mb=lambda wildcards: config["bbsplit_contam"].get("mem_mb", 0),
    params:
        in1=lambda wildcards, input: ",".join(sorted(input.r1)),
        in2=lambda wildcards, input: ",".join(sorted(input.r2)),
        ref_string=lambda wildcards: _collect_bbsplit_refs(),
        basename=MDIR + "{sample}/seqqc/bbsplit/{sample}.bbsplit.%.fastq.gz",
        extra_args=lambda wildcards: config["bbsplit_contam"].get("extra_args", ""),
        outdir=MDIR + "{sample}/seqqc/bbsplit/",
        logdir=MDIR + "{sample}/logs/seqqc/bbsplit/",
        cluster_sample=ret_sample,
    conda:
        config["bbsplit_contam"]["env_yaml"]
    shell:
        r"""
        set -euo pipefail

        mkdir -p "{params.outdir}" "{params.logdir}"

        bbsplit.sh \
            threads={threads} \
            in1="{params.in1}" \
            in2="{params.in2}" \
            ref="{params.ref_string}" \
            basename="{params.basename}" \
            outu1="{output.clean_r1}" \
            outu2="{output.clean_r2}" \
            outu="{output.clean_single}" \
            statsfile="{output.summary}" \
            refstats="{output.refstats}" \
            scafstats="{output.scafstats}" \
            {params.extra_args} \
            &>> {log}

        touch {output.done}
        """
