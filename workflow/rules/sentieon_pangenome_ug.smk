import os

####### Sentieon Pangenome (accelerated) – Ultima Genomics pipeline
#
# Uses sentieon-cli sentieon-pangenome which performs pangenome-aware
# alignment (via GBZ graph reference) and variant calling for Ultima
# Genomics single-end WGS data.
#
# Input:  Staged Ultima CRAM  →  pangenome pipeline (direct CRAM input via -i)
#
# Outputs per sample:
#   {sample}/align/pangenome_ug/spmd/snv/sentpg/{sample}.pangenome_ug.spmd.sentpg.snv.sort.vcf.gz
#   {sample}/align/pangenome_ug/spmd/{sample}.pangenome_ug.spmd.cram
#   {sample}/align/pangenome_ug/spmd/{sample}.pangenome_ug.spmd.cram.crai
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
        cram=MDIR
        + "{sample}/align/pangenome_ug/spmd/{sample}.pangenome_ug.spmd.cram",
        crai=MDIR
        + "{sample}/align/pangenome_ug/spmd/{sample}.pangenome_ug.spmd.cram.crai",
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
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        gbz=config["sentieon_pangenome_ug"]["gbz"],
        hapl=config["sentieon_pangenome_ug"]["hapl"],
        model=config["sentieon_pangenome_ug"]["model"],
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
        canonical_bed=config["sentieon_pangenome_ug"]["canonical_bed"],
        dbsnp=config["sentieon_pangenome_ug"]["dbsnp"],
        pcr_free=config["sentieon_pangenome_ug"]["pcr_free"],
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
        export TMPDIR="/fsx/scratch/pangenome_ug_tmp_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        if [ ! -d "$TMPDIR" ]; then
            echo "ERROR: Failed to create TMPDIR: $TMPDIR" >> {log} 2>&1;
            exit 5;
        fi
        echo "TMPDIR created: $TMPDIR" >> {log} 2>&1;
        ls -ld "$TMPDIR" >> {log} 2>&1;
        df -h /fsx/scratch >> {log} 2>&1;
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

        # --- Build optional flags ---
        pcr_flag="";
        if [[ "{params.pcr_free}" == "true" ]]; then
            pcr_flag="--pcr_free";
        fi

        # --- sentieon-cli sentieon-pangenome (accelerated pipeline) ---
        cli_out="$TMPDIR/{wildcards.sample}.pangenome_ug";

        echo "sentieon-cli sentieon-pangenome starting (Ultima, CRAM input mode)" >> {log} 2>&1;
        echo "  input_cram={input.cram}" >> {log} 2>&1;
        echo "  model={params.model}" >> {log} 2>&1;
        echo "  hapl={params.hapl}" >> {log} 2>&1;
        echo "  gbz={params.gbz}" >> {log} 2>&1;
        set +e;
        sentieon-cli sentieon-pangenome \
            -r {params.huref} \
            --hapl "{params.hapl}" \
            --gbz "{params.gbz}" \
            -m "{params.model}" \
            --pop_vcf "{params.pop_vcf}" \
            -i {input.cram} \
            -b "{params.canonical_bed}" \
            --dbsnp "{params.dbsnp}" \
            $pcr_flag \
            -t {threads} \
            "${{cli_out}}.vcf.gz" >> {log} 2>&1;
        cli_rc=$?;
        set -e;
        echo "sentieon-cli exit code: $cli_rc" >> {log} 2>&1;
        if [ $cli_rc -ne 0 ]; then
            echo "ERROR: sentieon-cli sentieon-pangenome failed with exit code $cli_rc" >> {log} 2>&1;
            exit $cli_rc;
        fi

        # --- Reheader VCF: rename sample to cluster_sample ---
        if [ -f "${{cli_out}}.vcf.gz" ]; then
            oldname=$(bcftools query -l "${{cli_out}}.vcf.gz" | head -n1);
            echo -e "${{oldname}}\\t{params.cluster_sample}" > "$TMPDIR/rename.txt";
            bcftools reheader -s "$TMPDIR/rename.txt" -o {output.vcfgz} "${{cli_out}}.vcf.gz" >> {log} 2>&1;
            bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;
        else
            echo "ERROR: VCF not produced by sentieon-cli sentieon-pangenome" >> {log} 2>&1;
            exit 20;
        fi

        # --- Preserve CRAM produced by sentieon-cli ---
        cram_src="${{cli_out}}_pangenome-aligned.cram";
        if [ -f "$cram_src" ]; then
            mkdir -p "$(dirname {output.cram})";
            cp "$cram_src" {output.cram} >> {log} 2>&1;
            samtools index -@ {threads} {output.cram} >> {log} 2>&1;
            echo "CRAM preserved: {output.cram} ($(du -h {output.cram} | cut -f1))" >> {log} 2>&1;
        else
            echo "WARNING: CRAM not found at $cram_src — listing TMPDIR:" >> {log} 2>&1;
            ls -la "$TMPDIR"/ >> {log} 2>&1;
            exit 21;
        fi

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\\t$itype\\t$elapsed_time" >> {log} 2>&1;

        """


localrules:
    clear_combined_pangenome_ug_vcf,


rule clear_combined_pangenome_ug_vcf:  # TARGET: clear combined pangenome ug vcf
    input:
        expand(
            MDIR + "{sample}/align/pangenome_ug/spmd/snv/sentpg/{sample}.pangenome_ug.spmd.sentpg.snv.sort.vcf.gz",
            sample=SAMPS,
        ),
    threads: 2
    priority: 42
    shell:
        """
        rm {input}*  1> /dev/null  2> /dev/null || echo 'file not found for deletion: {input}';
        """


localrules:
    produce_pangenome_ug_vcf,


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
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """

