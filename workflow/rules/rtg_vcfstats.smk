##### RTG TOOLS ARE A GENERAL SET OF BFX UTILITIES
# ------------------------------------------------
#
# This is uysig them to calculate qc info on
# VCF files.
#
# They are best known for their tool 'vcfeval'
# which compuites the concordance between 2 VCFS
# and also attempt to define the best hard filters
# for your data.  They are also heavy early adopters to
# The distant change in VCF spec to BND format.

import csv
import os


rule rtg_vcfstats:
    """https://github.com/RealTimeGenomics/rtg-tools"""
    input:
        svgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/{sample}.{alnr}.{ddup}.{snv_caller}.snv.sort.vcf.gz",
        svtbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/{sample}.{alnr}.{ddup}.{snv_caller}.snv.sort.vcf.gz.tbi",
    output:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/vcf_stats/{sample}.{alnr}.{ddup}.{snv_caller}.rtg.vcfstats.txt",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv_caller}.rtgvcfstats.bench.tsv"
    threads: config["rtg_vcfstats"]["threads"]
    resources:
        threads=config["rtg_vcfstats"]["threads"],
        partition=config["rtg_vcfstats"]["partition"],
    params:
        work_dir=MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/vcf_stats/",
        cluster_sample=ret_sample,
    conda:
        config["rtg_vcfstats"]["env_yaml"]
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/vcf_stats/logs/{sample}.{alnr}.{ddup}.{snv_caller}.rtg.vcf.stats.log",
    shell:
        """
        mkdir -p {params.work_dir} > {log} 2>&1 ;
        rtg vcfstats --allele-lengths {input.svgz} > {output}  ;
        ls {output};
        """


localrules:
    rtg_vcfstats_gather,


rule rtg_vcfstats_gather:
    input:
        [
            MDIR
            + f"{sample}/align/{alnr}/{ddup}/snv/{snv_caller}/vcf_stats/{sample}.{alnr}.{ddup}.{snv_caller}.rtg.vcfstats.txt"
            for sample in SSAMPS
            for ddup in DDUP
            for alnr, snv_caller in valid_snv_alnr_pairs(ALL_ALIGNERS, snv_CALLERS)
        ]
    output:
        MDIR + "other_reports/rtg_vcfstats_mqc.tsv"
    run:
        os.makedirs(os.path.dirname(str(output[0])), exist_ok=True)
        fieldnames = [
            "Sample",
            "base_sample",
            "aligner",
            "deduper",
            "snv_caller",
            "source_path",
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
                        "source_path": path,
                        "status": "ok",
                    }
                )
