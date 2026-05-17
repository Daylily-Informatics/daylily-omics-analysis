import os


def _get_queue():
    # Come back and have this threshold set by if the BAM is > 19G or not
    if "is_lcwgs" in config["qualimap"]:
        if config["qualimap"]["is_lcwgs"] in "lcwgs":
            return " -q dev-short "
    return " -q dev-long "

rule qualimap:
    """Run Qualimap on a temporary BAM sidecar for CRAM-reader compatibility."""
    input:
        bam=rules.legacy_cram_compat_bam.output.bam,
        bai=rules.legacy_cram_compat_bam.output.bai,
    output:
        d=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/qmap/{sample}.{alnr}/{ddup}/{sample}.{alnr}.{ddup}.qmap.done",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.qmap.bench.tsv"
    resources:
        vcpu=config["qualimap"]["threads"],
        threads=config["qualimap"]["threads"],
        mem_mb=config["qualimap"]["mem_mb"],
        partition=config["qualimap"]["partition"],
    params:
        java_mem_size=config["qualimap"]["java_mem_size"],
        cluster_sample=ret_sample,
        genome_gc_distr=config["qualimap"].get("genome_gc_distr", "HUMAN"),
    conda:
        config["qualimap"]["env_yaml"]
    threads: config["qualimap"]["threads"]
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/qmap/{sample}/logs/{sample}.{alnr}.{ddup}.qmap.log",
    shell:
        """
        set -euo pipefail
        rm -rf $(dirname {output.d:q})
        mkdir -p $(echo $(dirname {output.d:q})/logs ) ;
        export dn=$(dirname {output.d} );
        qualimap bamqc -bam {input.bam:q} -nt {threads} -c -gd {params.genome_gc_distr:q}  -outformat HTML  -outdir $dn --java-mem-size={params.java_mem_size:q} > {log:q} 2>&1
        test -s "$dn/genome_results.txt"
        touch {output.d:q};
        ls {output.d};
        """
