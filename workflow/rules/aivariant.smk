##### AIVariant
# ---------------------------

def get_aiv_chrom(wildcards):
    pchr = ""
    ret_str = ""
    sl = wildcards.aivchrm.replace("chr", "").split("-")
    sl2 = wildcards.aivchrm.replace("chr", "").split("~")

    if len(sl2) == 2:
        ret_str = pchr + wildcards.aivchrm
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
            "aiv chunks can only be one contiguous range per chunk : ie: 1-4 with the non numerical chrms assigned 23=X, 24=Y,25=MT"
        )
    return ret_mod_chrm(ret_str)


def get_aiv_normal_cram(wildcards):
    try:
        nsamp = TN_PAIRS[wildcards.sample]
    except KeyError:
        raise ValueError(f"No matched normal sample for {wildcards.sample}")
    return MDIR + f"{nsamp}/align/{wildcards.alnr}/{nsamp}.{wildcards.alnr}.cram"


def get_aiv_normal_crai(wildcards):
    try:
        nsamp = TN_PAIRS[wildcards.sample]
    except KeyError:
        raise ValueError(f"No matched normal sample for {wildcards.sample}")
    return MDIR + f"{nsamp}/align/{wildcards.alnr}/{nsamp}.{wildcards.alnr}.cram.crai"


def get_aiv_tumor_cram(wildcards):
    return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.{wildcards.alnr}.cram"


def get_aiv_tumor_crai(wildcards):
    return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.{wildcards.alnr}.cram.crai"


rule aiv:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_cram=get_aiv_tumor_cram,
        tumor_crai=get_aiv_tumor_crai,
        normal_cram=get_aiv_normal_cram,
        normal_crai=get_aiv_normal_crai,
        d=MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/{sample}.ready",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.som.vcf",
    log:
        MDIR + "{sample}/align/{alnr}/snv/aiv/log/{sample}.{alnr}.aiv.{aivchrm}.som.log",
    threads: config['aiv']['threads'],
    container:
        config['aiv']['aiv_container'],
    priority: 45,
    resources:
        vcpu=config['aiv']['threads'],
        threads=config['aiv']['threads'],
        partition=config['aiv']['partition'],
        mem_mb=config['aiv']['mem_mb'],
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.aiv.{aivchrm}.bench.tsv",
            0 if 'bench_repeat' not in config.get('aiv', {}) else config['aiv']['bench_repeat'],
        ),
    params:
        vchrm=get_aiv_chrom,
        cluster_sample=ret_sample,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mdir=MDIR,
        mem_mb=config['aiv']['mem_mb'],
        numa=config['aiv']['numa'],
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

        vchr=$(echo {params.cpre}{params.vchrm} | sed 's/~/\\:/g' | sed 's/23\\:/X\\:/' | sed 's/24\\:/Y\\:/' | sed 's/25\\:/{params.mito_code}\\:/');

        timestamp=$(date +%Y%m%d%H%M%S)_$(head /dev/urandom | tr -dc a-zA-Z0-9 | head -c 6)

        export TMPDIR=/dev/shm/aiv_tmp_$timestamp;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap "rm -rf \"$TMPDIR\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;
        echo "VCHRM: $vchr" >> {log} 2>&1;

        {params.numa} \
        aivariant \
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


rule aiv_sort_index_chunk_vcf:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcf=MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.som.vcf",
    priority: 46,
    output:
        vcfsort=MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.som.sort.vcf",
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.som.sort.vcf.gz",
        vcftbi=MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.som.sort.vcf.gz.tbi",
    conda:
        config['aiv']['conda'],
    log:
        MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/log/{sample}.{alnr}.aiv.{aivchrm}.som.sort.vcf.gz.log",
    resources:
        vcpu=4,
        threads=4,
        partition=config['aiv'].get('partition_other', config['aiv']['partition']),
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


rule aiv_concat_index_chunks:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcfs=lambda wildcards: expand(
            MDIR + "{sample}/align/{alnr}/snv/aiv/vcfs/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.som.sort.vcf.gz",
            sample=wildcards.sample,
            alnr=wildcards.alnr,
            aivchrm=AIV_CHRMS,
        ),
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/aiv/{sample}.{alnr}.aiv.som.sort.vcf.gz",
        vcfgztbi=MDIR + "{sample}/align/{alnr}/snv/aiv/{sample}.{alnr}.aiv.som.sort.vcf.gz.tbi",
    threads: 4,
    conda:
        config['aiv']['conda'],
    log:
        MDIR + "{sample}/align/{alnr}/snv/aiv/log/{sample}.{alnr}.aiv.som.merge.log",
    shell:
        """
        bcftools concat -a -O z -o {output.vcfgz} {input.vcfs} >> {log} 2>&1;
        bcftools index -f -t {output.vcfgz} >> {log} 2>&1;
        """


rule produce_aiv_vcf:  # TARGET: aiv vcf
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcftb=expand(
            MDIR + "{sample}/align/{alnr}/snv/aiv/{sample}.{alnr}.aiv.som.sort.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
        vcftbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/aiv/{sample}.{alnr}.aiv.som.sort.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
        ),
    output:
        "gatheredall.aiv",
    threads: 4,
    priority: 48,
    log:
        "gatheredall.aiv.log",
    conda:
        "../envs/vanilla_v0.1.yaml",
    shell:
        """
        for vcf in {input.vcftb}; do
            bcf="${vcf%.vcf.gz}.bcf";
            bcftools view -O b -o $bcf --threads {threads} $vcf && bcftools index --threads 4 $bcf;
        done;

        touch {output};

        {latency_wait};
        ls {output} >> {log} 2>&1;
        {latency_wait};
        ls {output} >> {log} 2>&1;
        """


localrules:
    prep_aiv_chunkdirs,


rule prep_aiv_chunkdirs:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        b=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        i=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/snv/aiv/vcfs/{aivchrm}/{{sample}}.ready",
            aivchrm=AIV_CHRMS,
        ),
    threads: 1,
    log:
        MDIR + "{sample}/align/{alnr}/snv/aiv/log/{sample}.{alnr}.chunkdirs.log",
    shell:
        """
        ( echo {output} ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
