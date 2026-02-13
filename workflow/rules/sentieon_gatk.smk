import os

####### Sentieon
#
# Our current prod aligner
#


rule sentieon_gatk_bsqr:  #TARGET: sent bwa sort
    input:
        cram=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        recal_data_table=MDIR + "{sample}/align/{alnr}/snv/gatk/{sample}.{alnr}.gatk.bsqr.recal_data.table",
        recal_cram=MDIR + "{sample}/align/{alnr}/snv/gatk/{sample}.{alnr}.gatk.bsqr.recal.cram",
        recal_cram_crai=MDIR + "{sample}/align/{alnr}/snv/gatk/{sample}.{alnr}.gatk.bsqr.recal.cram.crai",
    log: MDIR + "{sample}/align/{alnr}/snv/gatk/logs/{sample}.{alnr}.gatk.bsqr.sort.log",
    threads: config["sentieon_gatk"]["threads"]
    benchmark:
        repeat(MDIR + "{sample}/benchmarks/{sample}.{alnr}.gatk.bsqr.bench.tsv", 0)
    priority: 5
    resources:
        partition=config['sentieon_gatk']['partition'],
        vcpu=config['sentieon_gatk']['threads'],
        threads=config['sentieon_gatk']['threads'],
        mem_mb=config['sentieon_gatk']['mem_mb'],
        constraint=config['sentieon_gatk']['constraint'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mills=config["supporting_files"]["files"]["gatk"]["mills_vcf"],
        dbsnp=config["supporting_files"]["files"]["gatk"]["dbsnp_vcf"],
        onekg=config["supporting_files"]["files"]["gatk"]["onekg_vcf"],
        max_mem="130G"
        if "max_mem" not in config['sentieon_gatk']
        else config['sentieon_gatk']["max_mem"],
        sent_opts=config['sentieon_gatk']["sent_opts"],
        cluster_sample=ret_sample,
        bwa_threads=config['sentieon_gatk']["bwa_threads"],
        rgpl="presumedILLUMINA",  # ideally: passed in technology # nice to get to this point: https://support.sentieon.com/appnotes/read_groups/ :\ : note, the default sample name contains the RU_EX_SQ_Lane (0 for combined)
        rgpu="presumedCombinedLanes",  # ideally flowcell_lane(s)
        rgsm=ret_sample,  # samplename
        rgid=ret_sample,  # ideally samplename_flowcell_lane(s)_barcode  ! Imp this is unique, I add epoc seconds to the end of start of this rule
        rglb="_presumedNoAmpWGS",  # prepend with cluster sample nanme ideally samplename_libprep
        rgcn="CenterName",  # center name
        rgpg="sentieonBWAmem",  #program
        sort_thread_mem=config['sentieon_gatk']['sort_thread_mem'],
        sort_threads=config['sentieon_gatk']['sort_threads'],
        igz=config['sentieon_gatk']['igz'],
        mbuffer=config['sentieon_gatk']['mbuffer'],
        bwa_model=config['sentieon_gatk']['bwa_model'],
        subsample_head=get_subsample_head,
        subsample_tail=get_subsample_tail,
    conda:
        config['sentieon_gatk']["env_yaml"]
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
        
        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR=/dev/shm/sentieon_tmp_$timestamp;
        export SENTIEON_TMPDIR=$TMPDIR;

        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
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
        LD_PRELOAD=$LD_PRELOAD /fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon driver \
            -t {threads} \
            -r {params.huref} \
            -i {input.cram} \
            --algo QualCal \
            -k {params.dbsnp} \
            -k {params.onekg} \
            -k {params.mills} \
            {output.recal_data_table} >> {log} 2>&1;

        LD_PRELOAD=$LD_PRELOAD /fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon driver \
            -t {threads} \
            -r {params.huref} \
            -i {input.cram} \
            -q {output.recal_data_table} \
            --algo ReadWriter \
            {output.recal_cram} >> {log} 2>&1;


        samtools index {output.recal_cram} {output.recal_cram_crai} >> {log} 2>&1;
        
        
        """

localrules: produce_sentieon_gatk_bsqr,

rule produce_sentieon_gatk_bsqr:  # TARGET: produce_sentieon_bwa_sort_bam
     input:
         expand(MDIR + "{sample}/align/{alnr}/snv/gatk/{sample}.{alnr}.gatk.bsqr.recal.cram", sample=SAMPS, alnr=ALIGNERS)



rule sentieon_gatk_snv:  #TARGET: sent bwa sort
    input:
        cram=MDIR + "{sample}/align/{alnr}/snv/gatk/{sample}.{alnr}.gatk.bsqr.recal.cram",
        cram_crai=MDIR + "{sample}/align/{alnr}/snv/gatk/{sample}.{alnr}.gatk.bsqr.recal.cram.crai",
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/gatk/{sample}.{alnr}.gatk.snv.sort.vcf.gz",
        vcfgz_tbi=MDIR + "{sample}/align/{alnr}/snv/gatk/{sample}.{alnr}.gatk.snv.sort.vcf.gz.tbi",
        vcfsort=temp(MDIR + "{sample}/align/{alnr}/snv/gatk/{sample}.{alnr}.gatk.snv.sort.vcf"),
        vcftmp=temp(MDIR + "{sample}/align/{alnr}/snv/gatk/{sample}.{alnr}.gatk.snv.vcf.gz"),
    log: MDIR + "{sample}/align/{alnr}/snv/gatk/logs/{sample}.{alnr}.gatk.snv.sort.log",
    threads: config["sentieon_gatk"]["threads"]
    benchmark:
        repeat(MDIR + "{sample}/benchmarks/{sample}.{alnr}.gatk.snv.bench.tsv", 0)
    priority: 5
    resources:
        partition=config['sentieon_gatk']['partition'],
        vcpu=config['sentieon_gatk']['threads'],
        threads=config['sentieon_gatk']['threads'],
        mem_mb=config['sentieon_gatk']['mem_mb'],
        constraint=config['sentieon_gatk']['constraint'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mills=config["supporting_files"]["files"]["gatk"]["mills_vcf"],
        dbsnp=config["supporting_files"]["files"]["gatk"]["dbsnp_vcf"],
        onekg=config["supporting_files"]["files"]["gatk"]["onekg_vcf"],
        max_mem="130G"
        if "max_mem" not in config['sentieon_gatk']
        else config['sentieon_gatk']["max_mem"],
        sent_opts=config['sentieon_gatk']["sent_opts"],
        cluster_sample=ret_sample,
        bwa_threads=config['sentieon_gatk']["bwa_threads"],
        rgpl="presumedILLUMINA",  # ideally: passed in technology # nice to get to this point: https://support.sentieon.com/appnotes/read_groups/ :\ : note, the default sample name contains the RU_EX_SQ_Lane (0 for combined)
        rgpu="presumedCombinedLanes",  # ideally flowcell_lane(s)
        rgsm=ret_sample,  # samplename
        rgid=ret_sample,  # ideally samplename_flowcell_lane(s)_barcode  ! Imp this is unique, I add epoc seconds to the end of start of this rule
        rglb="_presumedNoAmpWGS",  # prepend with cluster sample nanme ideally samplename_libprep
        rgcn="CenterName",  # center name
        rgpg="sentieonBWAmem",  #program
        sort_thread_mem=config['sentieon_gatk']['sort_thread_mem'],
        sort_threads=config['sentieon_gatk']['sort_threads'],
        igz=config['sentieon_gatk']['igz'],
        mbuffer=config['sentieon_gatk']['mbuffer'],
        bwa_model=config['sentieon_gatk']['bwa_model'],
        subsample_head=get_subsample_head,
        subsample_tail=get_subsample_tail,
    conda:
        config['sentieon_gatk']["env_yaml"]
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
        
        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR=/dev/shm/sentieon_tmp_$timestamp;
        export SENTIEON_TMPDIR=$TMPDIR;

        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
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
        LD_PRELOAD=$LD_PRELOAD /fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon driver \
            -t {threads} \
            -r {params.huref} \
            -i {input.cram} \
            --algo Haplotyper \
            --emit_mode confident \
            {output.vcftmp} >> {log} 2>&1;

        bcftools sort -O v -o {output.vcfsort}  {output.vcftmp} >> {log} 2>&1;
        
        bgzip {output.vcfsort} >> {log} 2>&1;     

        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1; 
        touch {output};
        """