import sys
import os

##### AIVariant
# ---------------------------

rule aiv:
    input:
        tumor_cram=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        tumor_crai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
        normal_cram=get_aiv_normal_cram,
        normal_crai=get_aiv_normal_crai,
        d=MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/{sample}.ready",
    output:
        vcf=temp(MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.snv.vcf"),
    log:
        MDIR + "{sample}/align/{alnr}/snv/aiv/log/{sample}.{alnr}.aiv.{aivchrm}.snv.log",
    threads: config['aiv']['threads']
    container:
        config['aiv']['container']
    priority: 45
    resources:
        vcpu=config['aiv']['threads'],
        threads=config['aiv']['threads'],
        partition=config['aiv']['partition'],
        mem_mb=config['aiv']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        dchrm=get_aivchrm_day,
        normal_sample=get_normal_sample,
        cluster_sample=ret_sample,
    shell:
        """
        touch {log};
        aivariant --tumor {input.tumor_cram} --normal {input.normal_cram} --ref {params.huref} --region {params.dchrm} --out {output.vcf} >> {log} 2>&1;
        """


rule aiv_sort_index_chunk_vcf:
    input:
        vcf=MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.snv.vcf",
    priority: 46
    output:
        vcfsort=MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.snv.sort.vcf",
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.snv.sort.vcf.gz",
        vcftbi=MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.snv.sort.vcf.gz.tbi",
    conda:
        config['aiv']['aiv_conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/log/{sample}.{alnr}.aiv.{aivchrm}.snv.sort.vcf.gz.log",
    resources:
        vcpu=4,
        threads=4,
        partition=config['aiv']['partition'],
    params:
        cluster_sample=ret_sample,
    threads: 4
    shell:
        """
        bedtools sort -header -i {input.vcf} > {output.vcfsort} 2>> {log};
        bgzip {output.vcfsort} >> {log} 2>&1;
        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1;
        """


rule aiv_concat_fofn:
    input:
        chunk_tbi=sorted(
            expand(
                MDIR + "{{sample}}/align/{{alnr}}/snv/aiv/vcfs/{aivc}/{{sample}}.{{alnr}}.aiv.{aivc}.snv.sort.vcf.gz.tbi",
                aivc=AIV_CHRMS,
            ),
            key=lambda x: float(
                str(x.replace("~", ".").replace(":", ".")).split("vcfs/")[1].split("/")[0].split("-")[0]
            ),
        ),
    priority: 44
    output:
        fin_fofn=MDIR + "{sample}/align/{alnr}/snv/aiv/{sample}.{alnr}.aiv.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR + "{sample}/align/{alnr}/snv/aiv/{sample}.{alnr}.aiv.snv.concat.vcf.gz.fofn.tmp",
    threads: 2
    resources:
        vcpu=2,
        threads=2,
        partition="i192,i192mem",
    params:
        fn_stub="{sample}.{alnr}.aiv.",
        cluster_sample=ret_sample,
    conda:
        config['aiv']['aiv_conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/aiv/log/{sample}.{alnr}.aiv.concat.fofn.log",
    shell:
        """
        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\.tbi$//g');
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.aiv. {output.fin_fofn}) >> {log} 2>&1;
        """


rule aiv_concat_index_chunks:
    input:
        fofn=MDIR + "{sample}/align/{alnr}/snv/aiv/{sample}.{alnr}.aiv.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR + "{sample}/align/{alnr}/snv/aiv/{sample}.{alnr}.aiv.snv.concat.vcf.gz.fofn.tmp",
    output:
        vcfgz=touch(MDIR + "{sample}/align/{alnr}/snv/aiv/{sample}.{alnr}.aiv.snv.sort.vcf.gz"),
        vcfgztemp=temp(MDIR + "{sample}/align/{alnr}/snv/aiv/{sample}.{alnr}.aiv.snv.sort.temp.vcf.gz"),
        vcfgztbi=touch(MDIR + "{sample}/align/{alnr}/snv/aiv/{sample}.{alnr}.aiv.snv.sort.vcf.gz.tbi"),
    threads: 4
    resources:
        vcpu=4,
        threads=4,
        partition=config['aiv']['partition'],
    conda:
        config['aiv']['aiv_conda']
    params:
        cluster_sample=ret_sample,
    log:
        MDIR + "{sample}/align/{alnr}/snv/aiv/log/{sample}.{alnr}.aiv.snv.merge.log",
    shell:
        """
        touch {log};
        bcftools concat -a -d all --threads {threads} -f {input.fofn} -O z -o {output.vcfgztemp} >> {log} 2>&1;
        bcftools reheader -s <(echo -e "$(bcftools query -l {output.vcfgztemp} | head -n1)\t{wildcards.sample}") -o {output.vcfgz} {output.vcfgztemp} >> {log} 2>&1;
        bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;
        rm -rf $(dirname {output.vcfgz})/vcfs >> {log} 2>&1;
        """


localrules:
    prep_aiv_chunkdirs,


rule prep_aiv_chunkdirs:
    input:
        b=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        i=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/snv/aiv/vcfs/{aivc}/{{sample}}.ready",
            aivc=AIV_CHRMS,
        ),
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/snv/aiv/log/{sample}.{alnr}.chunkdirs.log",
    shell:
        """
        ( echo {output};
        mkdir -p $(dirname {output});
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """


rule produce_aiv_vcf:
    input:
        vcftb=expand(
            MDIR + "{sample}/align/{alnr}/snv/aiv/{sample}.{alnr}.aiv.snv.sort.vcf.gz",
            sample=TN_TUMORS,
            alnr=ALIGNERS,
        ),
        vcftbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/aiv/{sample}.{alnr}.aiv.snv.sort.vcf.gz.tbi",
            sample=TN_TUMORS,
            alnr=ALIGNERS,
        ),
    output:
        "logs/aiv_gathered.done",
    shell:
        "touch {output};"
