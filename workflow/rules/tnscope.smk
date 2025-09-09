import sys
import os

##### Sentieon TNscope - somatic SNV and INDEL caller
# ---------------------------


def get_tnscope_chrm_day(wildcards):
    pchr=""
    ret_str=""
    sl = wildcards.tnscopechrm.replace('chr', '').split('-')
    sl2 = wildcards.tnscopechrm.replace('chr', '').split('~')

    if len(sl2) == 2:
        ret_str = pchr + wildcards.tnscopechrm
    elif len(sl) == 1:
        ret_str = pchr + sl[0]
    elif len(sl) == 2:
        start = int(sl[0])
        end = int(sl[1])
        while start <= end:
            ret_str = str(ret_str) + " " + pchr + str(start)
            start = start + 1
    else:
        raise Exception(
            "tnscope chunks can only be one contiguous range per chunk : ie: 1-4 with the non numerical chrms assigned 23=X, 24=Y,25=MT"
        )

    return ret_mod_chrm(ret_str)


rule tnscope:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_cram=get_somcall_tumor_cram,
        tumor_crai=get_somcall_tumor_crai,
        normal_cram=get_somcall_normal_cram,
        normal_crai=get_somcall_normal_crai,
        d=MDIR + "{sample}/align/{alnr}/snv/tnscope/vcfs/{tnscopechrm}/{sample}.ready",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/snv/tnscope/vcfs/{tnscopechrm}/{sample}.{alnr}.tnscope.{tnscopechrm}.snv.vcf",
    log:
        MDIR + "{sample}/align/{alnr}/snv/tnscope/log/{sample}.{alnr}.tnscope.{tnscopechrm}.snv.log",
    threads: config['senttn']['threads']
    conda: config['senttn']['env_yaml']
    priority: 45
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.tnscope.{tnscopechrm}.bench.tsv",
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
        chrm=get_tnscope_chrm_day,
        tumor_sample=ret_sample,
        normal_sample=lambda wc: TN_PAIRS[wc.sample],
        numa=config['senttn']['numa'],
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail
        ulimit -n 65536 || true

        tchr=$(echo {params.cpre}{params.chrm} | sed 's/~/\\:/g' | sed 's/23\\:/X\\:/' | sed 's/24\\:/Y\\:/' | sed 's/25\\:/{params.mito_code}\\:/')
        tchr=${tchr%:}
        IFS=':' read -r tcontig tstart tend <<< "$tchr"
        if [ -z "${tend:-}" ]; then
            tstart=0
            tend=$(awk -v c="$tcontig" '$1==c{print $2; exit}' {params.huref}.fai)
        fi
        region="$tcontig:$tstart-$tend"

        timestamp=$(date +%Y%m%d%H%M%S)_$(head -c 12 /dev/urandom | tr -dc 'a-zA-Z0-9')
        export TMPDIR=/dev/shm/tnscope_tmp_$timestamp
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
            --interval "$region" \
            --algo TNscope \
            {output.vcf} >> {log} 2>&1
        """


rule tnscope_sort_index_chunk_vcf:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcf=MDIR + "{sample}/align/{alnr}/snv/tnscope/vcfs/{tnscopechrm}/{sample}.{alnr}.tnscope.{tnscopechrm}.snv.vcf",
    priority: 46
    output:
        vcfsort=MDIR + "{sample}/align/{alnr}/snv/tnscope/vcfs/{tnscopechrm}/{sample}.{alnr}.tnscope.{tnscopechrm}.snv.sort.vcf",
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/tnscope/vcfs/{tnscopechrm}/{sample}.{alnr}.tnscope.{tnscopechrm}.snv.sort.vcf.gz",
        vcftbi=MDIR + "{sample}/align/{alnr}/snv/tnscope/vcfs/{tnscopechrm}/{sample}.{alnr}.tnscope.{tnscopechrm}.snv.sort.vcf.gz.tbi",
    conda:
        config['senttn']['conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/tnscope/vcfs/{tnscopechrm}/log/{sample}.{alnr}.tnscope.{tnscopechrm}.snv.sort.vcf.gz.log",
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


rule tnscope_concat_index_chunks:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcfs=lambda wildcards: expand(
            MDIR + "{sample}/align/{alnr}/snv/tnscope/vcfs/{tnscopechrm}/{sample}.{alnr}.tnscope.{tnscopechrm}.snv.sort.vcf.gz",
            sample=wildcards.sample,
            alnr=wildcards.alnr,
            tnscopechrm=SENTTN_CHRMS,
        ),
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/tnscope/{sample}.{alnr}.tnscope.snv.sort.vcf.gz",
        vcfgztbi=MDIR + "{sample}/align/{alnr}/snv/tnscope/{sample}.{alnr}.tnscope.snv.sort.vcf.gz.tbi",
    threads: 4
    conda:
        config['senttn']['conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/tnscope/log/{sample}.{alnr}.tnscope.snv.merge.log",
    params:
        cluster_sample=ret_sample,
    shell:
        """
        bcftools concat -a -O z -o {output.vcfgz} {input.vcfs} >> {log} 2>&1;
        bcftools index -f -t {output.vcfgz} >> {log} 2>&1;
        """


rule produce_tnscope_vcf:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcftb=expand(
            MDIR + "{sample}/align/{alnr}/snv/tnscope/{sample}.{alnr}.tnscope.snv.sort.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        vcftbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/tnscope/{sample}.{alnr}.tnscope.snv.sort.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
    output:
        "gatheredall.tnscope",
    threads: 4
    priority: 48
    log:
        "gatheredall.tnscope.log",
    conda:
        config['senttn']['conda']
    params:
        cluster_sample=ret_sample,
    shell:
        """
        for vcf in {input.vcftb}; do
            bcf="${vcf%.vcf.gz}.bcf";
            bcftools view -O b -o $bcf --threads {threads} $vcf && bcftools index --threads 4 $bcf;
        done;
        touch {output};
        {latency_wait};
        ls {output} >> {log} 2>&1;
        {latency_wait};
        ls {output} >> {log} 2>&1;
        """
