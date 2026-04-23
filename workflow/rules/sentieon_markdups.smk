#########  sentieon markdup (smd)
# -------------------------------
# Sentieon-based duplicate marking.
# code=smd
#
# No conditional guard — rule is always defined.
# Selection is via target rules expanding over ddup=DDUP.

SENT_DEDUP_CFG = config["sent_dedup"]
SENT_CFG = config["sentieon"]

rule sent_dedup:
    """Runs duplicate marking on the merged BAM using Sentieon → CRAM."""
    input:
        bam=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.sort.bam",
        bai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.sort.bam.bai",
    priority: 3
    output:
        cram=MDIR + "{sample}/align/{alnr}/smd/{sample}.{alnr}.smd.cram",
        crai=MDIR + "{sample}/align/{alnr}/smd/{sample}.{alnr}.smd.cram.crai",
        score=MDIR + "{sample}/align/{alnr}/smd/{sample}.{alnr}.smd.score.txt",
        metrics=MDIR + "{sample}/align/{alnr}/smd/{sample}.{alnr}.smd.metrics.txt",
    wildcard_constraints:
        alnr="|".join(OG_ALIGNERS) if OG_ALIGNERS else r"(?!x)x"
    threads: SENT_DEDUP_CFG["threads"]
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.smd.mrkdup.bench.tsv",
            0,
        )
    conda:
        SENT_DEDUP_CFG["env_yaml"]
    resources:
        threads=SENT_DEDUP_CFG["threads"],
        partition=SENT_DEDUP_CFG["partition"],
        vcpu=SENT_DEDUP_CFG["threads"],
        mem_mb=SENT_DEDUP_CFG["mem_mb"],
        constraint=SENT_DEDUP_CFG["constraint"],
    params:
        cluster_sample=ret_sample,
        reference=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        numa=SENT_DEDUP_CFG["numactl"],
        cram_opts=SENT_DEDUP_CFG["cram_opts"],
        tmp_base=SENT_DEDUP_CFG["tmp_base"],
        sentieon_driver=SENT_CFG["driver_path"],
        index_threads=SENT_DEDUP_CFG["index_threads"],
    log:
        MDIR + "{sample}/align/{alnr}/smd/logs/dedupe.smd.{sample}.{alnr}.log",
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
        echo "===== sent_dedup attempt $(date -u +%Y-%m-%dT%H:%M:%SZ) =====" >> {log};
        echo "INSTANCE TYPE: $itype" >> {log};
        echo "INSTANCE TYPE: $itype";
        start_time=$(date +%s);

        ulimit -n 65536 || echo "ulimit mod failed" >> {log} 2>&1;

        timestamp=$(date +%Y%m%d%H%M%S)_$$;
        export TMPDIR={params.tmp_base}/smd_sentieon_tmp_$timestamp;
        sentieon_tmp=$TMPDIR/sentieon_tmp;
        mkdir -p "$sentieon_tmp";
        export SENTIEON_TMPDIR=$sentieon_tmp;
        export APPTAINER_HOME=$TMPDIR;

        score_tmp=$TMPDIR/{wildcards.sample}.{wildcards.alnr}.smd.score.txt;
        metrics_tmp=$TMPDIR/{wildcards.sample}.{wildcards.alnr}.smd.metrics.txt;
        score_out={output.score};
        metrics_out={output.metrics};
        rm -f "$score_tmp" "$metrics_tmp" "$score_out" "$metrics_out";
        trap 'status=$?; echo "Cleanup TMPDIR=$TMPDIR score_tmp=$score_tmp metrics_tmp=$metrics_tmp score_out=$score_out metrics_out=$metrics_out status=$status" >> {log} 2>&1; df -h {params.tmp_base} >> {log} 2>&1 || true; ls -ld "$TMPDIR" "$SENTIEON_TMPDIR" >> {log} 2>&1 || true; ls -l "$score_tmp" "$metrics_tmp" "$score_out" "$metrics_out" >> {log} 2>&1 || true; find "$SENTIEON_TMPDIR" -maxdepth 3 -type f -ls >> {log} 2>&1 || true; rm -rf "$TMPDIR" 2>/dev/null || true; trap - EXIT; exit "$status"' EXIT;

        df -h {params.tmp_base} >> {log} 2>&1;
        ls -ld "$TMPDIR" "$SENTIEON_TMPDIR" >> {log} 2>&1;
        echo "SCORE_TMP: $score_tmp" >> {log};
        echo "METRICS_TMP: $metrics_tmp" >> {log};
        echo "SCORE_OUT: $score_out" >> {log};
        echo "METRICS_OUT: $metrics_out" >> {log};

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
            --algo LocusCollector --fun score_info "$score_tmp" >> {log} 2>&1;

        if [ ! -s "$score_tmp" ]; then
            echo "LocusCollector did not create a non-empty score file: $score_tmp" >> {log} 2>&1;
            ls -l "$score_tmp" >> {log} 2>&1 || true;
            find "$SENTIEON_TMPDIR" -maxdepth 3 -type f -ls >> {log} 2>&1 || true;
            exit 6;
        fi;
        cp "$score_tmp" "$score_out";

        {params.numa} LD_PRELOAD=$LD_PRELOAD {params.sentieon_driver} driver \
            --input {input.bam} \
            --reference {params.reference} \
            --thread_count {threads} \
            --algo Dedup \
            --score_info "$score_tmp" \
            --metrics "$metrics_tmp" \
            {params.cram_opts} \
            {output.cram} >> {log} 2>&1;

        if [ ! -s "$metrics_tmp" ]; then
            echo "Dedup did not create a non-empty metrics file: $metrics_tmp" >> {log} 2>&1;
            ls -l "$metrics_tmp" >> {log} 2>&1 || true;
            exit 7;
        fi;
        cp "$metrics_tmp" "$metrics_out";

        samtools index -@ {params.index_threads} {output.cram} {output.crai} >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" | tee -a {log};
        """
