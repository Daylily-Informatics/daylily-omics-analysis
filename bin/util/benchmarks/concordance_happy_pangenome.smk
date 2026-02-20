# Optional: hap.py concordance for pangenome VCF vs GIAB truth
#
# Required config keys (example layout):
#   config['truth']['vcf']   -> truth VCF.gz
#   config['truth']['bed']   -> confident regions BED
#   config['supporting_files']['files']['huref']['fasta']['name'] -> reference fasta
#
# Usage:
#   include: "concordance_happy_pangenome.smk"
#   snakemake -j 50 {DIR}/tools/qc/happy/{sample}.summary.csv

import os

MDIR = "{DIR}/tools/"

rule happy_concordance_pangenome:
    input:
        truth_vcf=config["truth"]["vcf"],
        truth_bed=config["truth"]["bed"],
        ref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        query_vcf=MDIR + "align/pangenome/{sample}.vcf.gz",
    output:
        summary=MDIR + "qc/happy/{sample}.summary.csv",
    log:
        MDIR + "qc/happy/{sample}.happy.log",
    threads:
        config.get("qc", {}).get("happy_threads", 8)
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.summary})
        hap.py {input.truth_vcf} {input.query_vcf} \
          -f {input.truth_bed} \
          -r {input.ref} \
          -o {MDIR}qc/happy/{wildcards.sample} \
          --threads {threads} \
          > {log} 2>&1
        """
