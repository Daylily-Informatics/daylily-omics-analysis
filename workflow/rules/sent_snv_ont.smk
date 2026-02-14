import sys
import os

#
# This pipeline will use the ONT aligned cram directly and call variants
# using sentieon-cli dnascope-longread --tech ONT
#

ALIGNERS_ONT = ["ont"]


# ---------------------------------------------------------------------------
# sent_snv_ont: Sentieon DNAscope LongRead pipeline (Oxford Nanopore)
# Uses sentieon-cli dnascope-longread which implements the full two-pass
# phased variant calling pipeline (DNAscope → VariantPhaser → RepeatModel →
# DNAscopeHP per-haplotype → merge).  Outputs SNV/indel VCF + SV VCF.
# ---------------------------------------------------------------------------

rule sent_snv_ont:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.cram.crai",
    output:
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdont/{sample}.{alnr}.sentdont.snv.sort.vcf.gz",
        vcfgztbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdont/{sample}.{alnr}.sentdont.snv.sort.vcf.gz.tbi",
        svvcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdont/{sample}.{alnr}.sentdont.sv.vcf.gz",
        svvcfgztbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdont/{sample}.{alnr}.sentdont.sv.vcf.gz.tbi",
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdont/log/{sample}.{alnr}.sentdont.snv.log",
    threads: config['sentdont']['threads']
    conda:
        config["sentdont"]["env_yaml"]
    priority: 45
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdont.bench.tsv",
            0
            if "bench_repeat" not in config["sentdont"]
            else config["sentdont"]["bench_repeat"],
        )
    resources:
        attempt_n=lambda wildcards, attempt:  (attempt + 0),
        partition=config['sentdont']['partition'],
        threads=config['sentdont']['threads'],
        vcpu=config['sentdont']['threads'],
        mem_mb=config['sentdont']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdont"]["dna_scope_snv_model"],
        pop_vcf=config["sentdont"]["pop_vcf"],
        cluster_sample=ret_sample,
    shell:
        """
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/
        timestamp=$(date +%Y%m%d%H%M%S);
	export PATH=$PATH:$SENTIEON_BIN_DIR
        export TMPDIR=/dev/shm/sentdont_tmp_$timestamp;
        export SENTIEON_TMPDIR=$TMPDIR;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap "rm -rf \"$TMPDIR\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;

        if [ -z "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE not set." >> {log} 2>&1;
            exit 3;
        fi

        if [ ! -f "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE file not found: '$SENTIEON_LICENSE'" >> {log} 2>&1;
            exit 4;
        fi

        TOKEN=$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type);
        echo "INSTANCE TYPE: $itype" > {log};
        start_time=$(date +%s);

        ulimit -n 65536 || echo "ulimit mod failed" >> {log} 2>&1;

        # --- Validate input CRAM contains aligned data ---
        echo "Validating CRAM: {input.cram}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.cram} >> {log} 2>&1; then
            echo "ERROR: CRAM failed integrity check: {input.cram}" | tee -a {log};
            exit 10;
        fi
        _sq_count=$(samtools view -H {input.cram} 2>/dev/null | grep -c '^@SQ' || true);
        if [ "$_sq_count" -eq 0 ]; then
            echo "ERROR: CRAM has no @SQ headers (unaligned?): {input.cram}" | tee -a {log};
            exit 11;
        fi
        echo "CRAM validation passed ($_sq_count reference sequences)" >> {log} 2>&1;

        # Find jemalloc in the active conda environment
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

        # --- sentieon-cli dnascope-longread (ONT) ---
        # The CLI runs the full two-pass phased pipeline internally.
        # Outputs: <basename>.vcf.gz (SNV/indel) and <basename>.sv.vcf.gz (SV)
        cli_out="$TMPDIR/{wildcards.sample}.{wildcards.alnr}.sentdont";

        echo "sentieon-cli dnascope-longread starting: model={params.model} tech=ONT" >> {log} 2>&1;
        set +e;
        sentieon-cli dnascope-longread \
            -r {params.huref} \
            -i {input.cram} \
            -m "{params.model}" \
            -d "{params.pop_vcf}" \
            -t {threads} \
            --tech ONT \
            "${{cli_out}}.vcf.gz" >> {log} 2>&1;
        cli_rc=$?;
        set -e;
        echo "sentieon-cli exit code: $cli_rc" >> {log} 2>&1;
        if [ $cli_rc -ne 0 ]; then
            echo "ERROR: sentieon-cli dnascope-longread failed with exit code $cli_rc" >> {log} 2>&1;
            exit $cli_rc;
        fi

        # --- Reheader SNV VCF: rename sample to cluster_sample ---
        if [ -f "${{cli_out}}.vcf.gz" ]; then
            oldname=$(bcftools query -l "${{cli_out}}.vcf.gz" | head -n1);
            echo -e "${{oldname}}\t{params.cluster_sample}" > "$TMPDIR/rename.txt";
            bcftools reheader -s "$TMPDIR/rename.txt" -o {output.vcfgz} "${{cli_out}}.vcf.gz" >> {log} 2>&1;
            bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;
        else
            echo "ERROR: SNV VCF not produced by sentieon-cli" >> {log} 2>&1;
            exit 20;
        fi

        # --- Reheader SV VCF ---
        if [ -f "${{cli_out}}.sv.vcf.gz" ]; then
            bcftools reheader -s "$TMPDIR/rename.txt" -o {output.svvcfgz} "${{cli_out}}.sv.vcf.gz" >> {log} 2>&1;
            bcftools index -f -t --threads {threads} -o {output.svvcfgztbi} {output.svvcfgz} >> {log} 2>&1;
        else
            echo "WARNING: SV VCF not produced; creating empty placeholder" >> {log} 2>&1;
            touch {output.svvcfgz} {output.svvcfgztbi};
        fi

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;

        """


localrules:
    clear_combined_sentdont_vcf,


rule clear_combined_sentdont_vcf:  # TARGET:  clear combined sentdont vcf so the chunks can be re-evaluated if needed.
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdont/{sample}.{alnr}.sentdont.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=ALIGNERS_ONT,
            ddup=DDUP,
        ),
    threads: 2
    priority: 42
    shell:
        """
        rm {input}*  1> /dev/null  2> /dev/null || echo 'file not found for deletion: {input}';
        """

localrules:
    produce_sentdont_vcf,

rule produce_sentdont_vcf:  # TARGET: sentieon dnascope vcf
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdont/{sample}.{alnr}.sentdont.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS_ONT,
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdont",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdont.log",
    shell:
        """( touch {output} ;

        {latency_wait}; ls {output} ) >> {log} 2>&1;
        """
