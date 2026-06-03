#### ENSEMBL VEP
# -------------------------------------
# github: https://github.com/Ensembl/ensembl-vep
# docker: https://hub.docker.com/r/ensemblorg/ensembl-vep:release_109.3

import csv
import os


rule vep_validate_input_contigs:
    input:
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/{sample}.{alnr}.{ddup}.{snv}.snv.sort.vcf.gz",
        vcftbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/{sample}.{alnr}.{ddup}.{snv}.snv.sort.vcf.gz.tbi",
    output:
        done=touch(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{sample}.{alnr}.{ddup}.{snv}.vep.input_contigs.ok"
        ),
        observed_contigs=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{sample}.{alnr}.{ddup}.{snv}.vep.input_contigs.observed.txt",
        allowed_contigs=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{sample}.{alnr}.{ddup}.{snv}.vep.input_contigs.allowed.txt",
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/log/{sample}.{alnr}.{ddup}.{snv}.vep.validate_contigs.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.vep_validate_input_contigs.bench.tsv"
    resources:
        vcpu=1,
        threads=1,
        partition=config["vep"].get("concat_partition", config["vep"]["partition"]),
        mem_mb=4000,
    params:
        allowed_contigs=get_vep_allowed_contigs,
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.done}) $(dirname {log})
        bcftools index -s {input.vcfgz} | awk '$3 > 0 {{print $1}}' | sort -u > {output.observed_contigs}
        printf '%s\n' "{params.allowed_contigs}" | tr ',' '\n' | sort -u > {output.allowed_contigs}
        unexpected="{output.done}.unexpected"
        comm -23 {output.observed_contigs} {output.allowed_contigs} > "$unexpected"
        if [ -s "$unexpected" ]; then
            echo "ERROR: VEP chromosome config would drop input VCF contigs:" >&2
            cat "$unexpected" >&2
            exit 2
        fi
        """


rule vep_chromosome_input:
    input:
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/{sample}.{alnr}.{ddup}.{snv}.snv.sort.vcf.gz",
        vcftbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/{sample}.{alnr}.{ddup}.{snv}.snv.sort.vcf.gz.tbi",
        validated=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{sample}.{alnr}.{ddup}.{snv}.vep.input_contigs.ok",
    output:
        chunk_vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{vepchrm}/{sample}.{alnr}.{ddup}.{snv}.{vepchrm}.input.vcf.gz",
        chunk_tbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{vepchrm}/{sample}.{alnr}.{ddup}.{snv}.{vepchrm}.input.vcf.gz.tbi",
        record_count=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{vepchrm}/{sample}.{alnr}.{ddup}.{snv}.{vepchrm}.input.vcf.gz.record_count",
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{vepchrm}/log/{sample}.{alnr}.{ddup}.{snv}.{vepchrm}.input.log",
    threads: 1
    resources:
        vcpu=1,
        threads=1,
        partition=config["vep"].get("concat_partition", config["vep"]["partition"]),
        mem_mb=4000,
    params:
        cluster_sample=ret_sample,
        contig=get_vepchrm,
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.{vepchrm}.vep_input.bench.tsv"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.chunk_vcfgz}) $(dirname {log})
        if bcftools index -s {input.vcfgz} | cut -f1 | grep -Fxq "{params.contig}"; then
            bcftools view -r {params.contig} -O z -o {output.chunk_vcfgz} {input.vcfgz} >> {log} 2>&1
        else
            bcftools view -h {input.vcfgz} | bgzip -c > {output.chunk_vcfgz}
        fi
        tabix -f -p vcf {output.chunk_vcfgz} >> {log} 2>&1
        bcftools view -H {output.chunk_vcfgz} | wc -l | awk '{{print $1}}' > {output.record_count}
        test -s {output.chunk_vcfgz}
        test -s {output.chunk_tbi}
        """


rule vep_chromosome:
    input:
        chunk_vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{vepchrm}/{sample}.{alnr}.{ddup}.{snv}.{vepchrm}.input.vcf.gz",
        chunk_tbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{vepchrm}/{sample}.{alnr}.{ddup}.{snv}.{vepchrm}.input.vcf.gz.tbi",
        record_count=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{vepchrm}/{sample}.{alnr}.{ddup}.{snv}.{vepchrm}.input.vcf.gz.record_count",
    output:
        annovcf=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{vepchrm}/{sample}.{alnr}.{ddup}.{snv}.{vepchrm}.vep.vcf.gz",
        annovcftbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{vepchrm}/{sample}.{alnr}.{ddup}.{snv}.{vepchrm}.vep.vcf.gz.tbi",
        ann_record_count=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{vepchrm}/{sample}.{alnr}.{ddup}.{snv}.{vepchrm}.vep.vcf.gz.record_count",
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/chunks/{vepchrm}/log/{sample}.{alnr}.{ddup}.{snv}.{vepchrm}.vep.log",
    threads: config["vep"]["threads"]
    resources:
        vcpu=config["vep"]["threads"],
        partition=config["vep"]["partition"],
        threads=config["vep"]["threads"],
        mem_mb=config["vep"].get("mem_mb", 3000),
    params:
        contig=get_vepchrm,
        cluster_sample=ret_sample,
        genome_build="GRCh37" if 'b37' in config['genome_build'] else "GRCh38",
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        vep_cache=config["supporting_files"]["files"]["vep"]["vep_cache"]['name'],
        cache_version=config["supporting_files"]["files"]["vep"]["vep_genome_build"].split("_", 1)[0],
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.{vepchrm}.vep.bench.tsv"
    container:
        "docker://ensemblorg/ensembl-vep:release_114.2"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.annovcf}) $(dirname {log})
        test -d {params.vep_cache}/homo_sapiens/{params.cache_version}_{params.genome_build} || (
            echo "ERROR: VEP cache not found: {params.vep_cache}/homo_sapiens/{params.cache_version}_{params.genome_build}" >&2
            exit 2
        )
        records=$(cat {input.record_count})
        if [ "$records" -eq 0 ]; then
            gzip -cd {input.chunk_vcfgz} | awk '/^#/' | bgzip -c > {output.annovcf}
        else
            vep \
            --dir_cache {params.vep_cache} \
            --offline \
            --vcf \
            --cache \
            --cache_version {params.cache_version} \
            --input_file {input.chunk_vcfgz} \
            --chr {params.contig} \
            --fork {threads} \
            --fasta {params.huref} \
            --species homo_sapiens \
            --assembly {params.genome_build} \
            --output_file {output.annovcf} \
            --force_overwrite --everything \
            --hgvs \
            --symbol \
            --protein \
            --freq_pop \
            --terms \
            --variant_class \
            --compress_output bgzip >> {log} 2>&1
        fi
        tabix -f -p vcf {output.annovcf} >> {log} 2>&1
        cat {input.record_count} > {output.ann_record_count}
        test -s {output.annovcf}
        test -s {output.annovcftbi}
        """


localrules:
    vep_validate_input_contigs,
    vep_concat_fofn,


rule vep_concat_fofn:
    input:
        ann_tbis=expand(
            MDIR
            + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/{{snv}}/vep/chunks/{vepchrm}/{{sample}}.{{alnr}}.{{ddup}}.{{snv}}.{vepchrm}.vep.vcf.gz.tbi",
            vepchrm=VEP_CHRMS,
        ),
        ann_counts=expand(
            MDIR
            + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/{{snv}}/vep/chunks/{vepchrm}/{{sample}}.{{alnr}}.{{ddup}}.{{snv}}.{vepchrm}.vep.vcf.gz.record_count",
            vepchrm=VEP_CHRMS,
        ),
    output:
        fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.concat.vcf.gz.fofn",
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/log/{sample}.{alnr}.{ddup}.{snv}.vep.concat_fofn.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.vep_concat_fofn.bench.tsv"
    params:
        tmp_fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.concat.vcf.gz.fofn.tmp",
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.fofn}) $(dirname {log})
        : > {params.tmp_fofn}
        for count_path in {input.ann_counts}; do
            count=$(cat "$count_path")
            if [ "$count" -gt 0 ]; then
                echo "${{count_path%.record_count}}" >> {params.tmp_fofn}
            fi
        done
        if [ ! -s {params.tmp_fofn} ]; then
            echo "ERROR: no non-empty VEP chromosome chunks to concatenate" >&2
            exit 2
        fi
        mv {params.tmp_fofn} {output.fofn}
        """


rule vep_concat_index_chunks:
    input:
        fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.concat.vcf.gz.fofn",
        input_counts=expand(
            MDIR
            + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/{{snv}}/vep/chunks/{vepchrm}/{{sample}}.{{alnr}}.{{ddup}}.{{snv}}.{vepchrm}.input.vcf.gz.record_count",
            vepchrm=VEP_CHRMS,
        ),
        ann_counts=expand(
            MDIR
            + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/{{snv}}/vep/chunks/{vepchrm}/{{sample}}.{{alnr}}.{{ddup}}.{{snv}}.{vepchrm}.vep.vcf.gz.record_count",
            vepchrm=VEP_CHRMS,
        ),
    output:
        ovcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.vcf.gz",
        ovcftbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.vcf.gz.tbi",
        done=touch(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.done"),
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/log/{sample}.{alnr}.{ddup}.{snv}.vep.concat.log",
    threads: config["vep"].get("concat_threads", 4)
    resources:
        vcpu=config["vep"].get("concat_threads", 4),
        partition=config["vep"].get("concat_partition", config["vep"]["partition"]),
        threads=config["vep"].get("concat_threads", 4),
        mem_mb=config["vep"].get("concat_mem_mb", 16000),
    params:
        cluster_sample=ret_sample,
        ovcfgztemp=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.temp.vcf.gz",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.vep_concat.bench.tsv"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.ovcfgz}) $(dirname {log})
        input_count=$(awk '{{s+=$1}} END {{print s+0}}' {input.input_counts})
        ann_count=$(awk '{{s+=$1}} END {{print s+0}}' {input.ann_counts})
        if [ "$input_count" -ne "$ann_count" ]; then
            echo "ERROR: VEP annotated variant count ($ann_count) does not match input chunk count ($input_count)" >&2
            exit 2
        fi
        bcftools concat -a -d all --threads {threads} -f {input.fofn} -O z -o {params.ovcfgztemp} >> {log} 2>&1
        mv {params.ovcfgztemp} {output.ovcfgz}
        tabix -f -p vcf {output.ovcfgz} >> {log} 2>&1
        final_count=$(bcftools view -H {output.ovcfgz} | wc -l | awk '{{print $1}}')
        if [ "$final_count" -ne "$input_count" ]; then
            echo "ERROR: final VEP VCF count ($final_count) does not match input count ($input_count)" >&2
            exit 2
        fi
        test -s {output.ovcfgz}
        test -s {output.ovcftbi}
        """

localrules:
    vep_annotation_gather,
    produce_vep,


rule vep_annotation_gather:
    input:
        [
            MDIR
            + f"{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.vcf.gz.tbi"
            for sample in SSAMPS
            for ddup in DDUP
            for alnr, snv in valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)
        ],
    output:
        MDIR + "other_reports/vep_annotation_mqc.tsv",
    log:
        MDIR + "logs/vep_annotation_gather.log"
    run:
        os.makedirs(os.path.dirname(str(output[0])), exist_ok=True)
        fieldnames = [
            "Sample",
            "base_sample",
            "aligner",
            "deduper",
            "snv_caller",
            "annotation_tool",
            "vcf_gz",
            "summary_glob",
            "status",
        ]
        with open(output[0], "w", newline="") as out_handle:
            writer = csv.DictWriter(out_handle, fieldnames=fieldnames, delimiter="\t")
            writer.writeheader()
            for path in input:
                sample, aligner, deduper, caller = _variant_qc_parts(path)
                sample_id = day_stage_sample_id(sample, aligner, deduper, caller)
                vcf_gz = str(path).removesuffix(".tbi")
                vep_dir = os.path.dirname(vcf_gz)
                vep_prefix = os.path.basename(vcf_gz).removesuffix(".vep.vcf.gz")
                summary_glob = os.path.join(
                    vep_dir,
                    "chunks",
                    "*",
                    f"{vep_prefix}.*.vep.vcf.gz_summary.html",
                )
                writer.writerow(
                    {
                        "Sample": sample_id,
                        "base_sample": sample,
                        "aligner": aligner,
                        "deduper": deduper,
                        "snv_caller": caller,
                        "annotation_tool": "vep",
                        "vcf_gz": vcf_gz,
                        "summary_glob": summary_glob,
                        "status": "ok",
                    }
                )


rule produce_vep:  # TARGET: just produce vep results
    input:
        [
            MDIR
            + f"{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.vcf.gz.tbi"
            for sample in SSAMPS
            for ddup in DDUP
            for alnr, snv in valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)
        ],
        MDIR + "other_reports/vep_annotation_mqc.tsv",
    output:
        "logs/vep_gathered.done",
    log:
        MDIR + "logs/produce_vep.log"
    shell:
        "touch {output};"
