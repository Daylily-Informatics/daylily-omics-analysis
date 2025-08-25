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
        ref_fa=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ref_fai=lambda wc: config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
        d=MDIR + "{sample}/align/{alnr}/snv/varn/vcfs/{varnchrm}/{sample}.ready",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/snv/varn/vcfs/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.snv.vcf",
    log:
        MDIR + "{sample}/align/{alnr}/snv/varn/log/{sample}.{alnr}.varn.{varnchrm}.snv.log",
    threads: config['varn']['threads'],
    container: config['varn']['varn_container'],
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
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        numa=config['varn']['numa'],
        cpre="" if "b37" == config['genome_build'] else "chr",
        mito_code="MT" if "b37" == config['genome_build'] else "M",
    shell:
        r"""
        set -euo pipefail
        ulimit -n 65536 || true

        # Resolve region from wildcard (supports 1, 1~start~end, 23->X, 24->Y, 25->M/MT)
        vchr=$(echo {params.cpre}{params.vchrm} | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/')
        vchr=${{vchr%:}}
        IFS=':' read -r vcontig vstart vend <<< "$vchr"
        if [ -z "${{vend:-}}" ]; then
            vend=$(awk -v c="$vcontig" '$1==c{{print $2; exit}}' {input.ref_fai})
            vreg="$vcontig"
            vstart=0
        else
            vreg="$vcontig:$vstart-$vend"
        fi

        timestamp=$(date +%Y%m%d%H%M%S)_$(head -c 8 /dev/urandom | tr -dc 'a-zA-Z0-9')
        export TMPDIR=/dev/shm/varnet_tmp_$timestamp
        mkdir -p "$TMPDIR"
        trap 'rm -rf "$TMPDIR" || true' EXIT

        bed="$TMPDIR/region.bed"
        printf "%s\t%s\t%s\n" "$vcontig" "$vstart" "$vend" > "$bed"

        echo "Preflight: listing ref and fai" >> {log} 2>&1
        ls -l {input.ref_fa} {input.ref_fai} >> {log} 2>&1 || true

        # Quick CRAM sanity from INSIDE the container with the provided FASTA
        set +e
        samtools view -T {input.ref_fa} -c {input.tumor_cram} "$vreg" >> {log} 2>&1
        rc_t=$?
        samtools view -T {input.ref_fa} -c {input.normal_cram} "$vreg" >> {log} 2>&1
        rc_n=$?
        set -e

        sname="{wildcards.sample}.{wildcards.alnr}.varn.{wildcards.varnchrm}.snv"
        sname=$(echo "$sname" | tr ':~' '__')
        outbase_dir="$TMPDIR/varnet_out"

        run_varnet () {{
            {params.numa} python /VarNet/filter.py \
              --sample_name "$sname" \
              --normal_bam "$1" \
              --tumor_bam  "$2" \
              --processes  {threads} \
              --output_dir "$outbase_dir" \
              --reference  {input.ref_fa} \
              --region_bed "$bed" \
              -snv >> {log} 2>&1

            {params.numa} python /VarNet/predict.py \
              --sample_name "$sname" \
              --normal_bam "$1" \
              --tumor_bam  "$2" \
              --processes  {threads} \
              --output_dir "$outbase_dir" \
              --reference  {input.ref_fa} \
              --region_bed "$bed" \
              -snv >> {log} 2>&1
        }}

        if [ $rc_t -eq 0 ] && [ $rc_n -eq 0 ]; then
            echo "CRAM decode OK with provided FASTA; running VarNet directly on CRAMs." >> {log} 2>&1
            run_varnet "{input.normal_cram}" "{input.tumor_cram}"
        else
            echo "CRAM decode failed (rc_t=$rc_t rc_n=$rc_n). Falling back to CRAM→BAM for region $vreg." >> {log} 2>&1

            # Force htslib to use the supplied FASTA while slicing
            t_bam="$TMPDIR/tumor.$timestamp.bam"
            n_bam="$TMPDIR/normal.$timestamp.bam"

            samtools view -@ {threads} -T {input.ref_fa} -b {input.tumor_cram} "$vreg" | \
              samtools sort -@ {threads} -o "$t_bam" -  >> {log} 2>&1
            samtools index -@ {threads} "$t_bam"       >> {log} 2>&1

            samtools view -@ {threads} -T {input.ref_fa} -b {input.normal_cram} "$vreg" | \
              samtools sort -@ {threads} -o "$n_bam" -  >> {log} 2>&1
            samtools index -@ {threads} "$n_bam"       >> {log} 2>&1

            run_varnet "$n_bam" "$t_bam"
        fi

        src_vcf="$outbase_dir/$sname/$sname.vcf"
        test -s "$src_vcf"
        mkdir -p "$(dirname {output.vcf})"
        cp -f "$src_vcf" {output.vcf}
        """

rule varn_sort_index_chunk_vcf:
    wildcard_constraints:
        sample=VARNTUMORS_REGEX
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
    wildcard_constraints:
        sample=VARNTUMORS_REGEX
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
    wildcard_constraints:
        sample=VARNTUMORS_REGEX
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
    wildcard_constraints:
        sample=VARNTUMORS_REGEX
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

