#### snpeff
# -------------------------------------

import csv
import os


rule snpeff:
    input:
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/{sample}.{alnr}.{ddup}.{snv}.snv.sort.vcf.gz",
    output:
        annovcf=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/snpeff/{sample}.{alnr}.{ddup}.{snv}.snpeff.vcf.gz",
        annovcftbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/snpeff/{sample}.{alnr}.{ddup}.{snv}.snpeff.vcf.gz.tbi",
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/snpeff/log/{sample}.{alnr}.{ddup}.{snv}.snpeff.log",
    threads: config["snpeff"]["threads"]
    resources:
        vcpu=config["snpeff"]["threads"],
        partition=config["snpeff"]["partition"],
        threads=config["snpeff"]["threads"],
    params:
        cluster_sample=ret_sample,
        snpeff_genome_build=config["supporting_files"]["files"]["snpeff"]["ref_build_code"],
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        snpeff_xmx="16g" if "xmx" not in config["snpeff"] else config["snpeff"]["xmx"],
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.snpeff.bench.tsv"
    conda:
        "../envs/snpeff_v0.1.yaml"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.annovcf}) $(dirname {log})
        java -Xmx{params.snpeff_xmx} -jar  \
        $(find $CONDA_PREFIX -name snpEff.jar) \
        -v {params.snpeff_genome_build} \
        {input.vcfgz} \
        2> {log} | bgzip -c > {output.annovcf}
        tabix -f -p vcf {output.annovcf} >> {log} 2>&1
        test -s {output.annovcf}
        test -s {output.annovcftbi}
        """


localrules:
    snpeff_annotation_gather,
    produce_snpeff,


rule snpeff_annotation_gather:
    input:
        [
            MDIR
            + f"{sample}/align/{alnr}/{ddup}/snv/{snv}/snpeff/{sample}.{alnr}.{ddup}.{snv}.snpeff.vcf.gz.tbi"
            for sample in SSAMPS
            for ddup in DDUP
            for alnr, snv in valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)
        ],
    output:
        MDIR + "other_reports/snpeff_annotation_mqc.tsv",
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
            "status",
        ]
        with open(output[0], "w", newline="") as out_handle:
            writer = csv.DictWriter(out_handle, fieldnames=fieldnames, delimiter="\t")
            writer.writeheader()
            for path in input:
                sample, aligner, deduper, caller = _variant_qc_parts(path)
                sample_id = day_stage_sample_id(sample, aligner, deduper, caller)
                writer.writerow(
                    {
                        "Sample": sample_id,
                        "base_sample": sample,
                        "aligner": aligner,
                        "deduper": deduper,
                        "snv_caller": caller,
                        "annotation_tool": "snpeff",
                        "vcf_gz": str(path).removesuffix(".tbi"),
                        "status": "ok",
                    }
                )


rule produce_snpeff:  # TARGET: just produce snpeff results
    input:
        [
            MDIR
            + f"{sample}/align/{alnr}/{ddup}/snv/{snv}/snpeff/{sample}.{alnr}.{ddup}.{snv}.snpeff.vcf.gz.tbi"
            for sample in SSAMPS
            for ddup in DDUP
            for alnr, snv in valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)
        ],
        MDIR + "other_reports/snpeff_annotation_mqc.tsv",
    output:
        "logs/snpeff_gathered.done",
    shell:
        "touch {output};"
