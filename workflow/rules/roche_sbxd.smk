import sys
import os


ALIGNERS_ROCHE = ["roche"]


# ---------------------------------------------------------------------------
# no_dedup_roche_bam: BAM passthrough into /na/ dedup directory
# ---------------------------------------------------------------------------
# Roche pre-aligned BAMs stay as BAM (not CRAM) because downstream
# GATK HaplotypeCaller requires BAM input with --bamout.

ruleorder: no_dedup_roche_bam > pre_prep_roche_bam


rule no_dedup_roche_bam:
    """Symlink staged Roche BAM into the /na/ dedup directory."""
    input:
        bam=MDIR + "{sample}/align/roche/{sample}.roche.bam",
        bai=MDIR + "{sample}/align/roche/{sample}.roche.bam.bai",
    output:
        bam=MDIR + "{sample}/align/{alnr}/na/{sample}.{alnr}.na.bam",
        bai=MDIR + "{sample}/align/{alnr}/na/{sample}.{alnr}.na.bam.bai",
    wildcard_constraints:
        alnr="roche",
    priority: 3
    params:
        cluster_sample=ret_sample,
    threads: 1
    resources:
        threads=1,
        partition=config.get("no_dedup", {}).get("partition", "i192"),
        vcpu=1,
        mem_mb=1000,
    log:
        MDIR + "{sample}/align/{alnr}/na/logs/no_dedup_roche.{sample}.{alnr}.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.na.no_dedup_roche.bench.tsv"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.bam})
        touch {log}

        ln -sfn "$(realpath --relative-to=$(dirname {output.bam}) {input.bam})" {output.bam} >> {log} 2>&1
        ln -sfn "$(realpath --relative-to=$(dirname {output.bai}) {input.bai})" {output.bai} >> {log} 2>&1

        echo "Symlinked {input.bam} → {output.bam}" >> {log} 2>&1
        echo "Symlinked {input.bai} → {output.bai}" >> {log} 2>&1
        """


# ---------------------------------------------------------------------------
# roche_gatk_haplotypecaller: GATK HC with duplex-optimised parameters
# ---------------------------------------------------------------------------
# Uses container: directive — bind mounts handled by profile singularity-args.
# -OVI / -OBI flags tell GATK to create the VCF and BAM indices.

rule roche_gatk_haplotypecaller:
    input:
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.bam",
        bai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.bam.bai",
    output:
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/rochehc/{sample}.{alnr}.{ddup}.rochehc.gatk_raw.vcf.gz",
        vcfgztbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/rochehc/{sample}.{alnr}.{ddup}.rochehc.gatk_raw.vcf.gz.tbi",
        bamout=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/rochehc/{sample}.{alnr}.{ddup}.rochehc.bamout.bam",
        bamouti=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/rochehc/{sample}.{alnr}.{ddup}.rochehc.bamout.bam.bai",
    wildcard_constraints:
        alnr="roche",
        ddup="na",
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/rochehc/log/{sample}.{alnr}.{ddup}.rochehc.snv.log",
    threads: config['roche_gatk_haplotypecaller']['threads']
    container:
        config['roche_gatk_haplotypecaller']['container']
    conda:
        config["roche_gatk_haplotypecaller"]["env_yaml"]
    priority: 45
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.rochehc.bench.tsv",
            0
            if "bench_repeat" not in config["roche_gatk_haplotypecaller"]
            else config["roche_gatk_haplotypecaller"]["bench_repeat"],
        )
    resources:
        attempt_n=lambda wildcards, attempt: (attempt + 0),
        partition=config['roche_gatk_haplotypecaller']['partition'],
        threads=config['roche_gatk_haplotypecaller']['threads'],
        vcpu=config['roche_gatk_haplotypecaller']['threads'],
        mem_mb=config['roche_gatk_haplotypecaller']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["roche"]["grch38_noalt_fasta"],
        native_hmm_threads=config['roche_gatk_haplotypecaller']['native_pair_hmm_threads'],
        cluster_sample=ret_sample,
    shell:
        """
        timestamp=$(date +%Y%m%d%H%M%S)_$$;
        export TMPDIR=/dev/shm/rochehc_tmp_$timestamp;
        mkdir -p $TMPDIR;
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        TOKEN=$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' \
            -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' 2>/dev/null) || true;
        itype=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
            http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null) || itype="unknown";
        echo "INSTANCE TYPE: $itype" > {log};
        start_time=$(date +%s);

        echo "Running GATK HaplotypeCaller (Roche SBX Duplex)" >> {log} 2>&1;
        mkdir -p $(dirname {output.vcfgz});

        gatk --java-options "-Xmx{resources.mem_mb}m -Djava.io.tmpdir=$TMPDIR" \
            HaplotypeCaller \
            -I {input.bam} \
            -R {params.huref} \
            -O {output.vcfgz} \
            -OVI \
            -bamout {output.bamout} \
            -OBI \
            -A AssemblyComplexity \
            -A TandemRepeat \
            -RF MappingQualityReadFilter \
            --activeregion-alt-multiplier 5 \
            --adaptive-pruning true \
            --enable-dynamic-read-disqualification-for-genotyping true \
            --mapping-quality-threshold-for-genotyping 1 \
            --minimum-mapping-quality 1 \
            --min-base-quality-score 6 \
            --native-pair-hmm-threads {params.native_hmm_threads} \
            --smith-waterman FASTEST_AVAILABLE \
            --tmp-dir $TMPDIR >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;
        """


# ---------------------------------------------------------------------------
# roche_filter_variants: Roche Small Variant Caller post-filtering
# ---------------------------------------------------------------------------
# Uses container: directive — bind mounts handled by profile singularity-args.
# Model files at /resources/ are inside the container image.

rule roche_filter_variants:
    input:
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/rochehc/{sample}.{alnr}.{ddup}.rochehc.gatk_raw.vcf.gz",
        bamout=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/rochehc/{sample}.{alnr}.{ddup}.rochehc.bamout.bam",
    output:
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/rochehc/{sample}.{alnr}.{ddup}.rochehc.snv.sort.vcf.gz",
        vcfgztbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/rochehc/{sample}.{alnr}.{ddup}.rochehc.snv.sort.vcf.gz.tbi",
    wildcard_constraints:
        alnr="roche",
        ddup="na",
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/rochehc/log/{sample}.{alnr}.{ddup}.rochehc.filt.log",
    threads: config['roche_filter_variants']['threads']
    container:
        config['roche_filter_variants']['container']
    conda:
        config["roche_filter_variants"]["env_yaml"]
    priority: 46
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.rochehc.filt.bench.tsv",
            0
            if "bench_repeat" not in config["roche_filter_variants"]
            else config["roche_filter_variants"]["bench_repeat"],
        )
    resources:
        attempt_n=lambda wildcards, attempt: (attempt + 0),
        partition=config['roche_filter_variants']['partition'],
        threads=config['roche_filter_variants']['threads'],
        vcpu=config['roche_filter_variants']['threads'],
        mem_mb=config['roche_filter_variants']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["roche"]["grch38_noalt_fasta"],
        gnomad=config["supporting_files"]["files"]["roche"]["gnomad_af_vcf"],
        model_snv=config["supporting_files"]["files"]["roche"]["filter_model_snv"],
        model_indel=config["supporting_files"]["files"]["roche"]["filter_model_indel"],
        cluster_sample=ret_sample,
    shell:
        """
        start_time=$(date +%s);
        echo "Running Roche filter_variants" > {log} 2>&1;
        mkdir -p $(dirname {output.vcfgz});


        filter_variants \
            --bam-input {input.bamout} \
            --vcf-input {input.vcfgz} \
            --pop-af-vcf {params.gnomad} \
            --workflow germline \
            --threads {threads} \
            --genome {params.huref} \
            --model {params.model_snv} {params.model_indel} \
            --vcf-output {output.vcfgz} >> {log} 2>&1;

        # Index filtered VCF using host tabix (from conda env)
        tabix -p vcf {output.vcfgz} >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$elapsed_time" >> {log} 2>&1;
        """


localrules:
    produce_rochehc_vcf,


rule produce_rochehc_vcf:  # TARGET: Roche GATK HaplotypeCaller filtered VCF
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/rochehc/{sample}.{alnr}.{ddup}.rochehc.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS_ROCHE,
            ddup=["na"],
        ),
    output:
        "gatheredall.rochehc",
    priority: 48
    threads: 1
    log:
        "gatheredall.rochehc.log",
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """

