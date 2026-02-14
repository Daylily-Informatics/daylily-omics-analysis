#########  sentieon markdup (smd)
# -------------------------------
# Sentieon-based duplicate marking.
# code=smd
#
# No conditional guard — rule is always defined.
# Selection is via target rules expanding over ddup=DDUP.

DOPPEL_SENT_CFG = config.get("doppelmark_sentieon", {})
SENT_CFG = config.get("sentieon", {})

rule doppelmark_sentieon_dups:
    """Runs duplicate marking on the merged BAM using Sentieon → CRAM."""
    input:
        bam=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.sort.bam",
        bai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.sort.bam.bai",
    priority: 3
    output:
        cram="{MDIR}{sample}/align/{alnr}/smd/{sample}.{alnr}.smd.cram",
        crai="{MDIR}{sample}/align/{alnr}/smd/{sample}.{alnr}.smd.cram.crai",
    wildcard_constraints:
        alnr="|".join(OG_ALIGNERS)
    threads: DOPPEL_SENT_CFG.get("threads", 1)
    benchmark:
        repeat(
            "{MDIR}{sample}/benchmarks/{sample}.{alnr}.smd.mrkdup.bench.tsv",
            0,
        )
    conda:
        DOPPEL_SENT_CFG.get(
            "env_yaml",
            SENT_CFG.get("env_yaml", "../envs/sentieon_v0.1.yaml"),
        )
    resources:
        threads=DOPPEL_SENT_CFG.get("threads", 1),
        partition=DOPPEL_SENT_CFG.get("partition", "i8"),
        vcpu=DOPPEL_SENT_CFG.get("threads", 1),
        mem_mb=DOPPEL_SENT_CFG.get("mem_mb", 64000),
        constraint=DOPPEL_SENT_CFG.get("constraint", ""),
    params:
        cluster_sample=ret_sample,
        reference=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        numa=DOPPEL_SENT_CFG.get("numactl", ""),
        cram_opts=DOPPEL_SENT_CFG.get(
            "cram_opts",
            " --cram_write_options version=3.0,compressor=rans ",
        ),
        tmp_base=DOPPEL_SENT_CFG.get("tmp_base", "/dev/shm"),
        optical_distance=DOPPEL_SENT_CFG.get(
            "optical_distance",
            config.get("doppelmark", {}).get("optical_distance", 2500),
        ),
        sentieon_driver=SENT_CFG.get(
            "driver_path",
            "/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon",
        ),
        index_threads=DOPPEL_SENT_CFG.get("index_threads", 4),
        metrics_path=lambda wildcards: (
            f"{MDIR}{wildcards.sample}/align/{wildcards.alnr}/smd/"
            f"{wildcards.sample}.{wildcards.alnr}.smd.metrics.txt"
        ),
    log:
        "{MDIR}{sample}/align/{alnr}/smd/logs/dedupe.smd.{sample}.{alnr}.log",
    shell:
        """
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
        echo "INSTANCE TYPE: $itype";
        start_time=$(date +%s);

        ulimit -n 65536 || echo "ulimit mod failed" >> {log} 2>&1;

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR={params.tmp_base}/smd_sentieon_$timestamp;
        mkdir -p "$TMPDIR";
        export SENTIEON_TMPDIR=$TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap "rm -rf \"$TMPDIR\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;

        score_file=$TMPDIR/{wildcards.sample}.{wildcards.alnr}.score.txt;
        metrics_tmp=$TMPDIR/{wildcards.sample}.{wildcards.alnr}.metrics.txt;

        read_name=$(samtools view {input.bam} | head -n 1 | cut -f1 || true);

        jemalloc_path=$(find "$CONDA_PREFIX" \( -name "libjemalloc*.so*" -o -name "libjemalloc*.dylib" \) | head -n 1 || true);
        if [[ -n "$jemalloc_path" ]]; then
            export LD_PRELOAD="$jemalloc_path";
            echo "LD_PRELOAD set to: $LD_PRELOAD" >> {log};
        else
            echo "libjemalloc not found in the active conda environment $CONDA_PREFIX." >> {log};
            exit 5;
        fi;

        {params.numa} LD_PRELOAD=$LD_PRELOAD {params.sentieon_driver} driver \
            --input {input.bam} \
            --reference {params.reference} \
            --thread_count {threads} \
            --algo LocusCollector --fun score_info "$score_file" >> {log} 2>&1;

        {params.numa} LD_PRELOAD=$LD_PRELOAD {params.sentieon_driver} driver \
            --input {input.bam} \
            --reference {params.reference} \
            --thread_count {threads} \
            --algo Dedup \
            --score_info "$score_file" \
            --metrics "$metrics_tmp" \
            {params.cram_opts} \
            {output.cram} >> {log} 2>&1;

        samtools index -@ {params.index_threads} {output.cram} {output.crai} >> {log} 2>&1;

        if [ -f "$metrics_tmp" ]; then
            rm -f {params.metrics_path};
            mv "$metrics_tmp" {params.metrics_path};
        fi;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" | tee -a {log};
        """
