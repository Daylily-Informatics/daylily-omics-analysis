import sys
import os

##### sentieon TNscope - somatic SNV and INDEL caller
# ---------------------------
# This rule runs Sentieon's TNscope algorithm for somatic calling on
# tumour/normal pairs.  The structure mirrors the sentieon_dnascope rule
# to keep behaviour consistent across callers.

rule sent_TNscope:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_cram=get_somcall_tumor_cram,
        tumor_crai=get_somcall_tumor_crai,
        normal_cram=get_somcall_normal_cram,
        normal_crai=get_somcall_normal_crai,
        d=MDIR + "{sample}/align/{alnr}/snv/senttn/vcfs/{senttnchrm}/{sample}.ready",
    output:
        vcf=temp(MDIR + "{sample}/align/{alnr}/snv/senttn/vcfs/{senttnchrm}/{sample}.{alnr}.senttn.{senttnchrm}.snv.vcf"),
    log:
        MDIR + "{sample}/align/{alnr}/snv/senttn/log/{sample}.{alnr}.senttn.{senttnchrm}.snv.log",
    threads: config['senttn']['threads']
    conda: config['senttn']['env_yaml']
    priority: 45
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.senttn.{senttnchrm}.bench.tsv",
            0 if 'bench_repeat' not in config.get('senttn', {}) else config['senttn']['bench_repeat'],
        )
    resources:
        vcpu=config['senttn']['threads'],
        threads=config['senttn']['threads'],
        partition=config['senttn']['partition'],
        mem_mb=config['senttn']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cpre="" if "b37" == config['genome_build'] else "chr",
        mito_code="MT" if "b37" == config['genome_build'] else "M",
        chrm=get_senttn_chrm_day,
        tumor_sample=ret_sample,
        normal_sample=lambda wc: TN_PAIRS[wc.sample],
        numa=config['senttn']['numa'],
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail
        ulimit -n 65536 || true

        tchr=$(echo {params.cpre}{params.chrm} | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/')
        tchr=${{tchr%:}}
        IFS=':' read -r tcontig tstart tend <<< "$tchr"
        if [ -z "${{tend:-}}" ]; then
            tstart=0
            tend=$(awk -v c="$tcontig" '$1==c{{print $2; exit}}' {params.huref}.fai)
        fi
        region="$tcontig:$tstart-$tend"

        timestamp=$(date +%Y%m%d%H%M%S)_$(head -c 12 /dev/urandom | tr -dc 'a-zA-Z0-9')
        export TMPDIR=/dev/shm/senttn_tmp_$timestamp
        mkdir -p "$TMPDIR"
        export SENTIEON_TMPDIR=$TMPDIR
        export APPTAINER_HOME=$TMPDIR
        trap 'rm -rf "$TMPDIR" || true' EXIT

        if [ -z "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE not set. Please set the SENTIEON_LICENSE environment variable to the license file path & make this update to your dyinit file as well." >> {log} 2>&1
            exit 3
        fi

        if [ ! -f "$SENTIEON_LICENSE" ]; then
            echo "The file referenced by SENTIEON_LICENSE ('$SENTIEON_LICENSE') does not exist. Please provide a valid file path." >> {log} 2>&1
            exit 4
        fi

        {params.numa} /fsx/data/cached_envs/sentieon-genomics-202503.01.rc1/bin/sentieon driver \
            --tumor_sample {params.tumor_sample} \
            --normal_sample {params.normal_sample} \
            -t {threads} \
            -r {params.huref} \
            -i {input.tumor_cram} \
            -i {input.normal_cram} \
            --interval $region \
            --algo TNscope \
            {output.vcf} >> {log} 2>&1
        """


rule sent_TNscope_sort_index_chunk_vcf:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcf=MDIR + "{sample}/align/{alnr}/snv/senttn/vcfs/{senttnchrm}/{sample}.{alnr}.senttn.{senttnchrm}.snv.vcf",
    priority: 46
    output:
        vcfsort=touch(MDIR + "{sample}/align/{alnr}/snv/senttn/vcfs/{senttnchrm}/{sample}.{alnr}.senttn.{senttnchrm}.snv.sort.vcf"),
        vcfgz=touch(MDIR + "{sample}/align/{alnr}/snv/senttn/vcfs/{senttnchrm}/{sample}.{alnr}.senttn.{senttnchrm}.snv.sort.vcf.gz"),
        vcftbi=touch(MDIR + "{sample}/align/{alnr}/snv/senttn/vcfs/{senttnchrm}/{sample}.{alnr}.senttn.{senttnchrm}.snv.sort.vcf.gz.tbi"),
    conda:
        config['senttn']['conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/senttn/vcfs/{senttnchrm}/log/{sample}.{alnr}.senttn.{senttnchrm}.snv.sort.vcf.gz.log",
    resources:
        vcpu=4,
        threads=4,
        partition=config['senttn'].get('partition_other', config['senttn']['partition']),
    params:
        cluster_sample=ret_sample,
    threads: 4
    shell:
        """
        bedtools sort -header -i {input.vcf} > {output.vcfsort} 2>> {log};
        bgzip {output.vcfsort} >> {log} 2>&1;
        touch {output.vcfsort};
        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1;
        """


rule sent_TNscope_concat_index_chunks:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcfs=lambda wildcards: expand(
            MDIR + "{sample}/align/{alnr}/snv/senttn/vcfs/{senttnchrm}/{sample}.{alnr}.senttn.{senttnchrm}.snv.sort.vcf.gz",
            sample=wildcards.sample,
            alnr=wildcards.alnr,
            senttnchrm=SENTTN_CHRMS,
        ),
    output:
        vcfgz=touch(MDIR + "{sample}/align/{alnr}/snv/senttn/{sample}.{alnr}.senttn.snv.sort.vcf.gz"),
        vcfgztbi=touch(MDIR + "{sample}/align/{alnr}/snv/senttn/{sample}.{alnr}.senttn.snv.sort.vcf.gz.tbi"),
    threads: 4
    conda:
        config['senttn']['conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/senttn/log/{sample}.{alnr}.senttn.snv.merge.log",
    params:
        cluster_sample=ret_sample,
    shell:
        """
        bcftools concat -a -O z -o {output.vcfgz} {input.vcfs} >> {log} 2>&1;
        bcftools index -f -t {output.vcfgz} >> {log} 2>&1;
        """

rule produce_sent_TNscope_vcf:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcftb=expand(
            MDIR + "{sample}/align/{alnr}/snv/senttn/{sample}.{alnr}.senttn.snv.sort.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        vcftbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/senttn/{sample}.{alnr}.senttn.snv.sort.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
    output:
        "gatheredall.senttn",
    threads: 4
    priority: 48
    log:
        "gatheredall.senttn.log",
    conda:
        config['senttn']['conda']
    params:
        cluster_sample=ret_sample,
    shell:
        """
        for vcf in {input.vcftb}; do
            bcf="${{vcf%.vcf.gz}}.bcf";
            bcftools view -O b -o $bcf --threads {threads} $vcf && bcftools index --threads 4 $bcf;
        done;
        touch {output};
        {latency_wait};
        ls {output} >> {log} 2>&1;
        {latency_wait};
        ls {output} >> {log} 2>&1;
        """



localrules:
    prep_sentTN_chunkdirs,


rule prep_sentTN_chunkdirs:
    input:
        c=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        i=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/snv/senttn/vcfs/{dchrm}/{{sample}}.ready",
            dchrm=SENTTN_CHRMS,
        ),
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/snv/senttn/logs/{sample}.{alnr}.chunkdirs.log",
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
