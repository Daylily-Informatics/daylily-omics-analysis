import sys
import os

##### varscan2
# ---------------------------


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
        ready=MDIR + "{sample}/align/{alnr}/snv/varscan2/vcfs/{varscan2chrm}/{sample}.ready",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/snv/varscan2/vcfs/{varscan2chrm}/{sample}.{alnr}.varscan2.{varscan2chrm}.somatic.vcf",
    log:
        MDIR + "{sample}/align/{alnr}/snv/varscan2/log/{sample}.{alnr}.varscan2.{varscan2chrm}.somatic.log",
    threads: config['varscan2']['threads']
    container:
        config['varscan2']['container']
    conda:
        config['varscan2']['conda']
    priority: 45
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.varscan2.{varscan2chrm}.bench.tsv",
            0 if 'bench_repeat' not in config.get('varscan2', {}) else config['varscan2']['bench_repeat'],
        )
    resources:
        vcpu=config['varscan2']['threads'],
        threads=config['varscan2']['threads'],
        partition=config['varscan2']['partition'],
        mem_mb=config['varscan2']['mem_mb'],
    params:
        cluster_sample=ret_sample,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        vchrm=get_varscan2_chrm_day,
        cpre="" if "b37" == config['genome_build'] else "chr",
        mito_code="MT" if "b37" == config['genome_build'] else "M",
        mpileup_opts=config['varscan2'].get('mpileup_opts', "-q 1 -Q 20 --count-orphans --max-depth 10000"),
        somatic_opts=config['varscan2'].get('somatic_opts', "--min-coverage-normal 8 --min-coverage-tumor 6 --min-var-freq 0.05 --p-value 0.05"),
        java_opts=config['varscan2'].get('java_opts', ""),
        tmp_root=config['varscan2'].get('tmp_root', '/dev/shm'),
    shell:
        r"""
        set -euo pipefail
        ulimit -n 65536 || true

        vchr=$(echo {params.cpre}{params.vchrm} | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/')
        vchr=${{vchr%:}}

        IFS=':' read -r vcontig vstart vend <<< "$vchr"
        if [ -z "${{vend:-}}" ]; then
            vstart=0
            vend=$(awk -v c="$vcontig" '$1==c{{print $2; exit}}' {input.ref_fai})
            region="$vcontig"
        else
            region="$vcontig:$vstart-$vend"
        fi

        if [ ! -s {input.ref_fai} ]; then
            samtools faidx {input.ref_fa} >> {log} 2>&1
        fi

        timestamp=$(date +%Y%m%d%H%M%S)_$(head -c 12 /dev/urandom | tr -dc 'a-zA-Z0-9')
        export TMPDIR={params.tmp_root}/varscan2_tmp_$timestamp
        mkdir -p "$TMPDIR"
        trap 'rm -rf "$TMPDIR" || true' EXIT

        pileup="$TMPDIR/{wildcards.sample}.{wildcards.alnr}.varscan2.{wildcards.varscan2chrm}.mpileup"
        prefix="$TMPDIR/{wildcards.sample}.{wildcards.alnr}.varscan2.{wildcards.varscan2chrm}"
        combined="$TMPDIR/{wildcards.sample}.{wildcards.alnr}.varscan2.{wildcards.varscan2chrm}.somatic.vcf"

        samtools mpileup \
            -@ {threads} \
            -f {params.huref} \
            {params.mpileup_opts} \
            -r "$region" \
            {input.normal_cram} \
            {input.tumor_cram} \
            > "$pileup" 2>> {log}

        export JAVA_TOOL_OPTIONS="{params.java_opts}"
        varscan somatic \
            "$pileup" "$prefix" \
            --mpileup 1 \
            --output-vcf 1 \
            {params.somatic_opts} >> {log} 2>&1

        snp_vcf="$prefix.snp.vcf"
        indel_vcf="$prefix.indel.vcf"

        mkdir -p "$(dirname {output.vcf})"
        : > "$combined"

        header_src=""
        if [ -s "$snp_vcf" ]; then
            header_src="$snp_vcf"
        elif [ -s "$indel_vcf" ]; then
            header_src="$indel_vcf"
        elif [ -f "$snp_vcf" ]; then
            header_src="$snp_vcf"
        elif [ -f "$indel_vcf" ]; then
            header_src="$indel_vcf"
        fi

        if [ -n "$header_src" ]; then
            grep '^#' "$header_src" > "$combined"
        else
            echo "##fileformat=VCFv4.2" > "$combined"
            echo -e "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t{wildcards.sample}" >> "$combined"
        fi

        if [ -s "$snp_vcf" ]; then
            grep -v '^#' "$snp_vcf" >> "$combined"
        fi
        if [ -s "$indel_vcf" ]; then
            grep -v '^#' "$indel_vcf" >> "$combined"
        fi

        cp -f "$combined" {output.vcf}
        """


rule varscan2_sort_index_chunk_vcf:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcf=MDIR + "{sample}/align/{alnr}/snv/varscan2/vcfs/{varscan2chrm}/{sample}.{alnr}.varscan2.{varscan2chrm}.somatic.vcf",
    priority: 46
    output:
        vcfsort=MDIR + "{sample}/align/{alnr}/snv/varscan2/vcfs/{varscan2chrm}/{sample}.{alnr}.varscan2.{varscan2chrm}.somatic.sort.vcf",
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/varscan2/vcfs/{varscan2chrm}/{sample}.{alnr}.varscan2.{varscan2chrm}.somatic.sort.vcf.gz",
        vcftbi=MDIR + "{sample}/align/{alnr}/snv/varscan2/vcfs/{varscan2chrm}/{sample}.{alnr}.varscan2.{varscan2chrm}.somatic.sort.vcf.gz.tbi",
    conda:
        config['varscan2']['conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/varscan2/vcfs/{varscan2chrm}/log/{sample}.{alnr}.varscan2.{varscan2chrm}.somatic.sort.vcf.gz.log",
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
            MDIR + "{sample}/align/{alnr}/snv/varscan2/vcfs/{varscan2chrm}/{sample}.{alnr}.varscan2.{varscan2chrm}.somatic.sort.vcf.gz",
            sample=wildcards.sample,
            alnr=wildcards.alnr,
            varscan2chrm=VARSCAN2_CHRMS,
        ),
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/varscan2/{sample}.{alnr}.varscan2.somatic.sort.vcf.gz",
        vcfgztbi=MDIR + "{sample}/align/{alnr}/snv/varscan2/{sample}.{alnr}.varscan2.somatic.sort.vcf.gz.tbi",
    threads: 4
    conda:
        config['varscan2']['conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/varscan2/log/{sample}.{alnr}.varscan2.somatic.merge.log",
    params:
        cluster_sample=ret_sample,
    shell:
        """
        bcftools concat -a -O z -o {output.vcfgz} {input.vcfs} >> {log} 2>&1;
        bcftools index -f -t {output.vcfgz} >> {log} 2>&1;
        """


rule produce_varscan2_vcf:  # Target: produce varscan2 somatic calls
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcftb=expand(
            MDIR + "{sample}/align/{alnr}/snv/varscan2/{sample}.{alnr}.varscan2.somatic.sort.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        vcftbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/varscan2/{sample}.{alnr}.varscan2.somatic.sort.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
    output:
        "gatheredall.varscan2",
    threads: 4
    priority: 48
    log:
        "gatheredall.varscan2.log",
    conda:
        config['varscan2']['conda']
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
    prep_varscan2_chunkdirs,


rule prep_varscan2_chunkdirs:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        b=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        i=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/snv/varscan2/vcfs/{varscan2chrm}/{{sample}}.ready",
            varscan2chrm=VARSCAN2_CHRMS,
        ),
    threads: 1
    params:
        cluster_sample=ret_sample,
    log:
        MDIR + "{sample}/align/{alnr}/snv/varscan2/log/{sample}.{alnr}.chunkdirs.log",
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
