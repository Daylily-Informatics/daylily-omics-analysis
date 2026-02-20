import sys
import os

##### deepvariant roche (deep19r)
# ---------------------------
# DeepVariant 1.9 variant calling for Roche SBX Duplex pre-aligned BAMs.
# Triggered via: dy-r produce_deep19_r_vcf
#
# Uses container: directive — bind mounts handled by profile singularity-args.
#

_ALIGNERS_ROCHE_DV = ["roche"]


rule deepvariant_19_r:
    input:
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.bam",
        bai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.bam.bai",
        d=MDIR + "{sample}/align/{alnr}/{ddup}/snv/deep19r/vcfs/{dvchrm}/{sample}.ready",
    output:
        vcf=temp(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deep19r/vcfs/{dvchrm}/{sample}.{alnr}.{ddup}.deep19r.{dvchrm}.snv.vcf"),
    wildcard_constraints:
        alnr="roche",
        ddup="na",
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deep19r/log/{sample}.{alnr}.{ddup}.deep19r.{dvchrm}.snv.log",
    threads: config['deepvariant_1_9_roche']['threads']
    container:
        config['deepvariant_1_9_roche']['container']
    priority: 45
    resources:
        vcpu=config['deepvariant_1_9_roche']['threads'],
        threads=config['deepvariant_1_9_roche']['threads'],
        partition=config['deepvariant_1_9_roche']['partition'],
        mem_mb=config['deepvariant_1_9_roche']['mem_mb'],
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.deep19r.{dvchrm}.bench.tsv",
            0
            if "bench_repeat" not in config["deepvariant_1_9_roche"]
            else config["deepvariant_1_9_roche"]["bench_repeat"],
        )
    params:
        dchrm=get_dvchrm_day,
        cluster_sample=ret_sample,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mdir=MDIR,
        mem_mb=config['deepvariant_1_9_roche']['mem_mb'],
        numa=config['deepvariant_1_9_roche']['numa'],
        cpre="" if "b37" == config['genome_build'] else "chr",
        deep_threads=config['deepvariant_1_9_roche']['deep_threads'],
        mito_code="MT" if "b37" == config['genome_build'] else "M",
        deep_model=get_deep_model,
        instrument=get_instrument,
        pangenome_gbz=config["supporting_files"]["files"]["roche"]["pangenome_gbz"],
    shell:
        """
        TOKEN=$(curl -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type);
        echo "INSTANCE TYPE: $itype" > {log};

        ulimit -n 65536 || echo "ulimit mod failed" > {log} 2>&1;

        # Log the start time as 0 seconds
        start_time=$(date +%s);
        echo "Start-Time-sec:$itype\t0" >> {log} 2>&1;

        dchr=$(echo {params.cpre}{params.dchrm} | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/' );

        timestamp=$(date +%Y%m%d%H%M%S)_$(head /dev/urandom | tr -dc a-zA-Z0-9 | head -c 6)

        export TMPDIR=/fsx/tmp/deepvariant_tmp_$timestamp;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;
        echo "DCHRM: $dchr" >> {log} 2>&1;

        # --- Validate input BAM contains aligned data ---
        echo "Validating BAM: {input.bam}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.bam} >> {log} 2>&1; then
            echo "ERROR: BAM failed integrity check: {input.bam}" | tee -a {log};
            exit 10;
        fi
        _sq_count=$(samtools view -H {input.bam} 2>/dev/null | grep -c '^@SQ' || true);
        echo "BAM @SQ header count: $_sq_count" >> {log} 2>&1;
        if [ "$_sq_count" -eq 0 ]; then
            echo "ERROR: BAM has no @SQ headers (unaligned?): {input.bam}" | tee -a {log};
            exit 11;
        fi
        echo "BAM validation passed ($_sq_count reference sequences)" >> {log} 2>&1;

        {params.numa} \
        /opt/deepvariant/bin/run_pangenome_aware_deepvariant \
        --model_type={params.deep_model} --ref={params.huref} \
        --reads={input.bam} \
        --pangenome={params.pangenome_gbz} \
        --regions=$dchr \
        --output_vcf={output.vcf} \
        --num_shards={params.deep_threads} \
        --gbz_shared_memory_size_gb=50 \
        --logging_dir=$(dirname {log}) \
        --customized_model resources/model/model.ckpt \
        --make_examples_extra_args="alt_aligned_pileup=single_row,create_complex_alleles=true,enable_strict_insertion_filter=true,keep_legacy_allele_counter_behavior=true,keep_only_window_spanning_haplotypes=true,keep_supplementary_alignments=true,min_mapping_quality=0,normalize_reads=true,pileup_image_height_pangenome=100,pileup_image_height_reads=100,pileup_image_width=301,sort_by_haplotypes=true,trim_reads_for_pileup=true,vsc_min_fraction_indels=0.08,ws_min_base_quality=25" \
        --postprocess_variants_extra_args="multiallelic_mode=product" \
        --dry_run=false >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));

        # Log the elapsed time
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;
        """



rule deep19_r_sort_index_chunk_vcf:
    input:
        vcf=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deep19r/vcfs/{dvchrm}/{sample}.{alnr}.{ddup}.deep19r.{dvchrm}.snv.vcf",
    wildcard_constraints:
        alnr="roche",
        ddup="na",
    priority: 46
    output:
        vcfsort=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deep19r/vcfs/{dvchrm}/{sample}.{alnr}.{ddup}.deep19r.{dvchrm}.snv.sort.vcf",
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deep19r/vcfs/{dvchrm}/{sample}.{alnr}.{ddup}.deep19r.{dvchrm}.snv.sort.vcf.gz",
        vcftbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deep19r/vcfs/{dvchrm}/{sample}.{alnr}.{ddup}.deep19r.{dvchrm}.snv.sort.vcf.gz.tbi",
    conda:
        config['deepvariant_1_9_roche']['conda']
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deep19r/vcfs/{dvchrm}/log/{sample}.{alnr}.{ddup}.deep19r.{dvchrm}.snv.sort.vcf.gz.log",
    resources:
        vcpu=4,
        threads=4,
        partition=config['deepvariant_1_9_roche']['partition_other'],
    params:
        cluster_sample=ret_sample,
    threads: 4
    shell:
        """
        bedtools sort -header -i {input.vcf} > {output.vcfsort} 2>> {log};

        bgzip {output.vcfsort} >> {log} 2>&1;
        touch {output.vcfsort};

        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1;

        """


rule deep19_r_concat_fofn:
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/deep19r/vcfs/{dvchm}/{{sample}}.{{alnr}}.{{ddup}}.deep19r.{dvchm}.snv.sort.vcf.gz.tbi",
                dvchm=DEEP19R_CHRMS,
            ),
            key=lambda x: float(
                str(x.replace("~", ".").replace(":", "."))
                .split("vcfs/")[1]
                .split("/")[0]
                .split("-")[0]
            ),
        ),
    wildcard_constraints:
        alnr="roche",
        ddup="na",
    priority: 44
    output:
        fin_fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deep19r/{sample}.{alnr}.{ddup}.deep19r.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deep19r/{sample}.{alnr}.{ddup}.deep19r.snv.concat.vcf.gz.fofn.tmp",
    threads: 2
    resources:
        vcpu=2,
        threads=2,
        partition="i192,i192mem",
    params:
        fn_stub="{sample}.{alnr}.{ddup}.deep19r.",
        cluster_sample=ret_sample,
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.deep19r.concat.fofn.bench.tsv"
    conda:
        config['deepvariant_1_9_roche']['conda']
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/deep19r/log/{sample}.{alnr}.{ddup}.deep19r.concat.fofn.log",
    shell:
        """

        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\.tbi$//g'; );
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.deep19r. {output.fin_fofn}) >> {log} 2>&1;

        """


rule deep19_r_concat_index_chunks:
    input:
        fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deep19r/{sample}.{alnr}.{ddup}.deep19r.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deep19r/{sample}.{alnr}.{ddup}.deep19r.snv.concat.vcf.gz.fofn.tmp",
    output:
        vcfgz=touch(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/deep19r/{sample}.{alnr}.{ddup}.deep19r.snv.sort.vcf.gz"
        ),
        vcfgztemp=temp(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/deep19r/{sample}.{alnr}.{ddup}.deep19r.snv.sort.temp.vcf.gz"
        ),
        vcfgztbi=touch(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/deep19r/{sample}.{alnr}.{ddup}.deep19r.snv.sort.vcf.gz.tbi"
        ),
    wildcard_constraints:
        alnr="roche",
        ddup="na",
    threads: 4
    resources:
        vcpu=4,
        threads=4,
        partition=config['deepvariant_1_9_roche']['partition_other'],
    priority: 47
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    resources:
        attempt_n=lambda wildcards, attempt: (attempt + 0)
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.deep19r.merge.bench.tsv"
    conda:
        config['deepvariant_1_9_roche']['conda']
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deep19r/log/{sample}.{alnr}.{ddup}.deep19r.snv.merge.sort.gathered.log",
    shell:
        """

        touch {log};
        mkdir -p $(dirname {log});

        bcftools concat -a -d all --threads {threads} -f {input.fofn}  -O z -o {output.vcfgztemp} >> {log} 2>&1;

        export oldname=$(bcftools query -l {output.vcfgztemp} | head -n1) >> {log} 2>&1;
        echo -e "${{oldname}}\t{params.cluster_sample}" > {output.vcfgz}.rename.txt
        bcftools reheader -s {output.vcfgz}.rename.txt -o {output.vcfgz} {output.vcfgztemp} >> {log} 2>&1;
        bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;

        rm -rf $(dirname {output.vcfgz})/vcfs >> {log} 2>&1;

        """


rule clear_combined_deep19_r_vcf:  # TARGET: clear combined deep19r vcf so chunks can be re-evaluated
    input:
        vcf=expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/deep19r/{sample}.{alnr}.{ddup}.deep19r.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=_ALIGNERS_ROCHE_DV,
            ddup=["na"],
        ),
    priority: 42
    conda:
        config['deepvariant_1_9_roche']['conda']
    resources:
        vcpu=2,
        threads=2,
        partition="i192,i192mem",
    shell:
        "(rm {input.vcf}*   1> /dev/null  2> /dev/null ) || echo 'file not found for deletion: {input}';"


rule produce_deep19_r_vcf:  # TARGET: DeepVariant 1.9 Roche VCF
    input:
        vcftb=expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/deep19r/{sample}.{alnr}.{ddup}.deep19r.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=_ALIGNERS_ROCHE_DV,
            ddup=["na"],
        ),
        vcftbi=expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/deep19r/{sample}.{alnr}.{ddup}.deep19r.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=_ALIGNERS_ROCHE_DV,
            ddup=["na"],
        ),
    output:
        "gatheredall.deep19r",
    threads: 4
    params:
	cluster_sample=ret_sample,
    priority: 48
    log:
        "gatheredall.deep19r.log",
    conda:
        config['deepvariant_1_9_roche']['conda']
    shell:
        """
        # Convert VCF to BCF and index it
        for vcf in {input.vcftb}; do
            bcf="${{vcf%.vcf.gz}}.bcf";
            bcftools view -O b -o $bcf --threads {threads} $vcf && bcftools index --threads 4 $bcf;
        done;

        # Mark the output as completed
        touch {output};

        # Log completion and list output
        ls {output} >> {log} 2>&1;
        """


localrules:
    prep_deep19_r_chunkdirs,
    produce_deep19_r_vcf,


rule prep_deep19_r_chunkdirs:
    input:
        b=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.bam",
        i=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.bam.bai",
    wildcard_constraints:
        alnr="roche",
        ddup="na",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/deep19r/vcfs/{dvchrm}/{{sample}}.ready",
            dvchrm=DEEP19R_CHRMS,
        ),
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/deep19r/log/{sample}.{alnr}.{ddup}.chunkdirs.log",
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """

