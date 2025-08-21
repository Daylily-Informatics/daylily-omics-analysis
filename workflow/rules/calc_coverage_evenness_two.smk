import os

rule calc_coverage_evenness_two:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        metrics=MDIR + "{sample}/align/{alnr}/alignqc/coverage_evenness_two/{sample}.{alnr}.coverage_evenness_two.tsv",
    conda:
        "../envs/coverage_evenness_two.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.coverage_evenness_two.bench.tsv"
    threads: config['calc_coverage_evenness_two']['threads']
    resources:
        vcpu=config['calc_coverage_evenness_two']['threads'],
        partition=config['calc_coverage_evenness_two']['partition'],
    log:
        MDIR + "{sample}/align/{alnr}/alignqc/coverage_evenness_two/logs/coverage_evenness_two.log",
    params:
        window=config['calc_coverage_evenness_two'].get('window', 100000),
        cluster_sample=ret_sample,
    shell:
        """
        mkdir -p $(dirname {output.metrics}) $(dirname {log});
        python workflow/scripts/coverage_evenness_two.py --window {params.window} {input.cram} {output.metrics} &> {log}
        {latency_wait};
        ls {output.metrics};
        """
