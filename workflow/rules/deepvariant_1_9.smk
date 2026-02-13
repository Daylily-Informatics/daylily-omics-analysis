import sys
import os

##### deepvariant
# ---------------------------
#
 

rule deepvariant_19:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
        d=MDIR + "{sample}/align/{alnr}/snv/deep19/vcfs/{dvchrm}/{sample}.ready",
    output:
        vcf=temp(MDIR
        + "{sample}/align/{alnr}/snv/deep19/vcfs/{dvchrm}/{sample}.{alnr}.deep19.{dvchrm}.snv.vcf"),
        #gvcf=temp(MDIR + "{sample}/align/{alnr}/snv/deep19/vcfs/{dvchrm}/{sample}.{alnr}.deep19.{dvchrm}.snv.g.vcf"),
    log:
        MDIR
        + "{sample}/align/{alnr}/snv/deep19/log/{sample}.{alnr}.deep19.{dvchrm}.snv.log",
    threads: config['deepvariant']['threads']
    container:
        config['deepvariant']['deep19_container'] 
    priority: 45
    resources:
        vcpu=config['deepvariant']['threads'],
        threads=config['deepvariant']['threads'],
        partition=config['deepvariant']['partition'],
        mem_mb=config['deepvariant']['mem_mb'],
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.deep19.{dvchrm}.bench.tsv",
            0
            if "bench_repeat" not in config["deepvariant"]
            else config["deepvariant"]["bench_repeat"],
        )
    params:
        dchrm=get_dvchrm_day,
        cluster_sample=ret_sample, #
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mdir=MDIR,
        mem_mb=config['deepvariant']['mem_mb'],
        numa=config['deepvariant']['numa'],
        cpre="" if "b37" == config['genome_build'] else "chr",
        deep_threads=config['deepvariant']['deep_threads'],
        mito_code="MT" if "b37" == config['genome_build'] else "M",
        deep_model=get_deep_model, # ultima and ILMN, use WGS or WES. PacBio PACBIO, on ONT_R104
        instrument=get_instrument, 
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

        export TMPDIR=/dev/shm/deepvariant_tmp_$timestamp;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap "rm -rf \"$TMPDIR\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;
        echo "DCHRM: $dchr" >> {log} 2>&1;

        # --- Validate input CRAM contains aligned data ---
        echo "Validating CRAM: {input.cram}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.cram} >> {log} 2>&1; then
            echo "ERROR: CRAM failed integrity check: {input.cram}" | tee -a {log};
            exit 10;
        fi
        _sq_count=$(samtools view -H {input.cram} 2>/dev/null | grep -c '^@SQ' || true);
        echo "CRAM @SQ header count: $_sq_count" >> {log} 2>&1;
        if [ "$_sq_count" -eq 0 ]; then
            echo "ERROR: CRAM has no @SQ headers (unaligned?): {input.cram}" | tee -a {log};
            exit 11;
        fi
        echo "CRAM validation passed ($_sq_count reference sequences)" >> {log} 2>&1;

        {params.numa} \
        /opt/deepvariant/bin/run_deepvariant \
        --model_type={params.deep_model} --ref={params.huref} \
        --reads={input.cram} \
        --regions=$dchr \
        --output_vcf={output.vcf} \
        --num_shards={params.deep_threads} \
        --logging_dir=$(dirname {log}) \
        --dry_run=false >> {log} 2>&1;  

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));

        # Log the elapsed time
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;
        """



rule deep19_sort_index_chunk_vcf:
    input:
        vcf=MDIR
        + "{sample}/align/{alnr}/snv/deep19/vcfs/{dvchrm}/{sample}.{alnr}.deep19.{dvchrm}.snv.vcf",
    priority: 46
    output:
        vcfsort=MDIR
        + "{sample}/align/{alnr}/snv/deep19/vcfs/{dvchrm}/{sample}.{alnr}.deep19.{dvchrm}.snv.sort.vcf",
        vcfgz=MDIR
        + "{sample}/align/{alnr}/snv/deep19/vcfs/{dvchrm}/{sample}.{alnr}.deep19.{dvchrm}.snv.sort.vcf.gz",
        vcftbi=MDIR
        + "{sample}/align/{alnr}/snv/deep19/vcfs/{dvchrm}/{sample}.{alnr}.deep19.{dvchrm}.snv.sort.vcf.gz.tbi",
    conda:
        config['deepvariant']['deep19_conda'] 
    log:
        MDIR
        + "{sample}/align/{alnr}/snv/deep19/vcfs/{dvchrm}/log/{sample}.{alnr}.deep19.{dvchrm}.snv.sort.vcf.gz.log",
    resources:
        vcpu=4,
        threads=4,
        partition=config['deepvariant']['partition_other'],
    params:
        cluster_sample=ret_sample,
    threads: 4 #config["config"]["sort_index_deepDna_chunk_vcf"]['threads']
    shell:
        """
        bedtools sort -header -i {input.vcf} > {output.vcfsort} 2>> {log};
        
        bgzip {output.vcfsort} >> {log} 2>&1;     
        touch {output.vcfsort};

        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1;

        """


rule deep19_concat_fofn:
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/snv/deep19/vcfs/{dvchm}/{{sample}}.{{alnr}}.deep19.{dvchm}.snv.sort.vcf.gz.tbi",
                dvchm=DEEPD_CHRMS,            ),            key=lambda x: float(                str(x.replace("~", ".").replace(":", "."))               .split("vcfs/")[1]                .split("/")[0]                .split("-")[0]            ),        ),    # This expand pattern is neat.  the escaped {} remain acting as a snakemake wildcard and expect to be derived from the dag, while th dvchrm wildcard is effectively being constrained by the values in the DEEPD_CHRMS array;  So you produce 1 input array of files for every sample+dvchrm parir, with one list string/file name per array.  The rule will only begin when all array members are produced. It's then sorted by first deepdvchrm so they can be concatenated w/out another soort as all the chunks had been sorted already.
    priority: 44
    output:
        fin_fofn=MDIR
        + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR        + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.concat.vcf.gz.fofn.tmp",
        #gfin_fofn=MDIR+ "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.g.concat.vcf.gz.fofn",
        #gtmp_fofn=MDIR        + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.g.concat.vcf.gz.fofn.tmp",
    threads: 2
    resources:
        vcpu=2,
        threads=2,
        partition="i192,i192mem",
    params:
        fn_stub="{sample}.{alnr}.deep19.",
        cluster_sample=ret_sample,
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.deep19.concat.fofn.bench.tsv"
    conda:
        config['deepvariant']['deep19_conda'] 
    log:
        MDIR + "{sample}/align/{alnr}/snv/deep19/log/{sample}.{alnr}.deep19.cocncat.fofn.log",
    shell:
        """

        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\.tbi$//g'; );
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.deep19. {output.fin_fofn}) >> {log} 2>&1;

        """


rule deep19_concat_index_chunks:
    input:
        fofn=MDIR
        + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR        + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.concat.vcf.gz.fofn.tmp",
        #gfofn=MDIR
        #+ "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.g.concat.vcf.gz.fofn",
        #gtmp_fofn=MDIR        + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.g.concat.vcf.gz.fofn.tmp",
    output:
        vcfgz=touch(
            MDIR + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.sort.vcf.gz"
        ),
        vcfgztemp=temp(
            MDIR + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.sort.temp.vcf.gz"
        ),
        vcfgztbi=touch(
            MDIR
            + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.sort.vcf.gz.tbi"
        ),   #gvcf=touch(            MDIR + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.g.sort.vcf"),        #gvcfgz=touch(            MDIR + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.g.sort.vcf.gz"),
    threads: 4
    resources:
        vcpu=4,
        threads=4,
        partition=config['deepvariant']['partition_other'],
    priority: 47
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    resources:
        attempt_n=lambda wildcards, attempt:  (attempt + 0)
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.deep19.merge.bench.tsv"
    conda:
        config['deepvariant']['deep19_conda'] 
    log:
        MDIR
        + "{sample}/align/{alnr}/snv/deep19/log/{sample}.{alnr}.deep19.snv.merge.sort.gatherered.log",
    shell:
        """
 
        touch {log};
        mkdir -p $(dirname {log});
        # This is acceptable bc I am concatenating from the same tools output, not across tools
        #touch {output.vcfgztemp};

        bcftools concat -a -d all --threads {threads} -f {input.fofn}  -O z -o {output.vcfgztemp} >> {log} 2>&1;

        export oldname=$(bcftools query -l {output.vcfgztemp} | head -n1) >> {log} 2>&1;
        echo -e "${{oldname}}\t{params.cluster_sample}" > {output.vcfgz}.rename.txt
        bcftools reheader -s {output.vcfgz}.rename.txt -o {output.vcfgz} {output.vcfgztemp} >> {log} 2>&1;
        bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;

        rm -rf $(dirname {output.vcfgz})/vcfs >> {log} 2>&1;

        """


rule clear_combined_deep19_vcf:  # TARGET:  clear combined deep vcf so the chunks can be re-evaluated if needed.
    input:
        vcf=expand(
            MDIR + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=ALIGNERS,
        ),
    priority: 42
    conda:
        config['deepvariant']['deep19_conda'] 
    resources:
        vcpu=2,
        threads=2,
        partition="i192,i192mem",
    shell:
        "(rm {input.vcf}*   1> /dev/null  2> /dev/null ) || echo 'file not found for deletion: {input}';"


rule produce_deep19_vcf:  # TARGET: deep variant vcf
    input:
        vcftb=expand(
            MDIR
            + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=ALIGNERS,
        ),
        vcftbi=expand(
            MDIR
            + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS,
        ),
        #gvcf=expand(
        #    MDIR
        #    + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.g.sort.vcf.gzi",
        #    sample=SSAMPS,
        #    alnr=ALIGNERS,
        #),
        #gvcftbi=expand(
        #    MDIR
        #    + "{sample}/align/{alnr}/snv/deep19/{sample}.{alnr}.deep19.snv.g.sort.vcf.gz.tbi",
        #    sample=SSAMPS,
        #    alnr=ALIGNERS,
        #),
    output:
        "gatheredall.deep",
    threads: 4
    priority: 48
    log:
        "gatheredall.deep19.log",
    conda:
        config['deepvariant']['deep19_conda'] 
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
        {latency_wait};
        ls {output} >> {log} 2>&1;

        {latency_wait}; 
        ls {output}  >> {log} 2>&1;
        """


localrules:
    prep_deep19_chunkdirs,


rule prep_deep19_chunkdirs:
    input:
        b=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        i=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/snv/deep19/vcfs/{dvchrm}/{{sample}}.ready",
            dvchrm=DEEPD_CHRMS,
        ),
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/snv/deep19/log/{sample}.{alnr}.chunkdirs.log",
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
 
