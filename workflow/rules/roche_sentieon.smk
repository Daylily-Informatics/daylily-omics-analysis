import os

ROCHE_SENT_CFG = config.get("roche_sentieon", {})
SENT_CFG = config.get("sentieon", {})


rule roche_sentieon:
    """Roche SBX duplex germline pipeline with Sentieon GATK equivalents.

    Starts from per-lane FASTQs; when the manifest provides BAMs, ensure the
    produce_fastqs_from_bams rule is in the DAG to emit these FASTQs first.
    """
    input:
        r1=getR1s,
        r2=getR2s,
    output:
        cram=MDIR + "{sample}/align/roche_sentieon/{sample}.roche_sentieon.cram",
        crai=MDIR + "{sample}/align/roche_sentieon/{sample}.roche_sentieon.cram.crai",
        vcfgz=MDIR
        + "{sample}/align/roche_sentieon/{sample}.roche_sentieon.vcf.gz",
        vcfgz_tbi=MDIR
        + "{sample}/align/roche_sentieon/{sample}.roche_sentieon.vcf.gz.tbi",
    log:
        MDIR + "{sample}/align/roche_sentieon/logs/{sample}.roche_sentieon.log",
    threads: ROCHE_SENT_CFG.get("threads", 16)
    resources:
        threads=ROCHE_SENT_CFG.get("threads", 16),
        partition=ROCHE_SENT_CFG.get("partition", "i8"),
        vcpu=ROCHE_SENT_CFG.get("threads", 16),
        mem_mb=ROCHE_SENT_CFG.get("mem_mb", 64000),
        constraint=ROCHE_SENT_CFG.get("constraint", ""),
    conda:
        ROCHE_SENT_CFG.get("env_yaml", "../envs/sentieon_gatk_v0.1.yaml")
    params:
        reference=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        dbsnp=config["supporting_files"]["files"]["gatk"]["dbsnp_vcf"],
        onekg=config["supporting_files"]["files"]["gatk"]["onekg_vcf"],
        mills=config["supporting_files"]["files"]["gatk"]["mills_vcf"],
        bwa_model=ROCHE_SENT_CFG.get("bwa_model", "GATK"),
        bwa_threads=ROCHE_SENT_CFG.get("bwa_threads", 8),
        sort_threads=ROCHE_SENT_CFG.get("sort_threads", 8),
        sort_thread_mem=ROCHE_SENT_CFG.get("sort_thread_mem", "2G"),
        tmp_base=ROCHE_SENT_CFG.get("tmp_base", "/dev/shm"),
        sentieon_driver=SENT_CFG.get(
            "driver_path",
            "/fsx/data/cached_envs/sentieon-genomics-202503.01.rc1/bin/sentieon",
        ),
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail;
        touch {log};

        if [ -z "${{SENTIEON_LICENSE:-}}" ]; then
            echo "SENTIEON_LICENSE not set. Please export the license path or server." >> {log} 2>&1;
            exit 3;
        fi;
        if [[ ! "$SENTIEON_LICENSE" =~ : ]] && [ ! -f "$SENTIEON_LICENSE" ]; then
            echo "The file referenced by SENTIEON_LICENSE ('$SENTIEON_LICENSE') does not exist." >> {log} 2>&1;
            exit 4;
        fi;

        TOKEN=$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type || echo "unknown");
        echo "INSTANCE TYPE: $itype" > {log};
        start_time=$(date +%s);

        ulimit -n 65536 || echo "ulimit mod failed" >> {log} 2>&1;

        timestamp=$(date +%Y%m%d%H%M%S);
        TMPDIR={params.tmp_base}/roche_sentieon_$timestamp;
        mkdir -p "$TMPDIR";
        export SENTIEON_TMPDIR=$TMPDIR;
        trap "rm -rf \"$TMPDIR\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;

        sorted_bam=$TMPDIR/{wildcards.sample}.sort.bam;
        score_info=$TMPDIR/{wildcards.sample}.score.txt;
        metrics_tmp=$TMPDIR/{wildcards.sample}.dedup.metrics.txt;
        recal_table=$TMPDIR/{wildcards.sample}.recal.table;
        raw_vcf=$TMPDIR/{wildcards.sample}.raw.vcf.gz;

        jemalloc_path=$(find "$CONDA_PREFIX" \( -name "libjemalloc*.so*" -o -name "libjemalloc*.dylib" \) | head -n 1 || true);
        if [[ -n "$jemalloc_path" ]]; then
            export LD_PRELOAD="$jemalloc_path";
            echo "LD_PRELOAD set to: $LD_PRELOAD" >> {log};
        else
            echo "libjemalloc not found in the active conda environment $CONDA_PREFIX." >> {log};
            exit 5;
        fi;

        {params.sentieon_driver} bwa mem \
            -t {params.bwa_threads} \
            -x {params.bwa_model} \
            -R "@RG\\tID:{params.cluster_sample}-$timestamp\\tSM:{params.cluster_sample}\\tLB:{params.cluster_sample}-LB-1\\tPL:ILLUMINA" \
            {params.reference} \
            {input.r1} {input.r2} \
        | {params.sentieon_driver} util sort \
            -t {params.sort_threads} \
            --reference {params.reference} \
            --sortblock_thread_count {params.sort_threads} \
            --block_size {params.sort_thread_mem} \
            --sam2bam \
            -o "$sorted_bam" - >> {log} 2>&1;

        {params.sentieon_driver} driver \
            --input "$sorted_bam" \
            --reference {params.reference} \
            --thread_count {threads} \
            --algo LocusCollector --fun score_info "$score_info" >> {log} 2>&1;

        {params.sentieon_driver} driver \
            --input "$sorted_bam" \
            --reference {params.reference} \
            --thread_count {threads} \
            --algo Dedup \
            --score_info "$score_info" \
            --metrics "$metrics_tmp" \
            "$TMPDIR/{wildcards.sample}.dedup.bam" >> {log} 2>&1;

        {params.sentieon_driver} driver \
            --input "$TMPDIR/{wildcards.sample}.dedup.bam" \
            --reference {params.reference} \
            --thread_count {threads} \
            --algo QualCal \
            -k {params.dbsnp} \
            -k {params.onekg} \
            -k {params.mills} \
            "$recal_table" >> {log} 2>&1;

        {params.sentieon_driver} driver \
            --input "$TMPDIR/{wildcards.sample}.dedup.bam" \
            --reference {params.reference} \
            --thread_count {threads} \
            --algo ReadWriter \
            -q "$recal_table" \
            --cram_write_options version=3.0,compressor=rans \
            {output.cram} >> {log} 2>&1;

        samtools index -@ {threads} {output.cram} {output.crai} >> {log} 2>&1;

        {params.sentieon_driver} driver \
            --input {output.cram} \
            --reference {params.reference} \
            --thread_count {threads} \
            --algo Haplotyper \
            --emit_mode confident \
            "$raw_vcf" >> {log} 2>&1;

        bcftools sort -O v -o "$TMPDIR/{wildcards.sample}.sorted.vcf" "$raw_vcf" >> {log} 2>&1;
        bgzip -c "$TMPDIR/{wildcards.sample}.sorted.vcf" > {output.vcfgz};
        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" | tee -a {log};
        """
