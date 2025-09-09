import sys
import os

##### mutect2
# ---------------------------

rule mutect2:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_cram=get_somcall_tumor_cram,
        tumor_crai=get_somcall_tumor_crai,
        normal_cram=get_somcall_normal_cram,
        normal_crai=get_somcall_normal_crai,
        ref_fa=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ref_fai=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
        d=MDIR + "{sample}/align/{alnr}/snv/mutect2/vcfs/{m2chrm}/{sample}.ready",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/snv/mutect2/vcfs/{m2chrm}/{sample}.{alnr}.mutect2.{m2chrm}.snv.vcf",
    log:
        MDIR + "{sample}/align/{alnr}/snv/mutect2/log/{sample}.{alnr}.mutect2.{m2chrm}.snv.log",
    threads: config['mutect2']['threads']
    container:
        config['mutect2']['container']
    priority: 45
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.mutect2.{m2chrm}.bench.tsv",
            0 if 'bench_repeat' not in config.get('mutect2', {}) else config['mutect2']['bench_repeat'],
        )
    resources:
        vcpu=config['mutect2']['threads'],
        threads=config['mutect2']['threads'],
        partition=config['mutect2']['partition'],
        mem_mb=config['mutect2']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cpre="" if "b37" == config['genome_build'] else "chr",
        mito_code="MT" if "b37" == config['genome_build'] else "M",
        chrm=get_mutect2_chrm_day,
        tumor_sample=ret_sample,
        normal_sample=lambda wc: TN_PAIRS[wc.sample],
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

        gatk --java-options "-Xmx{resources.mem_mb}M" Mutect2 \
            -R {params.huref} \
            -I {input.tumor_cram} -tumor {params.tumor_sample} \
            -I {input.normal_cram} -normal {params.normal_sample} \
            -L $region \
            -O {output.vcf} >> {log} 2>&1
        """


rule mutect2_sort_index_chunk_vcf:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcf=MDIR + "{sample}/align/{alnr}/snv/mutect2/vcfs/{m2chrm}/{sample}.{alnr}.mutect2.{m2chrm}.snv.vcf",
    priority: 46
    output:
        vcfsort=MDIR + "{sample}/align/{alnr}/snv/mutect2/vcfs/{m2chrm}/{sample}.{alnr}.mutect2.{m2chrm}.snv.sort.vcf",
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/mutect2/vcfs/{m2chrm}/{sample}.{alnr}.mutect2.{m2chrm}.snv.sort.vcf.gz",
        vcftbi=MDIR + "{sample}/align/{alnr}/snv/mutect2/vcfs/{m2chrm}/{sample}.{alnr}.mutect2.{m2chrm}.snv.sort.vcf.gz.tbi",
    conda:
        config['mutect2']['conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/mutect2/vcfs/{m2chrm}/log/{sample}.{alnr}.mutect2.{m2chrm}.snv.sort.vcf.gz.log",
    resources:
        vcpu=4,
        threads=4,
        partition=config['mutect2'].get('partition_other', config['mutect2']['partition']),
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


rule mutect2_concat_index_chunks:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcfs=lambda wildcards: expand(
            MDIR + "{sample}/align/{alnr}/snv/mutect2/vcfs/{m2chrm}/{sample}.{alnr}.mutect2.{m2chrm}.snv.sort.vcf.gz",
            sample=wildcards.sample,
            alnr=wildcards.alnr,
            m2chrm=M2_CHRMS,
        ),
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/mutect2/{sample}.{alnr}.mutect2.snv.sort.vcf.gz",
        vcfgztbi=MDIR + "{sample}/align/{alnr}/snv/mutect2/{sample}.{alnr}.mutect2.snv.sort.vcf.gz.tbi",
    threads: 4
    conda:
        config['mutect2']['conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/mutect2/log/{sample}.{alnr}.mutect2.snv.merge.log",
    params:
        cluster_sample=ret_sample,
    shell:
        """
        bcftools concat -a -O z -o {output.vcfgz} {input.vcfs} >> {log} 2>&1;
        bcftools index -f -t {output.vcfgz} >> {log} 2>&1;
        """


rule produce_mutect2_vcf:  # Target: produce mutect2
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcftb=expand(
            MDIR + "{sample}/align/{alnr}/snv/mutect2/{sample}.{alnr}.mutect2.snv.sort.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        vcftbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/mutect2/{sample}.{alnr}.mutect2.snv.sort.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
    output:
        "gatheredall.mutect2",
    threads: 4
    priority: 48
    log:
        "gatheredall.mutect2.log",
    conda:
        config['mutect2']['conda']
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
