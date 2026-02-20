##### Sentieon GATK HaplotypeCaller — per-sample SNV calling
#
# Pipeline: input CRAM → BSQR recalibration → HaplotypeCaller → per-sample VCF
# Output VCFs follow the standard daylily convention expected by produce_snv_concordances:
#   {sample}.{alnr}.{ddup}.gatk.snv.sort.vcf.gz
#


rule sentieon_gatk_bsqr:
    """Base quality score recalibration via Sentieon QualCal + ReadWriter."""
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        recal_data_table=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.bsqr.recal_data.table",
        recal_cram=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.bsqr.recal.cram",
        recal_cram_crai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.bsqr.recal.cram.crai",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/logs/{sample}.{alnr}.{ddup}.gatk.bsqr.sort.log",
    threads: config["sentieon_gatk"]["threads"]
    benchmark:
        repeat(MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.gatk.bsqr.bench.tsv", 0)
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
        cluster_sample=ret_sample,
    conda:
        config['sentieon_gatk']["env_yaml"]
    shell:
        """
        if [ -z "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE not set." >> {log} 2>&1;
            exit 3;
        fi
        if [ ! -f "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE file does not exist: '$SENTIEON_LICENSE'" >> {log} 2>&1;
            exit 4;
        fi

        TOKEN=$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type);
        echo "INSTANCE TYPE: $itype" > {log};
        start_time=$(date +%s);

        ulimit -n 65536 || echo "ulimit mod failed" >> {log} 2>&1;

        timestamp=$(date +%Y%m%d%H%M%S)_$$;
        export TMPDIR=/dev/shm/sentieon_gatk_bsqr_tmp_$timestamp;
        export SENTIEON_TMPDIR=$TMPDIR;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        # --- Validate input CRAM ---
        echo "Validating CRAM: {input.cram}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.cram} >> {log} 2>&1; then
            echo "ERROR: CRAM failed integrity check: {input.cram}" | tee -a {log};
            exit 10;
        fi
        _sq_count=$(samtools view -H {input.cram} 2>/dev/null | grep -c '^@SQ' || true);
        echo "CRAM @SQ header count: $_sq_count" >> {log} 2>&1;
        if [ "$_sq_count" -eq 0 ]; then
            echo "ERROR: CRAM has no @SQ headers (unaligned?): {input.cram}" | tee -a {log};
            exit 11;
        fi
        echo "CRAM validation passed ($_sq_count reference sequences)" >> {log} 2>&1;

        # --- Find jemalloc ---
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
        else
            echo "libjemalloc not found in CONDA_PREFIX=$CONDA_PREFIX" >> {log};
            exit 3;
        fi

        # --- QualCal (BSQR) ---
        LD_PRELOAD=$LD_PRELOAD /fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon driver \
            -t {threads} \
            -r {params.huref} \
            -i {input.cram} \
            --algo QualCal \
            -k {params.dbsnp} \
            -k {params.onekg} \
            -k {params.mills} \
            {output.recal_data_table} >> {log} 2>&1;

        # --- ReadWriter (apply recalibration) ---
        LD_PRELOAD=$LD_PRELOAD /fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon driver \
            -t {threads} \
            -r {params.huref} \
            -i {input.cram} \
            -q {output.recal_data_table} \
            --algo ReadWriter \
            {output.recal_cram} >> {log} 2>&1;

        samtools index {output.recal_cram} {output.recal_cram_crai} >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min: $itype $elapsed_time" >> {log} 2>&1;
        """


rule sentieon_gatk_snv:
    """Per-sample Sentieon GATK HaplotypeCaller → sorted VCF."""
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.bsqr.recal.cram",
        cram_crai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.bsqr.recal.cram.crai",
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.snv.sort.vcf.gz",
        vcfgz_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.snv.sort.vcf.gz.tbi",
        vcfsort=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.snv.sort.vcf"),
        vcftmp=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.snv.vcf.gz"),
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/logs/{sample}.{alnr}.{ddup}.gatk.snv.sort.log",
    threads: config["sentieon_gatk"]["threads"]
    benchmark:
        repeat(MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.gatk.snv.bench.tsv", 0)
    priority: 5
    resources:
        partition=config['sentieon_gatk']['partition'],
        vcpu=config['sentieon_gatk']['threads'],
        threads=config['sentieon_gatk']['threads'],
        mem_mb=config['sentieon_gatk']['mem_mb'],
        constraint=config['sentieon_gatk']['constraint'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    conda:
        config['sentieon_gatk']["env_yaml"]
    shell:
        """
        if [ -z "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE not set." >> {log} 2>&1;
            exit 3;
        fi
        if [ ! -f "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE file does not exist: '$SENTIEON_LICENSE'" >> {log} 2>&1;
            exit 4;
        fi

        TOKEN=$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type);
        echo "INSTANCE TYPE: $itype" > {log};
        start_time=$(date +%s);

        ulimit -n 65536 || echo "ulimit mod failed" >> {log} 2>&1;

        timestamp=$(date +%Y%m%d%H%M%S)_$$;
        export TMPDIR=/dev/shm/sentieon_gatk_snv_tmp_$timestamp;
        export SENTIEON_TMPDIR=$TMPDIR;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        # --- Validate input CRAM ---
        echo "Validating CRAM: {input.cram}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.cram} >> {log} 2>&1; then
            echo "ERROR: CRAM failed integrity check: {input.cram}" | tee -a {log};
            exit 10;
        fi
        _sq_count=$(samtools view -H {input.cram} 2>/dev/null | grep -c '^@SQ' || true);
        echo "CRAM @SQ header count: $_sq_count" >> {log} 2>&1;
        if [ "$_sq_count" -eq 0 ]; then
            echo "ERROR: CRAM has no @SQ headers (unaligned?): {input.cram}" | tee -a {log};
            exit 11;
        fi
        echo "CRAM validation passed ($_sq_count reference sequences)" >> {log} 2>&1;

        # --- Find jemalloc ---
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
        else
            echo "libjemalloc not found in CONDA_PREFIX=$CONDA_PREFIX" >> {log};
            exit 3;
        fi

        # --- HaplotypeCaller (per-sample, confident mode) ---
        LD_PRELOAD=$LD_PRELOAD /fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon driver \
            -t {threads} \
            -r {params.huref} \
            -i {input.cram} \
            --algo Haplotyper \
            --emit_mode confident \
            {output.vcftmp} >> {log} 2>&1;

        # --- Sort and compress ---
        bcftools sort -O v -o {output.vcfsort} {output.vcftmp} >> {log} 2>&1;
        bgzip {output.vcfsort} >> {log} 2>&1;
        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min: $itype $elapsed_time" >> {log} 2>&1;

        touch {output};
        """


localrules:
    produce_sentieon_gatk_vcf,


rule produce_sentieon_gatk_vcf:  # TARGET: sentieon GATK HaplotypeCaller per-sample VCF
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS,
            ddup=DDUP,
        ),
    output:
        "gatheredall.gatk",
    priority: 48
    threads: 1
    log:
        "gatheredall.gatk.log",
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """

