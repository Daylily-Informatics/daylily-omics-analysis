####### sentmm2ont – minimap2 alignment for ONT unaligned BAM reads
# Aligns unaligned ONT BAM → CRAM via minimap2 -ax map-ont | samtools sort
# Optional long-read trimming via LONGREADTRIM_READ_LENGTH / LONGREADTRIM_MODE.
# No deduplication step: ONT long reads aligned from uBAM do not require it.

# Filter SAMPS to only those with ONT_BAM_ALIGNER == 'sentmm2ont'
ONT_SENTMM2ONT_SAMPS = list(
    samples[
        samples["ONT_BAM_ALIGNER"].isin(["sentmm2ont"])
    ]["sample_lane"].unique()
)


rule sentmm2ont_align_sort:
    """Align ONT uBAM with minimap2, sort to CRAM."""
    input:
        bam=get_ont_bam,
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
    conda:
        config["sentmm2ont_align_sort"]["env_yaml"]
    shell:
        """

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
        export TMPDIR=/dev/shm/sentmm2ont_tmp_$timestamp;
        export SENTIEON_TMPDIR=$TMPDIR;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap "rm -rf \\"$TMPDIR\\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;

        tdir=$TMPDIR;
        epocsec=$(date +'%s');

        # Find the jemalloc library in the active conda environment
        jemalloc_path=$(find "$CONDA_PREFIX" -name "libjemalloc*" | grep -E '\.so|\.dylib' | head -n 1);

        # Check if jemalloc was found and set LD_PRELOAD accordingly
        if [[ -n "$jemalloc_path" ]]; then
            LD_PRELOAD="$jemalloc_path";
            echo "LD_PRELOAD set to: $LD_PRELOAD" >> {log};
        else
            echo "libjemalloc not found in the active conda environment $CONDA_PREFIX.";
            exit 3;
        fi

        samtools fastq -@ 4 -T MM,ML {input.bam} \
        {params.longread_trim_head} {params.longread_trim_tail} \
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
        -T $tdir \
        -O CRAM \
        --reference {params.huref} \
        --write-index \
        -o {output.cramo}##idx##{output.crami} >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;

        """


localrules: produce_sentmm2ont_align_sort,

rule produce_sentmm2ont_align_sort:  # TARGET: produce_sentmm2ont_align_sort
    input:
        expand(MDIR + "{sample}/align/sentmm2ont/{sample}.sentmm2ont.cram", sample=ONT_SENTMM2ONT_SAMPS)

