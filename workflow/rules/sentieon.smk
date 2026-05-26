import os

####### Sentieon
#
# Our current prod aligner
#


rule sentieon_bwa_sort:  #TARGET: sent bwa sort
    input:
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        f1=getR1s,
        f2=getR2s,
    output:
        bamo=temp(MDIR + "{sample}/align/sent/{sample}.sent.sort.bam"),
        baio=temp(MDIR + "{sample}/align/sent/{sample}.sent.sort.bam.bai")
    log: MDIR + "{sample}/align/sent/logs/{sample}.sent.sort.log",
    threads: config["sentieon"]["threads"]
    benchmark:
        repeat(MDIR + "{sample}/benchmarks/{sample}.sent.alNsort.bench.tsv", 0)
    priority: 5
    resources:
        partition=config['sentieon']['partition'],
        vcpu=config['sentieon']['threads'],
        threads=config['sentieon']['threads'],
        mem_mb=config['sentieon']['mem_mb'],
        constraint=config['sentieon']['constraint'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        max_mem="130G"
        if "max_mem" not in config["sentieon"]
        else config["sentieon"]["max_mem"],
        sent_opts=config["sentieon"]["sent_opts"],
        cluster_sample=ret_sample,
        bwa_threads=config["sentieon"]["bwa_threads"],
        rgpl="presumedILLUMINA",  # ideally: passed in technology # nice to get to this point: https://support.sentieon.com/appnotes/read_groups/ :\ : note, the default sample name contains the RU_EX_SQ_Lane (0 for combined)
        rgpu="presumedCombinedLanes",  # ideally flowcell_lane(s)
        rgsm=ret_sample,  # samplename
        rgid=ret_sample,  # ideally samplename_flowcell_lane(s)_barcode  ! Imp this is unique, I add epoc seconds to the end of start of this rule
        rglb="_presumedNoAmpWGS",  # prepend with cluster sample nanme ideally samplename_libprep
        rgcn="CenterName",  # center name
        rgpg="sentieonBWAmem",  #program
        sort_thread_mem=config['sentieon']['sort_thread_mem'],
        sort_threads=config['sentieon']['sort_threads'],
        igz=config['sentieon']['igz'],
        mbuffer=config['sentieon']['mbuffer'],
        bwa_model=config['sentieon']['bwa_model'],
        subsample_head=get_subsample_head,
        subsample_tail=get_subsample_tail,
        trim_head=get_ilmn_trim_head,
        trim_tail=get_ilmn_trim_tail,
    conda:
        config["sentieon"]["env_yaml"]
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
        export bwt_max_mem={params.max_mem} ;
        epocsec=$(date +'%s');

        ulimit -n 65536 || echo "ulimit mod failed" > {log} 2>&1;

        timestamp=$(date +%Y%m%d%H%M%S)_$$;
        main_bashpid=${{BASHPID:-}};
        tmp_root=$(dirname {log})/../tmp;
        mkdir -p "$tmp_root";
        export TMPDIR="$tmp_root";
        meta_tmp=$TMPDIR/sentieon_meta_$timestamp;
        sort_tmp=$TMPDIR/sentieon_sort_$timestamp;
        export SENTIEON_TMPDIR=$TMPDIR/sentieon_driver_tmp_$timestamp;
        export APPTAINER_HOME=$meta_tmp/apptainer_home;

        mkdir -p "$sort_tmp" "$SENTIEON_TMPDIR" "$APPTAINER_HOME";
        trap 'status=$?; if [ "${{BASHPID:-}}" != "$main_bashpid" ]; then exit "$status"; fi; echo "Cleanup TMPDIR_BASE=$TMPDIR meta_tmp=$meta_tmp sort_tmp=$sort_tmp SENTIEON_TMPDIR=$SENTIEON_TMPDIR APPTAINER_HOME=$APPTAINER_HOME status=$status" >> {log} 2>&1; df -h "$TMPDIR" >> {log} 2>&1 || true; ls -ld "$TMPDIR" "$meta_tmp" "$sort_tmp" "$SENTIEON_TMPDIR" "$APPTAINER_HOME" >> {log} 2>&1 || true; find "$meta_tmp" -maxdepth 3 -type f -ls 2>/dev/null | head -200 >> {log} 2>&1 || true; find "$sort_tmp" -maxdepth 3 -type f -ls 2>/dev/null | head -200 >> {log} 2>&1 || true; find "$SENTIEON_TMPDIR" -maxdepth 3 -type f -ls 2>/dev/null | head -200 >> {log} 2>&1 || true; if [ "$status" -eq 0 ]; then rm -rf "$meta_tmp" "$sort_tmp" "$SENTIEON_TMPDIR" 2>/dev/null || true; else echo "Preserving scratch after failure under $TMPDIR" >> {log} 2>&1; fi; trap - EXIT; exit "$status"' EXIT;
        echo "TMPDIR_BASE: $TMPDIR" >> {log};
        echo "META_TMP: $meta_tmp" >> {log};
        echo "SORT_TMP: $sort_tmp" >> {log};
        echo "SENTIEON_TMPDIR: $SENTIEON_TMPDIR" >> {log};
        echo "APPTAINER_HOME: $APPTAINER_HOME" >> {log};

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

        if [[ -n "{params.trim_head}" ]]; then
            echo "ILMN_TRIM_READ_LENGTH: trimming reads via seqkit subseq" >> {log} 2>&1;
        fi

        LD_PRELOAD=$LD_PRELOAD /fsx/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/sentieon bwa mem \
        -t {params.bwa_threads}  {params.sent_opts}  \
        -x {params.bwa_model} \
        -R "@RG\\tID:{params.cluster_sample}-$epocsec\\tSM:{params.cluster_sample}\\tLB:{params.cluster_sample}-LB-1\\tPL:ILLUMINA" \
        {params.huref} \
         {params.subsample_head} <( {params.igz} -q  {input.f1} {params.trim_head} )  {params.subsample_tail}  \
         {params.subsample_head} <( {params.igz} -q  {input.f2} {params.trim_head} )  {params.subsample_tail} {params.mbuffer} \
        | /fsx/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/sentieon  util sort \
        -t  {params.sort_threads} \
        --reference {params.huref} \
        --cram_write_options version=3.0,compressor=rans \
        --sortblock_thread_count {params.sort_threads} \
        --bam_compression 1 \
        --temp_dir "$sort_tmp" \
        --intermediate_compress_level 1  \
        --block_size {params.sort_thread_mem}   \
        --sam2bam \
        -o {output.bamo} - >> {log} 2>&1;

        #samtools index -b -@ {threads} {output.baio}  >> {log} 2>&1;

        end_time=$(date +%s);
    	elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;
        """


rule sentieon_cgt7p_bwa_sort:  # TARGET: Complete Genomics / MGI Sentieon bwa sort
    input:
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        f1=getR1s,
        f2=getR2s,
    output:
        bamo=temp(MDIR + "{sample}/align/sentcg/{sample}.sentcg.sort.bam"),
        baio=temp(MDIR + "{sample}/align/sentcg/{sample}.sentcg.sort.bam.bai")
    log: MDIR + "{sample}/align/sentcg/logs/{sample}.sentcg.sort.log",
    threads: config["sentieon_cgt7p"]["threads"]
    benchmark:
        repeat(MDIR + "{sample}/benchmarks/{sample}.sentcg.alNsort.bench.tsv", 0)
    priority: 5
    resources:
        partition=config["sentieon_cgt7p"]["partition"],
        vcpu=config["sentieon_cgt7p"]["threads"],
        threads=config["sentieon_cgt7p"]["threads"],
        mem_mb=config["sentieon_cgt7p"]["mem_mb"],
        constraint=config["sentieon_cgt7p"]["constraint"],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        max_mem=config["sentieon_cgt7p"]["max_mem"],
        sent_opts=config["sentieon_cgt7p"]["sent_opts"],
        cluster_sample=ret_sample,
        bwa_threads=config["sentieon_cgt7p"]["bwa_threads"],
        sort_thread_mem=config["sentieon_cgt7p"]["sort_thread_mem"],
        sort_threads=config["sentieon_cgt7p"]["sort_threads"],
        igz=config["sentieon_cgt7p"]["igz"],
        mbuffer=config["sentieon_cgt7p"]["mbuffer"],
        bwa_model=config["sentieon_cgt7p"]["bwa_model"],
        rg_platform=config["sentieon_cgt7p"]["read_group_platform"],
        subsample_head=get_subsample_head,
        subsample_tail=get_subsample_tail,
        trim_head=get_ilmn_trim_head,
        trim_tail=get_ilmn_trim_tail,
    conda:
        config["sentieon_cgt7p"]["env_yaml"]
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
        export bwt_max_mem={params.max_mem} ;
        epocsec=$(date +'%s');

        ulimit -n 65536 || echo "ulimit mod failed" > {log} 2>&1;

        timestamp=$(date +%Y%m%d%H%M%S)_$$;
        main_bashpid=${{BASHPID:-}};
        tmp_root=$(dirname {log})/../tmp;
        mkdir -p "$tmp_root";
        export TMPDIR="$tmp_root";
        meta_tmp=$TMPDIR/sentieon_meta_$timestamp;
        sort_tmp=$TMPDIR/sentieon_sort_$timestamp;
        export SENTIEON_TMPDIR=$TMPDIR/sentieon_driver_tmp_$timestamp;
        export APPTAINER_HOME=$meta_tmp/apptainer_home;

        mkdir -p "$sort_tmp" "$SENTIEON_TMPDIR" "$APPTAINER_HOME";
        trap 'status=$?; if [ "${{BASHPID:-}}" != "$main_bashpid" ]; then exit "$status"; fi; echo "Cleanup TMPDIR_BASE=$TMPDIR meta_tmp=$meta_tmp sort_tmp=$sort_tmp SENTIEON_TMPDIR=$SENTIEON_TMPDIR APPTAINER_HOME=$APPTAINER_HOME status=$status" >> {log} 2>&1; df -h "$TMPDIR" >> {log} 2>&1 || true; ls -ld "$TMPDIR" "$meta_tmp" "$sort_tmp" "$SENTIEON_TMPDIR" "$APPTAINER_HOME" >> {log} 2>&1 || true; find "$meta_tmp" -maxdepth 3 -type f -ls 2>/dev/null | head -200 >> {log} 2>&1 || true; find "$sort_tmp" -maxdepth 3 -type f -ls 2>/dev/null | head -200 >> {log} 2>&1 || true; find "$SENTIEON_TMPDIR" -maxdepth 3 -type f -ls 2>/dev/null | head -200 >> {log} 2>&1 || true; if [ "$status" -eq 0 ]; then rm -rf "$meta_tmp" "$sort_tmp" "$SENTIEON_TMPDIR" 2>/dev/null || true; else echo "Preserving scratch after failure under $TMPDIR" >> {log} 2>&1; fi; trap - EXIT; exit "$status"' EXIT;
        echo "TMPDIR_BASE: $TMPDIR" >> {log};
        echo "META_TMP: $meta_tmp" >> {log};
        echo "SORT_TMP: $sort_tmp" >> {log};
        echo "SENTIEON_TMPDIR: $SENTIEON_TMPDIR" >> {log};
        echo "APPTAINER_HOME: $APPTAINER_HOME" >> {log};

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

        if [[ -n "{params.trim_head}" ]]; then
            echo "ILMN_TRIM_READ_LENGTH: trimming reads via seqkit subseq" >> {log} 2>&1;
        fi

        LD_PRELOAD=$LD_PRELOAD /fsx/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/sentieon bwa mem \
        -t {params.bwa_threads}  {params.sent_opts}  \
        -x {params.bwa_model} \
        -R "@RG\\tID:{params.cluster_sample}-$epocsec\\tSM:{params.cluster_sample}\\tLB:{params.cluster_sample}-LB-1\\tPL:{params.rg_platform}" \
        {params.huref} \
         {params.subsample_head} <( {params.igz} -q  {input.f1} {params.trim_head} )  {params.subsample_tail}  \
         {params.subsample_head} <( {params.igz} -q  {input.f2} {params.trim_head} )  {params.subsample_tail} {params.mbuffer} \
        | /fsx/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/sentieon  util sort \
        -t  {params.sort_threads} \
        --reference {params.huref} \
        --cram_write_options version=3.0,compressor=rans \
        --sortblock_thread_count {params.sort_threads} \
        --bam_compression 1 \
        --temp_dir "$sort_tmp" \
        --intermediate_compress_level 1  \
        --block_size {params.sort_thread_mem}   \
        --sam2bam \
        -o {output.bamo} - >> {log} 2>&1;

        samtools index -@ {params.sort_threads} {output.bamo} {output.baio} >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;
        """

localrules: produce_sentieon_bwa_sort_bam,

rule produce_sentieon_bwa_sort_bam:  # DEPRECATED TARGET: use produce_sent_align
     input:
         expand(MDIR + "{sample}/align/sent/{sample}.sent.sort.bam", sample=SAMPS)


rule produce_sentieon_cgt7p_bwa_sort_bam:  # DEPRECATED TARGET: use produce_sentcg_align
     input:
         expand(MDIR + "{sample}/align/sentcg/{sample}.sentcg.sort.bam", sample=SAMPS)
