ALIGNMENT_PRESERVATION_AUDIT_CFG = config.get("alignment_preservation_audit", {})
ALIGNMENT_PRESERVATION_AUDIT_DIR = MDIR + "reports/alignment_preservation_audit"


localrules:
    produce_alignment_preservation_audit,


rule alignment_preservation_audit:
    output:
        markdown=ALIGNMENT_PRESERVATION_AUDIT_DIR + "/alignment_preservation_audit.md",
        tsv=ALIGNMENT_PRESERVATION_AUDIT_DIR + "/alignment_preservation_audit.tsv",
    benchmark:
        MDIR + "benchmarks/alignment_preservation_audit.bench.tsv"
    threads: ALIGNMENT_PRESERVATION_AUDIT_CFG.get("threads", 1)
    params:
        cluster_sample="alignment_preservation_audit",
    resources:
        threads=ALIGNMENT_PRESERVATION_AUDIT_CFG.get("threads", 1),
        vcpu=ALIGNMENT_PRESERVATION_AUDIT_CFG.get("threads", 1),
        mem_mb=ALIGNMENT_PRESERVATION_AUDIT_CFG.get("mem_mb", 1000),
        partition=ALIGNMENT_PRESERVATION_AUDIT_CFG.get("partition", "i8"),
    log:
        MDIR + "reports/logs/alignment_preservation_audit.log",
    conda:
        ALIGNMENT_PRESERVATION_AUDIT_CFG.get("env_yaml", "../envs/samtools_v0.1.yaml")
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
