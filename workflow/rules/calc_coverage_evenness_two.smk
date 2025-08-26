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
        python - {params.window} {input.cram} {output.metrics} <<'PY' &> {log}
import math
import statistics
import subprocess
import sys
from pathlib import Path

window = int(sys.argv[1])
bam = Path(sys.argv[2])
outfile = Path(sys.argv[3])


def process_window(chrom, start, depths, out):
    if not depths:
        return
    n = len(depths)
    mean = sum(depths) / n
    median = statistics.median(depths)
    stdev = statistics.pstdev(depths)
    cv = stdev / mean if mean else 0.0
    even = math.exp(-cv)
    thr20 = 0.2 * mean
    thr50 = 0.5 * mean
    pct20 = sum(d >= thr20 for d in depths) / n * 100.0
    pct50 = sum(d >= thr50 for d in depths) / n * 100.0
    end = start + n
    out.write(
        f"{{chrom}}\t{{start}}\t{{end}}\t{{mean:.4f}}\t{{median:.4f}}\t{{stdev:.4f}}\t{{cv:.4f}}\t{{even:.4f}}\t{{pct20:.2f}}\t{{pct50:.2f}}\n"
    )


cmd = ["samtools", "depth", "-a", str(bam)]
proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)
current_chr = None
start_pos = None
depths = []
with outfile.open("w") as out:
    out.write("chrom\tstart\tend\tmean\tmedian\tstdev\tcv\tevenness\tpct_gt_0.2xmean\tpct_gt_0.5xmean\n")
    for line in proc.stdout:
        chrom, pos, depth = line.strip().split("\t")
        pos = int(pos)
        depth = int(depth)
        if current_chr is None:
            current_chr = chrom
            start_pos = pos
        if chrom != current_chr or len(depths) >= window:
            process_window(current_chr, start_pos, depths, out)
            depths = []
            current_chr = chrom
            start_pos = pos
        depths.append(depth)
    process_window(current_chr, start_pos, depths, out)
proc.stdout.close()
retcode = proc.wait()
if retcode != 0:
    raise RuntimeError(f"samtools depth failed with return code {{retcode}}")
PY
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