"""Rules for running SMNCopyNumberCaller."""

rule smn_copynumbercaller:
    """Call SMN1/SMN2 copy number using SMNCopyNumberCaller."""
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        summary=MDIR + "{sample}/align/{alnr}/{ddup}/htd/smn12/{sample}.{alnr}.{ddup}.smn12.summary.json",
    params:
        cluster_sample=ret_sample,
        reference=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/htd/smn12/logs/{sample}.{alnr}.{ddup}.smn12.log",
    threads: config["go_left"]["threads"]
    conda:
        "workflow/envs/smn12_v0.1.yaml"
    shell:
        """
        mkdir -p $(dirname {output.summary});
        mkdir -p $(dirname {log});
        SMNCopyNumberCaller \
            --sample-id {wildcards.sample} \
            --cram {input.cram} \
            --reference {params.reference} \
            --output-dir $(dirname {output.summary}) \
            --threads {threads} \
            > {log} 2>&1;
        if [ ! -s {output.summary} ]; then
            echo "{}" > {output.summary};
        fi;
        """

localrules: produce_smn12

rule produce_smn12:  # TARGET : Produce SMN1/SMN2 copy-number results
    input:
        expand(MDIR + "{sample}/align/{alnr}/htd/smn12/{sample}.{alnr}.smn12.summary.json", sample=SSAMPS, alnr=ALIGNERS)
    output:
        "./logs/smn12.done"
    shell:
        "touch {output}"
