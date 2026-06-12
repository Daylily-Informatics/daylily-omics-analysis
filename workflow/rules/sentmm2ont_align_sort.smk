####### sentmm2ont – minimap2 alignment for ONT reads
# Aligns ONT FASTQ or unaligned BAM → CRAM via minimap2 -ax map-ont | samtools sort
# Optional long-read trimming via LONGREADTRIM_READ_LENGTH / LONGREADTRIM_MODE.
# No deduplication step: ONT long reads do not require it.


def _sentmm2ont_clean(value):
    return str(value or "").strip()


def _has_sentmm2ont_fastq_input(row):
    ont_r1_path = _sentmm2ont_clean(row.get("ONT_R1_PATH", ""))
    return _is_ont_fastq_unit(row) or ont_r1_path.lower() not in {"", "na", "none"}


ONT_SENTMM2ONT_SAMPS = list(
    samples[
        samples.apply(
            lambda row: _has_sentmm2ont_fastq_input(row)
            or _sentmm2ont_clean(row.get("ONT_BAM_ALIGNER", "")) == "sentmm2ont",
            axis=1,
        )
    ]["sample_lane"].unique()
)


def get_sentmm2ont_reads(wildcards):
    row = samples[samples["sample_lane"] == wildcards.sample].iloc[0]
    if _has_sentmm2ont_fastq_input(row):
        reads = [
            os.path.abspath(path)
            for path in _split_fastq_path_list(row.get("ONT_R1_PATH", ""))
        ]
        if not reads:
            raise WorkflowError(
                f"sample {wildcards.sample} has no ONT FASTQ reads for sentmm2ont."
            )
        return reads
    bam_inputs = get_ont_bam(wildcards)
    if not bam_inputs:
        raise WorkflowError(f"sample {wildcards.sample} has no ONT reads for sentmm2ont.")
    return bam_inputs[0]


def get_sentmm2ont_input_kind(wildcards):
    row = samples[samples["sample_lane"] == wildcards.sample].iloc[0]
    if _has_sentmm2ont_fastq_input(row):
        return "fastq"
    if _sentmm2ont_clean(row.get("ONT_BAM_ALIGNER", "")) == "sentmm2ont":
        return "ubam"
    raise WorkflowError(
        f"sample {wildcards.sample} is not a sentmm2ont ONT FASTQ/uBAM unit."
    )


rule sentmm2ont_align_sort:
    """Align ONT FASTQ or uBAM with minimap2, sort to CRAM."""
    input:
        reads=get_sentmm2ont_reads,
    output:
        cramo=MDIR + "{sample}/align/sentmm2ont/{sample}.sentmm2ont.cram",
        crami=MDIR + "{sample}/align/sentmm2ont/{sample}.sentmm2ont.cram.crai",
    priority: 49
    log:
        MDIR + "{sample}/align/sentmm2ont/logs/{sample}.sentmm2ont_sort.log",
    resources:
        threads=config["sentmm2ont_align_sort"]["threads"],
        mem_mb=config["sentmm2ont_align_sort"]["mem_mb"],
        partition=config["sentmm2ont_align_sort"]["partition"],
        vcpu=config["sentmm2ont_align_sort"]["threads"],
        constraint=config["sentmm2ont_align_sort"]["constraint"],
    threads: config["sentmm2ont_align_sort"]["threads"]
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.sentmm2ont.alNsort.bench.tsv"
    params:
        cluster_sample=ret_sample,
        minimap2_threads=config["sentmm2ont_align_sort"]["minimap2_threads"],
        sort_threads=config["sentmm2ont_align_sort"]["sort_threads"],
        sort_thread_mem=config["sentmm2ont_align_sort"]["sort_thread_mem"],
        minimap2_opts=config["sentmm2ont_align_sort"]["minimap2_opts"],
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mbuffer=config["sentmm2ont_align_sort"]["mbuffer"],
        rgpl="ONT",
        rgpu="presumedCombinedLanes",
        rgsm=ret_sample,
        rgid=ret_sample,
        rglb="_presumedNoAmpWGS",
        rgcn="CenterName",
        rgpg="minimap2",
        longread_trim_head=get_longread_trim_head,
        longread_trim_tail=get_longread_trim_tail,
        input_kind=get_sentmm2ont_input_kind,
    conda:
        config["sentmm2ont_align_sort"]["env_yaml"]
    shell:
        """
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/
        if [ -z "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE not set. Please set the SENTIEON_LICENSE environment variable to the license file path & make this update to your dyinit file as well." >> {log} 2>&1;
            exit 3;
        fi

        if [ ! -f "$SENTIEON_LICENSE" ]; then
            echo "The file referenced by SENTIEON_LICENSE ('$SENTIEON_LICENSE') does not exist. Please provide a valid file path." >> {log} 2>&1;
            exit 4;
        fi

        TOKEN=$(curl -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type);
        echo "INSTANCE TYPE: $itype" > {log};
        start_time=$(date +%s);
        ulimit -n 65536 || echo "ulimit mod failed";

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/scratch/sentmm2ont_tmp_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        if [ ! -d "$TMPDIR" ]; then
            echo "ERROR: Failed to create TMPDIR: $TMPDIR" >> {log} 2>&1;
            exit 5;
        fi
        echo "TMPDIR created: $TMPDIR" >> {log} 2>&1;
        ls -ld "$TMPDIR" >> {log} 2>&1;
        df -h /scratch >> {log} 2>&1;
        export APPTAINER_HOME="$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        tdir="$TMPDIR";
        epocsec=$(date +'%s');

        # Find the jemalloc library in the active conda environment
        jemalloc_path="";
        for _dir in "$CONDA_PREFIX/lib" "$CONDA_PREFIX/lib64" "$CONDA_PREFIX/lib/x86_64-linux-gnu"; do
            if [[ -d "$_dir" ]]; then
                for _ext in so dylib; do
                    _candidate=$(find "$_dir" -maxdepth 1 -name "libjemalloc*.$_ext*" 2>/dev/null | head -n 1);
                    if [[ -n "$_candidate" && -r "$_candidate" ]]; then
                        jemalloc_path="$_candidate";
                        break 2;
                    fi
                done
            fi
        done

        # Check if jemalloc was found and set LD_PRELOAD accordingly
        if [[ -n "$jemalloc_path" ]]; then
            export LD_PRELOAD="$jemalloc_path";
            export MALLOC_CONF=background_thread:true,metadata_thp:auto,dirty_decay_ms:5000,muzzy_decay_ms:5000;
            echo "LD_PRELOAD set to: $LD_PRELOAD" >> {log};
            echo "MALLOC_CONF set to: $MALLOC_CONF" >> {log};
        else
            echo "libjemalloc not found in CONDA_PREFIX=$CONDA_PREFIX (searched lib, lib64, lib/x86_64-linux-gnu)." >> {log};
            echo "libjemalloc not found in CONDA_PREFIX=$CONDA_PREFIX (searched lib, lib64, lib/x86_64-linux-gnu).";
            exit 3;
        fi

        # Verify TMPDIR still exists before pipeline
        if [ ! -d "$tdir" ]; then
            echo "ERROR: TMPDIR disappeared before pipeline start: $tdir" >> {log} 2>&1;
            exit 6;
        fi

        set +e
        (
            if [[ "{params.input_kind}" == "fastq" ]]; then
                for read_path in {input.reads:q}; do
                    if [[ "$read_path" == *.gz || "$read_path" == *.bgz ]]; then
                        gzip -dc -- "$read_path";
                    else
                        cat -- "$read_path";
                    fi
                done;
            elif [[ "{params.input_kind}" == "ubam" ]]; then
                samtools fastq -@ 4 -T MM,ML {input.reads:q};
            else
                echo "ERROR: unsupported sentmm2ont input kind: {params.input_kind}" >> {log} 2>&1;
                exit 8;
            fi
        ) {params.longread_trim_head} {params.longread_trim_tail} \
        | LD_PRELOAD=$LD_PRELOAD /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/minimap2 \
        {params.minimap2_opts} \
        -R "@RG\\tID:{params.cluster_sample}-$epocsec\\tSM:{params.cluster_sample}\\tLB:{params.cluster_sample}-LB-1\\tPL:{params.rgpl}\\tPU:{params.rgpu}\\tCN:{params.rgcn}\\tPG:{params.rgpg}\\tLR:1" \
        -t {params.minimap2_threads} \
        {params.huref} \
        - {params.mbuffer} \
        | samtools sort \
        -l 1 \
        -m {params.sort_thread_mem} \
        -@ {params.sort_threads} \
        -T "$tdir/srt" \
        -O CRAM \
        --reference {params.huref} \
        --write-index \
        -o {output.cramo}##idx##{output.crami} >> {log} 2>&1;
        pipeline_status=("${{PIPESTATUS[@]}}");
        set -e

        printf 'sentmm2ont pipeline statuses: %s\n' "${{pipeline_status[*]}}" >> {log} 2>&1;
        bad_pipeline_status=0;
        last_pipeline_index=$((${{#pipeline_status[@]}} - 1));
        for status_index in "${{!pipeline_status[@]}}"; do
            status_value="${{pipeline_status[$status_index]}}";
            if [[ "$status_value" -eq 0 ]]; then
                continue;
            fi;
            if [[ "$status_index" -lt "$last_pipeline_index" && "$status_value" -eq 141 ]]; then
                echo "sentmm2ont tolerated upstream SIGPIPE 141 at pipeline index $status_index pending output validation." >> {log} 2>&1;
                continue;
            fi;
            echo "ERROR: sentmm2ont pipeline command index $status_index exited $status_value." >> {log} 2>&1;
            bad_pipeline_status=1;
        done;
        if [[ "$bad_pipeline_status" -ne 0 ]]; then
            exit 9;
        fi;
        test -s {output.cramo:q} || (echo "ERROR: sentmm2ont CRAM output missing or empty: {output.cramo}" >> {log} 2>&1; exit 10);
        test -s {output.crami:q} || (echo "ERROR: sentmm2ont CRAI output missing or empty: {output.crami}" >> {log} 2>&1; exit 11);
        samtools quickcheck -v {output.cramo:q} >> {log} 2>&1 || (echo "ERROR: samtools quickcheck failed for {output.cramo}" >> {log} 2>&1; exit 12);

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;

        """


localrules: produce_sentmm2ont_align_sort,

rule produce_sentmm2ont_align_sort:  # DEPRECATED TARGET: use produce_sentmm2ont_align
    input:
        expand(MDIR + "{sample}/align/sentmm2ont/{sample}.sentmm2ont.cram", sample=ONT_SENTMM2ONT_SAMPS)
    log:
        MDIR + "logs/produce_sentmm2ont_align_sort.log"
    benchmark:
        "logs/benchmarks/produce_sentmm2ont_align_sort.bench.tsv"
