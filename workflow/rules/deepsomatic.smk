import sys
import os

##### deepsomatic
# ---------------------------


def get_dvs_normal_cram(wildcards):
    try:
        nsamp = TN_PAIRS[wildcards.sample]
    except KeyError:
        raise ValueError(f"No matched normal sample for {wildcards.sample}")
    return MDIR + f"{nsamp}/align/{wildcards.alnr}/{nsamp}.{wildcards.alnr}.cram"

def get_dvs_normal_crai(wildcards):
    try:
        nsamp = TN_PAIRS[wildcards.sample]
    except KeyError:
        raise ValueError(f"No matched normal sample for {wildcards.sample}")
    return MDIR + f"{nsamp}/align/{wildcards.alnr}/{nsamp}.{wildcards.alnr}.cram.crai"

def get_dvs_tumor_cram(wildcards):
    return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.{wildcards.alnr}.cram"

def get_dvs_tumor_crai(wildcards):
    return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.{wildcards.alnr}.cram.crai"


rule dvsom:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_cram=get_somcall_tumor_cram,
        tumor_crai=get_somcall_tumor_crai,
        normal_cram=get_somcall_normal_cram,
        normal_crai=get_somcall_normal_crai,      
        ref_fa=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ref_fai=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
        d=MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/{sample}.ready",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/{sample}.{alnr}.dvsom.{dvsomchrm}.snv.vcf",
    log:
        MDIR + "{sample}/align/{alnr}/snv/dvsom/log/{sample}.{alnr}.dvsom.{dvsomchrm}.snv.log",
    threads: config['deepsomatic']['threads']
    container:
        config['deepsomatic']['container']
    priority: 45
    resources:
        vcpu=config['deepsomatic']['threads'],
        threads=config['deepsomatic']['threads'],
        partition=config['deepsomatic']['partition'],
        mem_mb=config['deepsomatic']['mem_mb'],
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.dvsom.{dvsomchrm}.bench.tsv",
            0 if "bench_repeat" not in config["deepsomatic"] else config["deepsomatic"]["bench_repeat"],
        )
    params:
        dchrm=get_dvsom_chrm_day,
        cluster_sample=ret_sample,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mem_mb=config['deepsomatic']['mem_mb'],
        numa=config['deepsomatic']['numa'],
        cpre="" if "b37" == config['genome_build'] else "chr",
        deep_threads=config['deepsomatic']['deep_threads'],
        mito_code="MT" if "b37" == config['genome_build'] else "M",
        deep_model=get_deep_model,
    shell:
        r"""
        set -euo pipefail
        ulimit -n 65536 || true

        dchr=$(echo {params.cpre}{params.dchrm} | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/')
        dchr=${{dchr%:}}

        IFS=':' read -r dcontig dstart dend <<< "$dchr"
        if [ -z "${{dend:-}}" ]; then
            dstart=0
            dend=$(awk -v c="$dcontig" '$1==c{{print $2; exit}}' {params.huref}.fai)
        fi
        region="$dcontig:$dstart-$dend"

        timestamp=$(date +%Y%m%d%H%M%S)_$(head -c 12 /dev/urandom | tr -dc 'a-zA-Z0-9')

        export TMPDIR=/dev/shm/deepsomatic_tmp_$timestamp
        mkdir -p "$TMPDIR"
        export APPTAINER_HOME="$TMPDIR"
        trap 'rm -rf "$TMPDIR" || true' EXIT

        out_vcf="$TMPDIR/{wildcards.sample}.{wildcards.alnr}.dvsom.{wildcards.dvsomchrm}.snv.vcf"
        mkdir -p "$(dirname {output.vcf})"

        {params.numa} run_deepsomatic \
            --model_type={params.deep_model} --ref={params.huref} \
            --reads_tumor={input.tumor_cram} \
            --reads_normal={input.normal_cram} \
            --regions "$region" \
            --output_vcf "$out_vcf" \
            --num_shards={params.deep_threads} \
            --logging_dir=$(dirname {log}) \
            --dry_run=false >> {log} 2>&1

        cp -f "$out_vcf" {output.vcf}
        """


rule dvsom_sort_index_chunk_vcf:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcf=MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/{sample}.{alnr}.dvsom.{dvsomchrm}.snv.vcf",
    priority: 46
    output:
        vcfsort=MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/{sample}.{alnr}.dvsom.{dvsomchrm}.snv.sort.vcf",
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/{sample}.{alnr}.dvsom.{dvsomchrm}.snv.sort.vcf.gz",
        vcftbi=MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/{sample}.{alnr}.dvsom.{dvsomchrm}.snv.sort.vcf.gz.tbi",
    conda:
        config['deepsomatic']['dvsom_conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/log/{sample}.{alnr}.dvsom.{dvsomchrm}.snv.sort.vcf.gz.log",
    resources:
        vcpu=4,
        threads=4,
        partition=config['deepsomatic']['partition_other'],
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


rule dvsom_concat_index_chunks:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcfs=lambda wildcards: expand(
            MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/{sample}.{alnr}.dvsom.{dvsomchrm}.snv.sort.vcf.gz",
            sample=wildcards.sample,
            alnr=wildcards.alnr,
            dvsomchrm=DVSOM_CHRMS,
        ),
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/dvsom/{sample}.{alnr}.dvsom.snv.sort.vcf.gz",
        vcfgztbi=MDIR + "{sample}/align/{alnr}/snv/dvsom/{sample}.{alnr}.dvsom.snv.sort.vcf.gz.tbi",
    threads: 4,
    conda:
        config['deepsomatic']['dvsom_conda'],
    log:
        MDIR + "{sample}/align/{alnr}/snv/dvsom/log/{sample}.{alnr}.dvsom.snv.merge.log",
    params:
        cluster_sample=ret_sample,
    shell:
        """
        bcftools concat -a -d all --threads {threads} -O z -o {output.vcfgz}.tmp {input.vcfs} >> {log} 2>&1;
        oldname=$(bcftools query -l {output.vcfgz}.tmp | head -n1) >> {log} 2>&1;
        echo -e "${{oldname}}	{params.cluster_sample}" > {output.vcfgz}.rename.txt;
        bcftools reheader -s {output.vcfgz}.rename.txt -o {output.vcfgz} {output.vcfgz}.tmp >> {log} 2>&1;
        bcftools index -f -t --threads {threads} {output.vcfgz} >> {log} 2>&1;
        rm -f {output.vcfgz}.tmp {output.vcfgz}.rename.txt;
        """


rule produce_dvsom_vcf:  # Target: produce deep-somatic
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcftb=expand(
            MDIR + "{sample}/align/{alnr}/snv/dvsom/{sample}.{alnr}.dvsom.snv.sort.vcf.gz",           sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        vcftbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/dvsom/{sample}.{alnr}.dvsom.snv.sort.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS
        ),
    output:
        "gatheredall.dvsom",
    threads: 4
    priority: 48
    log:
        "gatheredall.dvsom.log",
    conda:
        config['deepsomatic']['dvsom_conda']
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
        ls {output}  >> {log} 2>&1;
        """


localrules:
    prep_dvsom_chunkdirs,


rule prep_dvsom_chunkdirs:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        b=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        i=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/snv/dvsom/vcfs/{dvsomchrm}/{{sample}}.ready",
            dvsomchrm=DVSOM_CHRMS,
        ),
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/snv/dvsom/log/{sample}.{alnr}.chunkdirs.log",
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
