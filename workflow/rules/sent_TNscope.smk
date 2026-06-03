import sys
import os

##### sentieon TNscope - somatic SNV and INDEL caller
# ---------------------------

rule sent_TNscope:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_cram=get_somcall_tumor_cram,
        tumor_crai=get_somcall_tumor_crai,
        normal_cram=get_somcall_normal_cram,
        normal_crai=get_somcall_normal_crai,
        d=MDIR + "{sample}/align/{alnr}/{ddup}/snv/senttn/vcfs/{senttnchrm}/{sample}.ready",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/senttn/vcfs/{senttnchrm}/{sample}.{alnr}.senttn.{senttnchrm}.snv.vcf",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/senttn/log/{sample}.{alnr}.senttn.{senttnchrm}.snv.log",
    threads: config['senttn']['threads']
    conda: config['senttn']['env_yaml']
    priority: 45
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.senttn.{senttnchrm}.bench.tsv",
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
        pon_vcf=lambda wc: config['senttn'].get('pon_vcf', '') or '',
        pon_index=lambda wc: config['senttn'].get('pon_index', '') or '',
        germline_vcf=lambda wc: config['senttn'].get('germline_vcf', '')
        if config['senttn'].get('germline_vcf', '')
        else config['senttn'].get('germline_resource', '') or '',
        cosmic_vcf=lambda wc: config['senttn'].get('cosmic_vcf', '') or '',
        dbsnp_vcf=lambda wc: config['senttn'].get('dbsnp_vcf', '') or '',
        annotation_bed=lambda wc: config['senttn'].get('annotation_bed', '') or '',
        emit_conf=str(config['senttn'].get('emit_conf', '') or ''),
        filter_conf=str(config['senttn'].get('filter_conf', '') or ''),
        extra_args=config['senttn'].get('extra_args', '') or '',
    shell:
        r"""
        set -euo pipefail
        ulimit -n 65536 || true

        mkdir -p "$(dirname {output.vcf})"
        mkdir -p "$(dirname {log})"

        tchr=$(echo {params.cpre}{params.chrm} | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/')
        tchr=${{tchr%:}}
        IFS=':' read -r tcontig tstart tend <<< "$tchr"

        contig_len=$(awk -v c="$tcontig" '$1==c{{print $2; exit}}' "{params.huref}.fai")
        if [ -z "${{contig_len}}" ]; then
            echo "ERROR: Contig '$tcontig' not found in {params.huref}.fai" >> {log} 2>&1
            exit 1
        fi

        if [ -z "${{tend:-}}" ]; then
            region="$tcontig"
        else
            : "${{tstart:=1}}"
            if [ "$tstart" -lt 1 ]; then tstart=1; fi
            if [ "$tend" -gt "$contig_len" ]; then tend="$contig_len"; fi
            if [ "$tstart" -gt "$tend" ]; then
                echo "ERROR: Empty/invalid interval after normalization: $tcontig:$tstart-$tend" >> {log} 2>&1
                exit 1
            fi
            region="$tcontig:$tstart-$tend"
        fi

        timestamp=$(date +%Y%m%d%H%M%S)_$(head -c 12 /dev/urandom | tr -dc 'a-zA-Z0-9')
        export TMPDIR=/dev/shm/senttn_tmp_$timestamp
        mkdir -p "$TMPDIR"
        export SENTIEON_TMPDIR=$TMPDIR
        export APPTAINER_HOME=$TMPDIR
        trap 'rm -rf "$TMPDIR" || true' EXIT

        # --- Validate tumor CRAM contains aligned data ---
        echo "Validating tumor CRAM: {input.tumor_cram}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.tumor_cram} >> {log} 2>&1; then
            echo "ERROR: Tumor CRAM failed integrity check: {input.tumor_cram}" | tee -a {log};
            exit 10;
        fi
        _sq_count=$(samtools view -H {input.tumor_cram} 2>/dev/null | grep -c '^@SQ' || true);
        echo "Tumor CRAM @SQ header count: $_sq_count" >> {log} 2>&1;
        if [ "$_sq_count" -eq 0 ]; then
            echo "ERROR: Tumor CRAM has no @SQ headers (unaligned?): {input.tumor_cram}" | tee -a {log};
            exit 11;
        fi
        echo "Tumor CRAM validation passed ($_sq_count reference sequences)" >> {log} 2>&1;

        # --- Validate normal CRAM contains aligned data ---
        echo "Validating normal CRAM: {input.normal_cram}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.normal_cram} >> {log} 2>&1; then
            echo "ERROR: Normal CRAM failed integrity check: {input.normal_cram}" | tee -a {log};
            exit 12;
        fi
        _sq_count=$(samtools view -H {input.normal_cram} 2>/dev/null | grep -c '^@SQ' || true);
        echo "Normal CRAM @SQ header count: $_sq_count" >> {log} 2>&1;
        if [ "$_sq_count" -eq 0 ]; then
            echo "ERROR: Normal CRAM has no @SQ headers (unaligned?): {input.normal_cram}" | tee -a {log};
            exit 13;
        fi
        echo "Normal CRAM validation passed ($_sq_count reference sequences)" >> {log} 2>&1;

        if [ -z "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE not set. Please set the SENTIEON_LICENSE environment variable to the license file path & make this update to your dyinit file as well." >> {log} 2>&1
            exit 3
        fi

        if [ ! -f "$SENTIEON_LICENSE" ]; then
            echo "The file referenced by SENTIEON_LICENSE ('$SENTIEON_LICENSE') does not exist. Please provide a valid file path." >> {log} 2>&1
            exit 4
        fi

        pon_arg=""
        if [ -n "{params.pon_vcf}" ]; then
            pon_arg="--pon {params.pon_vcf}"
            if [ -n "{params.pon_index}" ]; then
                pon_arg="$pon_arg --pon_index {params.pon_index}"
            fi
        fi

        germline_arg=""
        if [ -n "{params.germline_vcf}" ]; then
            germline_arg="--germline_resource {params.germline_vcf}"
        fi

        cosmic_arg=""
        if [ -n "{params.cosmic_vcf}" ]; then
            cosmic_arg="--cosmic {params.cosmic_vcf}"
        fi

        dbsnp_arg=""
        if [ -n "{params.dbsnp_vcf}" ]; then
            dbsnp_arg="--dbsnp {params.dbsnp_vcf}"
        fi

        annotation_arg=""
        if [ -n "{params.annotation_bed}" ]; then
            annotation_arg="--annotation {params.annotation_bed}"
        fi

        emit_arg=""
        if [ -n "{params.emit_conf}" ]; then
            emit_arg="--emit_conf {params.emit_conf}"
        fi

        filter_arg=""
        if [ -n "{params.filter_conf}" ]; then
            filter_arg="--filter_conf {params.filter_conf}"
        fi

        extra_args="{params.extra_args}"
        if [ "$extra_args" = "None" ]; then
            extra_args=""
        fi

        {params.numa} /fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/sentieon driver \
            --tumor_sample {params.tumor_sample} \
            --normal_sample {params.normal_sample} \
            -t {threads} \
            -r {params.huref} \
            -i {input.tumor_cram} \
            -i {input.normal_cram} \
            --interval "$region" \
            --algo TNscope \
            $pon_arg \
            $germline_arg \
            $cosmic_arg \
            $dbsnp_arg \
            $annotation_arg \
            $emit_arg \
            $filter_arg \
            $extra_args \
            {output.vcf} >> {log} 2>&1

        touch {output.vcf}
        """


rule sent_TNscope_sort_index_chunk_vcf:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/senttn/vcfs/{senttnchrm}/{sample}.{alnr}.senttn.{senttnchrm}.snv.vcf",
    priority: 46
    output:
        vcfsort=MDIR + "{sample}/align/{alnr}/{ddup}/snv/senttn/vcfs/{senttnchrm}/{sample}.{alnr}.senttn.{senttnchrm}.snv.sort.vcf",
        vcfgz=MDIR + "{sample}/align/{alnr}/{ddup}/snv/senttn/vcfs/{senttnchrm}/{sample}.{alnr}.senttn.{senttnchrm}.snv.sort.vcf.gz",
        vcftbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/senttn/vcfs/{senttnchrm}/{sample}.{alnr}.senttn.{senttnchrm}.snv.sort.vcf.gz.tbi",
    conda:
        config['senttn']['conda']
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/senttn/vcfs/{senttnchrm}/log/{sample}.{alnr}.senttn.{senttnchrm}.snv.sort.vcf.gz.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{senttnchrm}.sent_TNscope_sort_index_chunk_vcf.bench.tsv"
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
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/senttn/vcfs/{senttnchrm}/{sample}.{alnr}.senttn.{senttnchrm}.snv.sort.vcf.gz",
            sample=wildcards.sample,
            alnr=wildcards.alnr,
            ddup=wildcards.ddup,
            senttnchrm=SENTTN_CHRMS,
        ),
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/{ddup}/snv/senttn/{sample}.{alnr}.senttn.snv.sort.vcf.gz",
        vcfgztbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/senttn/{sample}.{alnr}.senttn.snv.sort.vcf.gz.tbi",
    threads: 4
    conda:
        config['senttn']['conda']
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/senttn/log/{sample}.{alnr}.senttn.snv.merge.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sent_TNscope_concat_index_chunks.bench.tsv"
    params:
        cluster_sample=ret_sample,
    shell:
        """
        bcftools concat -a -O z -o {output.vcfgz} {input.vcfs} >> {log} 2>&1;
        bcftools index -f -t {output.vcfgz} >> {log} 2>&1;
        """


rule produce_sent_TNscope_vcf:  # TARGET : Produce Sentieon TNscope somatic VCFs
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcftb=expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/senttn/{sample}.{alnr}.senttn.snv.sort.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
            ddup=DDUP,
        ),
        vcftbi=expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/senttn/{sample}.{alnr}.senttn.snv.sort.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
            ddup=DDUP,
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
            bcf="${vcf%.vcf.gz}.bcf";
            bcftools view -O b -o $bcf --threads {threads} $vcf && bcftools index --threads 4 $bcf;
        done;
        touch {output};
        ls {output} >> {log} 2>&1;
        ls {output} >> {log} 2>&1;
        """
