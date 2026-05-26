from snakemake.exceptions import WorkflowError


if "alignment_preservation_audit" not in config or not isinstance(
    config["alignment_preservation_audit"], dict
):
    raise WorkflowError(
        "produce_alignment_preservation_audit requires alignment_preservation_audit config."
    )


ALIGNMENT_PRESERVATION_AUDIT_CFG = config["alignment_preservation_audit"]
ALIGNMENT_PRESERVATION_AUDIT_DIR = MDIR + "reports/alignment_preservation_audit"


def _alignment_preservation_required_config_value(key):
    value = str(ALIGNMENT_PRESERVATION_AUDIT_CFG.get(key, "")).strip()
    if value == "":
        raise WorkflowError(
            f"produce_alignment_preservation_audit requires "
            f"alignment_preservation_audit.{key}."
        )
    return value


def _alignment_preservation_required_config_int(key):
    value = _alignment_preservation_required_config_value(key)
    try:
        return int(value)
    except ValueError as exc:
        raise WorkflowError(
            f"alignment_preservation_audit.{key} must be an integer."
        ) from exc


ALIGNMENT_PRESERVATION_AUDIT_THREADS = _alignment_preservation_required_config_int("threads")
ALIGNMENT_PRESERVATION_AUDIT_MEM_MB = _alignment_preservation_required_config_int("mem_mb")
ALIGNMENT_PRESERVATION_AUDIT_PARTITION = _alignment_preservation_required_config_value("partition")
ALIGNMENT_PRESERVATION_AUDIT_ENV_YAML = _alignment_preservation_required_config_value("env_yaml")


localrules:
    produce_alignment_preservation_audit,


rule alignment_preservation_audit:
    output:
        markdown=ALIGNMENT_PRESERVATION_AUDIT_DIR + "/alignment_preservation_audit.md",
        tsv=ALIGNMENT_PRESERVATION_AUDIT_DIR + "/alignment_preservation_audit.tsv",
    benchmark:
        MDIR + "benchmarks/alignment_preservation_audit.bench.tsv"
    threads: ALIGNMENT_PRESERVATION_AUDIT_THREADS
    params:
        cluster_sample="alignment_preservation_audit",
    resources:
        threads=ALIGNMENT_PRESERVATION_AUDIT_THREADS,
        vcpu=ALIGNMENT_PRESERVATION_AUDIT_THREADS,
        mem_mb=ALIGNMENT_PRESERVATION_AUDIT_MEM_MB,
        partition=ALIGNMENT_PRESERVATION_AUDIT_PARTITION,
    log:
        MDIR + "reports/logs/alignment_preservation_audit.log",
    conda:
        ALIGNMENT_PRESERVATION_AUDIT_ENV_YAML
    container: None
    shell:
        """
        set -euo pipefail
        mkdir -p {ALIGNMENT_PRESERVATION_AUDIT_DIR:q} $(dirname {log:q})
        python workflow/scripts/alignment_preservation_audit.py audit \
          --repo-root . \
          --out-md {output.markdown:q} \
          --out-tsv {output.tsv:q} > {log:q} 2>&1
        """


rule produce_alignment_preservation_audit:  # TARGET: Audit BAM/CRAM read preservation contracts
    input:
        ALIGNMENT_PRESERVATION_AUDIT_DIR + "/alignment_preservation_audit.md",
        ALIGNMENT_PRESERVATION_AUDIT_DIR + "/alignment_preservation_audit.tsv",
