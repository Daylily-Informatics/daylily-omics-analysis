import sys
import os

##### deepvariant
# ---------------------------
#
 
rule deepvariant_ultima_make_examples:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
        d=MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/vcfs/{dvchrm}/{sample}.ready",
    output:
        examples=MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/vcfs/{dvchrm}/{sample}.{alnr}.{dvchrm}.examples.tfrecord@"+f"{config['deepvariant']['threads']}.gz"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/log/{sample}.{alnr}.make_examples.{dvchrm}."+f"{config['deepvariant']['threads']}.log"
    threads: config['deepvariant']['threads']
    container:
        config['deepvariant']['deepug_me_container']
    priority: 45
    resources:
        vcpu=config['deepvariant']['threads'],
        threads=config['deepvariant']['threads'],
        partition=config['deepvariant']['partition'],
        mem_mb=config['deepvariant']['mem_mb'],
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.deepug.{dvchrm}."+f"{config['deepvariant']['threads']}.bench.tsv"
    params:
        dchrm=get_dvchrm_day,
        deep_model="WGS",
        cluster_sample=ret_sample, #
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mdir=MDIR,
        mem_mb=config['deepvariant']['mem_mb'],
        numa=config['deepvariant']['numa'],
        cpre="" if "b37" == config['genome_build'] else "chr",
        deep_threads=config['deepvariant']['deep_threads'],
        mito_code="MT" if "b37" == config['genome_build'] else "M",
        instrument=get_instrument, 
        realign="true" if  get_instrument in ["ultima","ug"] else "false",
        perror=" --p_error=0.005 " if  get_instrument in ["ultima","ug"] else "",
    shell:
        """
        mkdir -p $(dirname {output.examples});

        TOKEN=$(curl -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type);
        echo "INSTANCE TYPE: $itype" > {log};
        
        # Log the start time as 0 seconds
        start_time=$(date +%s);
        echo "Start-Time-sec:$itype\t0" >> {log} 2>&1;

        dchr=$(echo {params.cpre}{params.dchrm} | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/' );

        timestamp=$(date +%Y%m%d%H%M%S)_$(head /dev/urandom | tr -dc a-zA-Z0-9 | head -c 6);

        export TMPDIR=$(dirname {log})/dv_me_tmp_$timestamp;
        mkdir -p $TMPDIR;
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;
        echo "DCHRM: $dchr" >> {log} 2>&1;


        {params.numa} \
        /opt/deepvariant/bin/make_examples \
            --mode calling \
            --ref={params.huref} \
            --reads={input.cram} \
            --regions=$dchr \
            --channel_list="read_base,base_quality,mapping_quality,strand,read_supports_variant,base_differs_from_ref,is_homopolymer" \
            --sample_name="{params.cluster_sample}" \
            --enable_joint_realignment={params.realign} {params.perror} \
            --examples={output.examples}  >> {log} 2>&1;

        touch {output.examples} >> {log} 2>&1;
                
        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));

        # Log the elapsed time
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;
        """


rule deepvariant_ultima_call_variants:
    input:
       examples=MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/vcfs/{dvchrm}/{sample}.{alnr}.{dvchrm}.examples.tfrecord@"+f"{config['deepvariant']['threads']}.gz"
    output:
        trf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/vcfs/{dvchrm}/{sample}.{alnr}.deepug.{dvchrm}.snv.vars.tfrecord.gz",
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/vcfs/{dvchrm}/log/{sample}.{alnr}.call_variants.{dvchrm}."+f"{config['deepvariant']['threads']}.log",
    threads: config['deepvariant']['threads']
    container:
        config['deepvariant']['deepug_cv_container']
    priority: 44  # slightly lower priority to ensure examples first
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.deepug.{dvchrm}.cv."+f"{config['deepvariant']['threads']}.bench.tsv"
    resources:
        vcpu=config['deepvariant']['threads'],
        threads=config['deepvariant']['threads'],
        partition=config['deepvariant']['partition'],
        mem_mb=config['deepvariant']['mem_mb'],
    params:
        checkpoint="/opt/models/wgs",
        dchrm=get_dvchrm_day,
        deep_model=get_deep_model,
        cluster_sample=ret_sample, #
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mdir=MDIR,
        mem_mb=config['deepvariant']['mem_mb'],
        numa=config['deepvariant']['numa'],
        cpre="" if "b37" == config['genome_build'] else "chr",
        deep_threads=config['deepvariant']['deep_threads'],
        mito_code="MT" if "b37" == config['genome_build'] else "M",
    shell:
        """
        mkdir -p $(dirname {output.trf});

        TOKEN=$(curl -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type);
        echo "INSTANCE TYPE: $itype" > {log};

        
        # Log the start time as 0 seconds
        start_time=$(date +%s);
        echo "Start-Time-sec:$itype\t0" >> {log} 2>&1;

        dchr=$(echo {params.cpre}{params.dchrm} | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/' );

        timestamp=$(date +%Y%m%d%H%M%S)_$(head /dev/urandom | tr -dc a-zA-Z0-9 | head -c 6)
        export TMPDIR=$(dirname {log})/deepvariantugcv_tmp_$timestamp;
        mkdir -p $TMPDIR;
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;
        echo "DCHRM: $dchr" >> {log} 2>&1;

        {params.numa} \
        /opt/deepvariant/bin/call_variants \
            --outfile={output.trf} \
            --examples={input.examples} \
            --checkpoint={params.checkpoint}             >> {log} 2>&1;

        touch {output.trf} >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));

        # Log the elapsed time
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;

        """

 

rule dvug_sort_index_chunk_vcf:
    input:
        trf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/vcfs/{dvchrm}/{sample}.{alnr}.deepug.{dvchrm}.snv.vars.tfrecord.gz",
    priority: 46
    output:
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deepug/vcfs/{dvchrm}/{sample}.{alnr}.deepug.{dvchrm}.snv.sort.vcf.gz",
        vcftbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deepug/vcfs/{dvchrm}/{sample}.{alnr}.deepug.{dvchrm}.snv.sort.vcf.gz.tbi",
        trftmp=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/vcfs/{dvchrm}/{sample}.{alnr}.deepug.{dvchrm}.snv.vars@1.tfrecord.gz"),
    container:
        config['deepvariant']['deepug_cv_container']
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deepug/vcfs/{dvchrm}/log/{sample}.{alnr}.deepug.{dvchrm}.snv.sort.vcf.gz.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.deepug.{dvchrm}.srt."+f"{config['deepvariant']['threads']}.bench.tsv"
    resources:
        vcpu=4,
        threads=4,
        partition=config['deepvariant']['partition_other'],
    params:
        mem_mb=config['deepvariant']['mem_mb'],
        numa=config['deepvariant']['numa'],
        mito_code="MT" if "b37" == config['genome_build'] else "M",
        cpre="" if "b37" == config['genome_build'] else "chr",
        dchrm=get_dvchrm_day,
        deep_model=get_deep_model,
        cluster_sample=ret_sample, #
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
    threads: 4 #config["config"]["sort_index_deepDna_chunk_vcf"]['threads']
    shell:
        """

        dchr=$(echo {params.cpre}{params.dchrm} | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/' );


        /opt/deepvariant/bin/postprocess_variants -j {threads} \
        --ref={params.huref} \
        --regions=$dchr \
        --sample_name="{params.cluster_sample}" \
        --infile={output.trftmp} \
        --outfile={output.vcfgz}  >> {log} 2>&1;

        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1;
        touch {output} >> {log} 2>&1;

        """


rule deepug_concat_fofn:
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/deepug/vcfs/{dvchm}/{{sample}}.{{alnr}}.deepug.{dvchm}.snv.sort.vcf.gz.tbi",
                dvchm=DEEPD_CHRMS,            ),            key=lambda x: float(                str(x.replace("~", ".").replace(":", "."))               .split("vcfs/")[1]                .split("/")[0]                .split("-")[0]            ),        ),    # This expand pattern is neat.  the escaped {} remain acting as a snakemake wildcard and expect to be derived from the dag, while th dvchrm wildcard is effectively being constrained by the values in the DEEPD_CHRMS array;  So you produce 1 input array of files for every sample+dvchrm parir, with one list string/file name per array.  The rule will only begin when all array members are produced. It's then sorted by first deepdvchrm so they can be concatenated w/out another soort as all the chunks had been sorted already.
    priority: 44
    output:
        fin_fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR        + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.concat.vcf.gz.fofn.tmp",
        #gfin_fofn=MDIR+ "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.g.concat.vcf.gz.fofn",
        #gtmp_fofn=MDIR        + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.g.concat.vcf.gz.fofn.tmp",
    threads: 2
    resources:
        vcpu=2,
        threads=2,
        partition="i192,i192mem",
    params:
        fn_stub="{sample}.{alnr}.deepug.",
        cluster_sample=ret_sample,
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.deepug.concat.fofn.bench.tsv"
    conda:
        config['deepvariant']['deepug_conda']
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/log/{sample}.{alnr}.deepug.cocncat.fofn.log",
    shell:
        """

        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\.tbi$//g'; );
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.deepug. {output.fin_fofn}) >> {log} 2>&1;

        """


rule deepug_concat_index_chunks:
    input:
        fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR        + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.concat.vcf.gz.fofn.tmp",
        #gfofn=MDIR
        #+ "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.g.concat.vcf.gz.fofn",
        #gtmp_fofn=MDIR        + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.g.concat.vcf.gz.fofn.tmp",
    output:
        vcfgz=touch(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.sort.vcf.gz"
        ),
        vcfgztemp=temp(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.sort.temp.vcf.gz"
        ),
        vcfgztbi=touch(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.sort.vcf.gz.tbi"
        ),   #gvcf=touch(            MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.g.sort.vcf"),        #gvcfgz=touch(            MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.g.sort.vcf.gz"),
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
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.deepug.merge.bench.tsv"
    conda:
        config['deepvariant']['deepug_conda']
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/deepug/log/{sample}.{alnr}.deepug.snv.merge.sort.gatherered.log",
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


rule clear_combined_deepug_vcf:  # TARGET:  clear combined deep vcf so the chunks can be re-evaluated if needed.
    input:
        vcf=expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=ALIGNERS,
            ddup=DDUP,
        ),
    log:
        MDIR + "logs/clear_combined_deepug_vcf.log"
    priority: 42
    conda:
        config['deepvariant']['deepug_conda']
    resources:
        vcpu=2,
        threads=2,
        partition="i192,i192mem",
    shell:
        "(rm {input.vcf}*   1> /dev/null  2> /dev/null ) || echo 'file not found for deletion: {input}';"


rule produce_deepug_vcf:  # TARGET: deep variant vcf
    input:
        vcftb=expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=ALIGNERS,
            ddup=DDUP,
        ),
        vcftbi=expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS,
            ddup=DDUP,
        ),
        #gvcf=expand(
        #    MDIR
        #    + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.g.sort.vcf.gzi",
        #    sample=SSAMPS,
        #    alnr=ALIGNERS,
        #    ddup=DDUP,
        #),
        #gvcftbi=expand(
        #    MDIR
        #    + "{sample}/align/{alnr}/{ddup}/snv/deepug/{sample}.{alnr}.deepug.snv.g.sort.vcf.gz.tbi",
        #    sample=SSAMPS,
        #    alnr=ALIGNERS,
        #    ddup=DDUP,
        #),
    output:
        "gatheredall.deep",
    threads: 4
    priority: 48
    log:
        "gatheredall.deepug.log",
    conda:
        config['deepvariant']['deepug_conda']
    params:
        cluster_sample=ret_sample,
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

        ls {output}  >> {log} 2>&1;
        """


localrules:
    clear_combined_deepug_vcf,
    prep_deepug_chunkdirs,


rule prep_deepug_chunkdirs:
    input:
        b=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        i=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/deepug/vcfs/{dvchrm}/{{sample}}.ready",
            dvchrm=DEEPD_CHRMS,
        ),
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/deepug/log/{sample}.{alnr}.chunkdirs.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.prep_deepug_chunkdirs.bench.tsv"
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
 
