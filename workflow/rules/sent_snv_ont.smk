import sys
import os

#
# This pipeline will use the ONT aligned cram directly and call variants
# using sentieon-cli dnascope-longread --tech ONT
#

ALIGNERS_ONT = ["ont", "sentmm2ont"]

# ONT-only sentdont produces SNV/indel and SV VCFs; DayOA has no ONT-only
# sentdont CNV target. Hybrid CNV support, where present, is separate.
SENTDONT_CNV_SUPPORTED = False


def get_sentdont_cram(wildcards):
    """Return CRAM input for sentdont SNV calling.

    - 'ont' (pre-aligned): raw CRAM in align dir ({sample}.cram).
    - 'sentmm2ont' (from uBAM): deduped via no_dedup_cram passthrough
      ({sample}.{alnr}.{ddup}.cram).
    """
    if wildcards.alnr == "ont":
        return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.cram"
    return (
        MDIR
        + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/"
        + f"{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.cram"
    )


def get_sentdont_crai(wildcards):
    """Return CRAM index for sentdont SNV calling (mirrors get_sentdont_cram)."""
    return get_sentdont_cram(wildcards) + ".crai"


# ---------------------------------------------------------------------------
# sent_snv_ont: Sentieon DNAscope LongRead pipeline (Oxford Nanopore)
# Uses sentieon-cli dnascope-longread which implements the full two-pass
# phased variant calling pipeline (DNAscope → VariantPhaser → RepeatModel →
# DNAscopeHP per-haplotype → merge).  Outputs SNV/indel VCF + SV VCF.
# ---------------------------------------------------------------------------

rule sent_snv_ont:
    input:
        cram=get_sentdont_cram,
        crai=get_sentdont_crai,
    output:
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdont/{sample}.{alnr}.{ddup}.sentdont.snv.sort.vcf.gz",
        vcfgztbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdont/{sample}.{alnr}.{ddup}.sentdont.snv.sort.vcf.gz.tbi",
        svvcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdont/{sample}.{alnr}.{ddup}.sentdont.sv.vcf.gz",
        svvcfgztbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdont/{sample}.{alnr}.{ddup}.sentdont.sv.vcf.gz.tbi",
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdont/log/{sample}.{alnr}.{ddup}.sentdont.snv.log",
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
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
        cluster_sample=ret_sample,
        haploid_bed=get_haploid_bed_arg,
        diploid_bed=get_diploid_bed_arg,
        keep_tmp_dirs=config["sentdont"]["keep_tmp_dirs"],
    shell:
        """
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/
        timestamp=$(date +%Y%m%d%H%M%S)_$$;

        export TMPDIR=/dev/shm/sentdont_tmp_$timestamp;
        export SENTIEON_TMPDIR=$TMPDIR;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap 'status=$?; keep_tmp="{params.keep_tmp_dirs}"; if [ "$keep_tmp" = "True" ] || [ "$keep_tmp" = "true" ] || [ "$keep_tmp" = "1" ]; then echo "Retaining sentdont TMPDIR because sentdont.keep_tmp_dirs=true: $TMPDIR" >> {log} 2>&1; df -h /dev/shm >> {log} 2>&1 || true; else rm -rf "$TMPDIR" 2>/dev/null || true; fi; trap - EXIT; exit "$status"' EXIT;

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
        echo "sentieon-cli dnascope-longread retain_tmpdir enabled; TMPDIR=$TMPDIR" >> {log} 2>&1;
        set +e;
        sentieon-cli dnascope-longread \
            -r {params.huref} \
            -i {input.cram} \
            -m "{params.model}" \
            -d "{params.pop_vcf}" \
            -t {threads} \
            --tech ONT \
            --retain_tmpdir \
            {params.diploid_bed} {params.haploid_bed} \
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
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdont/{sample}.{alnr}.{ddup}.sentdont.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=[a for a in ALIGNERS_ONT if a in ALL_ALIGNERS],
            ddup=DDUP,
        ),
    log:
        MDIR + "logs/clear_combined_sentdont_vcf.log"
    benchmark:
        MDIR + "benchmarks/clear_combined_sentdont_vcf.bench.tsv"
    threads: 2
    priority: 42
    shell:
        """
        rm {input}*  1> /dev/null  2> /dev/null || echo 'file not found for deletion: {input}';
        """

localrules:
    produce_sentdont_vcf,

rule produce_sentdont_vcf:  # DEPRECATED TARGET: use produce_sentdont_snv_vcf
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdont/{sample}.{alnr}.{ddup}.sentdont.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=[a for a in ALIGNERS_ONT if a in ALL_ALIGNERS],
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdont",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdont.log",
    benchmark:
        MDIR + "benchmarks/produce_sentdont_vcf.bench.tsv"
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """
