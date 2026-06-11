"""Rules for running SMNCopyNumberCaller."""


SMN12_GENOME_ARG = "37" if config["genome_build"] == "b37" else "38"


def smn12_cram(wildcards):
    return smn_short_cram(wildcards)


def smn12_crai(wildcards):
    return smn_short_crai(wildcards)


rule smn_copynumbercaller:
    """Call SMN1/SMN2 copy number using SMNCopyNumberCaller."""
    input:
        cram=smn12_cram,
        crai=smn12_crai,
    output:
        summary=MDIR + "{sample}/align/{alnr}/{ddup}/htd/smn12/{sample}.{alnr}.{ddup}.smn12.summary.json",
        done=MDIR + "{sample}/align/{alnr}/{ddup}/htd/smn12/{sample}.{alnr}.{ddup}.smn12.done",
    params:
        cluster_sample=ret_sample,
        reference=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        data_dir="workflow/resources/smn12",
        genome=SMN12_GENOME_ARG,
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/htd/smn12/logs/{sample}.{alnr}.{ddup}.smn12.log",
    benchmark:
        MDIR + "benchmarks/smn_copynumbercaller.{alnr}.{ddup}.{sample}.bench.tsv"
    threads: config["smn12"]["threads"]
    resources:
        partition=config["smn12"]["partition"],
        threads=config["smn12"]["threads"],
        vcpu=config["smn12"]["threads"],
        mem_mb=config["smn12"]["mem_mb"],
    conda:
        "../envs/smn12_v0.1.yaml"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.summary});
        mkdir -p $(dirname {log});
        rm -f {output.summary} {output.done}
        manifest=$(mktemp)
        smn_workdir=$(mktemp -d)
        trap 'rm -f "$manifest"; rm -rf "$smn_workdir"' EXIT
        realpath {input.cram} > "$manifest"
        test -s {params.data_dir}/SMN_region_{params.genome}.bed
        test -s {params.data_dir}/SMN_SNP_{params.genome}.txt
        test -s {params.data_dir}/SMN_target_variant_{params.genome}.txt
        test -s {params.data_dir}/SMN_gmm.txt
        cp "$(command -v smn_caller.py)" "$smn_workdir/smn_caller.py"
        ln -s "$PWD/{params.data_dir}" "$smn_workdir/data"
        "$CONDA_PREFIX/bin/python" "$smn_workdir/smn_caller.py" \
            --manifest "$manifest" \
            --genome {params.genome} \
            --outDir $(dirname {output.summary}) \
            --prefix {wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.smn12.summary \
            --reference {params.reference} \
            --threads {threads} \
            > {log} 2>&1;
        test -s {output.summary}
        "$CONDA_PREFIX/bin/python" -m json.tool {output.summary} >/dev/null
        touch {output.done}
        """

localrules: produce_smn12

rule produce_smn12:  # TARGET : Produce SMN1/SMN2 copy-number results
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/htd/smn12/{sample}.{alnr}.{ddup}.smn12.done",
            sample=SSAMPS,
            alnr=smn_short_read_aligners(),
            ddup=DDUP,
        )
    output:
        "./logs/smn12.done"
    log:
        "./logs/produce_smn12.log"
    benchmark:
        "./logs/benchmarks/produce_smn12.bench.tsv"
    shell:
        "touch {output}"
