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

        TOKEN=$(curl -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type);
        echo "INSTANCE TYPE: $itype" > {log};
        start_time=$(date +%s);
        ulimit -n 65536 || echo "ulimit mod failed";

        timestamp=$(date +%Y%m%d%H%M%S);
        TMPDIR=/fsx/scratch/sentmm2_tmp_$timestamp;
        mkdir -p $TMPDIR;
        APPTAINER_HOME=$TMPDIR;
        trap "rm -rf \\"$TMPDIR\\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;

        tdir=$TMPDIR;
        epocsec=$(date +'%s');

        minimap2 \
        {params.minimap2_opts} \
        -R '@RG\\tID:{params.cluster_sample}-$epocsec\\tSM:{params.cluster_sample}\\tLB:{params.cluster_sample}-LB-1\\tPL:{params.rgpl}\\tPU:{params.rgpu}\\tCN:{params.rgcn}\\tPG:{params.rgpg}' \
        -t {params.minimap2_threads} \
        {params.huref} \
        {input.bam} {params.mbuffer} \
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


localrules: produce_sentmm2_align_sort,

rule produce_sentmm2_align_sort:  # TARGET: produce_sentmm2_align_sort
    input:
        expand(MDIR + "{sample}/align/sentmm2/{sample}.sentmm2.cram", sample=PB_SENTMM2_SAMPS)

