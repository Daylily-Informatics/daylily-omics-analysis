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
        mem_mb=int(config.get("legacy_cram_compat_bam", {}).get("mem_mb", 32000)),
        partition=config.get("legacy_cram_compat_bam", {}).get("partition", "i192,i192mem,i128"),
    params:
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.bam}) $(dirname {log})
        samtools view -@ {threads} -b -T {input.ref_fa} -o {output.bam} {input.cram} > {log} 2>&1
        samtools index -@ {threads} {output.bam} {output.bai} >> {log} 2>&1
        samtools quickcheck {output.bam} >> {log} 2>&1
        test -s {output.bai}
        """
