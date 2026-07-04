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
        partition=derive_partition_order(SENT_DEDUP_CFG["partition"]),
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
        score_out=lambda wildcards: (
            f"{MDIR}{wildcards.sample}/align/{wildcards.alnr}/smd/"
            f"{wildcards.sample}.{wildcards.alnr}.smd.score.txt"
        ),
        metrics_out=lambda wildcards: (
            f"{MDIR}{wildcards.sample}/align/{wildcards.alnr}/smd/"
            f"{wildcards.sample}.{wildcards.alnr}.smd.metrics.txt"
        ),
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
        main_bashpid=${{BASHPID:-}};
        tmp_root="{params.tmp_base}";
        tmp_root="${{tmp_root%/}}/sentieon_markdups";
        mkdir -p "$tmp_root";
        export TMPDIR="$tmp_root";
        work_tmp=$TMPDIR/smd_meta_tmp_$timestamp;
        driver_tmp=$TMPDIR/smd_driver_tmp_$timestamp;
        export SENTIEON_TMPDIR=$driver_tmp;
        export APPTAINER_HOME=$work_tmp/apptainer_home;
        mkdir -p "$SENTIEON_TMPDIR" "$APPTAINER_HOME";

        score_out={params.score_out:q};
        metrics_out={params.metrics_out:q};
        cram_out={output.cram:q};
        crai_out={output.crai:q};
        score_tmp="$work_tmp/$(basename "$score_out")";
        metrics_tmp="$work_tmp/$(basename "$metrics_out")";
        cram_tmp="$driver_tmp/$(basename "$cram_out")";
        crai_tmp="$driver_tmp/$(basename "$crai_out")";
        score_copy_tmp="${{score_out}}.copy_tmp_$timestamp";
        metrics_copy_tmp="${{metrics_out}}.copy_tmp_$timestamp";
        cram_copy_tmp="${{cram_out}}.copy_tmp_$timestamp";
        crai_copy_tmp="${{crai_out}}.copy_tmp_$timestamp";
        rm -f "$score_out" "$metrics_out" "$cram_out" "$crai_out" \
              "$score_copy_tmp" "$metrics_copy_tmp" "$cram_copy_tmp" "$crai_copy_tmp";
        trap 'status=$?; if [ "${{BASHPID:-}}" != "$main_bashpid" ]; then exit "$status"; fi; echo "Cleanup TMPDIR_BASE=$TMPDIR work_tmp=$work_tmp driver_tmp=$driver_tmp SENTIEON_TMPDIR=$SENTIEON_TMPDIR APPTAINER_HOME=$APPTAINER_HOME score_tmp=$score_tmp metrics_tmp=$metrics_tmp cram_tmp=$cram_tmp status=$status" >> {log} 2>&1; df -h "$TMPDIR" >> {log} 2>&1 || true; ls -ld "$TMPDIR" "$work_tmp" "$driver_tmp" "$SENTIEON_TMPDIR" "$APPTAINER_HOME" "$(dirname "$score_out")" >> {log} 2>&1 || true; ls -l "$score_tmp" "$metrics_tmp" "$cram_tmp" "$crai_tmp" >> {log} 2>&1 || true; find "$work_tmp" -maxdepth 3 -type f -ls 2>/dev/null | head -200 >> {log} 2>&1 || true; find "$driver_tmp" -maxdepth 3 -type f -ls 2>/dev/null | head -200 >> {log} 2>&1 || true; rm -f "$score_copy_tmp" "$metrics_copy_tmp" "$cram_copy_tmp" "$crai_copy_tmp" 2>/dev/null || true; if [ "$status" -eq 0 ]; then rm -rf "$work_tmp" "$driver_tmp" 2>/dev/null || true; else echo "Preserving scratch after failure under $TMPDIR" >> {log} 2>&1; fi; trap - EXIT; exit "$status"' EXIT;

        df -h {params.tmp_base} >> {log} 2>&1;
        ls -ld "$TMPDIR" "$work_tmp" "$driver_tmp" "$SENTIEON_TMPDIR" "$APPTAINER_HOME" >> {log} 2>&1;
        mkdir -p "$(dirname "$score_out")" "$(dirname "$metrics_out")" "$(dirname "$cram_out")";
        echo "TMPDIR_BASE: $TMPDIR" >> {log};
        echo "WORK_TMP: $work_tmp" >> {log};
        echo "DRIVER_TMP: $driver_tmp" >> {log};
        echo "SCORE_TMP: $score_tmp" >> {log};
        echo "METRICS_TMP: $metrics_tmp" >> {log};
        echo "CRAM_TMP: $cram_tmp" >> {log};
        echo "CRAI_TMP: $crai_tmp" >> {log};
        echo "SCORE_OUT: $score_out" >> {log};
        echo "METRICS_OUT: $metrics_out" >> {log};
        echo "CRAM_OUT: $cram_out" >> {log};
        echo "CRAI_OUT: $crai_out" >> {log};

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
            find "$TMPDIR" -maxdepth 3 -type f -ls 2>/dev/null | head -200 >> {log} 2>&1 || true;
            exit 6;
        fi;

        {params.numa} LD_PRELOAD=$LD_PRELOAD {params.sentieon_driver} driver \
            --input {input.bam} \
            --reference {params.reference} \
            --thread_count {threads} \
            --algo Dedup \
            --score_info "$score_tmp" \
            --metrics "$metrics_tmp" \
            {params.cram_opts} \
            "$cram_tmp" >> {log} 2>&1;

        if [ ! -s "$metrics_tmp" ]; then
            echo "Dedup did not create a non-empty metrics file: $metrics_tmp" >> {log} 2>&1;
            ls -l "$metrics_tmp" >> {log} 2>&1 || true;
            exit 7;
        fi;

        if [ ! -s "$cram_tmp" ]; then
            echo "Dedup did not create a non-empty scratch CRAM: $cram_tmp" >> {log} 2>&1;
            ls -l "$cram_tmp" >> {log} 2>&1 || true;
            exit 8;
        fi;

        samtools index -@ {params.index_threads} "$cram_tmp" "$crai_tmp" >> {log} 2>&1;
        if [ ! -s "$crai_tmp" ]; then
            echo "samtools index did not create a non-empty scratch CRAI: $crai_tmp" >> {log} 2>&1;
            ls -l "$crai_tmp" >> {log} 2>&1 || true;
            exit 9;
        fi;

        cp -f "$score_tmp" "$score_copy_tmp";
        cp -f "$metrics_tmp" "$metrics_copy_tmp";
        cp -f "$cram_tmp" "$cram_copy_tmp";
        cp -f "$crai_tmp" "$crai_copy_tmp";
        mv -f "$score_copy_tmp" "$score_out";
        mv -f "$metrics_copy_tmp" "$metrics_out";
        mv -f "$cram_copy_tmp" "$cram_out";
        mv -f "$crai_copy_tmp" "$crai_out";

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" | tee -a {log};
        """
