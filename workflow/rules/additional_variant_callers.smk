"""Snakemake rules for additional variant callers.

Each tool pulls configuration from ``config[tool_name]`` with
commonly used keys such as ``threads``, ``mem_mb``, ``partition``,
``env_yaml`` (or ``conda``) and ``container``.  A
``command_template`` entry can be provided for fully customised
execution.  When a command template is not supplied the rules fall
back to touching their expected outputs so that the workflow can be
wired and tested without immediately invoking the caller.
"""

from textwrap import dedent


# ---------------------------------------------------------------------------
# Helper utilities shared across the caller rules
# ---------------------------------------------------------------------------

def _default_reference():
    """Return the configured primary reference FASTA when available."""

    files = config.get("supporting_files", {}).get("files", {})
    huref = files.get("huref", {})
    fasta = huref.get("fasta", {})
    return fasta.get("name")


def _prepare_inputs(base_inputs, extra_cfg):
    """Merge common inputs with any static files requested in the config."""

    inputs = dict(base_inputs)
    for key, value in extra_cfg.get("extra_inputs", {}).items():
        if value:
            inputs[key] = value
    return inputs


def _build_command(tool, cfg, wildcards, inputs, outputs, threads, log):
    """Return the command to execute for *tool* based on ``command_template``.

    The template receives the combined ``inputs``/``outputs`` mapping along
    with ``sample``, ``aligner``, ``threads``, ``tool`` and ``log``.
    If no template is provided the command falls back to simply touching the
    primary output so the workflow remains functional in dry-run / skeleton
    mode.
    """

    template = cfg.get("command_template", "").strip()
    values = {
        "tool": tool,
        "sample": wildcards.sample,
        "aligner": getattr(wildcards, "alnr", ""),
        "threads": threads,
        "log": log if isinstance(log, str) else " ".join(log),
        "extra_args": cfg.get("extra_args", ""),
    }
    values.update({k: v for k, v in inputs.items() if v})
    values.update({k: v for k, v in outputs.items() if v})

    if template:
        command = template.format(**values)
        return dedent(command).strip()

    # Default placeholder command – touch the first declared output.
    primary_output = next(iter(outputs.values()))
    return f"touch {primary_output}"


# ---------------------------------------------------------------------------
# ASCAT – Somatic copy number caller
# ---------------------------------------------------------------------------

ASCAT_CFG = config.get("ascat", {})
ASCAT_THREADS = ASCAT_CFG.get("threads", 4)
ASCAT_MEM_MB = ASCAT_CFG.get("mem_mb", 16000)
ASCAT_ENV = ASCAT_CFG.get("env_yaml", "../envs/vanilla_v0.1.yaml")


def _ascat_inputs(wildcards):
    base = {
        "tumor_cram": get_somcall_tumor_cram(wildcards),
        "tumor_crai": get_somcall_tumor_crai(wildcards),
    }
    if ASCAT_CFG.get("use_normal", True):
        base.update(
            {
                "normal_cram": get_somcall_normal_cram(wildcards),
                "normal_crai": get_somcall_normal_crai(wildcards),
            }
        )
    reference = ASCAT_CFG.get("reference", _default_reference())
    if reference:
        base["reference"] = reference
    return _prepare_inputs(base, ASCAT_CFG)


rule ascat:
    """Run ASCAT on tumour/normal pairs."""

    input:
        _ascat_inputs
    output:
        results_dir=directory(MDIR + "{sample}/align/{alnr}/cnv/ascat/{sample}.{alnr}.ascat"),
        done=MDIR + "{sample}/align/{alnr}/cnv/ascat/{sample}.{alnr}.ascat.done",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards, input, output, threads, log: _build_command(
            "ascat",
            ASCAT_CFG,
            wildcards,
            {
                "tumor_cram": input.tumor_cram,
                "tumor_crai": input.tumor_crai,
                "normal_cram": getattr(input, "normal_cram", None),
                "normal_crai": getattr(input, "normal_crai", None),
                "reference": getattr(input, "reference", None),
            },
            {
                "results_dir": output.results_dir,
                "done": output.done,
            },
            threads,
            log,
        ),
    log:
        MDIR + "{sample}/align/{alnr}/cnv/ascat/logs/{sample}.{alnr}.ascat.log",
    threads: ASCAT_THREADS
    resources:
        mem_mb=ASCAT_MEM_MB
    conda:
        ASCAT_ENV
    shell:
        """
        set -euo pipefail
        mkdir -p "$(dirname {log})"
        rm -rf {output.results_dir}
        mkdir -p {output.results_dir}
        {params.command} > {log} 2>&1 || {{ cat {log} >&2; exit 1; }}
        touch {output.done}
        """


# ---------------------------------------------------------------------------
# CNVkit – Somatic copy number caller
# ---------------------------------------------------------------------------

CNVKIT_CFG = config.get("cnvkit", {})
CNVKIT_THREADS = CNVKIT_CFG.get("threads", 4)
CNVKIT_MEM_MB = CNVKIT_CFG.get("mem_mb", 16000)
CNVKIT_ENV = CNVKIT_CFG.get("env_yaml", "../envs/vanilla_v0.1.yaml")


def _cnvkit_inputs(wildcards):
    base = {
        "tumor_cram": get_somcall_tumor_cram(wildcards),
        "tumor_crai": get_somcall_tumor_crai(wildcards),
    }
    if CNVKIT_CFG.get("use_normal", True):
        base.update(
            {
                "normal_cram": get_somcall_normal_cram(wildcards),
                "normal_crai": get_somcall_normal_crai(wildcards),
            }
        )
    reference = CNVKIT_CFG.get("reference", _default_reference())
    if reference:
        base["reference"] = reference
    return _prepare_inputs(base, CNVKIT_CFG)


rule cnvkit:
    """Run CNVkit on tumour/normal pairs."""

    input:
        _cnvkit_inputs
    output:
        results_dir=directory(MDIR + "{sample}/align/{alnr}/cnv/cnvkit/{sample}.{alnr}.cnvkit"),
        done=MDIR + "{sample}/align/{alnr}/cnv/cnvkit/{sample}.{alnr}.cnvkit.done",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards, input, output, threads, log: _build_command(
            "cnvkit",
            CNVKIT_CFG,
            wildcards,
            {
                "tumor_cram": input.tumor_cram,
                "tumor_crai": input.tumor_crai,
                "normal_cram": getattr(input, "normal_cram", None),
                "normal_crai": getattr(input, "normal_crai", None),
                "reference": getattr(input, "reference", None),
            },
            {
                "results_dir": output.results_dir,
                "done": output.done,
            },
            threads,
            log,
        ),
    log:
        MDIR + "{sample}/align/{alnr}/cnv/cnvkit/logs/{sample}.{alnr}.cnvkit.log",
    threads: CNVKIT_THREADS
    resources:
        mem_mb=CNVKIT_MEM_MB
    conda:
        CNVKIT_ENV
    shell:
        """
        set -euo pipefail
        mkdir -p "$(dirname {log})"
        rm -rf {output.results_dir}
        mkdir -p {output.results_dir}
        {params.command} > {log} 2>&1 || {{ cat {log} >&2; exit 1; }}
        touch {output.done}
        """


# ---------------------------------------------------------------------------
# Control-FREEC – Somatic copy number caller
# ---------------------------------------------------------------------------

FREEC_CFG = config.get("control_freec", {})
FREEC_THREADS = FREEC_CFG.get("threads", 4)
FREEC_MEM_MB = FREEC_CFG.get("mem_mb", 16000)
FREEC_ENV = FREEC_CFG.get("env_yaml", "../envs/vanilla_v0.1.yaml")


def _freec_inputs(wildcards):
    base = {
        "tumor_cram": get_somcall_tumor_cram(wildcards),
        "tumor_crai": get_somcall_tumor_crai(wildcards),
    }
    if FREEC_CFG.get("use_normal", True):
        base.update(
            {
                "normal_cram": get_somcall_normal_cram(wildcards),
                "normal_crai": get_somcall_normal_crai(wildcards),
            }
        )
    reference = FREEC_CFG.get("reference", _default_reference())
    if reference:
        base["reference"] = reference
    return _prepare_inputs(base, FREEC_CFG)


rule control_freec:
    """Run Control-FREEC on tumour/normal pairs."""

    input:
        _freec_inputs
    output:
        results_dir=directory(MDIR + "{sample}/align/{alnr}/cnv/control_freec/{sample}.{alnr}.freec"),
        done=MDIR + "{sample}/align/{alnr}/cnv/control_freec/{sample}.{alnr}.freec.done",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards, input, output, threads, log: _build_command(
            "control_freec",
            FREEC_CFG,
            wildcards,
            {
                "tumor_cram": input.tumor_cram,
                "tumor_crai": input.tumor_crai,
                "normal_cram": getattr(input, "normal_cram", None),
                "normal_crai": getattr(input, "normal_crai", None),
                "reference": getattr(input, "reference", None),
            },
            {
                "results_dir": output.results_dir,
                "done": output.done,
            },
            threads,
            log,
        ),
    log:
        MDIR + "{sample}/align/{alnr}/cnv/control_freec/logs/{sample}.{alnr}.freec.log",
    threads: FREEC_THREADS
    resources:
        mem_mb=FREEC_MEM_MB
    conda:
        FREEC_ENV
    shell:
        """
        set -euo pipefail
        mkdir -p "$(dirname {log})"
        rm -rf {output.results_dir}
        mkdir -p {output.results_dir}
        {params.command} > {log} 2>&1 || {{ cat {log} >&2; exit 1; }}
        touch {output.done}
        """


# ---------------------------------------------------------------------------
# FreeBayes – Germline SNV caller
# ---------------------------------------------------------------------------

FREEBAYES_CFG = config.get("freebayes", {})
FREEBAYES_THREADS = FREEBAYES_CFG.get("threads", 4)
FREEBAYES_MEM_MB = FREEBAYES_CFG.get("mem_mb", 16000)
FREEBAYES_ENV = FREEBAYES_CFG.get("env_yaml", "../envs/vanilla_v0.1.yaml")


def _freebayes_inputs(wildcards):
    base = {
        "cram": get_somcall_tumor_cram(wildcards),
        "crai": get_somcall_tumor_crai(wildcards),
    }
    reference = FREEBAYES_CFG.get("reference", _default_reference())
    if reference:
        base["reference"] = reference
    return _prepare_inputs(base, FREEBAYES_CFG)


rule freebayes:
    """Run FreeBayes germline calling."""

    input:
        _freebayes_inputs
    output:
        vcf=MDIR + "{sample}/align/{alnr}/snv/freebayes/{sample}.{alnr}.freebayes.vcf.gz",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards, input, output, threads, log: _build_command(
            "freebayes",
            FREEBAYES_CFG,
            wildcards,
            {
                "cram": input.cram,
                "crai": input.crai,
                "reference": getattr(input, "reference", None),
            },
            {"vcf": output.vcf},
            threads,
            log,
        ),
    log:
        MDIR + "{sample}/align/{alnr}/snv/freebayes/logs/{sample}.{alnr}.freebayes.log",
    threads: FREEBAYES_THREADS
    resources:
        mem_mb=FREEBAYES_MEM_MB
    conda:
        FREEBAYES_ENV
    shell:
        """
        set -euo pipefail
        mkdir -p "$(dirname {output.vcf})"
        mkdir -p "$(dirname {log})"
        {params.command} > {log} 2>&1 || {{ cat {log} >&2; exit 1; }}
        """


# ---------------------------------------------------------------------------
# GATK HaplotypeCaller – Germline caller
# ---------------------------------------------------------------------------

GHC_CFG = config.get("gatk_haplotypecaller", {})
GHC_THREADS = GHC_CFG.get("threads", 4)
GHC_MEM_MB = GHC_CFG.get("mem_mb", 16000)
GHC_ENV = GHC_CFG.get("env_yaml", "../envs/vanilla_v0.1.yaml")


def _haplotype_inputs(wildcards):
    base = {
        "cram": get_somcall_tumor_cram(wildcards),
        "crai": get_somcall_tumor_crai(wildcards),
    }
    reference = GHC_CFG.get("reference", _default_reference())
    if reference:
        base["reference"] = reference
    return _prepare_inputs(base, GHC_CFG)


rule gatk_haplotypecaller:
    """Run GATK HaplotypeCaller in GVCF mode."""

    input:
        _haplotype_inputs
    output:
        gvcf=MDIR + "{sample}/align/{alnr}/snv/gatk_haplotypecaller/{sample}.{alnr}.haplotypecaller.g.vcf.gz",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards, input, output, threads, log: _build_command(
            "gatk_haplotypecaller",
            GHC_CFG,
            wildcards,
            {
                "cram": input.cram,
                "crai": input.crai,
                "reference": getattr(input, "reference", None),
            },
            {"gvcf": output.gvcf},
            threads,
            log,
        ),
    log:
        MDIR + "{sample}/align/{alnr}/snv/gatk_haplotypecaller/logs/{sample}.{alnr}.haplotypecaller.log",
    threads: GHC_THREADS
    resources:
        mem_mb=GHC_MEM_MB
    conda:
        GHC_ENV
    shell:
        """
        set -euo pipefail
        mkdir -p "$(dirname {output.gvcf})"
        mkdir -p "$(dirname {log})"
        {params.command} > {log} 2>&1 || {{ cat {log} >&2; exit 1; }}
        """


# ---------------------------------------------------------------------------
# GATK Mutect2 – Somatic caller (single-interval entry point)
# ---------------------------------------------------------------------------

M2_SIMPLE_CFG = config.get("gatk_mutect2", {})
M2_SIMPLE_THREADS = M2_SIMPLE_CFG.get("threads", 4)
M2_SIMPLE_MEM_MB = M2_SIMPLE_CFG.get("mem_mb", 16000)
M2_SIMPLE_ENV = M2_SIMPLE_CFG.get("env_yaml", "../envs/vanilla_v0.1.yaml")


def _mutect2_inputs(wildcards):
    base = {
        "tumor_cram": get_somcall_tumor_cram(wildcards),
        "tumor_crai": get_somcall_tumor_crai(wildcards),
        "normal_cram": get_somcall_normal_cram(wildcards),
        "normal_crai": get_somcall_normal_crai(wildcards),
    }
    reference = M2_SIMPLE_CFG.get("reference", _default_reference())
    if reference:
        base["reference"] = reference
    return _prepare_inputs(base, M2_SIMPLE_CFG)


rule gatk_mutect2:
    """Run a simple GATK Mutect2 somatic call."""

    input:
        _mutect2_inputs
    output:
        vcf=MDIR + "{sample}/align/{alnr}/snv/gatk_mutect2/{sample}.{alnr}.mutect2.vcf.gz",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards, input, output, threads, log: _build_command(
            "gatk_mutect2",
            M2_SIMPLE_CFG,
            wildcards,
            {
                "tumor_cram": input.tumor_cram,
                "tumor_crai": input.tumor_crai,
                "normal_cram": input.normal_cram,
                "normal_crai": input.normal_crai,
                "reference": getattr(input, "reference", None),
            },
            {"vcf": output.vcf},
            threads,
            log,
        ),
    log:
        MDIR + "{sample}/align/{alnr}/snv/gatk_mutect2/logs/{sample}.{alnr}.mutect2.log",
    threads: M2_SIMPLE_THREADS
    resources:
        mem_mb=M2_SIMPLE_MEM_MB
    conda:
        M2_SIMPLE_ENV
    shell:
        """
        set -euo pipefail
        mkdir -p "$(dirname {output.vcf})"
        mkdir -p "$(dirname {log})"
        {params.command} > {log} 2>&1 || {{ cat {log} >&2; exit 1; }}
        """


# ---------------------------------------------------------------------------
# indexcov – Coverage QC
# ---------------------------------------------------------------------------

INDEXCOV_CFG = config.get("indexcov", {})
INDEXCOV_THREADS = INDEXCOV_CFG.get("threads", 2)
INDEXCOV_MEM_MB = INDEXCOV_CFG.get("mem_mb", 8000)
INDEXCOV_ENV = INDEXCOV_CFG.get("env_yaml", "../envs/vanilla_v0.1.yaml")


def _indexcov_inputs(wildcards):
    base = {
        "cram": get_somcall_tumor_cram(wildcards),
        "crai": get_somcall_tumor_crai(wildcards),
    }
    reference = INDEXCOV_CFG.get("reference", _default_reference())
    if reference:
        base["reference"] = reference
    return _prepare_inputs(base, INDEXCOV_CFG)


rule indexcov:
    """Run indexcov QC reporting."""

    input:
        _indexcov_inputs
    output:
        tar=MDIR + "{sample}/align/{alnr}/qc/indexcov/{sample}.{alnr}.indexcov.tar.gz",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards, input, output, threads, log: _build_command(
            "indexcov",
            INDEXCOV_CFG,
            wildcards,
            {
                "cram": input.cram,
                "crai": input.crai,
                "reference": getattr(input, "reference", None),
            },
            {"tar": output.tar},
            threads,
            log,
        ),
    log:
        MDIR + "{sample}/align/{alnr}/qc/indexcov/logs/{sample}.{alnr}.indexcov.log",
    threads: INDEXCOV_THREADS
    resources:
        mem_mb=INDEXCOV_MEM_MB
    conda:
        INDEXCOV_ENV
    shell:
        """
        set -euo pipefail
        mkdir -p "$(dirname {output.tar})"
        mkdir -p "$(dirname {log})"
        {params.command} > {log} 2>&1 || {{ cat {log} >&2; exit 1; }}
        """


# ---------------------------------------------------------------------------
# mpileup – Raw pileup generation
# ---------------------------------------------------------------------------

MPILEUP_CFG = config.get("mpileup", {})
MPILEUP_THREADS = MPILEUP_CFG.get("threads", 2)
MPILEUP_MEM_MB = MPILEUP_CFG.get("mem_mb", 8000)
MPILEUP_ENV = MPILEUP_CFG.get("env_yaml", "../envs/vanilla_v0.1.yaml")


def _mpileup_inputs(wildcards):
    base = {
        "cram": get_somcall_tumor_cram(wildcards),
        "crai": get_somcall_tumor_crai(wildcards),
    }
    reference = MPILEUP_CFG.get("reference", _default_reference())
    if reference:
        base["reference"] = reference
    return _prepare_inputs(base, MPILEUP_CFG)


rule mpileup:
    """Generate a mpileup track for downstream inspection."""

    input:
        _mpileup_inputs
    output:
        pileup=MDIR + "{sample}/align/{alnr}/snv/mpileup/{sample}.{alnr}.mpileup.txt",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards, input, output, threads, log: _build_command(
            "mpileup",
            MPILEUP_CFG,
            wildcards,
            {
                "cram": input.cram,
                "crai": input.crai,
                "reference": getattr(input, "reference", None),
            },
            {"pileup": output.pileup},
            threads,
            log,
        ),
    log:
        MDIR + "{sample}/align/{alnr}/snv/mpileup/logs/{sample}.{alnr}.mpileup.log",
    threads: MPILEUP_THREADS
    resources:
        mem_mb=MPILEUP_MEM_MB
    conda:
        MPILEUP_ENV
    shell:
        """
        set -euo pipefail
        mkdir -p "$(dirname {output.pileup})"
        mkdir -p "$(dirname {log})"
        {params.command} > {log} 2>&1 || {{ cat {log} >&2; exit 1; }}
        """


# ---------------------------------------------------------------------------
# MSIsensor2 – Microsatellite instability caller
# ---------------------------------------------------------------------------

MSIS2_CFG = config.get("msisensor2", {})
MSIS2_THREADS = MSIS2_CFG.get("threads", 4)
MSIS2_MEM_MB = MSIS2_CFG.get("mem_mb", 8000)
MSIS2_ENV = MSIS2_CFG.get("env_yaml", "../envs/vanilla_v0.1.yaml")


def _msisensor2_inputs(wildcards):
    base = {
        "tumor_cram": get_somcall_tumor_cram(wildcards),
        "tumor_crai": get_somcall_tumor_crai(wildcards),
    }
    if MSIS2_CFG.get("use_normal", True):
        base.update(
            {
                "normal_cram": get_somcall_normal_cram(wildcards),
                "normal_crai": get_somcall_normal_crai(wildcards),
            }
        )
    reference = MSIS2_CFG.get("reference", _default_reference())
    if reference:
        base["reference"] = reference
    return _prepare_inputs(base, MSIS2_CFG)


rule msisensor2:
    """Run MSIsensor2 for MSI detection."""

    input:
        _msisensor2_inputs
    output:
        report=MDIR + "{sample}/align/{alnr}/msi/msisensor2/{sample}.{alnr}.msisensor2.txt",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards, input, output, threads, log: _build_command(
            "msisensor2",
            MSIS2_CFG,
            wildcards,
            {
                "tumor_cram": input.tumor_cram,
                "tumor_crai": input.tumor_crai,
                "normal_cram": getattr(input, "normal_cram", None),
                "normal_crai": getattr(input, "normal_crai", None),
                "reference": getattr(input, "reference", None),
            },
            {"report": output.report},
            threads,
            log,
        ),
    log:
        MDIR + "{sample}/align/{alnr}/msi/msisensor2/logs/{sample}.{alnr}.msisensor2.log",
    threads: MSIS2_THREADS
    resources:
        mem_mb=MSIS2_MEM_MB
    conda:
        MSIS2_ENV
    shell:
        """
        set -euo pipefail
        mkdir -p "$(dirname {output.report})"
        mkdir -p "$(dirname {log})"
        {params.command} > {log} 2>&1 || {{ cat {log} >&2; exit 1; }}
        """


# ---------------------------------------------------------------------------
# MSIsensor-pro – Microsatellite instability caller
# ---------------------------------------------------------------------------

MSISPRO_CFG = config.get("msisensor_pro", {})
MSISPRO_THREADS = MSISPRO_CFG.get("threads", 4)
MSISPRO_MEM_MB = MSISPRO_CFG.get("mem_mb", 8000)
MSISPRO_ENV = MSISPRO_CFG.get("env_yaml", "../envs/vanilla_v0.1.yaml")


def _msisensor_pro_inputs(wildcards):
    base = {
        "tumor_cram": get_somcall_tumor_cram(wildcards),
        "tumor_crai": get_somcall_tumor_crai(wildcards),
    }
    if MSISPRO_CFG.get("use_normal", True):
        base.update(
            {
                "normal_cram": get_somcall_normal_cram(wildcards),
                "normal_crai": get_somcall_normal_crai(wildcards),
            }
        )
    reference = MSISPRO_CFG.get("reference", _default_reference())
    if reference:
        base["reference"] = reference
    return _prepare_inputs(base, MSISPRO_CFG)


rule msisensor_pro:
    """Run MSIsensor-pro for MSI detection."""

    input:
        _msisensor_pro_inputs
    output:
        report=MDIR + "{sample}/align/{alnr}/msi/msisensor_pro/{sample}.{alnr}.msisensor_pro.txt",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards, input, output, threads, log: _build_command(
            "msisensor_pro",
            MSISPRO_CFG,
            wildcards,
            {
                "tumor_cram": input.tumor_cram,
                "tumor_crai": input.tumor_crai,
                "normal_cram": getattr(input, "normal_cram", None),
                "normal_crai": getattr(input, "normal_crai", None),
                "reference": getattr(input, "reference", None),
            },
            {"report": output.report},
            threads,
            log,
        ),
    log:
        MDIR + "{sample}/align/{alnr}/msi/msisensor_pro/logs/{sample}.{alnr}.msisensor_pro.log",
    threads: MSISPRO_THREADS
    resources:
        mem_mb=MSISPRO_MEM_MB
    conda:
        MSISPRO_ENV
    shell:
        """
        set -euo pipefail
        mkdir -p "$(dirname {output.report})"
        mkdir -p "$(dirname {log})"
        {params.command} > {log} 2>&1 || {{ cat {log} >&2; exit 1; }}
        """


# ---------------------------------------------------------------------------
# MuSE – Somatic caller
# ---------------------------------------------------------------------------

MUSE_CFG = config.get("muse", {})
MUSE_THREADS = MUSE_CFG.get("threads", 4)
MUSE_MEM_MB = MUSE_CFG.get("mem_mb", 16000)
MUSE_ENV = MUSE_CFG.get("env_yaml", "../envs/vanilla_v0.1.yaml")


def _muse_inputs(wildcards):
    base = {
        "tumor_cram": get_somcall_tumor_cram(wildcards),
        "tumor_crai": get_somcall_tumor_crai(wildcards),
        "normal_cram": get_somcall_normal_cram(wildcards),
        "normal_crai": get_somcall_normal_crai(wildcards),
    }
    reference = MUSE_CFG.get("reference", _default_reference())
    if reference:
        base["reference"] = reference
    return _prepare_inputs(base, MUSE_CFG)


rule muse:
    """Run MuSE somatic calling."""

    input:
        _muse_inputs
    output:
        vcf=MDIR + "{sample}/align/{alnr}/snv/muse/{sample}.{alnr}.muse.vcf.gz",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards, input, output, threads, log: _build_command(
            "muse",
            MUSE_CFG,
            wildcards,
            {
                "tumor_cram": input.tumor_cram,
                "tumor_crai": input.tumor_crai,
                "normal_cram": input.normal_cram,
                "normal_crai": input.normal_crai,
                "reference": getattr(input, "reference", None),
            },
            {"vcf": output.vcf},
            threads,
            log,
        ),
    log:
        MDIR + "{sample}/align/{alnr}/snv/muse/logs/{sample}.{alnr}.muse.log",
    threads: MUSE_THREADS
    resources:
        mem_mb=MUSE_MEM_MB
    conda:
        MUSE_ENV
    shell:
        """
        set -euo pipefail
        mkdir -p "$(dirname {output.vcf})"
        mkdir -p "$(dirname {log})"
        {params.command} > {log} 2>&1 || {{ cat {log} >&2; exit 1; }}
        """


# ---------------------------------------------------------------------------
# Strelka – Somatic caller wrapper (germline or tumour/normal)
# ---------------------------------------------------------------------------

STRELKA_CFG = config.get("strelka", {})
STRELKA_THREADS = STRELKA_CFG.get("threads", 4)
STRELKA_MEM_MB = STRELKA_CFG.get("mem_mb", 16000)
STRELKA_ENV = STRELKA_CFG.get("env_yaml", "../envs/vanilla_v0.1.yaml")


def _strelka_inputs(wildcards):
    base = {
        "tumor_cram": get_somcall_tumor_cram(wildcards),
        "tumor_crai": get_somcall_tumor_crai(wildcards),
    }
    if STRELKA_CFG.get("use_normal", True):
        base.update(
            {
                "normal_cram": get_somcall_normal_cram(wildcards),
                "normal_crai": get_somcall_normal_crai(wildcards),
            }
        )
    reference = STRELKA_CFG.get("reference", _default_reference())
    if reference:
        base["reference"] = reference
    return _prepare_inputs(base, STRELKA_CFG)


rule strelka:
    """Run the Strelka somatic caller wrapper."""

    input:
        _strelka_inputs
    output:
        vcf=MDIR + "{sample}/align/{alnr}/snv/strelka/{sample}.{alnr}.strelka.vcf.gz",
    params:
        cluster_sample=ret_sample,
        command=lambda wildcards, input, output, threads, log: _build_command(
            "strelka",
            STRELKA_CFG,
            wildcards,
            {
                "tumor_cram": input.tumor_cram,
                "tumor_crai": input.tumor_crai,
                "normal_cram": getattr(input, "normal_cram", None),
                "normal_crai": getattr(input, "normal_crai", None),
                "reference": getattr(input, "reference", None),
            },
            {"vcf": output.vcf},
            threads,
            log,
        ),
    log:
        MDIR + "{sample}/align/{alnr}/snv/strelka/logs/{sample}.{alnr}.strelka.log",
    threads: STRELKA_THREADS
    resources:
        mem_mb=STRELKA_MEM_MB
    conda:
        STRELKA_ENV
    shell:
        """
        set -euo pipefail
        mkdir -p "$(dirname {output.vcf})"
        mkdir -p "$(dirname {log})"
        {params.command} > {log} 2>&1 || {{ cat {log} >&2; exit 1; }}
        """
