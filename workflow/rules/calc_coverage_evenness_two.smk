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
        set -euo pipefail;
        mkdir -p $(dirname {output.metrics}) $(dirname {log});
        samtools depth -a {input.cram} 2> {log} | \
            bin/calc_coverage_evenness_two.py --window {params.window} > {output.metrics};
        {latency_wait};
        ls {output.metrics};
    """

localrules: 
    produce_coverage_evenness_two,

rule produce_coverage_evenness_two:  # TARGET: Produce cov eveness TWO.
    input:
            expand(MDIR + "{sample}/align/{alnr}/alignqc/coverage_evenness_two/{sample}.{alnr}.coverage_evenness_two.tsv", sample=SSAMPS, alnr=ALL_ALIGNERS)
    container: None
    threads: 8
    output:
        mqc=MDIR+"other_reports/coverage_evenness_two_combo_mqc.tsv",
    shell:
        """
        mkdir -p $(dirname {output});
        single_file=$( find results | grep coverage_evenness_two.tsv | head -n 1);
        if [[ "$single_file" == "" ]]; then
            echo "NO DATA FOUND" > {output.mqc};
        else
            head -n 1 $single_file > {output.mqc};
            find results | grep .coverage_evenness_two.tsv | parallel -j 1 'tail -n +2 {{}} >> {output.mqc}';
        fi;
        {latency_wait};
        ls {input};
        """