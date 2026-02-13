####### sentmm2 – minimap2 alignment for PacBio HiFi uBAM reads
# Aligns unaligned PacBio BAM → CRAM via minimap2 -ax map-hifi | samtools sort
# No deduplication step: PacBio HiFi PCR-free reads do not require it.

# Filter SAMPS to only those with PB_BAM_ALIGNER == 'sentmm2'
PB_SENTMM2_SAMPS = list(
    samples[
        samples["PB_BAM_ALIGNER"].isin(["sentmm2"])
    ]["sample_lane"].unique()
)


rule sentmm2_align_sort:
    """Align PacBio HiFi uBAM with minimap2, sort to CRAM."""
    input:
        bam=get_pb_bam,
    output:
        cramo=MDIR + "{sample}/align/sentmm2/{sample}.sentmm2.cram",
        crami=MDIR + "{sample}/align/sentmm2/{sample}.sentmm2.cram.crai",
    priority: 49
    log:
        MDIR + "{sample}/align/sentmm2/logs/{sample}.sentmm2_sort.log",
    resources:
        threads=config["sentmm2_align_sort"]["threads"],
        mem_mb=config["sentmm2_align_sort"]["mem_mb"],
        partition=config["sentmm2_align_sort"]["partition"],
        vcpu=config["sentmm2_align_sort"]["threads"],
        constraint=config["sentmm2_align_sort"]["constraint"],
    threads: config["sentmm2_align_sort"]["threads"]
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.sentmm2.alNsort.bench.tsv"
    params:
        cluster_sample=ret_sample,
        minimap2_threads=config["sentmm2_align_sort"]["minimap2_threads"],
        sort_threads=config["sentmm2_align_sort"]["sort_threads"],
        sort_thread_mem=config["sentmm2_align_sort"]["sort_thread_mem"],
        minimap2_opts=config["sentmm2_align_sort"]["minimap2_opts"],
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mbuffer=config["sentmm2_align_sort"]["mbuffer"],
        rgpl="PACBIO",
        rgpu="presumedCombinedLanes",
        rgsm=ret_sample,
        rgid=ret_sample,
        rglb="_presumedNoAmpWGS",
        rgcn="CenterName",
        rgpg="minimap2",
    conda:
        config["sentmm2_align_sort"]["env_yaml"]
    shell:
        """
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/
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
        export TMPDIR="/dev/shm/sentmm2_tmp_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        if [ ! -d "$TMPDIR" ]; then
            echo "ERROR: Failed to create TMPDIR: $TMPDIR" >> {log} 2>&1;
            exit 5;
        fi
        echo "TMPDIR created: $TMPDIR" >> {log} 2>&1;
        ls -ld "$TMPDIR" >> {log} 2>&1;
        df -h /dev/shm >> {log} 2>&1;
        export APPTAINER_HOME="$TMPDIR";
        trap "rm -rf \"$TMPDIR\" || echo 'TMPDIR rm fails' >> {log} 2>&1" EXIT;

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

        samtools fastq -@ 4 -T MM,ML {input.bam} \
        | LD_PRELOAD=$LD_PRELOAD /fsx/data/cached_envs/sentieon-genomics-202503.02/bin/minimap2 \
        {params.minimap2_opts} \
        -R '@RG\\tID:{params.cluster_sample}-$epocsec\\tSM:{params.cluster_sample}\\tLB:{params.cluster_sample}-LB-1\\tPL:{params.rgpl}\\tPU:{params.rgpu}\\tCN:{params.rgcn}\\tPG:{params.rgpg}' \
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

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;

        """


localrules: produce_sentmm2_align_sort,

rule produce_sentmm2_align_sort:  # TARGET: produce_sentmm2_align_sort
    input:
        expand(MDIR + "{sample}/align/sentmm2/{sample}.sentmm2.cram", sample=PB_SENTMM2_SAMPS)

