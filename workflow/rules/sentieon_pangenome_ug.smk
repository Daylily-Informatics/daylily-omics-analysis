import os


def _sentpgs_dchrm_sort_key(path):
    token = str(path).split("/vcfs/", 1)[1].split("/", 1)[0]
    try:
        return SENTPGS_CHRMS.index(token)
    except ValueError:
        return len(SENTPGS_CHRMS)


####### Sentieon Pangenome (accelerated) – Ultima Genomics pipeline
#
# Uses bin/dayoa_sentieon_cli dnascope-pangenome which performs pangenome-aware
# alignment (via GBZ graph reference) and variant calling for Ultima
# Genomics single-end WGS data.
#
# Input:  Staged Ultima CRAM  →  pangenome pipeline (direct CRAM input via -i)
#
# Outputs per sample (at standard concordance-compatible path):
#   {sample}/align/pangenome_ug/spmd/snv/sentpg/{sample}.pangenome_ug.spmd.sentpg.snv.sort.vcf.gz
#

rule sentieon_pangenome_ug:
    """Sentieon pangenome (accelerated): graph-align + variant call (Ultima CRAM → VCF)."""
    input:
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        cram=MDIR + "{sample}/align/ug/{sample}.cram",
        crai=MDIR + "{sample}/align/ug/{sample}.cram.crai",
    output:
        vcfgz=MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpg/{sample}.pangenome_ug.spmd.sentpg.snv.sort.vcf.gz",
        vcfgztbi=MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpg/{sample}.pangenome_ug.spmd.sentpg.snv.sort.vcf.gz.tbi",
    log:
        MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpg/log/{sample}.pangenome_ug.spmd.sentpg.log",
    threads: config["sentieon_pangenome_ug"]["threads"]
    conda:
        config["sentieon_pangenome_ug"]["env_yaml"]
    priority: 5
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.pangenome_ug.spmd.sentpg.bench.tsv",
            0
            if "bench_repeat" not in config["sentieon_pangenome_ug"]
            else config["sentieon_pangenome_ug"]["bench_repeat"],
        )
    resources:
        attempt_n=lambda wildcards, attempt: (attempt + 0),
        partition=config["sentieon_pangenome_ug"]["partition"],
        threads=config["sentieon_pangenome_ug"]["threads"],
        vcpu=config["sentieon_pangenome_ug"]["threads"],
        mem_mb=config["sentieon_pangenome_ug"]["mem_mb"],
        constraint=config["sentieon_pangenome_ug"]["constraint"],
        distribution=config["sentieon_pangenome_ug"]["distribution"],
        exclude=config["sentieon_pangenome_ug"]["exclude"],
        include=config["sentieon_pangenome_ug"]["include"],
        exclusive=config["sentieon_pangenome_ug"]["exclusive"],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        gbz=config["sentieon_pangenome_ug"]["gbz"],
        hapl=config["sentieon_pangenome_ug"]["hapl"],
        model=config["sentieon_pangenome_ug"]["model"],
        pop_vcf=config["sentieon_pangenome_ug"]["pop_vcf"],
        canonical_bed=config["sentieon_pangenome_ug"]["canonical_bed"],
        dbsnp=config["sentieon_pangenome_ug"]["dbsnp"],
        cli_threads=min(int(config["sentieon_pangenome_ug"]["threads"]), 128),
        cluster_sample=ret_sample,
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

        # Prepend patched KMC (Sentieon fork with stdin support) to PATH
        export PATH="$DAY_ROOT/resources/kmc/bin:$PATH";
        if ! command -v kmc &>/dev/null; then
            echo "ERROR: patched kmc not found at $DAY_ROOT/resources/kmc/bin/kmc" >> {log} 2>&1;
            exit 6;
        fi
        echo "Using patched KMC: $(which kmc)" >> {log} 2>&1;

        ulimit -n 65536 || echo "ulimit mod failed" >> {log} 2>&1;

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/scratch/pangenome_ug_tmp_${{timestamp}}_$$";
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

        # Find jemalloc in active conda env
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
            echo "WARNING: libjemalloc not found in CONDA_PREFIX=$CONDA_PREFIX" >> {log};
        fi

        # --- bin/dayoa_sentieon_cli dnascope-pangenome (accelerated pipeline) ---
        cli_out="$TMPDIR/{wildcards.sample}.pangenome_ug";

        echo "bin/dayoa_sentieon_cli dnascope-pangenome starting (Ultima, CRAM input mode)" >> {log} 2>&1;
        echo "  input_cram={input.cram}" >> {log} 2>&1;
        echo "  model={params.model}" >> {log} 2>&1;
        echo "  hapl={params.hapl}" >> {log} 2>&1;
        echo "  gbz={params.gbz}" >> {log} 2>&1;
        set +e;
        bin/dayoa_sentieon_cli dnascope-pangenome \
            -r {params.huref} \
            --hapl "{params.hapl}" \
            --gbz "{params.gbz}" \
            -m "{params.model}" \
            --pop_vcf "{params.pop_vcf}" \
            -i {input.cram} \
            -b "{params.canonical_bed}" \
            --dbsnp "{params.dbsnp}" \
            -t {params.cli_threads} \
            "${{cli_out}}.vcf.gz" >> {log} 2>&1;
        cli_rc=$?;
        set -e;
        echo "sentieon-cli exit code: $cli_rc" >> {log} 2>&1;
        if [ $cli_rc -ne 0 ]; then
            echo "ERROR: bin/dayoa_sentieon_cli dnascope-pangenome failed with exit code $cli_rc" >> {log} 2>&1;
            exit $cli_rc;
        fi

        # --- Reheader VCF: rename sample to cluster_sample ---
        if [ -f "${{cli_out}}.vcf.gz" ]; then
            oldname=$(bcftools query -l "${{cli_out}}.vcf.gz" | head -n1);
            echo -e "${{oldname}}\\t{params.cluster_sample}" > "$TMPDIR/rename.txt";
            bcftools reheader -s "$TMPDIR/rename.txt" -o {output.vcfgz} "${{cli_out}}.vcf.gz" >> {log} 2>&1;
            bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;
        else
            echo "ERROR: VCF not produced by bin/dayoa_sentieon_cli dnascope-pangenome" >> {log} 2>&1;
            exit 20;
        fi

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\\t$itype\\t$elapsed_time" >> {log} 2>&1;

        """


localrules:
    sentieon_pangenome_ug_shard_bed,
    sentpgs_concat_fofn,


rule sentieon_pangenome_ug_shard_bed:
    """Scope the pangenome canonical BED to one configured sentpgs shard."""
    output:
        bed=MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/vcfs/{dchrm}/tmp/{sample}.pangenome_ug.spmd.sentpgs.{dchrm}.bed",
    priority: 5
    threads: 1
    resources:
        threads=1,
        vcpu=1,
        mem_mb=4000,
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        canonical_bed=config["sentieon_pangenome_ug"]["canonical_bed"],
        regions=get_dchrm_day,
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.pangenome_ug.spmd.sentpgs.{dchrm}.bed.bench.tsv"
    log:
        MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/log/{sample}.pangenome_ug.spmd.sentpgs.{dchrm}.bed.log",
    shell:
        """
        mkdir -p $(dirname {log}) $(dirname {output.bed});
        python workflow/scripts/make_scoped_pangenome_bed.py \
            --regions "{params.regions}" \
            --canonical-bed "{params.canonical_bed}" \
            --fai "{params.huref}.fai" \
            --output {output.bed} > {log} 2>&1;
        """


rule sentieon_pangenome_ug_sharded:
    """Sentieon pangenome Ultima caller over one scoped chromosome shard."""
    input:
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        cram=MDIR + "{sample}/align/ug/{sample}.cram",
        crai=MDIR + "{sample}/align/ug/{sample}.cram.crai",
        bed=MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/vcfs/{dchrm}/tmp/{sample}.pangenome_ug.spmd.sentpgs.{dchrm}.bed",
    output:
        vcfgz=MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/vcfs/{dchrm}/{sample}.pangenome_ug.spmd.sentpgs.{dchrm}.snv.sort.vcf.gz",
        vcfgztbi=MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/vcfs/{dchrm}/{sample}.pangenome_ug.spmd.sentpgs.{dchrm}.snv.sort.vcf.gz.tbi",
    log:
        MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/log/{sample}.pangenome_ug.spmd.sentpgs.{dchrm}.log",
    threads: config["sentieon_pangenome_ug"]["shard_threads"]
    conda:
        config["sentieon_pangenome_ug"]["env_yaml"]
    priority: 5
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.pangenome_ug.spmd.sentpgs.{dchrm}.bench.tsv",
            0
            if "bench_repeat" not in config["sentieon_pangenome_ug"]
            else config["sentieon_pangenome_ug"]["bench_repeat"],
        )
    resources:
        attempt_n=lambda wildcards, attempt: (attempt + 0),
        partition=config["sentieon_pangenome_ug"]["shard_partition"],
        threads=config["sentieon_pangenome_ug"]["shard_threads"],
        vcpu=config["sentieon_pangenome_ug"]["shard_threads"],
        mem_mb=config["sentieon_pangenome_ug"]["shard_mem_mb"],
        constraint=config["sentieon_pangenome_ug"]["constraint"],
        distribution=config["sentieon_pangenome_ug"]["distribution"],
        exclude=config["sentieon_pangenome_ug"]["exclude"],
        include=config["sentieon_pangenome_ug"]["include"],
        exclusive=config["sentieon_pangenome_ug"]["exclusive"],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        gbz=config["sentieon_pangenome_ug"]["gbz"],
        hapl=config["sentieon_pangenome_ug"]["hapl"],
        model=config["sentieon_pangenome_ug"]["model"],
        pop_vcf=config["sentieon_pangenome_ug"]["pop_vcf"],
        canonical_bed=config["sentieon_pangenome_ug"]["canonical_bed"],
        dbsnp=config["sentieon_pangenome_ug"]["dbsnp"],
        cli_threads=min(int(config["sentieon_pangenome_ug"]["shard_threads"]), 128),
        cluster_sample=ret_sample,
    shell:
        """
        mkdir -p $(dirname {log}) $(dirname {output.vcfgz});

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

        # Prepend patched KMC (Sentieon fork with stdin support) to PATH
        export PATH="$DAY_ROOT/resources/kmc/bin:$PATH";
        if ! command -v kmc &>/dev/null; then
            echo "ERROR: patched kmc not found at $DAY_ROOT/resources/kmc/bin/kmc" >> {log} 2>&1;
            exit 6;
        fi
        echo "Using patched KMC: $(which kmc)" >> {log} 2>&1;

        ulimit -n 65536 || echo "ulimit mod failed" >> {log} 2>&1;

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/scratch/pangenome_ug_sentpgs_tmp_${{timestamp}}_$$";
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

        # Find jemalloc in active conda env
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
            echo "WARNING: libjemalloc not found in CONDA_PREFIX=$CONDA_PREFIX" >> {log};
        fi

        # --- bin/dayoa_sentieon_cli dnascope-pangenome (accelerated pipeline) ---
        cli_out="$TMPDIR/{wildcards.sample}.pangenome_ug.spmd.sentpgs.{wildcards.dchrm}";
        scoped_canonical_bed="{input.bed}";

        echo "bin/dayoa_sentieon_cli dnascope-pangenome starting (Ultima, CRAM input mode, sentpgs shard)" >> {log} 2>&1;
        echo "  input_cram={input.cram}" >> {log} 2>&1;
        echo "  shard={wildcards.dchrm}" >> {log} 2>&1;
        echo "  scoped_canonical_bed=$scoped_canonical_bed" >> {log} 2>&1;
        echo "  canonical_bed={params.canonical_bed}" >> {log} 2>&1;
        echo "  model={params.model}" >> {log} 2>&1;
        echo "  hapl={params.hapl}" >> {log} 2>&1;
        echo "  gbz={params.gbz}" >> {log} 2>&1;
        set +e;
        bin/dayoa_sentieon_cli dnascope-pangenome \
            -r {params.huref} \
            --hapl "{params.hapl}" \
            --gbz "{params.gbz}" \
            -m "{params.model}" \
            --pop_vcf "{params.pop_vcf}" \
            -i {input.cram} \
            -b "$scoped_canonical_bed" \
            --dbsnp "{params.dbsnp}" \
            -t {params.cli_threads} \
            "${{cli_out}}.vcf.gz" >> {log} 2>&1;
        cli_rc=$?;
        set -e;
        echo "sentieon-cli exit code: $cli_rc" >> {log} 2>&1;
        if [ $cli_rc -ne 0 ]; then
            echo "ERROR: bin/dayoa_sentieon_cli dnascope-pangenome failed with exit code $cli_rc" >> {log} 2>&1;
            exit $cli_rc;
        fi

        # --- Reheader VCF: rename sample to cluster_sample ---
        if [ -f "${{cli_out}}.vcf.gz" ]; then
            oldname=$(bcftools query -l "${{cli_out}}.vcf.gz" | head -n1);
            echo -e "${{oldname}}\\t{params.cluster_sample}" > "$TMPDIR/rename.txt";
            bcftools reheader -s "$TMPDIR/rename.txt" -o {output.vcfgz} "${{cli_out}}.vcf.gz" >> {log} 2>&1;
            bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;
        else
            echo "ERROR: VCF not produced by bin/dayoa_sentieon_cli dnascope-pangenome" >> {log} 2>&1;
            exit 20;
        fi

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\\t$itype\\t$elapsed_time" >> {log} 2>&1;
        """


rule sentpgs_concat_fofn:
    """Build file-of-filenames for sentpgs chromosome shards."""
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/pangenome_ug/spmd/snv/sentpgs/vcfs/{dchrm}/{{sample}}.pangenome_ug.spmd.sentpgs.{dchrm}.snv.sort.vcf.gz.tbi",
                dchrm=SENTPGS_CHRMS,
            ),
            key=_sentpgs_dchrm_sort_key,
        ),
    priority: 44
    output:
        fin_fofn=MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/{sample}.pangenome_ug.spmd.sentpgs.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/{sample}.pangenome_ug.spmd.sentpgs.snv.concat.vcf.gz.fofn.tmp",
    threads: 1
    resources:
        threads=1,
        vcpu=1,
        mem_mb=4000,
    params:
        cluster_sample=ret_sample,
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.pangenome_ug.spmd.sentpgs.concat.fofn.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/log/{sample}.pangenome_ug.spmd.sentpgs.concat.fofn.log",
    shell:
        """
        mkdir -p $(dirname {log}) $(dirname {output.fin_fofn});
        rm -f {output.tmp_fofn} {output.fin_fofn};
        touch {log};
        for i in {input.chunk_tbi}; do
            ii=$(echo "$i" | perl -pe 's/\\.tbi$//g'; );
            echo "$ii" >> {output.tmp_fofn};
        done;
        mv {output.tmp_fofn} {output.fin_fofn};
        """


rule sentpgs_concat_index_chunks:
    """Concatenate sentpgs chromosome shards and index the final VCF."""
    input:
        fofn=MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/{sample}.pangenome_ug.spmd.sentpgs.snv.concat.vcf.gz.fofn",
    output:
        vcfgz=MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/{sample}.pangenome_ug.spmd.sentpgs.snv.sort.vcf.gz",
        vcfgztemp=MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/{sample}.pangenome_ug.spmd.sentpgs.snv.sort.temp.vcf.gz",
        vcfgztbi=MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/{sample}.pangenome_ug.spmd.sentpgs.snv.sort.vcf.gz.tbi",
    threads: config["sentieon_pangenome_ug"]["concat_threads"]
    resources:
        vcpu=config["sentieon_pangenome_ug"]["concat_threads"],
        threads=config["sentieon_pangenome_ug"]["concat_threads"],
        partition=config["sentieon_pangenome_ug"]["concat_partition"],
        mem_mb=config["sentieon_pangenome_ug"]["concat_mem_mb"],
        constraint=config["sentieon_pangenome_ug"]["constraint"],
        distribution=config["sentieon_pangenome_ug"]["distribution"],
        exclude=config["sentieon_pangenome_ug"]["exclude"],
        include=config["sentieon_pangenome_ug"]["include"],
        exclusive=config["sentieon_pangenome_ug"]["exclusive"],
    priority: 47
    params:
        cluster_sample=ret_sample,
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.pangenome_ug.spmd.sentpgs.merge.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR
        + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/log/{sample}.pangenome_ug.spmd.sentpgs.snv.merge.sort.gathered.log",
    shell:
        """
        mkdir -p $(dirname {log}) $(dirname {output.vcfgz});
        touch {log};

        bcftools concat -a -d all --threads {threads} -f {input.fofn} -O z -o {output.vcfgztemp} >> {log} 2>&1;

        export oldname=$(bcftools query -l {output.vcfgztemp} | head -n1) >> {log} 2>&1;
        echo -e "${{oldname}}\\t{params.cluster_sample}" > {output.vcfgz}.rename.txt
        bcftools reheader --threads {threads} -s {output.vcfgz}.rename.txt -o {output.vcfgz} {output.vcfgztemp} >> {log} 2>&1;
        bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;
        """


localrules:
    clear_combined_pangenome_ug_vcf,


rule clear_combined_pangenome_ug_vcf:  # TARGET: clear combined pangenome ug vcf
    input:
        expand(
            MDIR + "{sample}/align/pangenome_ug/spmd/snv/sentpg/{sample}.pangenome_ug.spmd.sentpg.snv.sort.vcf.gz",
            sample=SAMPS,
        ),
    log:
        MDIR + "logs/clear_combined_pangenome_ug_vcf.log"
    benchmark:
        "logs/benchmarks/clear_combined_pangenome_ug_vcf.bench.tsv"
    threads: 2
    priority: 42
    shell:
        """
        rm {input}*  1> /dev/null  2> /dev/null || echo 'file not found for deletion: {input}';
        """


localrules:
    produce_pangenome_ug_sharded_vcf,
    produce_pangenome_ug_vcf,


rule produce_pangenome_ug_sharded_vcf:  # TARGET: sharded sentieon pangenome ug vcf
    input:
        expand(
            MDIR
            + "{sample}/align/pangenome_ug/spmd/snv/sentpgs/{sample}.pangenome_ug.spmd.sentpgs.snv.sort.vcf.gz.tbi",
            sample=SAMPS,
        ),
    output:
        "gatheredall.pangenome_ug_sharded",
    priority: 48
    threads: 1
    log:
        "gatheredall.pangenome_ug_sharded.log",
    benchmark:
        "logs/benchmarks/produce_pangenome_ug_sharded_vcf.bench.tsv"
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """


rule produce_pangenome_ug_vcf:  # TARGET: sentieon pangenome ug vcf
    input:
        expand(
            MDIR
            + "{sample}/align/pangenome_ug/spmd/snv/sentpg/{sample}.pangenome_ug.spmd.sentpg.snv.sort.vcf.gz.tbi",
            sample=SAMPS,
        ),
    output:
        "gatheredall.pangenome_ug",
    priority: 48
    threads: 1
    log:
        "gatheredall.pangenome_ug.log",
    benchmark:
        "logs/benchmarks/produce_pangenome_ug_vcf.bench.tsv"
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """
