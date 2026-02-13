#########  SENTIEON DEDUPING
# --------------------------

if "sent" in DDUP:

    def get_input_bams(wildcards):
        return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.{wildcards.alnr}.sort.bam",

    rule sentieon_markdups:
        """Runs duplicate marking on the BAM."""
        input:
            bam=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.sort.bam",
            bai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.sort.bam.bai",
        priority: 3
        output:
            cram="{MDIR}{sample}/align/{alnr}/{sample}.{alnr}.cram",
            crai="{MDIR}{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
            score="{MDIR}{sample}/align/{alnr}/{sample}.{alnr}.cram.score.txt",
            metrics="{MDIR}{sample}/align/{alnr}/{sample}.{alnr}.cram.mrkdup.metrics",
        threads: config["sentieon_markdups"]["threads"]
        benchmark:
            repeat("{MDIR}{sample}/benchmarks/{sample}.{alnr}.mrkdup.bench.tsv", 0)
        conda:
            config["sentieon"]["env_yaml"]
        params:
            cluster_sample=ret_sample,
	        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
            max_mem=config["sentieon_markdups"]["max_mem"],
            numa=config['sentieon_markdups']['numactl'],
            cram_opts=" --cram_write_options version=3.0,compressor=rans ",
        resources:
            threads=config['sentieon_markdups']['threads'],
            partition=config['sentieon_markdups']['partition'],
            vcpu=config['sentieon_markdups']['threads'],
            mem_mb=config['sentieon_markdups']['max_mem'],
        log:
            "{MDIR}{sample}/align/{alnr}/logs/dedupe.{sample}.{alnr}.log",
        shell:
            """     
            export bwt_max_mem={params.max_mem} ;

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

            ulimit -n 65536 || echo "ulimit mod failed" > {log} 2>&1;
            
            timestamp=$(date +%Y%m%d%H%M%S);
            TMPDIR=/dev/shm/sentieon_mkduo_tmp_$timestamp;
            export SENTIEON_TMPDIR=$TMPDIR;
            mkdir -p $TMPDIR;
            APPTAINER_HOME=$TMPDIR;
            trap "rm -rf \"$TMPDIR\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;
            tdir=$TMPDIR;

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


            {params.numa} LD_PRELOAD=$LD_PRELOAD /fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon driver \
            --input {input.bam} \
            --reference {params.huref} \
            --thread_count {threads} \
            --algo LocusCollector --fun score_info {output.score} >> {log} 2>&1

            {params.numa} LD_PRELOAD=$LD_PRELOAD /fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon driver \
            --input {input.bam} \
            --reference {params.huref} \
            --thread_count {threads} \
            --algo Dedup \
            --score_info {output.score} \
            --metrics {output.metrics} {params.cram_opts} \
            {output.cram} >> {log} 2>&1

            end_time=$(date +%s);
            elapsed_time=$((($end_time - $start_time) / 60));
            echo "Elapsed-Time-min:\t$itype\t$elapsed_time\n";
            echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;

            """
