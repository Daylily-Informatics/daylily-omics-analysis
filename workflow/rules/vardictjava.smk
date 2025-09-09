import sys
import os

##### VarDictJava
# ---------------------------


def get_vardict_chrom(wildcards):
    pchr = ""
    ret_str = ""
    sl = wildcards.vardictchrm.replace("chr", "").split("-")
    sl2 = wildcards.vardictchrm.replace("chr", "").split("~")

    if len(sl2) == 2:
        ret_str = pchr + wildcards.vardictchrm
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
            "vardict chunks can only be one contiguous range per chunk : ie: 1-4 with the non numerical chrms assigned 23=X, 24=Y,25=MT"
        )
    return ret_mod_chrm(ret_str)


def get_vardict_normal_sample(wildcards):
    try:
        return TN_PAIRS[wildcards.sample]
    except KeyError:
        raise ValueError(f"No matched normal sample for {wildcards.sample}")


rule vardictjava:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_cram=get_somcall_tumor_cram,
        tumor_crai=get_somcall_tumor_crai,
        normal_cram=get_somcall_normal_cram,
        normal_crai=get_somcall_normal_crai,
        ref_fa=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ref_fai=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
        d=MDIR + "{sample}/align/{alnr}/snv/vardictjava/vcfs/{vardictchrm}/{sample}.ready",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/snv/vardictjava/vcfs/{vardictchrm}/{sample}.{alnr}.vardictjava.{vardictchrm}.somatic.vcf",
    log:
        MDIR + "{sample}/align/{alnr}/snv/vardictjava/log/{sample}.{alnr}.vardictjava.{vardictchrm}.somatic.log",
    threads: config['vardictjava']['threads']
    container:
        config['vardictjava']['container']
    priority: 45
    resources:
        vcpu=config['vardictjava']['threads'],
        threads=config['vardictjava']['threads'],
        partition=config['vardictjava']['partition'],
        mem_mb=config['vardictjava']['mem_mb'],
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.vardictjava.{vardictchrm}.bench.tsv",
            0 if 'bench_repeat' not in config.get('vardictjava', {}) else config['vardictjava']['bench_repeat'],
        )
    params:
        vchrm=get_vardict_chrom,
        cluster_sample=ret_sample,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        normal_sample=get_vardict_normal_sample,
        af=config['vardictjava'].get('allele_freq', 0.01),
        numa=config['vardictjava']['numa'],
        cpre="" if "b37" == config['genome_build'] else "chr",
        mito_code="MT" if "b37" == config['genome_build'] else "M",
    shell:
        r"""
        set -euo pipefail
        ulimit -n 65536 || true

        region=$(echo {params.cpre}{params.vchrm} | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/')
        region=${region%:}

        mkdir -p "$(dirname {output.vcf})"

        {params.numa} vardict-java -G {params.huref} -f {params.af} -N {wildcards.sample} \
            -b "{input.tumor_cram}|{input.normal_cram}" -c 1 -S 2 -E 3 -g 4 "$region" \
            | testsomatic.R \
            | var2vcf_paired.pl -N "{wildcards.sample}|{params.normal_sample}" -f {params.af} \
            > {output.vcf} 2>> {log}
        """


rule vardictjava_sort_index_chunk_vcf:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcf=MDIR + "{sample}/align/{alnr}/snv/vardictjava/vcfs/{vardictchrm}/{sample}.{alnr}.vardictjava.{vardictchrm}.somatic.vcf",
    priority: 46
    output:
        vcfsort=MDIR + "{sample}/align/{alnr}/snv/vardictjava/vcfs/{vardictchrm}/{sample}.{alnr}.vardictjava.{vardictchrm}.somatic.sort.vcf",
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/vardictjava/vcfs/{vardictchrm}/{sample}.{alnr}.vardictjava.{vardictchrm}.somatic.sort.vcf.gz",
        vcftbi=MDIR + "{sample}/align/{alnr}/snv/vardictjava/vcfs/{vardictchrm}/{sample}.{alnr}.vardictjava.{vardictchrm}.somatic.sort.vcf.gz.tbi",
    conda:
        config['vardictjava']['vardict_conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/vardictjava/vcfs/{vardictchrm}/log/{sample}.{alnr}.vardictjava.{vardictchrm}.somatic.sort.vcf.gz.log",
    resources:
        vcpu=4,
        threads=4,
        partition=config['vardictjava']['partition_other'],
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


rule vardictjava_concat_index_chunks:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcfs=lambda wildcards: expand(
            MDIR + "{sample}/align/{alnr}/snv/vardictjava/vcfs/{vardictchrm}/{sample}.{alnr}.vardictjava.{vardictchrm}.somatic.sort.vcf.gz",
            sample=wildcards.sample,
            alnr=wildcards.alnr,
            vardictchrm=VARDICT_CHRMS,
        ),
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/vardictjava/{sample}.{alnr}.vardictjava.somatic.sort.vcf.gz",
        vcfgztbi=MDIR + "{sample}/align/{alnr}/snv/vardictjava/{sample}.{alnr}.vardictjava.somatic.sort.vcf.gz.tbi",
    threads: 4,
    resources:
        vcpu=4,
        threads=4,
        partition=config['vardictjava']['partition'],
        mem_mb=config['vardictjava']['mem_mb'],
    conda:
        config['vardictjava']['vardict_conda'],
    log:
        MDIR + "{sample}/align/{alnr}/snv/vardictjava/log/{sample}.{alnr}.vardictjava.somatic.merge.log",
    params:
        cluster_sample=ret_sample,
    shell:
        """
        bcftools concat -a -d all --threads {threads} -O z -o {output.vcfgz}.tmp {input.vcfs} >> {log} 2>&1;
        oldname=$(bcftools query -l {output.vcfgz}.tmp | head -n1) >> {log} 2>&1;
        echo -e "${oldname}\t{params.cluster_sample}" > {output.vcfgz}.rename.txt;
        bcftools reheader -s {output.vcfgz}.rename.txt -o {output.vcfgz} {output.vcfgz}.tmp >> {log} 2>&1;
        bcftools index -f -t --threads {threads} {output.vcfgz} >> {log} 2>&1;
        rm -f {output.vcfgz}.tmp {output.vcfgz}.rename.txt;
        """


rule produce_vardictjava_vcf:  # Target: produce VarDictJava
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcftb=expand(
            MDIR + "{sample}/align/{alnr}/snv/vardictjava/{sample}.{alnr}.vardictjava.somatic.sort.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        vcftbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/vardictjava/{sample}.{alnr}.vardictjava.somatic.sort.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
    output:
        "gatheredall.vardictjava",
    threads: 4
    priority: 48
    log:
        "gatheredall.vardictjava.log",
    params:
        cluster_sample=ret_sample,
    conda:
        config['vardictjava']['vardict_conda']
    resources:
        vcpu=4,
        threads=4,
        partition=config['vardictjava']['partition'],
        mem_mb=config['vardictjava']['mem_mb'],
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
        """


localrules:
    prep_vardict_chunkdirs,


rule prep_vardict_chunkdirs:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        b=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        i=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/snv/vardictjava/vcfs/{vardictchrm}/{{sample}}.ready",
            vardictchrm=VARDICT_CHRMS,
        ),
    threads: 1
    params:
        cluster_sample=ret_sample,
    log:
        MDIR + "{sample}/align/{alnr}/snv/vardictjava/log/{sample}.{alnr}.chunkdirs.log",
    shell:
        """
        ( echo {output} ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
