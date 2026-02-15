#########  no dedup – CRAM passthrough (na)
# -------------------------------------------
# code=na
# For CRAM-producing aligners, this rule symlinks into the /{ddup}/
# directory structure expected by downstream rules:
#   {sample}/align/{alnr}/na/{sample}.{alnr}.na.cram
#
# Handles two input naming conventions:
#   - Pre-aligned (ont, ug, pb): input is {sample}.cram  (no aligner infix)
#   - Pipeline   (sentmm2, sentmm2ont): input is {sample}.{alnr}.cram
#
# No conditional guard — rule is always defined.
# Selection is via wildcard_constraints restricting alnr to CRAM_ALIGNERS.

# Pre-aligned CRAM aligners produce {sample}.cram (no aligner infix)
_PRE_ALIGNED_CRAM_ALIGNERS = {"ont", "ug", "pb"}


def _no_dedup_cram_input(wildcards):
    """Return CRAM input path for the no_dedup_cram passthrough.

    Pre-aligned (ont, ug, pb): {sample}/align/{alnr}/{sample}.cram
    Pipeline (sentmm2, sentmm2ont): {sample}/align/{alnr}/{sample}.{alnr}.cram
    """
    if wildcards.alnr in _PRE_ALIGNED_CRAM_ALIGNERS:
        return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.cram"
    return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.{wildcards.alnr}.cram"


def _no_dedup_crai_input(wildcards):
    """Return CRAI input path (mirrors _no_dedup_cram_input)."""
    if wildcards.alnr in _PRE_ALIGNED_CRAM_ALIGNERS:
        return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.cram.crai"
    return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.{wildcards.alnr}.cram.crai"


# Prefer no_dedup_cram over the pre_prep_*_cram rules whose unconstrained
# {sample_lane} wildcard can accidentally match paths containing /na/.
ruleorder: no_dedup_cram > pre_prep_ont_cram
ruleorder: no_dedup_cram > pre_prep_ultima_cram
ruleorder: no_dedup_cram > pre_prep_pb_cram


rule no_dedup_cram:
    """Symlink CRAM-producing aligner output into the /na/ dedup directory."""
    input:
        cram=_no_dedup_cram_input,
        crai=_no_dedup_crai_input,
    priority: 3
    params:
        cluster_sample=ret_sample,
    output:
        cram=MDIR + "{sample}/align/{alnr}/na/{sample}.{alnr}.na.cram",
        crai=MDIR + "{sample}/align/{alnr}/na/{sample}.{alnr}.na.cram.crai",
    wildcard_constraints:
        alnr="|".join(CRAM_ALIGNERS) if CRAM_ALIGNERS else r"(?!x)x"
    threads: 1
    benchmark:
        repeat(MDIR + "{sample}/benchmarks/{sample}.{alnr}.na.mrkdup.bench.tsv", 0)
    resources:
        threads=1,
        partition=config.get("no_dedup", {}).get("partition", "i192"),
        vcpu=1,
        mem_mb=1000,
    log:
        MDIR + "{sample}/align/{alnr}/na/logs/dedupe.na.{sample}.{alnr}.log",
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.cram})
        touch {log}

        # Use relative symlinks so the tree is relocatable
        ln -sfn "$(realpath --relative-to=$(dirname {output.cram}) {input.cram})" {output.cram} >> {log} 2>&1
        ln -sfn "$(realpath --relative-to=$(dirname {output.crai}) {input.crai})" {output.crai} >> {log} 2>&1

        echo "Symlinked {input.cram} → {output.cram}" >> {log} 2>&1
        echo "Symlinked {input.crai} → {output.crai}" >> {log} 2>&1
        """

