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


rule aiv_bams:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_cram=get_somcall_tumor_cram,
        tumor_crai=get_somcall_tumor_crai,
        normal_cram=get_somcall_normal_cram,
        normal_crai=get_somcall_normal_crai,
        ref_fa=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ref_fai=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        region_bed=temp(MDIR + "{sample}/align/{alnr}/snv/aiv/tmp/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.region.bed"),
        tumor_bam=temp(MDIR + "{sample}/align/{alnr}/snv/aiv/tmp/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.tumor.bam"),
        tumor_bai=temp(MDIR + "{sample}/align/{alnr}/snv/aiv/tmp/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.tumor.bam.bai"),
        normal_bam=temp(MDIR + "{sample}/align/{alnr}/snv/aiv/tmp/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.normal.bam"),
        normal_bai=temp(MDIR + "{sample}/align/{alnr}/snv/aiv/tmp/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.normal.bam.bai"),
    log:
        MDIR + "{sample}/align/{alnr}/snv/aiv/log/{sample}.{alnr}.aiv.{aivchrm}.bamify.log",
    threads: config['aiv']['threads'],
    conda: "../envs/vanilla_v0.1.yaml"
    params:
        vchrm=get_aiv_chrom,
        cpre="" if "b37" == config['genome_build'] else "chr",
        mito_code="MT" if "b37" == config['genome_build'] else "M",
    shell:
        r"""
        set -euo pipefail
        ulimit -n 65536 || true

        mkdir -p "$(dirname {output.tumor_bam})"

        # Resolve region from wildcard (supports: 1 | 1~start~end | 23->X | 24->Y | 25->M/MT)
        vchr=$(echo {params.cpre}{params.vchrm} \
              | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/')
        vchr=${{vchr%:}}
        IFS=':' read -r vcontig vstart vend <<< "$vchr"

        # Ensure FASTA index exists
        if [ ! -s {input.ref_fai} ]; then
            samtools faidx {input.ref_fa} >> {log} 2>&1
        fi

        if [ -z "${{vend:-}}" ]; then
            vstart=0
            vend=$(awk -v c="$vcontig" '$1==c{{print $2; exit}}' {input.ref_fai})
            vreg="$vcontig"
        else
            vreg="$vcontig:$vstart-$vend"
        fi

        # Emit BED (aivet uses --region_bed)
        printf "%s\t%s\t%s\n" "$vcontig" "$vstart" "$vend" > {output.region_bed}
        echo "Region: $vreg ; BED: $(cat {output.region_bed})" >> {log} 2>&1

        # Slice CRAMs to per-region, coord-sorted BAMs (forces the correct reference with -T)
        samtools view -@ {threads} -T {input.ref_fa} -b {input.tumor_cram}  "$vreg" \
          | samtools sort -@ {threads} -o {output.tumor_bam} -           >> {log} 2>&1
        samtools index -@ {threads} {output.tumor_bam}                    >> {log} 2>&1

        samtools view -@ {threads} -T {input.ref_fa} -b {input.normal_cram} "$vreg" \
          | samtools sort -@ {threads} -o {output.normal_bam} -          >> {log} 2>&1
        samtools index -@ {threads} {output.normal_bam}                   >> {log} 2>&1
        """


def approximated_bam_depth(wildcards):
    return 30  # Placeholder value


rule aiv:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        tumor_bam=MDIR + "{sample}/align/{alnr}/snv/aiv/tmp/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.tumor.bam",
        tumor_bai=MDIR + "{sample}/align/{alnr}/snv/aiv/tmp/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.tumor.bam.bai",
        normal_bam=MDIR + "{sample}/align/{alnr}/snv/aiv/tmp/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.normal.bam",
        normal_bai=MDIR + "{sample}/align/{alnr}/snv/aiv/tmp/{aivchrm}/{sample}.{alnr}.aiv.{aivchrm}.normal.bam.bai",
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
        depth=approximated_bam_depth,
        mem_mb=config['aiv']['mem_mb'],
        numa=config['aiv']['numa'],
        cpre="" if "b37" == config['genome_build'] else "chr",
        genome_build=config['genome_build'],
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

        mkdir -p $(dirname {output.vcf}) >> {log} 2>&1;
        mkdir -p $(dirname {log}) ;
        touch {log};
        touch {output.vcf};

        log_wdir=${{PWD}}/{log};
        out_wdir=${{PWD}}/$(dirname {output.vcf});

        export TMPDIR=/dev/shm/aiv_tmp_$timestamp;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap "rm -rf \"$TMPDIR\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;
        echo "VCHRM: $vchr" >> {log} 2>&1;


        cd /opt/AIVariant/AIVariant/ >> {log} 2>&1;
        
        bash run.sh \
        -i input_env \
        -e eval_env \
        -t $(realpath {input.tumor_bam}) \
        -n $(realpath {input.normal_bam}) \
        -r {params.huref} \
        -g {params.genome_build} \
        -d {params.depth} \
        -o $(realpath {output.vcf}) >> $(realpath {log}) 2>&1;

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
