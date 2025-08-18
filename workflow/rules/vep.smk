0#### ENSEMBL VEP
# -------------------------------------
# github: https://github.com/Ensembl/ensembl-vep
# docker: https://hub.docker.com/r/ensemblorg/ensembl-vep:release_109.3


rule vep:
    input:
        vcfgz=MDIR
        + "{sample}/align/{alnr}/snv/{snv}/{sample}.{alnr}.{snv}.snv.sort.vcf.gz",
    output:
        ovcfgz=MDIR
        + "{sample}/align/{alnr}/snv/{snv}/vep/{sample}.{alnr}.{snv}.vep.vcf",
        done=touch(MDIR
        + "{sample}/align/{alnr}/snv/{snv}/vep/{sample}.{alnr}.{snv}.vep.done"),
    log:
        MDIR
        + "{sample}/align/{alnr}/snv/{snv}/vep/log/{sample}.{alnr}.{snv}.vep.log",
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
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{snv}.vep.bench.tsv"
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
        expand(
            MDIR
            + "{sample}/align/{alnr}/snv/{snv}/vep/{sample}.{alnr}.{snv}.vep.done",
            sample=SSAMPS,
            alnr=ALIGNERS,
            snv=snv_CALLERS,
        ),
    output:
        "logs/vep_gathered.done",
    shell:
        "touch {output};"
