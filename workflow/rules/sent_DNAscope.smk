import sys
import os

##### sentieon DNAscope - OUR snv CALLER
# ---------------------------
#

rule sent_DNAscope:
    input:
        c=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
        d=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentd/vcfs/{dchrm}/{sample}.ready",
    output:
     vcf=temp(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentd/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentd.{dchrm}.snv.vcf"),
     tvcf=temp(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentd/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentd.{dchrm}.snv.vcf.tmp"),
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentd/log/vcfs/{sample}.{alnr}.{ddup}.sentd.{dchrm}.snv.log",
    threads: config['sentD']['threads']
    conda:
        "../envs/sentD_v0.2.yaml"
    priority: 45
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentd.{dchrm}.bench.tsv",
            0
            if "bench_repeat" not in config["sentD"]
            else config["sentD"]["bench_repeat"],
        )
    resources:
        attempt_n=lambda wildcards, attempt:  (attempt + 0),
        partition=config['sentD']['partition'],
        threads=config['sentD']['threads'],
        vcpu=config['sentD']['threads'],
	mem_mb=config['sentD']['mem_mb'],
    params:
        schrm_mod=get_dchrm_day,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentD"]["dna_scope_snv_model"],
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
        cluster_sample=ret_sample,
        max_mem="100G"
    shell:
        """
        export bwt_max_mem={params.max_mem} ;
        timestamp=$(date +%Y%m%d%H%M%S)_$$;
        export TMPDIR=/scratch/sentd_tmp_$timestamp;
        export TMP="$TMPDIR";
        export TEMP="$TMPDIR";
        export TEMPDIR="$TMPDIR";
        export SENTIEON_TMPDIR=$TMPDIR;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;

        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;
        tdir=$TMPDIR;
        ulimit -n 65536 || echo "ulimit mod failed" > {log} 2>&1;

        if [ -z "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE not set. Please set the SENTIEON_LICENSE environment variable to the license file path & make this update to your dyinit file as well." >> {log} 2>&1;
            exit 3;
        fi

        if [ ! -f "$SENTIEON_LICENSE" ]; then
            echo "The file referenced by SENTIEON_LICENSE ('$SENTIEON_LICENSE') does not exist. Please provide a valid file path." >> {log} 2>&1;
            exit 4;
        fi

        TOKEN=$(curl -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type);
        echo "INSTANCE TYPE: $itype" > {log};
        echo "INSTANCE TYPE: $itype";
        start_time=$(date +%s);

        bin/dayoa_sentieon driver --thread_count {threads} \
        --interval {params.schrm_mod} --reference {params.huref} --input {input.c} \
        --algo DNAscope -d {params.pop_vcf} --pcr_indel_model none --emit_mode variant \
        --model {params.model}  {output.tvcf} >> {log} 2>&1;

        bin/dayoa_sentieon driver -t {threads} \
        -r {params.huref} --algo DNAModelApply --model {params.model} -v {output.tvcf} {output.vcf} >> {log} 2>&1;


        end_time=$(date +%s);
    	elapsed_time=$((($end_time - $start_time) / 60));
	    echo "Elapsed-Time-min:\t$itype\t$elapsed_time\n";
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;

        touch {output.vcf};
        """


rule sentD_sort_index_chunk_vcf:
    input:
        vcf=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentd/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentd.{dchrm}.snv.vcf",
    priority: 46
    output:
        vcfsort=touch(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentd/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentd.{dchrm}.snv.sort.vcf"),
        vcfgz=touch(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentd/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentd.{dchrm}.snv.sort.vcf.gz"),
        vcftbi=touch(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentd/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentd.{dchrm}.snv.sort.vcf.gz.tbi"),
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentd/vcfs/{dchrm}/log/{sample}.{alnr}.{ddup}.sentd.{dchrm}.snv.sort.vcf.gz.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{dchrm}.sentD_sort_index_chunk_vcf.bench.tsv"
    resources:
        vcpu=1,
        threads=1,
        partition="bcl2fq-i384-nvme-test"
    params:
        x='y',
        cluster_sample=ret_sample,
    threads: 1 #config["config"]["sort_index_sentDna_chunk_vcf"]['threads']
    shell:
        """
        bedtools sort -header -i {input.vcf} > {output.vcfsort} 2>> {log};
        
        bgzip {output.vcfsort} >> {log} 2>&1;
        touch {output.vcfsort};

        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1;
        
        """


localrules:
    sentD_concat_fofn,


rule sentD_concat_fofn:
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentd/vcfs/{ochm}/{{sample}}.{{alnr}}.{{ddup}}.sentd.{ochm}.snv.sort.vcf.gz.tbi",
                ochm=SENTD_CHRMS,            ),            key=lambda x: float(                str(x.replace("~", ".").replace(":", "."))               .split("vcfs/")[1]                .split("/")[0]                .split("-")[0]            ),        ),
    # This expand pattern is neat.  the escaped {} remain acting as a snakemake wildcard and expect to be derived from the dag, while th dchrm wildcard is effectively being constrained by the values in the SENTD_CHRMS array;  So you produce 1 input array of files for every sample+dchrm parir, with one list string/file name per array.  The rule will only begin when all array members are produced. It's then sorted by first sentdchrm so they can be concatenated w/out another soort as all the chunks had been sorted already.
    priority: 44
    output:
        fin_fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentd/{sample}.{alnr}.{ddup}.sentd.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR        + "{sample}/align/{alnr}/{ddup}/snv/sentd/{sample}.{alnr}.{ddup}.sentd.snv.concat.vcf.gz.fofn.tmp",
    threads: 1
    resources:
        threads=1
    params:
        fn_stub="{sample}.{alnr}.{ddup}.sentd."
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentd.concat.fofn.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentd/log/{sample}.{alnr}.{ddup}.sentd.cocncat.fofn.log",
    shell:
        """

        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\.tbi$//g'; );
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.sentd. {output.fin_fofn}) >> {log} 2>&1;

        """


rule sentD_concat_index_chunks:
    input:
        fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentd/{sample}.{alnr}.{ddup}.sentd.snv.concat.vcf.gz.fofn",
    output:
        vcfgz=touch(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentd/{sample}.{alnr}.{ddup}.sentd.snv.sort.vcf.gz"
        ),
        vcfgztemp=temp(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentd/{sample}.{alnr}.{ddup}.sentd.snv.sort.temp.vcf.gz"
        ),
        vcfgztbi=touch(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentd/{sample}.{alnr}.{ddup}.sentd.snv.sort.vcf.gz.tbi"
        ),
    threads: 4
    resources:
        vcpu=4,
        threads=4,
        partition="bcl2fq-i384-nvme-test"
    priority: 47
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    resources:
        attempt_n=lambda wildcards, attempt:  (attempt + 0)
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentd.merge.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentd/log/{sample}.{alnr}.{ddup}.sentd.snv.merge.sort.gatherered.log",
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

localrules:
    clear_combined_sentD_vcf,


rule clear_combined_sentD_vcf:  # TARGET:  clear combined sentD vcf so the chunks can be re-evaluated if needed.
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentd/{sample}.{alnr}.{ddup}.sentd.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=ALIGNERS,
            ddup=DDUP,
        ),
    log:
        MDIR + "logs/clear_combined_sentD_vcf.log"
    benchmark:
        "logs/benchmarks/clear_combined_sentD_vcf.bench.tsv"
    threads: 2
    priority: 42
    shell:
        """
        rm {input}*  1> /dev/null  2> /dev/null ) || echo 'file not found for deletion: {input}';
        """


localrules:
    produce_sentD_vcf,


rule produce_sentD_vcf:  # DEPRECATED TARGET: use produce_sentd_snv_vcf
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentd/{sample}.{alnr}.{ddup}.sentd.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS,
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentd",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentd.log",
    benchmark:
        "logs/benchmarks/produce_sentD_vcf.bench.tsv"
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """


localrules:
    prep_sentD_chunkdirs,


rule prep_sentD_chunkdirs:
    input:
        c=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        i=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentd/vcfs/{dchrm}/{{sample}}.ready",
            dchrm=SENTD_CHRMS,
        ),
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentd/logs/{sample}.{alnr}.chunkdirs.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.prep_sentD_chunkdirs.bench.tsv"
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
