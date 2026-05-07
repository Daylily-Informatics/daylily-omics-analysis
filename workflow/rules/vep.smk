#### ENSEMBL VEP
# -------------------------------------
# github: https://github.com/Ensembl/ensembl-vep
# docker: https://hub.docker.com/r/ensemblorg/ensembl-vep:release_109.3

import csv
import os


rule vep:
    input:
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/{sample}.{alnr}.{ddup}.{snv}.snv.sort.vcf.gz",
    output:
        ovcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.vcf.gz",
        ovcftbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.vcf.gz.tbi",
        done=touch(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.done"),
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/log/{sample}.{alnr}.{ddup}.{snv}.vep.log",
    threads: config["vep"]["threads"]
    resources:
        vcpu=config["vep"]["threads"],
        partition=config["vep"]["partition"],
        threads=config["vep"]["threads"],
    params:
        cluster_sample=ret_sample,
        genome_build="GRCh37" if 'b37' in config['genome_build'] else "GRCh38",
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        vep_cache=config["supporting_files"]["files"]["vep"]["vep_cache"]['name'],
        cache_version=config["supporting_files"]["files"]["vep"]["vep_genome_build"].split("_", 1)[0],
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.vep.bench.tsv"
    container:
        "docker://ensemblorg/ensembl-vep:release_114.2"        
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.ovcfgz}) $(dirname {log})
        test -d {params.vep_cache}/homo_sapiens/{params.cache_version}_{params.genome_build} || (
            echo "ERROR: VEP cache not found: {params.vep_cache}/homo_sapiens/{params.cache_version}_{params.genome_build}" >&2
            exit 2
        )
        vep \
        --dir_cache {params.vep_cache} \
        --offline \
        --vcf \
        --cache \
        --cache_version {params.cache_version} \
        --input_file {input.vcfgz} \
        --fork {threads} \
        --fasta {params.huref} \
        --species homo_sapiens \
        --assembly {params.genome_build} \
        --output_file {output.ovcfgz} \
        --force_overwrite --everything \
        --hgvs \
        --symbol \
        --protein \
        --freq_pop \
        --terms \
        --variant_class \
        --compress_output bgzip >> {log} 2>&1
        tabix -f -p vcf {output.ovcfgz} >> {log} 2>&1
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
    run:
        os.makedirs(os.path.dirname(str(output[0])), exist_ok=True)
        fieldnames = [
            "sample_id",
            "aligner",
            "deduper",
            "snv_caller",
            "annotation_tool",
            "vcf_gz",
            "status",
        ]
        with open(output[0], "w", newline="") as out_handle:
            writer = csv.DictWriter(out_handle, fieldnames=fieldnames, delimiter="\t")
            writer.writeheader()
            for path in input:
                sample, aligner, deduper, caller = _variant_qc_parts(path)
                writer.writerow(
                    {
                        "sample_id": sample,
                        "aligner": aligner,
                        "deduper": deduper,
                        "snv_caller": caller,
                        "annotation_tool": "vep",
                        "vcf_gz": str(path).removesuffix(".tbi"),
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
    shell:
        "touch {output};"
