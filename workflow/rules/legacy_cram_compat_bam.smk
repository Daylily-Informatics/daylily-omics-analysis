rule legacy_cram_compat_bam:
    """
    Materialize a temporary indexed BAM for tools with old or strict CRAM readers.

    The output is temp() so workflows that need a BAM path can share one
    conversion without leaving a persistent sidecar next to the canonical CRAM.
    """
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
        ref_fa=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    output:
        bam=temp(MDIR + "{sample}/align/{alnr}/{ddup}/compat_bam/{sample}.{alnr}.{ddup}.legacy_compat.bam"),
        bai=temp(MDIR + "{sample}/align/{alnr}/{ddup}/compat_bam/{sample}.{alnr}.{ddup}.legacy_compat.bam.bai"),
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/compat_bam/logs/{sample}.{alnr}.{ddup}.legacy_compat_bam.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.legacy_compat_bam.bench.tsv",
    conda:
        config.get("legacy_cram_compat_bam", {}).get("env_yaml", "../envs/samtools_v0.1.yaml")
    threads:
        int(config.get("legacy_cram_compat_bam", {}).get("threads", 16))
    resources:
        vcpu=int(config.get("legacy_cram_compat_bam", {}).get("threads", 16)),
        threads=int(config.get("legacy_cram_compat_bam", {}).get("threads", 16)),
        mem_mb=int(config.get("legacy_cram_compat_bam", {}).get("mem_mb", 50000)),
        partition=config.get("legacy_cram_compat_bam", {}).get("partition", "i384nvme,i192nvme,i192,i128"),
    params:
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.bam:q}) $(dirname {log:q})
        tmp_parent="/scratch"
        test -d "$tmp_parent"
        test -w "$tmp_parent"
        timestamp=$(date +%Y%m%d%H%M%S)_$$
        export TMPDIR="$tmp_parent/legacy_cram_compat_bam_$timestamp"
        mkdir -p "$TMPDIR"
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT
        tmp_bam="$TMPDIR/legacy_compat.bam"
        tmp_bai="$TMPDIR/legacy_compat.bam.bai"
        samtools view -@ {threads} -b -T {input.ref_fa:q} -o "$tmp_bam" {input.cram:q} > {log:q} 2>&1
        samtools index -@ {threads} "$tmp_bam" "$tmp_bai" >> {log:q} 2>&1
        samtools quickcheck "$tmp_bam" >> {log:q} 2>&1
        test -s "$tmp_bam"
        test -s "$tmp_bai"
        cp "$tmp_bam" {output.bam:q}
        cp "$tmp_bai" {output.bai:q}
        test -s {output.bam:q}
        test -s {output.bai:q}
        """
