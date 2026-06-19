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


# --- produce per-region temporary BAMs from CRAMs for VarNet ---
rule varn_bams:
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
        region_bed=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/tmp/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.region.bed"),
        tumor_bam=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/tmp/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.tumor.bam"),
        tumor_bai=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/tmp/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.tumor.bam.bai"),
        normal_bam=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/tmp/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.normal.bam"),
        normal_bai=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/tmp/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.normal.bam.bai"),
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/log/{sample}.{alnr}.varn.{varnchrm}.bamify.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{varnchrm}.varn_bams.bench.tsv"
    threads: config['varn']['threads'],
    conda: "../envs/vanilla_v0.1.yaml"
    params:
        vchrm=get_varn_chrom,
        cluster_sample=ret_sample,
        cpre="" if "b37" == config['genome_build'] else "chr",
        mito_code="MT" if "b37" == config['genome_build'] else "M",
    shell:
        r"""
        set -euo pipefail
        ulimit -n 65536 || true

        mkdir -p "$(dirname {output.tumor_bam})"

        # --- Validate tumor CRAM contains aligned data ---
        echo "Validating tumor CRAM: {input.tumor_cram}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.tumor_cram} >> {log} 2>&1; then
            echo "ERROR: Tumor CRAM failed integrity check: {input.tumor_cram}" | tee -a {log};
            exit 10;
        fi
        _sq_count=$(samtools view -H {input.tumor_cram} 2>/dev/null | grep -c '^@SQ' || true);
        echo "Tumor CRAM @SQ header count: $_sq_count" >> {log} 2>&1;
        if [ "$_sq_count" -eq 0 ]; then
            echo "ERROR: Tumor CRAM has no @SQ headers (unaligned?): {input.tumor_cram}" | tee -a {log};
            exit 11;
        fi
        echo "Tumor CRAM validation passed ($_sq_count reference sequences)" >> {log} 2>&1;

        # --- Validate normal CRAM contains aligned data ---
        echo "Validating normal CRAM: {input.normal_cram}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.normal_cram} >> {log} 2>&1; then
            echo "ERROR: Normal CRAM failed integrity check: {input.normal_cram}" | tee -a {log};
            exit 12;
        fi
        _sq_count=$(samtools view -H {input.normal_cram} 2>/dev/null | grep -c '^@SQ' || true);
        echo "Normal CRAM @SQ header count: $_sq_count" >> {log} 2>&1;
        if [ "$_sq_count" -eq 0 ]; then
            echo "ERROR: Normal CRAM has no @SQ headers (unaligned?): {input.normal_cram}" | tee -a {log};
            exit 13;
        fi
        echo "Normal CRAM validation passed ($_sq_count reference sequences)" >> {log} 2>&1;

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

        # Emit BED (VarNet uses --region_bed)
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


# --- run VarNet on the temporary BAMs ---
rule varn:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        region_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/tmp/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.region.bed",
        tumor_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/tmp/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.tumor.bam",
        tumor_bai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/tmp/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.tumor.bam.bai",
        normal_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/tmp/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.normal.bam",
        normal_bai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/tmp/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.normal.bam.bai",
        d=MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/vcfs/{varnchrm}/{sample}.ready",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/vcfs/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.snv.vcf",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/log/{sample}.{alnr}.varn.{varnchrm}.snv.log",
    threads: config['varn']['threads'],
    container: config['varn']['varn_container'],
    priority: 45,
    resources:
        vcpu=config['varn']['threads'],
        threads=config['varn']['threads'],
        partition=derive_partition_order(config['varn']['partition']),
        mem_mb=config['varn']['mem_mb'],
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.varn.{varnchrm}.bench.tsv",
            0 if 'bench_repeat' not in config.get('varn', {}) else config['varn']['bench_repeat'],
        ),
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
        numa=config['varn']['numa'],   # e.g., "numactl --interleave=all" or ""
    shell:
        r"""
        set -euo pipefail
        ulimit -n 65536 || true

        timestamp=$(date +%Y%m%d%H%M%S)_$(head -c 12 /dev/urandom | tr -dc 'a-zA-Z0-9')
        export TMPDIR=/dev/shm/varnet_tmp_$timestamp
        mkdir -p "$TMPDIR"
        export APPTAINER_HOME="$TMPDIR"
        trap 'rm -rf "$TMPDIR" || true' EXIT

        sname="{wildcards.sample}.{wildcards.alnr}.varn.{wildcards.varnchrm}.snv"
        sname=$(echo "$sname" | tr ':~' '__')
        outbase_dir="$TMPDIR/varnet_out"

        echo "Using region bed: {input.region_bed}" >> {log} 2>&1

        # VarNet: filter -> predict (SNVs only)
        {params.numa} python /VarNet/filter.py \
          --sample_name "$sname" \
          --normal_bam {input.normal_bam} \
          --tumor_bam  {input.tumor_bam} \
          --processes  {threads} \
          --output_dir "$outbase_dir" \
          --reference  {params.huref} \
          --region_bed {input.region_bed} \
          -indel \
          -snv >> {log} 2>&1

        {params.numa} python /VarNet/predict.py \
          --sample_name "$sname" \
          --normal_bam {input.normal_bam} \
          --tumor_bam  {input.tumor_bam} \
          --processes  {threads} \
          --output_dir "$outbase_dir" \
          --reference  {params.huref} \
          -indel \
          -snv >> {log} 2>&1

        src_vcf="$outbase_dir/$sname/$sname.vcf"
        test -s "$src_vcf"
        mkdir -p "$(dirname {output.vcf})"
        cp -f "$src_vcf" {output.vcf}
        """



rule varn_sort_index_chunk_vcf:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcf=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/varn/vcfs/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.snv.vcf",
    priority: 46,
    output:
        vcfsort=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/varn/vcfs/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.snv.sort.vcf",
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/varn/vcfs/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.snv.sort.vcf.gz",
        vcftbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/varn/vcfs/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.snv.sort.vcf.gz.tbi",
    conda:
        config['varn']['conda'],
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/varn/vcfs/{varnchrm}/log/{sample}.{alnr}.varn.{varnchrm}.snv.sort.vcf.gz.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{varnchrm}.varn_sort_index_chunk_vcf.bench.tsv"
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
        sample=TUMORS_REGEX
    input:
        vcfs=lambda wildcards: expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/vcfs/{varnchrm}/{sample}.{alnr}.varn.{varnchrm}.snv.sort.vcf.gz",
            sample=wildcards.sample,
            alnr=wildcards.alnr,
            ddup=wildcards.ddup,
            varnchrm=VARN_CHRMS,
        ),
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/{sample}.{alnr}.varn.snv.sort.vcf.gz",
        vcfgztbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/varn/{sample}.{alnr}.varn.snv.sort.vcf.gz.tbi",
    threads: 4,
    params:
        cluster_sample=ret_sample,
    conda:
        config['varn']['conda'],
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/log/{sample}.{alnr}.varn.snv.merge.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.varn_concat_index_chunks.bench.tsv"
    shell:
        """
        bcftools concat -a -O z -o {output.vcfgz} {input.vcfs} >> {log} 2>&1;
        bcftools index -f -t {output.vcfgz} >> {log} 2>&1;
        """


rule produce_varn_vcf:  # TARGET: varn vcf
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        vcftb=expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/varn/{sample}.{alnr}.varn.snv.sort.vcf.gz",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
            ddup=DDUP,
        ),
        vcftbi=expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/varn/{sample}.{alnr}.varn.snv.sort.vcf.gz.tbi",
            sample=TN_TUMOR_SAMPS,
            alnr=ALIGNERS,
            ddup=DDUP,
        ),
    output:
        "gatheredall.varn",
    threads: 4,
    priority: 48,
    log:
        "gatheredall.varn.log",
    benchmark:
        "logs/benchmarks/produce_varn_vcf.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml",
    params:
        cluster_sample=ret_sample,
    shell:
        """
        for vcf in {input.vcftb}; do
            bcf="${{vcf%.vcf.gz}}.bcf";
            bcftools view -O b -o $bcf --threads {threads} $vcf && bcftools index --threads 4 $bcf;
        done;

        touch {output};

        ls {output} >> {log} 2>&1;
        ls {output} >> {log} 2>&1;
        """


localrules:
    prep_varn_chunkdirs,


rule prep_varn_chunkdirs:
    wildcard_constraints:
        sample=TUMORS_REGEX
    input:
        b=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        i=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/varn/vcfs/{varnchrm}/{{sample}}.ready",
            varnchrm=VARN_CHRMS,
        ),
    threads: 1,
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/varn/log/{sample}.{alnr}.chunkdirs.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.prep_varn_chunkdirs.bench.tsv"
    params:
        cluster_sample=ret_sample,
    shell:
        """
        ( echo {output} ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
