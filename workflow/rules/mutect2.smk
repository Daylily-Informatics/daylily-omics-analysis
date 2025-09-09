import sys
import os

##### mutect2
# ---------------------------

rule mutect2_bams:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_cram=get_somcall_tumor_cram,
        tumor_crai=get_somcall_tumor_crai,
        normal_cram=get_somcall_normal_cram,
        normal_crai=get_somcall_normal_crai,
        ref_fa=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ref_fai=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        tumor_bam=temp(MDIR + "{sample}/align/{alnr}/snv/mutect2/tmp/{m2chrm}/{sample}.{alnr}.mutect2.{m2chrm}.tumor.bam"),
        tumor_bai=temp(MDIR + "{sample}/align/{alnr}/snv/mutect2/tmp/{m2chrm}/{sample}.{alnr}.mutect2.{m2chrm}.tumor.bam.bai"),
        normal_bam=temp(MDIR + "{sample}/align/{alnr}/snv/mutect2/tmp/{m2chrm}/{sample}.{alnr}.mutect2.{m2chrm}.normal.bam"),
        normal_bai=temp(MDIR + "{sample}/align/{alnr}/snv/mutect2/tmp/{m2chrm}/{sample}.{alnr}.mutect2.{m2chrm}.normal.bam.bai"),
    log:
        MDIR + "{sample}/align/{alnr}/snv/mutect2/log/{sample}.{alnr}.mutect2.{m2chrm}.bamify.log",
    threads: config['mutect2']['threads']
    conda: "../envs/vanilla_v0.1.yaml"
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cpre="" if "b37" == config['genome_build'] else "chr",
        mito_code="MT" if "b37" == config['genome_build'] else "M",
        chrm=get_mutect2_chrm_day,
        cluster_sample=ret_sample,
    resources:
        vcpu=config['mutect2']['threads'],
        threads=config['mutect2']['threads'],
        partition=config['mutect2']['partition'],
        mem_mb=config['mutect2']['mem_mb'],
    shell:
        r"""
        set -euo pipefail
        ulimit -n 65536 || true
        
        mkdir -p "$(dirname {output.tumor_bam}"

        # Build interval token; map 23→X, 24→Y, 25→{params.mito_code}; strip trailing colon.
        tchr=$(echo {params.cpre}{params.chrm} \
        | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/')
        tchr=${{tchr}}

        IFS=':' read -r tcontig tstart tend <<< "$tchr"

        # Look up contig length early
        contig_len=$(awk -v c="$tcontig" '$1==c{{print $2; exit}}' {input.ref_fai})
        if [ -z "${{contig_len}}" ]; then
          echo "ERROR: Contig '$tcontig' not found in {input.ref_fai}" >&2
          exit 1
        fi

        if [ -z "${{tend}}" ]; then
          # Whole contig
          region="$tcontig"
        else
          # Normalize to 1-based inclusive and clamp to [1, contig_len]
          if [ -z "${{tstart}}" ] || [ "$tstart" -lt 1 ]; then tstart=1; fi
          if [ "$tend" -gt "$contig_len" ]; then tend="$contig_len"; fi
          if [ "$tstart" -gt "$tend" ]; then
            echo "ERROR: Empty/invalid interval after normalization: $tcontig:$tstart-$tend" >&2
            exit 1
          fi
          region="$tcontig:$tstart-$tend"
        fi
        
        # Tumor
        samtools view -@ {threads} -T {input.ref_fa} -b {input.tumor_cram} "$region" \
          | samtools sort -@ {threads} -o {output.tumor_bam} -           >> {log} 2>&1
        samtools index -@ {threads} {output.tumor_bam}                    >> {log} 2>&1
        
        # Normal
        samtools view -@ {threads} -T {input.ref_fa} -b {input.normal_cram} "$region" \
          | samtools sort -@ {threads} -o {output.normal_bam} -          >> {log} 2>&1
        samtools index -@ {threads} {output.normal_bam}                   >> {log} 2>&1


        # ---- Fix SM in headers (preserve all other @RG fields) ----
        fix_sm () {{
          inbam=$1
          outbam=$2
          sm=$3
          tmphdr=$(mktemp)
          OFS="\t"
          samtools view -H "$inbam" \
            | awk -v sm="$sm" 'BEGIN{OFS="\t"}
                /^@RG/ {
                  hasSM=0
                  for (i=1;i<=NF;i++){
                    if ($i ~ /^SM:/) { $i="SM:" sm; hasSM=1 }
                  }
                  if (!hasSM){ $0 = $0 OFS "SM:" sm }
                }
                { print }
              ' > "$tmphdr"
          # Reheader and replace atomically
          samtools reheader "$tmphdr" "$inbam" > "$outbam"
          rm -f "$tmphdr"
          samtools index -@ {threads} "$outbam" >/dev/null 2>&1 || true
        }}
        
        # Distinct names for tumor/normal (required by Mutect2)
        T_SM="{params.cluster_sample}-T"
        N_SM="{params.cluster_sample}-N"
        
        fix_sm "{output.tumor_bam}"  "{output.tumor_bam}.smfix" "$T_SM"
        mv "{output.tumor_bam}.smfix" "{output.tumor_bam}"
        samtools index -@ {threads} -f "{output.tumor_bam}"                     >> {log} 2>&1
        
        fix_sm "{output.normal_bam}" "{output.normal_bam}.smfix" "$N_SM"
        mv "{output.normal_bam}.smfix" "{output.normal_bam}"
        samtools index -@ {threads} -f "{output.normal_bam}"                    >> {log} 2>&1
        
        # Optional: log the final names for sanity  
        gatk GetSampleName -I {output.tumor_bam} 2>>{log} | sed "s/^/Tumor SM: /"  >> {log}
        gatk GetSampleName -I {output.normal_bam} 2>>{log} | sed "s/^/Normal SM: /" >> {log}
        """

rule mutect2:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_bam=MDIR + "{sample}/align/{alnr}/snv/mutect2/tmp/{m2chrm}/{sample}.{alnr}.mutect2.{m2chrm}.tumor.bam",
        tumor_bai=MDIR + "{sample}/align/{alnr}/snv/mutect2/tmp/{m2chrm}/{sample}.{alnr}.mutect2.{m2chrm}.tumor.bam.bai",
        normal_bam=MDIR + "{sample}/align/{alnr}/snv/mutect2/tmp/{m2chrm}/{sample}.{alnr}.mutect2.{m2chrm}.normal.bam",
        normal_bai=MDIR + "{sample}/align/{alnr}/snv/mutect2/tmp/{m2chrm}/{sample}.{alnr}.mutect2.{m2chrm}.normal.bam.bai",
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
        #region="$tcontig:$tstart-$tend"
        region="$tcontig "

        gatk --java-options "-Xmx{resources.mem_mb}M" Mutect2 \
            -R {params.huref} \
            -I {input.tumor_bam} -tumor {params.tumor_sample} \
            -I {input.normal_bam} -normal {params.normal_sample} \
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
            bcf="${{vcf%.vcf.gz}}.bcf";
            bcftools view -O b -o $bcf --threads {threads} $vcf && bcftools index --threads 4 $bcf;
        done;
        touch {output};
        {latency_wait};
        ls {output} >> {log} 2>&1;
        {latency_wait};
        ls {output} >> {log} 2>&1;
        """

rule prep_mutect2_chunkdirs:
    input:
        b=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        i=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/snv/mutect2/vcfs/{dvchrm}/{{sample}}.ready",
            dvchrm=M2_CHRMS,
        ),
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/snv/mutect2/log/{sample}.{alnr}.chunkdirs.log",

    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
