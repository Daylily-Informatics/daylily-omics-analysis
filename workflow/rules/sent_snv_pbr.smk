import sys
import os

#
# This pipeline will realign the ONT reads and call variants
#

ALIGNERS_ONT = ["ont"]

rule sent_snv_ontr:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.cram.crai",
        d=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/vcfs/{dchrm}/{sample}.ready",
    output:
        vcf=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/vcfs/{dchrm}/{sample}.{alnr}.sentdpbr.{dchrm}.snv.sort.vcf.gz",
         vcftbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/vcfs/{dchrm}/{sample}.{alnr}.sentdpbr.{dchrm}.snv.sort.vcf.gz.tbi",
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/log/vcfs/{sample}.{alnr}.sentdpbr.{dchrm}.snv.log",
    threads: config['sentdpbr']['threads']
    conda:
        "../envs/sentieonHybrid_v0.1.yaml"
    priority: 45
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdpbr.{dchrm}.bench.tsv",
            0
            if "bench_repeat" not in config["sentdpbr"]
            else config["sentdpbr"]["bench_repeat"],
        )
    resources:
        attempt_n=lambda wildcards, attempt:  (attempt + 0),
        partition=config['sentdpbr']['partition'],
        threads=config['sentdpbr']['threads'],
        vcpu=config['sentdpbr']['threads'],
	mem_mb=config['sentdpbr']['mem_mb'],
    params:
        schrm_mod=get_dchrm_day,
        use_threads=config['sentdpbr']['use_threads'],
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdpbr"]["dnascope_model"],
        cluster_sample=ret_sample,
        haploid_bed=get_haploid_bed_arg,
        diploid_bed=get_diploid_bed_arg,
    shell:
        """
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR=/dev/shm/sentdpbr_tmp_$timestamp;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap "rm -rf \"$TMPDIR\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;

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

        ulimit -n 65536 || echo "ulimit mod failed" > {log} 2>&1;

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

        # Find the jemalloc library in the active conda environment
        jemalloc_path="";
        for _dir in "$CONDA_PREFIX/lib" "$CONDA_PREFIX/lib64" "$CONDA_PREFIX/lib/x86_64-linux-gnu"; do
            if [[ -d "$_dir" ]]; then
                for _ext in so dylib; do
                    _candidate=$(find "$_dir" -maxdepth 1 -name "libjemalloc*.$_ext*" 2>/dev/null | head -n 1);
                    if [[ -n "$_candidate" && -r "$_candidate" ]]; then
                        jemalloc_path="$_candidate";
                        break 2;
                    fi
                done
            fi
        done

        # Check if jemalloc was found and set LD_PRELOAD accordingly
        if [[ -n "$jemalloc_path" ]]; then
            export LD_PRELOAD="$jemalloc_path";
            export MALLOC_CONF=background_thread:true,metadata_thp:auto,dirty_decay_ms:5000,muzzy_decay_ms:5000;
            echo "LD_PRELOAD set to: $LD_PRELOAD" >> {log};
            echo "MALLOC_CONF set to: $MALLOC_CONF" >> {log};
        else
            echo "libjemalloc not found in CONDA_PREFIX=$CONDA_PREFIX (searched lib, lib64, lib/x86_64-linux-gnu)." >> {log};
            echo "libjemalloc not found in CONDA_PREFIX=$CONDA_PREFIX (searched lib, lib64, lib/x86_64-linux-gnu).";
            exit 3;
        fi

        LD_PRELOAD=$LD_PRELOAD sentieon-cli -v dnascope-longread \
            -t {params.use_threads} \
            -r {params.huref} \
            -i {input.cram} \
            -m  {params.model} \
            --tech ONT \
            --skip_svs \
            --skip_mosdepth \
            --skip_cnv \
            --skip_multiqc \
            {params.diploid_bed} {params.haploid_bed} {output.vcf} >> {log} 2>&1;

        end_time=$(date +%s);
    	elapsed_time=$((($end_time - $start_time) / 60));
	    echo "Elapsed-Time-min:\t$itype\t$elapsed_time\n";
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;

        """


#rule sentdpbr_sort_index_chunk_vcf:
#    input:
#        vcf=MDIR
#        + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/vcfs/{dchrm}/{sample}.{alnr}.sentdpbr.{dchrm}.snv.t.vcf.gz",
#    priority: 46
#    output:
#        vcfsort=touch(MDIR
#        + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/vcfs/{dchrm}/{sample}.{alnr}.sentdpbr.{dchrm}.snv.sort.vcf"),
#        vcfgz=touch(MDIR
#        + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/vcfs/{dchrm}/{sample}.{alnr}.sentdpbr.{dchrm}.snv.sort.vcf.gz"),
#        vcftbi=touch(MDIR
#        + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/vcfs/{dchrm}/{sample}.{alnr}.sentdpbr.{dchrm}.snv.sort.vcf.gz.tbi"),
#    conda:
#        "../envs/vanilla_v0.1.yaml"
#    log:
#        MDIR
#        + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/vcfs/{dchrm}/log/{sample}.{alnr}.sentdpbr.{dchrm}.snv.sort.vcf.gz.log",
#    resources:
#        vcpu=1,
#        threads=1,
#        partition="i192,i192mem"
#    params:
#        x='y',
#        cluster_sample=ret_sample,
#    threads: 64 #config["config"]["sort_index_sentdpbrna_chunk_vcf"]['threads']
#    shell:
#        """
#        
#        #bedtools sort -header -i {input.vcf} > {output.vcfsort} 2>> {log};
#        #awk 'BEGIN{{header=1}} 
#        #    header && /^#/ {{print; next}} 
#        #    header && /^[^#]/ {{header=0; exit}}' {input.vcf} > {output.vcfsort} 2>> {log};
#        #awk '/^[^#]/' {input.vcf} | sort --buffer-size=210G -T /fsx/scratch/ --parallel={threads} -k1,1V -k2,2n >> {output.vcfsort} 2>> {log};
#
#        cp {input.vcf} {output.vcfgz} 2>> {log};
#        touch {input.vcf};
#        sleep 1;
#        touch {output.vcfsort};
#        bgzip  -@ {threads} {output.vcfsort} >> {log} 2>&1;
#        touch {output.vcfsort};
#
#        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1;
#        
#        """


localrules:
    sentdpbr_concat_fofn,


rule sentdpbr_concat_fofn:
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdpbr/vcfs/{ochm}/{{sample}}.{{alnr}}.sentdpbr.{ochm}.snv.sort.vcf.gz.tbi",
                ochm=SENTDPBR_CHRMS,            ),            key=lambda x: float(                str(x.replace("~", ".").replace(":", "."))               .split("vcfs/")[1]                .split("/")[0]                .split("-")[0]            ),        ),
    # This expand pattern is neat.  the escaped {} remain acting as a snakemake wildcard and expect to be derived from the dag, while th dchrm wildcard is effectively being constrained by the values in the sentdpbr_CHRMS array;  So you produce 1 input array of files for every sample+dchrm parir, with one list string/file name per array.  The rule will only begin when all array members are produced. It's then sorted by first sentdpbrchrm so they can be concatenated w/out another soort as all the chunks had been sorted already.
    priority: 44
    output:
        fin_fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/{sample}.{alnr}.sentdpbr.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR        + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/{sample}.{alnr}.sentdpbr.snv.concat.vcf.gz.fofn.tmp",
    threads: 1
    resources:
        threads=1
    params:
        fn_stub="{sample}.{alnr}.sentdpbr."
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdpbr.concat.fofn.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/log/{sample}.{alnr}.sentdpbr.cocncat.fofn.log",
    shell:
        """

        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\.tbi$//g'; );
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.sentdpbr. {output.fin_fofn}) >> {log} 2>&1;

        """


rule sentdpbr_concat_index_chunks:
    input:
        fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/{sample}.{alnr}.sentdpbr.snv.concat.vcf.gz.fofn",
    output:
        vcfgz=touch(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/{sample}.{alnr}.sentdpbr.snv.sort.vcf.gz"
        ),
        vcfgztemp=temp(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/{sample}.{alnr}.sentdpbr.snv.sort.temp.vcf.gz"
        ),
        vcfgztbi=touch(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/{sample}.{alnr}.sentdpbr.snv.sort.vcf.gz.tbi"
        ),
    threads: 64
    resources:
        vcpu=64,
        threads=64,
        partition="i192,i192mem,i128"
    priority: 47
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    resources:
        attempt_n=lambda wildcards, attempt:  (attempt + 0)
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdpbr.merge.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/log/{sample}.{alnr}.sentdpbr.snv.merge.sort.gatherered.log",
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
    clear_combined_sentdpbr_vcf,


rule clear_combined_sentdpbr_vcf:  # TARGET:  clear combined sentdpbr vcf so the chunks can be re-evaluated if needed.
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/{sample}.{alnr}.sentdpbr.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=ALIGNERS_ONT,
            ddup=DDUP,
        ),
    threads: 2
    priority: 42
    shell:
        """
        rm {input}*  1> /dev/null  2> /dev/null ) || echo 'file not found for deletion: {input}';
        """


localrules:
    produce_sentdpbr_vcf,

 
rule produce_sentdpbr_vcf:  # TARGET: sentieon dnascope vcf
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/{sample}.{alnr}.sentdpbr.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS_ONT,
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdpbr",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdpbr.log",
    shell:
        """( touch {output} ;

        {latency_wait}; ls {output} ) >> {log} 2>&1;
        """


localrules:
    prep_sentdpbr_chunkdirs,


rule prep_sentdpbr_chunkdirs:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdpbr/vcfs/{dchrm}/{{sample}}.ready",
            dchrm=SENTDPBR_CHRMS,
        ),
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdpbr/logs/{sample}.{alnr}.chunkdirs.log",
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
