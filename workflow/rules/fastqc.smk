import os

# #### fastqc
# -----------
# github: https://github.com/s-andrews/FastQC


rule fastqc_subsampled:
    input:
        fqr1s=get_raw_fastq_qc_R1s,
        fqr2s=get_raw_fastq_qc_R2s,
    output:
        f"{MDIR}" + "{sample}/seqqc/fastqc/{sample}.fastqc.done",
    benchmark:
        f"{MDIR}" + "{sample}/benchmarks/{sample}.fastqc.bench.tsv"
    threads: config["fastqc"]["threads"]
    resources:
        vcpu=config["fastqc"]["threads"],
        partition=config['fastqc']['partition'],
    params:
        tmp=f"{MDIR}" + "{sample}/seqqc/fastqc/tmp",
        tool_dir=f"{MDIR}" + "{sample}/seqqc/fastqc",
        input_dir=f"{MDIR}" + "{sample}/seqqc/fastqc/input",
        r1_link=f"{MDIR}" + "{sample}/seqqc/fastqc/input/{sample}.R1.fastq.gz",
        r2_link=f"{MDIR}" + "{sample}/seqqc/fastqc/input/{sample}.R2.fastq.gz",
        cluster_sample=ret_sample,
        subsample_pct="0.25" if 'subsample_pct' not in config['fastqc'] else config['fastqc']['subsample_pct'],
    log:
        f"{MDIR}" + "{sample}/logs/fastqc/{sample}.fastqc.log",
    conda:
        config["fastqc"]["env_yaml"]
    shell:
        """
        rm -rf {params.tool_dir:q} ;
        mkdir -p {params.tool_dir:q} ;
        mkdir -p {params.tmp:q} ;
        mkdir -p {params.input_dir:q} ;
        r1_inputs=({input.fqr1s:q})
        r2_inputs=({input.fqr2s:q})
        if [[ "${{#r1_inputs[@]}}" -eq 0 && "${{#r2_inputs[@]}}" -eq 0 ]]; then
            printf 'SKIP: fastqc_subsampled found no paired FASTQ inputs for %s; likely CRAM/BAM-only or manifest FASTQ path is na.\n' "{wildcards.sample}" > {log:q}
            touch {output:q}
            exit 0
        fi
        if [[ "${{#r1_inputs[@]}}" -ne 1 || "${{#r2_inputs[@]}}" -ne 1 ]]; then
            printf 'fastqc_subsampled expects exactly one R1 and one R2 for %s; got R1=%s R2=%s\n' "{wildcards.sample}" "${{#r1_inputs[@]}}" "${{#r2_inputs[@]}}" >&2
            exit 1
        fi
        ln -sfn "$(realpath "${{r1_inputs[0]}}")" {params.r1_link:q}
        ln -sfn "$(realpath "${{r2_inputs[0]}}")" {params.r2_link:q}
        #fastqc -o {params.tool_dir} -t {threads} -d {params.tmp}  <(seqkit sample --proportion {params.subsample_pct} <(seqfu interleave -1 <(unpigz -c -q -- {input.fqr1s}) -2 <(unpigz -c -q -- {input.fqr2s}) ) )  ;
        fastqc -o {params.tool_dir:q} -t {threads} -d {params.tmp:q} {params.r1_link:q} {params.r2_link:q}
        rm -f {params.r1_link:q} {params.r2_link:q}
        touch {output};
        touch {output}_subsampled_at_{params.subsample_pct};
        ls {output};
        """
localrules:
    just_fastqc,


rule just_fastqc:
    input:
        expand(MDIR + "{sample}/seqqc/fastqc/{sample}.fastqc.done", sample=FASTQ_QC_SAMPS),
    output:
        "fqc.done",
    threads: 1
    shell:
        "touch {output}"
