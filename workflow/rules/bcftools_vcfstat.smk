######### BCFTOOLS stats
# ----------------------------
# This is a population agnostic contamination screening tool that can
# operate on single sample or multi sample BAM files.
# github: https://github.com/samtools/bcftools
# paper: http://samtools.github.io/bcftools/howtos/publications.html
# docs: https://samtools.github.io/bcftools/bcftools.html

import csv
import os


def _variant_qc_parts(path):
    name = os.path.basename(str(path))
    parts = name.split(".")
    return parts[0], parts[1], parts[2], parts[3]


rule bcftools_vcfstat:
    input:
        snv_vcf=(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/{sample}.{alnr}.{ddup}.{snv_caller}.snv.sort.vcf.gz"
        ),
        snv_vcf_tbi=(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/{sample}.{alnr}.{ddup}.{snv_caller}.snv.sort.vcf.gz.tbi"
        ),
    output:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/bcfstats/{sample}.{alnr}.{ddup}.{snv_caller}.bcfstats.tsv",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/bcfstats/logs/{sample}.{alnr}.{ddup}.{snv_caller}.bcfstats.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv_caller}.bcfstat.bench.tsv",
    conda:
        config["vanilla"]["env_yaml"]
    threads: config["bcftools_vcfstat"]["threads"]
    params:
        cluster_sample=ret_sample,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    shell:
        """
        bcftools stats --threads {threads} {input.snv_vcf} -F {params.huref} > {output};
        ls {output};
        """


localrules:
    bcftools_variant_stats_gather,
    produce_bcfvcfstats,


rule bcftools_variant_stats_gather:
    input:
        [
            MDIR
            + f"{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/bcfstats/{sample}.{alnr}.{ddup}.{snv_caller}.bcfstats.tsv"
            for sample in SSAMPS
            for ddup in DDUP
            for alnr, snv_caller in valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)
        ]
    output:
        MDIR + "other_reports/bcftools_variant_stats_mqc.tsv"
    run:
        os.makedirs(os.path.dirname(str(output[0])), exist_ok=True)
        fieldnames = [
            "sample_id",
            "aligner",
            "deduper",
            "snv_caller",
            "number_of_records",
            "number_of_snps",
            "number_of_indels",
            "source_path",
            "status",
        ]
        with open(output[0], "w", newline="") as out_handle:
            writer = csv.DictWriter(out_handle, fieldnames=fieldnames, delimiter="\t")
            writer.writeheader()
            for path in input:
                sample, aligner, deduper, caller = _variant_qc_parts(path)
                metrics = {}
                with open(path) as in_handle:
                    for line in in_handle:
                        fields = line.rstrip("\n").split("\t")
                        if len(fields) >= 4 and fields[0] == "SN":
                            metrics[fields[2].rstrip(":").lower()] = fields[3]
                writer.writerow(
                    {
                        "sample_id": sample,
                        "aligner": aligner,
                        "deduper": deduper,
                        "snv_caller": caller,
                        "number_of_records": metrics.get("number of records", ""),
                        "number_of_snps": metrics.get("number of snps", ""),
                        "number_of_indels": metrics.get("number of indels", ""),
                        "source_path": path,
                        "status": "ok",
                    }
                )


rule produce_bcfvcfstats:  # TARGET:  jusg genvcfstats
    input:
        [
            MDIR
            + f"{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/bcfstats/{sample}.{alnr}.{ddup}.{snv_caller}.bcfstats.tsv"
            for sample in SSAMPS
            for ddup in DDUP
            for alnr, snv_caller in valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)
        ],
        MDIR + "other_reports/bcftools_variant_stats_mqc.tsv",
