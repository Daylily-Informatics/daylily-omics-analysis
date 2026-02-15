#########  no dedup – CRAM passthrough (na)
# -------------------------------------------
# code=na
# For CRAM-producing aligners (sentmm2, sentmm2ont, etc.) that output
# directly to {sample}/align/{alnr}/{sample}.{alnr}.cram, this rule
# symlinks into the /{ddup}/ directory structure expected by downstream
# rules:  {sample}/align/{alnr}/na/{sample}.{alnr}.na.cram
#
# PacBio HiFi PCR-free and ONT long reads do not require deduplication,
# so the only valid dedup code for these aligners is "na".
#
# No conditional guard — rule is always defined.
# Selection is via wildcard_constraints restricting alnr to CRAM_ALIGNERS.


rule no_dedup_cram:
    """Symlink CRAM-producing aligner output into the /na/ dedup directory."""
    input:
        cram=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
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

