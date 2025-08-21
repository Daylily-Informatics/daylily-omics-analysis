##### VarNet
# ---------------------------


def get_varn_chrom(wildcards):
    pchr = ""
    ret_str = ""
    sl = wildcards.varnchrm.replace("chr", "").split("-")
    sl2 = wildcards.varnchrm.replace("chr", "").split("~")

    if len(sl2) == 2:
        ret_str = pchr + wildcards.varnchrm
    elif len(sl) == 1:
        ret_str = pchr + sl[0]
    elif len(sl) == 2:
        start = int(sl[0])
        end = int(sl[1])
        while start <= end:
            ret_str = str(ret_str) + " " + pchr + str(start)
            start = start + 1
    else:
        raise Exception(
            "varn chunks can only be one contiguous range per chunk : ie: 1-4 with the non numerical chrms assigned 23=X, 24=Y, 25=MT"
        )
    return ret_mod_chrm(ret_str)


def get_varn_normal_cram(wildcards):
    try:
        nsamp = TN_PAIRS[wildcards.sample]
    except KeyError:
        raise ValueError(f"No matched normal sample for {wildcards.sample}")
    return MDIR + f"{nsamp}/align/{wildcards.alnr}/{nsamp}.{wildcards.alnr}.cram"


def get_varn_normal_crai(wildcards):
    try:
        nsamp = TN_PAIRS[wildcards.sample]
    except KeyError:
        raise ValueError(f"No matched normal sample for {wildcards.sample}")
    return MDIR + f"{nsamp}/align/{wildcards.alnr}/{nsamp}.{wildcards.alnr}.cram.crai"

def get_varn_tumor_cram(wildcards):
    return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.{wildcards.alnr}.cram"

def get_varn_tumor_crai(wildcards):
    return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.{wildcards.alnr}.cram.crai"

rule varn:
    wildcard_constraints:
        sample=VARNTUMORS_REGEX
    input:
        tumor_cram=get_varn_tumor_cram,
        tumor_crai=get_varn_tumor_crai,
        normal_cram=get_varn_normal_cram,
        normal_crai=get_varn_normal_crai,
        d=MDIR + "{sample}/align/{alnr}/snv/varn/vcfs/{varnchrm}/{sample}.ready",
    output:
        vcf=MDIR
        + "{sample}/align/{alnr}/snv/varn/vcfs/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.snv.vcf",
    log:
        MDIR + "{sample}/align/{alnr}/snv/varn/log/{sample}.{alnr}.varn.{varnchrm}.snv.log",
    threads: config['varn']['threads'],
    container:
        config['varn']['varn_container'],
    priority: 45,
    resources:
        vcpu=config['varn']['threads'],
        threads=config['varn']['threads'],
        partition=config['varn']['partition'],
        mem_mb=config['varn']['mem_mb'],
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.varn.{varnchrm}.bench.tsv",
            0 if 'bench_repeat' not in config.get('varn', {}) else config['varn']['bench_repeat'],
        ),
    params:
        vchrm=get_varn_chrom,
        cluster_sample=ret_sample,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mdir=MDIR,
        mem_mb=config['varn']['mem_mb'],
        numa=config['varn']['numa'],
        cpre="" if "b37" == config['genome_build'] else "chr",
        mito_code="MT" if "b37" == config['genome_build'] else "M",
    shell:
        """
        TOKEN=$(curl -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type);
        echo "INSTANCE TYPE: $itype" > {log};

        ulimit -n 65536 || echo "ulimit mod failed" > {log} 2>&1;

        start_time=$(date +%s);
        echo "Start-Time-sec:$itype\t0" >> {log} 2>&1;

        vchr=$(echo {params.cpre}{params.vchrm} | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/' );

        timestamp=$(date +%Y%m%d%H%M%S)_$(head /dev/urandom | tr -dc a-zA-Z0-9 | head -c 6)

        export TMPDIR=/dev/shm/varnet_tmp_$timestamp;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap "rm -rf \"$TMPDIR\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;
        echo "VCHRM: $vchr" >> {log} 2>&1;

        {params.numa} \
        varnet \
        --ref {params.huref} \
        --tumor {input.tumor_cram} \
        --normal {input.normal_cram} \
        --regions $vchr \
        --threads {threads} \
        --out_vcf {output.vcf} >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));

        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;
        """


rule varn_sort_index_chunk_vcf:
    input:
        vcf=MDIR
        + "{sample}/align/{alnr}/snv/varn/vcfs/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.snv.vcf",
    priority: 46,
    output:
        vcfsort=MDIR
        + "{sample}/align/{alnr}/snv/varn/vcfs/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.snv.sort.vcf",
        vcfgz=MDIR
        + "{sample}/align/{alnr}/snv/varn/vcfs/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.snv.sort.vcf.gz",
        vcftbi=MDIR
        + "{sample}/align/{alnr}/snv/varn/vcfs/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.snv.sort.vcf.gz.tbi",
    conda:
        config['varn']['conda'],
    log:
        MDIR
        + "{sample}/align/{alnr}/snv/varn/vcfs/{varnchrm}/log/{sample}.{alnr}.varn.{varnchrm}.snv.sort.vcf.gz.log",
    resources:
        vcpu=4,
        threads=4,
        partition=config['varn'].get('partition_other', config['varn']['partition']),
    params:
        cluster_sample=ret_sample,
    threads: 4,
    shell:
        """
        bedtools sort -header -i {input.vcf} > {output.vcfsort} 2>> {log};

        bgzip {output.vcfsort} >> {log} 2>&1;
        touch {output.vcfsort};
        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1;
        """


rule varn_concat_index_chunks:
    input:
        vcfs=lambda wildcards: expand(
            MDIR + "{sample}/align/{alnr}/snv/varn/vcfs/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.snv.sort.vcf.gz",
            sample=wildcards.sample,
            alnr=wildcards.alnr,
            varnchrm=VARN_CHRMS,
        ),
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/varn/{sample}.{alnr}.varn.snv.sort.vcf.gz",
        vcfgztbi=MDIR
        + "{sample}/align/{alnr}/snv/varn/{sample}.{alnr}.varn.snv.sort.vcf.gz.tbi",
    threads: 4,
    conda:
        config['varn']['conda'],
    log:
        MDIR + "{sample}/align/{alnr}/snv/varn/log/{sample}.{alnr}.varn.snv.merge.log",
    shell:
        """
        bcftools concat -a -O z -o {output.vcfgz} {input.vcfs} >> {log} 2>&1;
        bcftools index -f -t {output.vcfgz} >> {log} 2>&1;
        """


rule produce_varn_vcf:  # TARGET: varn vcf
    input:
        vcftb=expand(
            MDIR
            + "{sample}/align/{alnr}/snv/varn/{sample}.{alnr}.varn.snv.sort.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        vcftbi=expand(
            MDIR
            + "{sample}/align/{alnr}/snv/varn/{sample}.{alnr}.varn.snv.sort.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
    output:
        "gatheredall.varn",
    threads: 4,
    priority: 48,
    log:
        "gatheredall.varn.log",
    conda:
        "../envs/vanilla_v0.1.yaml",
    shell:
        """
        for vcf in {input.vcftb}; do
            bcf="${{vcf%.vcf.gz}}.bcf";
            bcftools view -O b -o $bcf --threads {threads} $vcf && bcftools index --threads 4 $bcf;
        done;

        touch {output};

        {latency_wait};
        ls {output} >> {log} 2>&1;
        {latency_wait};
        ls {output} >> {log} 2>&1;
        """


localrules:
    prep_varn_chunkdirs,


rule prep_varn_chunkdirs:
    input:
        b=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        i=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/snv/varn/vcfs/{varnchrm}/{{sample}}.ready",
            varnchrm=VARN_CHRMS,
        ),
    threads: 1,
    log:
        MDIR + "{sample}/align/{alnr}/snv/varn/log/{sample}.{alnr}.chunkdirs.log",
    shell:
        """
        ( echo {output} ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """

