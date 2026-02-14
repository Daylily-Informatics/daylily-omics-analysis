# ###### Gauchian Cyrius
#
# Cyrius Caller
# github: see conda env for link


rule cp2d6_cyrius:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        manifest=MDIR + "{sample}/align/{alnr}/htd/cyp2d6/cyp2d6_cyrius.manifest",
    params:
        cluster_sample=ret_sample,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        genome="37" if "b37" == config['genome_build'] else "38",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.96cyriusbench.tsv"
    resources:
        vcpu=config['go_left']['threads'],
        threads=config['go_left']['threads'],
        partition=config['go_left']['partition'],
        mem_mb=1000,
    log:
        MDIR + "{sample}/align/{alnr}/htd/cyp2d6/logs/cyp2d6.log",
    threads: config["go_left"]["threads"]
    conda:
         "workflow/envs/cyrius_v0.1.yaml"
    shell:
        """
	    mkdir -p $(dirname {output.manifest});
        echo "{input.cram}" >  {output.manifest};
        star_caller.py -m {output.manifest}  -g {params.genome} --reference {params.huref} -o outdir $(dirname {output.manifest}) -p {sample}.cyp2d6_cyrius  -t {threads};
        ls {output};
        """

localrules: produce_cyp2d6,
rule produce_cyp2d6:  # TARGET : Produce CYP2D6 Cyrius results
    input:
        expand(MDIR + "{sample}/align/{alnr}/htd/cyp2d6/cyp2d6_cyrius.manifest",  sample=SSAMPS, alnr=ALIGNERS)
    output:
        "./logs/cyp2d6.done"
    shell:
        """
        touch {output}
        """
