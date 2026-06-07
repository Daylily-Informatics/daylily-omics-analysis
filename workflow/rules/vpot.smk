import os

##### VPOT
# ---------------
# github: https://github.com/VCCRI/VPOT


rule vpot:
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/{sample}.{alnr}.{snv}.snv.sort.vcf.gz",
    output:
        report=MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vpot/{sample}.{alnr}.{snv}.vpot.tsv",
        done=touch(MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vpot/{sample}.{alnr}.{snv}.vpot.done"),
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vpot/log/{sample}.{alnr}.{snv}.vpot.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.vpot.bench.tsv"
    threads: config["vpot"]["threads"]
    resources:
        vcpu=config["vpot"]["threads"],
        threads=config["vpot"]["threads"],
        mem_mb=config["vpot"]["mem_mb"],
        partition=config["vpot"]["partition"],
    params:
        extra=config["vpot"].get("extra", ""),
        cluster_sample=ret_sample,
    conda:
        config["vpot"]["env_yaml"]
    shell:
        """
        mkdir -p $(dirname {output.report}) $(dirname {log});
        touch {log};
        vpot {params.extra} -i {input.vcf} -o {output.report} >> {log} 2>&1;
        touch {output.done};
        """


localrules:
    produce_vpot,


rule produce_vpot:  # TARGET: run VPOT across all samples
    input:
        [
            MDIR + f"{sample}/align/{alnr}/{ddup}/snv/{snv}/vpot/{sample}.{alnr}.{snv}.vpot.done"
            for sample in SSAMPS
            for ddup in DDUP
            for alnr, snv in valid_snv_alnr_pairs(ALIGNERS, snv_CALLERS)
        ],
    output:
        "logs/vpot_gathered.done",
    log:
        MDIR + "logs/produce_vpot.log"
    benchmark:
        "logs/benchmarks/produce_vpot.bench.tsv"
    shell:
        "touch {output};"
