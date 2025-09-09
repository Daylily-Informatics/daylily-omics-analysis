import sys
import os

##### VarScan2
# ---------------------------


def get_vscn_chrm(wildcards):
    pchr = ""  # prefix handled already
    ret_str = ""
    sl = wildcards.vscnchrm.replace('chr', '').split("-")
    sl2 = wildcards.vscnchrm.replace('chr', '').split("~")

    if len(sl2) == 2:
        ret_str = pchr + wildcards.vscnchrm
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
            "varscan2 chunks can only be one contiguous range per chunk: e.g., 1-4 with the non numerical chromosomes assigned 23=X, 24=Y, 25=MT"
        )

    return ret_mod_chrm(ret_str)


rule varscan2:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_cram=get_somcall_tumor_cram,
        tumor_crai=get_somcall_tumor_crai,
        normal_cram=get_somcall_normal_cram,
        normal_crai=get_somcall_normal_crai,
        ref_fa=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ref_fai=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
        d=MDIR + "{sample}/align/{alnr}/snv/vscn/vcfs/{vscnchrm}/{sample}.ready",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/snv/vscn/vcfs/{vscnchrm}/{sample}.{alnr}.vscn.{vscnchrm}.snv.vcf",
    log:
        MDIR + "{sample}/align/{alnr}/snv/vscn/log/{sample}.{alnr}.vscn.{vscnchrm}.snv.log",
    threads: config['varscan2']['threads']
    container:
        config['varscan2']['container']
    priority: 45
    resources:
        vcpu=config['varscan2']['threads'],
        threads=config['varscan2']['threads'],
        partition=config['varscan2']['partition'],
        mem_mb=config['varscan2']['mem_mb'],
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.vscn.{vscnchrm}.bench.tsv",
            0 if 'bench_repeat' not in config['varscan2'] else config['varscan2']['bench_repeat'],
        )
    params:
        vchrm=get_vscn_chrm,
        cluster_sample=ret_sample,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cpre="" if "b37" == config['genome_build'] else "chr",
        mito_code="MT" if "b37" == config['genome_build'] else "M",
    shell:
        r"""
        set -euo pipefail
        ulimit -n 65536 || true

        vchr=$(echo {params.cpre}{params.vchrm} | sed 's/~/\\:/g' | sed 's/23\\:/X\\:/' | sed 's/24\\:/Y\\:/' | sed 's/25\\:/{params.mito_code}\\:/')
        vchr=${vchr%:}
        IFS=':' read -r vcontig vstart vend <<< "$vchr"
        if [ -z "${vend:-}" ]; then
            vstart=0
            vend=$(awk -v c="$vcontig" '$1==c{print $2; exit}' {params.huref}.fai)
        fi
        region="$vcontig:$vstart-$vend"

        mkdir -p "$(dirname {output.vcf})"
        outbase="$(dirname {output.vcf})/{wildcards.sample}.{wildcards.alnr}.vscn.{wildcards.vscnchrm}"

        samtools mpileup -f {params.huref} -q 1 -B -d 1000000 -r $region {input.normal_cram} {input.tumor_cram} \
            | varscan somatic --mpileup 1 --output-vcf 1 /dev/stdin $outbase >> {log} 2>&1

        bcftools concat -a -O v ${outbase}.snp.vcf ${outbase}.indel.vcf > {output.vcf} 2>> {log}
        rm -f ${outbase}.snp.vcf ${outbase}.indel.vcf
        """


rule varscan2_sort_index_chunk_vcf:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcf=MDIR + "{sample}/align/{alnr}/snv/vscn/vcfs/{vscnchrm}/{sample}.{alnr}.vscn.{vscnchrm}.snv.vcf",
    priority: 46
    output:
        vcfsort=MDIR + "{sample}/align/{alnr}/snv/vscn/vcfs/{vscnchrm}/{sample}.{alnr}.vscn.{vscnchrm}.snv.sort.vcf",
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/vscn/vcfs/{vscnchrm}/{sample}.{alnr}.vscn.{vscnchrm}.snv.sort.vcf.gz",
        vcftbi=MDIR + "{sample}/align/{alnr}/snv/vscn/vcfs/{vscnchrm}/{sample}.{alnr}.vscn.{vscnchrm}.snv.sort.vcf.gz.tbi",
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/snv/vscn/vcfs/{vscnchrm}/log/{sample}.{alnr}.vscn.{vscnchrm}.snv.sort.vcf.gz.log",
    resources:
        vcpu=4,
        threads=4,
        partition=config['varscan2'].get('partition_other', config['varscan2']['partition']),
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


rule varscan2_concat_index_chunks:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcfs=lambda wildcards: expand(
            MDIR + "{sample}/align/{alnr}/snv/vscn/vcfs/{vscnchrm}/{sample}.{alnr}.vscn.{vscnchrm}.snv.sort.vcf.gz",
            sample=wildcards.sample,
            alnr=wildcards.alnr,
            vscnchrm=VARSCAN_CHRMS,
        ),
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/vscn/{sample}.{alnr}.vscn.snv.sort.vcf.gz",
        vcfgztbi=MDIR + "{sample}/align/{alnr}/snv/vscn/{sample}.{alnr}.vscn.snv.sort.vcf.gz.tbi",
    threads: 4
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/snv/vscn/log/{sample}.{alnr}.vscn.snv.merge.log",
    params:
        cluster_sample=ret_sample,
    resources:
        vcpu=4,
        threads=4,
        partition=config['varscan2']['partition'],
        mem_mb=config['varscan2']['mem_mb'],
    shell:
        """
        bcftools concat -a -O z -o {output.vcfgz} {input.vcfs} >> {log} 2>&1;
        bcftools index -f -t {output.vcfgz} >> {log} 2>&1;
        """


rule produce_varscan2_vcf:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcftb=expand(
            MDIR + "{sample}/align/{alnr}/snv/vscn/{sample}.{alnr}.vscn.snv.sort.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        vcftbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/vscn/{sample}.{alnr}.vscn.snv.sort.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
    output:
        "gatheredall.vscn",
    threads: 4
    priority: 48
    log:
        "gatheredall.vscn.log",
    conda:
        "../envs/vanilla_v0.1.yaml"
    params:
        cluster_sample=ret_sample,
    resources:
        vcpu=4,
        threads=4,
        partition=config['varscan2']['partition'],
        mem_mb=config['varscan2']['mem_mb'],
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


localrules:
    prep_vscn_chunkdirs,


rule prep_vscn_chunkdirs:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        b=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        i=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/snv/vscn/vcfs/{vscnchrm}/{{sample}}.ready",
            vscnchrm=VARSCAN_CHRMS,
        ),
    threads: 1
    params:
        cluster_sample=ret_sample,
    log:
        MDIR + "{sample}/align/{alnr}/snv/vscn/log/{sample}.{alnr}.chunkdirs.log",
    shell:
        """
        ( echo {output} ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
