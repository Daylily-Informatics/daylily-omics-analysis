import sys
import os

#
# This pipeline will use the ONT aligned cram directly and call variants
# using Sentieon DNAscope with the ONT model bundle's diploid model.
#

ALIGNERS_ONT = ["ont", "sentmm2ont"]

# ONT-only sentdont produces SNV/indel VCFs. SV calling is handled by the
# explicit TIDDIT target; the Sentieon long-read SV subpipeline is skipped here
# because it can fail when low-output ONT samples do not generate a phased BED.
# DayOA has no ONT-only sentdont CNV target. Hybrid CNV support, where present,
# is separate.
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
# sent_snv_ont: Sentieon DNAscope SNV/indel caller (Oxford Nanopore)
# Runs the DNAscope driver directly for SNV/indels. The long-read wrapper's
# phased/SV stages are intentionally not used here; ONT SV calling is handled by
# the explicit TIDDIT target.
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
        diploid_bed=get_diploid_bed_interval_arg,
    shell:
        """
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/
        timestamp=$(date +%Y%m%d%H%M%S)_$$;

        export TMPDIR=/dev/shm/sentdont_tmp_$timestamp;
        export SENTIEON_TMPDIR=$TMPDIR;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

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

        # --- Sentieon DNAscope (ONT SNV/indel only) ---
        # SV is handled by TIDDIT.
        cli_out="$TMPDIR/{wildcards.sample}.{wildcards.alnr}.sentdont";

        echo "sentieon driver DNAscope starting: model={params.model}/diploid_model" >> {log} 2>&1;
        set +e;
        sentieon driver \
            --input {input.cram} \
            --reference {params.huref} \
            --thread_count {threads} \
            {params.diploid_bed} \
            --interval_padding 0 \
            --algo DNAscope \
            --dbsnp "{params.pop_vcf}" \
            --model "{params.model}/diploid_model" \
            "${{cli_out}}.vcf.gz" >> {log} 2>&1;

        driver_rc=$?;
        set -e;
        echo "sentieon driver exit code: $driver_rc" >> {log} 2>&1;
        if [ $driver_rc -ne 0 ]; then
            echo "ERROR: sentieon driver DNAscope failed with exit code $driver_rc" >> {log} 2>&1;
            exit $driver_rc;
        fi

        # --- Reheader SNV VCF: rename sample to cluster_sample ---
        if [ -f "${{cli_out}}.vcf.gz" ]; then
            oldname=$(bcftools query -l "${{cli_out}}.vcf.gz" | head -n1);
            echo -e "${{oldname}}\t{params.cluster_sample}" > "$TMPDIR/rename.txt";
            bcftools reheader -s "$TMPDIR/rename.txt" -o {output.vcfgz} "${{cli_out}}.vcf.gz" >> {log} 2>&1;
            bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;
        else
            echo "ERROR: SNV VCF not produced by sentieon driver" >> {log} 2>&1;
            exit 20;
        fi

        echo "Sentieon ONT SV calling skipped; TIDDIT is the ONT SV target." >> {log} 2>&1;
        touch {output.svvcfgz} {output.svvcfgztbi};

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
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """
