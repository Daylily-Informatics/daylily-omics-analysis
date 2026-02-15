#########  no dedup (na)
# --------------------------
# code=na
# comment="Skip duplicate marking. Convert sorted BAM to CRAM directly."
#
# No conditional guard — rule is always defined.
# Selection is via target rules expanding over ddup=DDUP.


rule no_dedup:
    """Convert sorted BAM → CRAM without duplicate marking."""
    input:
        bam=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.sort.bam",
        bai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.sort.bam.bai",
    priority: 3
    output:
        cram=MDIR + "{sample}/align/{alnr}/na/{sample}.{alnr}.na.cram",
        crai=MDIR + "{sample}/align/{alnr}/na/{sample}.{alnr}.na.cram.crai",
    wildcard_constraints:
        alnr="|".join(OG_ALIGNERS) if OG_ALIGNERS else r"(?!x)x"
    threads: config.get("no_dedup", {}).get("threads", 4)
    benchmark:
        repeat(MDIR + "{sample}/benchmarks/{sample}.{alnr}.na.mrkdup.bench.tsv", 0)
    resources:
        threads=config.get("no_dedup", {}).get("threads", 4),
        partition=config.get("no_dedup", {}).get("partition", "i192"),
        vcpu=config.get("no_dedup", {}).get("threads", 4),
        mem_mb=config.get("no_dedup", {}).get("mem_mb", 16000),
        constraint=config.get("no_dedup", {}).get("constraint", ""),
    params:
        cluster_sample=ret_sample,
        huref_fasta=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cram_compression=config.get("no_dedup", {}).get("cram_compression", "7"),
        view_threads=config.get("no_dedup", {}).get("view_threads", "4"),
    log:
        MDIR + "{sample}/align/{alnr}/na/logs/dedupe.na.{sample}.{alnr}.log",
    shell:
        """
        set -euo pipefail

        touch {log};
        TOKEN=$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type || echo "unknown");
        echo "INSTANCE TYPE: $itype" > {log};
        start_time=$(date +%s);

        samtools view \
            -@ {params.view_threads} \
            --output-fmt-option level={params.cram_compression} \
            -C -T {params.huref_fasta} \
            --write-index \
            -o {output.cram} \
            {input.bam} >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time";
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;

        """

