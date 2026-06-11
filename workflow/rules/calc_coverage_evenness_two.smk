rule calc_coverage_evenness_two:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        metrics=MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/coverage_evenness_two/{sample}.{alnr}.{ddup}.coverage_evenness_two.tsv",
    conda:
        "../envs/coverage_evenness_two.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.coverage_evenness_two.bench.tsv"
    threads: config['calc_coverage_evenness_two']['threads']
    resources:
        vcpu=config['calc_coverage_evenness_two']['threads'],
        partition=config['calc_coverage_evenness_two']['partition'],
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/coverage_evenness_two/logs/coverage_evenness_two.log",
    params:
        window=config['calc_coverage_evenness_two'].get('window', 100000),
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail;
        mkdir -p $(dirname {output.metrics}) $(dirname {log});
        samtools depth -a {input.cram} 2> {log} | \
            bin/calc_coverage_evenness_two.py --window {params.window} > {output.metrics};
        ls {output.metrics};
    """

localrules: 
    produce_coverage_evenness_two,

rule produce_coverage_evenness_two:  # TARGET: Produce cov eveness TWO.
    input:
            metrics=expand(MDIR + "{sample}/align/{alnr}/{ddup}/alignqc/coverage_evenness_two/{sample}.{alnr}.{ddup}.coverage_evenness_two.tsv", sample=SSAMPS, alnr=QC_CRAM_ALIGNERS, ddup=DDUP)
    container: None
    threads: 8
    output:
        mqc=MDIR+"other_reports/coverage_evenness_two_combo_mqc.tsv",
    log:
        MDIR + "logs/produce_coverage_evenness_two.log"
    benchmark:
        "logs/benchmarks/produce_coverage_evenness_two.bench.tsv"
    shell:
        """
        set -euo pipefail;
        mkdir -p $(dirname {output});
        metrics_files=({input.metrics:q});
        if [[ "${{#metrics_files[@]}}" -eq 0 ]]; then
            echo "NO DATA FOUND" > {output.mqc};
        else
            first_file="${{metrics_files[0]}}";
            head -n 1 "$first_file" > {output.mqc};
            for source_path in "${{metrics_files[@]}}"; do
                tail -n +2 "$source_path" >> {output.mqc};
            done;
        fi;
        printf '%s\n' "${{metrics_files[@]}}";
        """
