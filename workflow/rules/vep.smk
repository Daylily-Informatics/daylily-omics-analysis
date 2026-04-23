0#### ENSEMBL VEP
# -------------------------------------
# github: https://github.com/Ensembl/ensembl-vep
# docker: https://hub.docker.com/r/ensemblorg/ensembl-vep:release_109.3


rule vep:
    input:
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/{sample}.{alnr}.{ddup}.{snv}.snv.sort.vcf.gz",
    output:
        ovcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.vcf",
        done=touch(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.done"),
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/log/{sample}.{alnr}.{ddup}.{snv}.vep.log",
    threads: config["vep"]["threads"]
    resources:
        vcpu=config["vep"]["threads"],
        partition=config["vep"]["partition"],
        threads=config["vep"]["threads"],
    params:
        cluster_sample=ret_sample,
        genome_build="GRCh37" if 'b37' in config['genome_build'] else "GRCh38",
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        vep_cache=config["supporting_files"]["files"]["vep"]["vep_cache"]['name'],
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{snv}.vep.bench.tsv"
    container:
        "docker://ensemblorg/ensembl-vep:release_114.2"        
    shell:
        """
        vep \
        --dir {params.vep_cache} \
        --offline \
        --vcf \
        --cache {params.vep_cache} \
        --input_file {input.vcfgz} \

        --fork 64 \
        --fasta {params.huref} \
        --species homo_sapiens \
        --assembly GRCh38 \
        --output_file {output.ovcfgz} \
        --force_overwrite --everything \
        --hgvs \
        --symbol \
        --protein \
        --freq_pop \
        --terms \
        --variant_class \
        --compress_output bgzip >> {log} 2>&1;\
        """

localrules:
    produce_vep,


rule produce_vep:  # TARGET: just produce vep results
    input:
        [
            MDIR
            + f"{sample}/align/{alnr}/{ddup}/snv/{snv}/vep/{sample}.{alnr}.{ddup}.{snv}.vep.done"
            for sample in SSAMPS
            for ddup in DDUP
            for alnr, snv in valid_snv_alnr_pairs(ALIGNERS, snv_CALLERS)
        ],
    output:
        "logs/vep_gathered.done",
    shell:
        "touch {output};"
