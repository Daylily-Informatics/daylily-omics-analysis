"""Rules for running Cyrius CYP2D6 star-allele calling."""


rule cyrius:
    """Call CYP2D6 star alleles using Cyrius."""
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        manifest=MDIR + "{sample}/align/{alnr}/{ddup}/htd/cyrius/{sample}.{alnr}.{ddup}.cyrius.manifest",
        tsv=MDIR + "{sample}/align/{alnr}/{ddup}/htd/cyrius/{sample}.{alnr}.{ddup}.cyrius.tsv",
        json=MDIR + "{sample}/align/{alnr}/{ddup}/htd/cyrius/{sample}.{alnr}.{ddup}.cyrius.json",
        done=MDIR + "{sample}/align/{alnr}/{ddup}/htd/cyrius/{sample}.{alnr}.{ddup}.cyrius.done",
    params:
        cluster_sample=ret_sample,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        genome="37" if "b37" == config["genome_build"] else "38",
        prefix=lambda wildcards: f"{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.cyrius",
        out_dir=MDIR + "{sample}/align/{alnr}/{ddup}/htd/cyrius",
        resource_data="resources/cyrius/v0.0.0.6-jem/data",
        runtime_dir=MDIR + "{sample}/align/{alnr}/{ddup}/htd/cyrius/runtime",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.cyrius.benchmark.tsv"
    resources:
        vcpu=config["go_left"]["threads"],
        threads=config["go_left"]["threads"],
        partition=config["go_left"]["partition"],
        mem_mb=1000,
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/htd/cyrius/logs/{sample}.{alnr}.{ddup}.cyrius.log",
    threads: config["go_left"]["threads"]
    conda:
        "../envs/cyrius_v0.1.yaml"
    shell:
        """
        set -euo pipefail
        mkdir -p {params.out_dir} $(dirname {log})
        rm -f {output.tsv} {output.json} {output.done}
        realpath {input.cram} > {output.manifest}

        if [ ! -s {params.resource_data}/star_table.txt ]; then
            echo "Cyrius resource data missing at {params.resource_data}" > {log}
            exit 66
        fi

        cyrius_script=$(command -v star_caller.py)
        rm -rf {params.runtime_dir}
        mkdir -p {params.runtime_dir}
        ln -s "$cyrius_script" {params.runtime_dir}/star_caller.py
        ln -s "$PWD/{params.resource_data}" {params.runtime_dir}/data

        "$CONDA_PREFIX/bin/python" {params.runtime_dir}/star_caller.py \
            --manifest {output.manifest} \
            --genome {params.genome} \
            --reference {params.huref} \
            --prefix {params.prefix} \
            --outDir {params.out_dir} \
            --threads {threads} \
            > {log} 2>&1
        test -s {output.tsv}
        test -s {output.json}
        touch {output.done}
        """

localrules: produce_cyrius,

rule produce_cyrius:  # TARGET : Produce CYP2D6 Cyrius results
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/htd/cyrius/{sample}.{alnr}.{ddup}.cyrius.done",
            sample=SSAMPS,
            alnr=QC_CRAM_ALIGNERS,
            ddup=DDUP,
        )
    output:
        "logs/cyrius.done"
    log:
        MDIR + "logs/produce_cyrius.log"
    benchmark:
        "logs/benchmarks/produce_cyrius.bench.tsv"
    shell:
        "touch {output}"
