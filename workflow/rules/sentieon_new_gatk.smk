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
        LD_PRELOAD=$LD_PRELOAD /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/sentieon driver \
            -t {threads} \
            -r {params.huref} \
            -i {input.cram} \
            --algo QualCal \
            -k {params.dbsnp} \
            -k {params.onekg} \
            -k {params.mills} \
            {output.recal_data_table} >> {log} 2>&1;

        # --- ReadWriter (apply recalibration) ---
        LD_PRELOAD=$LD_PRELOAD /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/sentieon driver \
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


##### Per-chromosome scatter-gather pattern for HaplotypeCaller
#
# 1. prep_gatk_chunkdirs — create per-chrm output directories
# 2. sentieon_gatk_snv — run HaplotypeCaller on each chrm chunk
# 3. gatk_sort_index_chunk_vcf — sort/bgzip/tabix each chunk
# 4. gatk_concat_fofn — build ordered file-of-filenames
# 5. gatk_concat_index_chunks — bcftools concat into final VCF
#


localrules:
    prep_gatk_chunkdirs,


rule prep_gatk_chunkdirs:
    """Create per-chromosome output directories for GATK HaplotypeCaller scatter."""
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.bsqr.recal.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.bsqr.recal.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/gatk/vcfs/{gatkchrm}/{{sample}}.ready",
            gatkchrm=GATK_CHRMS,
        ),
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/logs/{sample}.{alnr}.{ddup}.chunkdirs.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.prep_gatk_chunkdirs.bench.tsv"
    shell:
        """
        ( echo {output};
        mkdir -p $(dirname {output});
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """


rule sentieon_gatk_snv:
    """Per-chromosome Sentieon GATK HaplotypeCaller."""
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.bsqr.recal.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.bsqr.recal.cram.crai",
        d=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/vcfs/{gatkchrm}/{sample}.ready",
    output:
        vcf=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/vcfs/{gatkchrm}/{sample}.{alnr}.{ddup}.gatk.{gatkchrm}.snv.vcf"),
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/log/vcfs/{sample}.{alnr}.{ddup}.gatk.{gatkchrm}.snv.log",
    threads: config["sentieon_gatk"]["threads"]
    benchmark:
        repeat(MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.gatk.{gatkchrm}.bench.tsv", 0)
    priority: 45
    resources:
        partition=config['sentieon_gatk']['partition'],
        vcpu=config['sentieon_gatk']['threads'],
        threads=config['sentieon_gatk']['threads'],
        mem_mb=config['sentieon_gatk']['mem_mb'],
        constraint=config['sentieon_gatk']['constraint'],
        attempt_n=lambda wildcards, attempt: attempt + 0,
    params:
        schrm_mod=get_gatkchrm,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
        max_mem="100G",
    conda:
        config['sentieon_gatk']["env_yaml"]
    shell:
        """
        export bwt_max_mem={params.max_mem};
        timestamp=$(date +%Y%m%d%H%M%S)_$$;
        export TMPDIR=/dev/shm/gatk_snv_tmp_$timestamp;
        export SENTIEON_TMPDIR=$TMPDIR;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;

        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;
        ulimit -n 65536 || echo "ulimit mod failed" > {log} 2>&1;

        if [ -z "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE not set." >> {log} 2>&1;
            exit 3;
        fi
        if [ ! -f "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE file does not exist: '$SENTIEON_LICENSE'" >> {log} 2>&1;
            exit 4;
        fi

        TOKEN=$(curl -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type);
        echo "INSTANCE TYPE: $itype" > {log};
        echo "INSTANCE TYPE: $itype";
        start_time=$(date +%s);

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

        # --- HaplotypeCaller (per-chrm, confident mode) ---
        /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/sentieon driver \
            --thread_count {threads} \
            --interval {params.schrm_mod} \
            --reference {params.huref} \
            --input {input.cram} \
            --algo Haplotyper \
            --emit_mode confident \
            {output.vcf} >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;

        touch {output.vcf};
        """


rule gatk_sort_index_chunk_vcf:
    """Sort and index per-chromosome GATK VCF chunk."""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/vcfs/{gatkchrm}/{sample}.{alnr}.{ddup}.gatk.{gatkchrm}.snv.vcf",
    output:
        vcfsort=touch(MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/vcfs/{gatkchrm}/{sample}.{alnr}.{ddup}.gatk.{gatkchrm}.snv.sort.vcf"),
        vcfgz=touch(MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/vcfs/{gatkchrm}/{sample}.{alnr}.{ddup}.gatk.{gatkchrm}.snv.sort.vcf.gz"),
        vcftbi=touch(MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/vcfs/{gatkchrm}/{sample}.{alnr}.{ddup}.gatk.{gatkchrm}.snv.sort.vcf.gz.tbi"),
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/vcfs/{gatkchrm}/log/{sample}.{alnr}.{ddup}.gatk.{gatkchrm}.snv.sort.vcf.gz.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{gatkchrm}.gatk_sort_index_chunk_vcf.bench.tsv"
    priority: 46
    threads: 1
    resources:
        vcpu=1,
        threads=1,
        partition=config['sentieon_gatk'].get('partition_other', config['sentieon_gatk']['partition']),
    params:
        cluster_sample=ret_sample,
    conda:
        "../envs/vanilla_v0.1.yaml"
    shell:
        """
        bedtools sort -header -i {input.vcf} > {output.vcfsort} 2>> {log};

        bgzip {output.vcfsort} >> {log} 2>&1;
        touch {output.vcfsort};

        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1;
        """


localrules:
    gatk_concat_fofn,


rule gatk_concat_fofn:
    """Build ordered file-of-filenames from sorted per-chromosome VCF chunks."""
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/gatk/vcfs/{gatkchrm}/{{sample}}.{{alnr}}.{{ddup}}.gatk.{gatkchrm}.snv.sort.vcf.gz.tbi",
                gatkchrm=GATK_CHRMS,
            ),
            key=lambda x: float(
                str(x.replace("~", ".").replace(":", "."))
                .split("vcfs/")[1]
                .split("/")[0]
                .split("-")[0]
            ),
        ),
    priority: 44
    output:
        fin_fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.snv.concat.vcf.gz.fofn.tmp",
    threads: 1
    resources:
        threads=1,
    params:
        fn_stub="{sample}.{alnr}.{ddup}.gatk.",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.gatk.concat.fofn.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/log/{sample}.{alnr}.{ddup}.gatk.concat.fofn.log",
    shell:
        """
        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\\.tbi$//g';);
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.gatk. {output.fin_fofn}) >> {log} 2>&1;
        """


rule gatk_concat_index_chunks:
    """Concatenate per-chromosome GATK VCFs into final sorted VCF."""
    input:
        fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.snv.concat.vcf.gz.fofn",
    output:
        vcfgz=touch(MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.snv.sort.vcf.gz"),
        vcfgztemp=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.snv.sort.temp.vcf.gz"),
        vcfgztbi=touch(MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/{sample}.{alnr}.{ddup}.gatk.snv.sort.vcf.gz.tbi"),
    threads: 4
    resources:
        vcpu=4,
        threads=4,
        partition=config['sentieon_gatk'].get('partition_other', config['sentieon_gatk']['partition']),
        attempt_n=lambda wildcards, attempt: attempt + 0,
    priority: 47
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.gatk.merge.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/gatk/log/{sample}.{alnr}.{ddup}.gatk.snv.merge.sort.gathered.log",
    shell:
        """
        touch {log};
        mkdir -p $(dirname {log});

        bcftools concat -a -d all --threads {threads} -f {input.fofn} -O z -o {output.vcfgztemp} >> {log} 2>&1;

        export oldname=$(bcftools query -l {output.vcfgztemp} | head -n1) >> {log} 2>&1;
        echo -e "${{oldname}}\t{params.cluster_sample}" > {output.vcfgz}.rename.txt
        bcftools reheader -s {output.vcfgz}.rename.txt -o {output.vcfgz} {output.vcfgztemp} >> {log} 2>&1;
        bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;

        rm -rf $(dirname {output.vcfgz})/vcfs >> {log} 2>&1;
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
    benchmark:
        MDIR + "benchmarks/produce_sentieon_gatk_vcf.bench.tsv"
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """
