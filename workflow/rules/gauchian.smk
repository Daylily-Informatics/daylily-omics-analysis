"""Rules for running the Gauchian GBA caller."""

rule gauchian:
    """Run the Gauchian caller on an input CRAM/CRAI pair."""
    input:
        cram=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        manifest=temp(MDIR + "{sample}/align/{alnr}/htd/gauchian/{sample}.{alnr}.gauchian.manifest"),
        results_dir=directory(MDIR + "{sample}/align/{alnr}/htd/gauchian/results/{sample}.{alnr}"),
        done=MDIR + "{sample}/align/{alnr}/htd/gauchian/{sample}.{alnr}.gauchian.done",
    params:
        cluster_sample=ret_sample,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        genome="37" if config["genome_build"] == "b37" else "38",
        prefix=lambda wildcards: f"{wildcards.sample}.{wildcards.alnr}.gauchian",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.gauchian.benchmark.tsv",
    log:
        MDIR + "{sample}/align/{alnr}/htd/gauchian/logs/gauchian.log",
    threads: config["go_left"]["threads"]
    conda:
         "workflow/envs/gba_v0.1.yaml"
    shell:
        """
        set -euo pipefail

        manifest_dir=$(dirname {output.manifest})
        log_dir=$(dirname {log})
        out_dir={output.results_dir}

        rm -rf "${{out_dir}}"
        mkdir -p "${{manifest_dir}}" "${{log_dir}}" "${{out_dir}}"

        cat <<'MANIFEST' > {output.manifest}
SampleId\tCram\tCrai
{wildcards.sample}.{wildcards.alnr}\t{input.cram}\t{input.crai}
MANIFEST

        gauchian \
            -m {output.manifest} \
            --reference {params.huref} \
            -g {params.genome} \
            -o "${{out_dir}}" \
            -p {params.prefix} \
            &> {log}

        touch {output.done}
        """


localrules: produce_gauchian

rule produce_gauchian:
    """Aggregate completion for all Gauchian runs."""
    input:
        expand(MDIR + "{sample}/align/{alnr}/htd/gauchian/{sample}.{alnr}.gauchian.done", sample=SSAMPS, alnr=ALIGNERS)
    output:
        "./logs/gauchian.done"
    shell:
        "touch {output}"


localrules: produce_all_htd

rule produce_all_htd:
    input:
        "./logs/gauchian.done",
        "./logs/smn12.done",
        "./logs/cyp2d6.done",
        "./logs/smaca.done"
    output:
        "./logs/all_htd_cmp_readsy"
    shell:
        "touch {output}"
