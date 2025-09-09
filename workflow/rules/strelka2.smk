import sys
import os

##### strelka2
# ---------------------------

rule strelka2_germline_chunkdirs:
    input:
        b=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        i=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/snv/strelka2/vcfs/{strelkachrm}/{{sample}}.ready",
            strelkachrm=STRELKA2_CHRMS,
        ),
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/snv/strelka2/log/{sample}.{alnr}.chunkdirs.log",
    shell:
        """
        ( echo {output}; mkdir -p $(dirname {output}); touch {output}; ls {output}; ) > {log} 2>&1;
        """


rule strelka2_germline:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
        ref_fa=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        d=MDIR + "{sample}/align/{alnr}/snv/strelka2/vcfs/{strelkachrm}/{sample}.ready",
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/strelka2/vcfs/{strelkachrm}/{sample}.{alnr}.strelka2.{strelkachrm}.germline.vcf.gz",
        vcftbi=MDIR + "{sample}/align/{alnr}/snv/strelka2/vcfs/{strelkachrm}/{sample}.{alnr}.strelka2.{strelkachrm}.germline.vcf.gz.tbi",
    log:
        MDIR + "{sample}/align/{alnr}/snv/strelka2/vcfs/{strelkachrm}/log/{sample}.{alnr}.strelka2.{strelkachrm}.germline.log",
    threads: config['strelka2']['threads']
    container:
        config['strelka2']['container']
    resources:
        vcpu=config['strelka2']['threads'],
        threads=config['strelka2']['threads'],
        partition=config['strelka2']['partition'],
        mem_mb=config['strelka2']['mem_mb'],
    params:
        run_dir=MDIR + "{sample}/align/{alnr}/snv/strelka2/work/{sample}.germline.{strelkachrm}",
        schrm=get_strelka_chrm_day,
        cluster_sample=ret_sample,
        cpre="" if "b37" == config['genome_build'] else "chr",
        mito_code="MT" if "b37" == config['genome_build'] else "M",
    shell:
        r"""
        set -euo pipefail
        mkdir -p {params.run_dir}

        vchr=$(echo {params.cpre}{params.schrm} | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/' )
        vchr=${vchr%:}
        IFS=':' read -r vcontig vstart vend <<< "$vchr"
        if [ -z "${vend:-}" ]; then
            vstart=0
            vend=$(awk -v c="$vcontig" '$1==c{print $2; exit}' {input.ref_fa}.fai)
        fi
        echo -e "$vcontig\t$vstart\t$vend" > {params.run_dir}/region.bed

        configureStrelkaGermlineWorkflow.py \
            --bam {input.cram} \
            --referenceFasta {input.ref_fa} \
            --callRegions {params.run_dir}/region.bed \
            --runDir {params.run_dir} >> {log} 2>&1
        {params.run_dir}/runWorkflow.py -m local -j {threads} >> {log} 2>&1
        cp {params.run_dir}/results/variants/variants.vcf.gz {output.vcfgz}
        cp {params.run_dir}/results/variants/variants.vcf.gz.tbi {output.vcftbi}
        """


rule strelka2_germline_concat:
    input:
        vcfs=lambda wildcards: expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/vcfs/{strelkachrm}/{sample}.{alnr}.strelka2.{strelkachrm}.germline.vcf.gz",
            sample=wildcards.sample,
            alnr=wildcards.alnr,
            strelkachrm=STRELKA2_CHRMS,
        ),
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.germline.vcf.gz",
        vcfgztbi=MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.germline.vcf.gz.tbi",
    threads: 4
    resources:
        vcpu=4,
        threads=4,
        partition=config['strelka2']['partition'],
        mem_mb=config['strelka2']['mem_mb'],
    conda: "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/snv/strelka2/log/{sample}.{alnr}.strelka2.germline.merge.log",
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


rule strelka2_somatic_chunkdirs:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        b=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        i=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/snv/strelka2/vcfs/{strelkachrm}/{{sample}}.ready",
            strelkachrm=STRELKA2_CHRMS,
        ),
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/snv/strelka2/log/{sample}.{alnr}.somatic.chunkdirs.log",
    shell:
        """
        ( echo {output}; mkdir -p $(dirname {output}); touch {output}; ls {output}; ) > {log} 2>&1;
        """


rule strelka2_somatic:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_cram=get_somcall_tumor_cram,
        tumor_crai=get_somcall_tumor_crai,
        normal_cram=get_somcall_normal_cram,
        normal_crai=get_somcall_normal_crai,
        ref_fa=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        d=MDIR + "{sample}/align/{alnr}/snv/strelka2/vcfs/{strelkachrm}/{sample}.ready",
    output:
        snv=MDIR + "{sample}/align/{alnr}/snv/strelka2/vcfs/{strelkachrm}/{sample}.{alnr}.strelka2.{strelkachrm}.somatic.snvs.vcf.gz",
        snvtbi=MDIR + "{sample}/align/{alnr}/snv/strelka2/vcfs/{strelkachrm}/{sample}.{alnr}.strelka2.{strelkachrm}.somatic.snvs.vcf.gz.tbi",
        indel=MDIR + "{sample}/align/{alnr}/snv/strelka2/vcfs/{strelkachrm}/{sample}.{alnr}.strelka2.{strelkachrm}.somatic.indels.vcf.gz",
        indeltbi=MDIR + "{sample}/align/{alnr}/snv/strelka2/vcfs/{strelkachrm}/{sample}.{alnr}.strelka2.{strelkachrm}.somatic.indels.vcf.gz.tbi",
    log:
        MDIR + "{sample}/align/{alnr}/snv/strelka2/vcfs/{strelkachrm}/log/{sample}.{alnr}.strelka2.{strelkachrm}.somatic.log",
    threads: config['strelka2']['threads']
    container:
        config['strelka2']['container']
    resources:
        vcpu=config['strelka2']['threads'],
        threads=config['strelka2']['threads'],
        partition=config['strelka2']['partition'],
        mem_mb=config['strelka2']['mem_mb'],
    params:
        run_dir=MDIR + "{sample}/align/{alnr}/snv/strelka2/work/{sample}.somatic.{strelkachrm}",
        schrm=get_strelka_chrm_day,
        cluster_sample=ret_sample,
        cpre="" if "b37" == config['genome_build'] else "chr",
        mito_code="MT" if "b37" == config['genome_build'] else "M",
    shell:
        r"""
        set -euo pipefail
        mkdir -p {params.run_dir}

        vchr=$(echo {params.cpre}{params.schrm} | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/' )
        vchr=${vchr%:}
        IFS=':' read -r vcontig vstart vend <<< "$vchr"
        if [ -z "${vend:-}" ]; then
            vstart=0
            vend=$(awk -v c="$vcontig" '$1==c{print $2; exit}' {input.ref_fa}.fai)
        fi
        echo -e "$vcontig\t$vstart\t$vend" > {params.run_dir}/region.bed

        configureStrelkaSomaticWorkflow.py \
            --tumorBam {input.tumor_cram} \
            --normalBam {input.normal_cram} \
            --referenceFasta {input.ref_fa} \
            --callRegions {params.run_dir}/region.bed \
            --runDir {params.run_dir} >> {log} 2>&1
        {params.run_dir}/runWorkflow.py -m local -j {threads} >> {log} 2>&1
        cp {params.run_dir}/results/variants/somatic.snvs.vcf.gz {output.snv}
        cp {params.run_dir}/results/variants/somatic.snvs.vcf.gz.tbi {output.snvtbi}
        cp {params.run_dir}/results/variants/somatic.indels.vcf.gz {output.indel}
        cp {params.run_dir}/results/variants/somatic.indels.vcf.gz.tbi {output.indeltbi}
        """


rule strelka2_somatic_concat:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        snv_vcfs=lambda wildcards: expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/vcfs/{strelkachrm}/{sample}.{alnr}.strelka2.{strelkachrm}.somatic.snvs.vcf.gz",
            sample=wildcards.sample,
            alnr=wildcards.alnr,
            strelkachrm=STRELKA2_CHRMS,
        ),
        indel_vcfs=lambda wildcards: expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/vcfs/{strelkachrm}/{sample}.{alnr}.strelka2.{strelkachrm}.somatic.indels.vcf.gz",
            sample=wildcards.sample,
            alnr=wildcards.alnr,
            strelkachrm=STRELKA2_CHRMS,
        ),
    output:
        snv=MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.snvs.vcf.gz",
        snvtbi=MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.snvs.vcf.gz.tbi",
        indel=MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.indels.vcf.gz",
        indeltbi=MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.indels.vcf.gz.tbi",
    threads: 4
    resources:
        vcpu=4,
        threads=4,
        partition=config['strelka2']['partition'],
        mem_mb=config['strelka2']['mem_mb'],
    conda: "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/snv/strelka2/log/{sample}.{alnr}.strelka2.somatic.merge.log",
    params:
        cluster_sample=ret_sample,
    shell:
        """
        bcftools concat -a -d all --threads {threads} -O z -o {output.snv}.tmp {input.snv_vcfs} >> {log} 2>&1;
        oldname=$(bcftools query -l {output.snv}.tmp | head -n1) >> {log} 2>&1;
        echo -e "${oldname}\t{params.cluster_sample}" > {output.snv}.rename.txt;
        bcftools reheader -s {output.snv}.rename.txt -o {output.snv} {output.snv}.tmp >> {log} 2>&1;
        bcftools index -f -t --threads {threads} {output.snv} >> {log} 2>&1;
        rm -f {output.snv}.tmp {output.snv}.rename.txt;

        bcftools concat -a -d all --threads {threads} -O z -o {output.indel}.tmp {input.indel_vcfs} >> {log} 2>&1;
        oldname=$(bcftools query -l {output.indel}.tmp | head -n1) >> {log} 2>&1;
        echo -e "${oldname}\t{params.cluster_sample}" > {output.indel}.rename.txt;
        bcftools reheader -s {output.indel}.rename.txt -o {output.indel} {output.indel}.tmp >> {log} 2>&1;
        bcftools index -f -t --threads {threads} {output.indel} >> {log} 2>&1;
        rm -f {output.indel}.tmp {output.indel}.rename.txt;
        """

rule produce_strelka2_germline_vcf:
    input:
        vcftb=expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.germline.vcf.gz",
            sample=SSAMPS,
            alnr=ALIGNERS,
        ),
        vcftbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.germline.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS,
        ),
    output:
        "gatheredall.strelka2.germline",
    threads: 4
    log:
        "gatheredall.strelka2.germline.log",
    params:
        cluster_sample=ret_sample,
    resources:
        vcpu=4,
        threads=4,
        partition=config['strelka2']['partition'],
        mem_mb=config['strelka2']['mem_mb'],


rule produce_strelka2_somatic_vcf:
    input:
        snv=expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.snvs.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        snvtbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.snvs.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        indel=expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.indels.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        indeltbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/strelka2/{sample}.{alnr}.strelka2.somatic.indels.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
    output:
        "gatheredall.strelka2.somatic",
    threads: 4
    log:
        "gatheredall.strelka2.somatic.log",
    params:
        cluster_sample=ret_sample,
    resources:
        vcpu=4,
        threads=4,
        partition=config['strelka2']['partition'],
        mem_mb=config['strelka2']['mem_mb'],
