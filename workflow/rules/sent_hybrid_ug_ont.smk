import sys
import os

ALIGNERS_UG = ["ug"]

rule sentdhuo_snv:
    input:
        ug_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        ug_crai=MDIR + "{sample}/align/{alnr}/{sample}.cram.crai",
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
        ont_crai=MDIR + "{sample}/align/ont/{sample}.cram.crai",
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        d=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/vcfs/{dchrm}/{sample}.ready",
    output:
     vcf=temp(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhuo.{dchrm}.snv.vcf.gz"),
     tvcf=temp(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhuo.{dchrm}.snv.vcf.tmp"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_UG)
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/log/vcfs/{sample}.{alnr}.{ddup}.sentdhuo.{dchrm}.snv.log",
    threads: config['sentdhuo']['threads']
    conda:
        "../envs/sentieon_v0.2b.yaml"
    priority: 45
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuo.{dchrm}.bench.tsv",
            0
            if "bench_repeat" not in config["sentdhuo"]
            else config["sentdhuo"]["bench_repeat"],
        )
    resources:
        attempt_n=lambda wildcards, attempt:  (attempt + 0),
        partition=config['sentdhuo']['partition'],
        threads=config['sentdhuo']['threads'],
        vcpu=config['sentdhuo']['threads'],
	    mem_mb=config['sentdhuo']['mem_mb'],
    params:
        schrm_mod=get_dchrm_day,
        huref="/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta", #config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuo"]["dna_scope_snv_model"],
        pop_vcf=config["sentdhuo"]["pop_vcf"],
        cluster_sample=ret_sample,
        haploid_bed="", #get_haploid_bed_arg,
        diploid_bed="", #get_diploid_bed_arg,
        use_threads=config["sentdhuo"]["use_threads"],
	alt_samp_name=get_alt_sample_name
    shell:
        """
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR=/fsx/tmp/sentdhuo_tmp_$timestamp;
        export SENTIEON_TMPDIR=$TMPDIR;
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

        # --- Validate Ultima (short-read) CRAM contains aligned data ---
        echo "Validating Ultima CRAM: {input.ug_cram}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.ug_cram} >> {log} 2>&1; then
            echo "ERROR: Ultima CRAM failed integrity check: {input.ug_cram}" | tee -a {log};
            exit 10;
        fi
        _sq_count=$(samtools view -H {input.ug_cram} 2>/dev/null | grep -c '^@SQ' || true);
        echo "Ultima CRAM @SQ header count: $_sq_count" >> {log} 2>&1;
        if [ "$_sq_count" -eq 0 ]; then
            echo "ERROR: Ultima CRAM has no @SQ headers (unaligned?): {input.ug_cram}" | tee -a {log};
            exit 11;
        fi
        echo "Ultima CRAM validation passed ($_sq_count reference sequences)" >> {log} 2>&1;

        # --- Validate ONT (long-read) CRAM contains aligned data ---
        echo "Validating ONT CRAM: {input.ont_cram}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.ont_cram} >> {log} 2>&1; then
            echo "ERROR: ONT CRAM failed integrity check: {input.ont_cram}" | tee -a {log};
            exit 12;
        fi
        _sq_count_ont=$(samtools view -H {input.ont_cram} 2>/dev/null | grep -c '^@SQ' || true);
        echo "ONT CRAM @SQ header count: $_sq_count_ont" >> {log} 2>&1;
        if [ "$_sq_count_ont" -eq 0 ]; then
            echo "ERROR: ONT CRAM has no @SQ headers (unaligned?): {input.ont_cram}" | tee -a {log};
            exit 13;
        fi
        echo "ONT CRAM validation passed ($_sq_count_ont reference sequences)" >> {log} 2>&1;

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


        LD_PRELOAD=$LD_PRELOAD sentieon-cli -v dnascope-hybrid \
            -t {params.use_threads} \
            -r  {params.huref} \
            --sr_aln {input.ug_cram} \
            --lr_aln {input.ont_cram} \
            -d "{params.pop_vcf}" \
            -m {params.model} \
            --skip_svs \
            --skip_mosdepth \
            --skip_cnv \
            --skip_multiqc \
	    --rgsm {params.alt_samp_name} \
            {params.diploid_bed} {output.vcf} >> {log} 2>&1;


        end_time=$(date +%s);
    	elapsed_time=$((($end_time - $start_time) / 60));
	    echo "Elapsed-Time-min:\t$itype\t$elapsed_time\n";
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;

        """


rule sentdhuo_sort_index_chunk_vcf:
    input:
        vcf=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhuo.{dchrm}.snv.vcf.gz",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_UG)
    priority: 46
    output:
        vcfsort=touch(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhuo.{dchrm}.snv.sort.vcf"),
        vcfgz=touch(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhuo.{dchrm}.snv.sort.vcf.gz"),
        vcftbi=touch(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhuo.{dchrm}.snv.sort.vcf.gz.tbi"),
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/vcfs/{dchrm}/log/{sample}.{alnr}.{ddup}.sentdhuo.{dchrm}.snv.sort.vcf.gz.log",
    resources:
        vcpu=1,
        threads=1,
        partition="i192,i192mem"
    params:
        x='y',
        cluster_sample=ret_sample,
    threads: 64 #config["config"]["sort_index_sentdhuona_chunk_vcf"]['threads']
    shell:
        """
        
        cp {input.vcf} {output.vcfsort} 2>> {log};
        bgzip  -@ {threads} {output.vcfsort} >> {log} 2>&1;
        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1;
        
        """


localrules:
    sentdhuo_concat_fofn,


rule sentdhuo_concat_fofn:
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhuo/vcfs/{ochm}/{{sample}}.{{alnr}}.{{ddup}}.sentdhuo.{ochm}.snv.sort.vcf.gz.tbi",
                ochm=SENTDHUO_CHRMS,            ),            key=lambda x: float(                str(x.replace("~", ".").replace(":", "."))               .split("vcfs/")[1]                .split("/")[0]                .split("-")[0]            ),        ),
    # This expand pattern is neat.  the escaped {} remain acting as a snakemake wildcard and expect to be derived from the dag, while th dchrm wildcard is effectively being constrained by the values in the sentdhuo_CHRMS array;  So you produce 1 input array of files for every sample+dchrm parir, with one list string/file name per array.  The rule will only begin when all array members are produced. It's then sorted by first sentdhuochrm so they can be concatenated w/out another soort as all the chunks had been sorted already.
    wildcard_constraints:
        alnr="|".join(ALIGNERS_UG)
    priority: 44
    output:
        fin_fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/{sample}.{alnr}.{ddup}.sentdhuo.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR        + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/{sample}.{alnr}.{ddup}.sentdhuo.snv.concat.vcf.gz.fofn.tmp",
    threads: 1
    resources:
        threads=1
    params:
        fn_stub="{sample}.{alnr}.{ddup}.sentdhuo."
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuo.concat.fofn.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/log/{sample}.{alnr}.{ddup}.sentdhuo.cocncat.fofn.log",
    shell:
        """

        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\.tbi$//g'; );
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.sentdhuo. {output.fin_fofn}) >> {log} 2>&1;

        """


rule sentdhuo_concat_index_chunks:
    input:
        fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/{sample}.{alnr}.{ddup}.sentdhuo.snv.concat.vcf.gz.fofn",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_UG)
    output:
        vcfgz=touch(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/{sample}.{alnr}.{ddup}.sentdhuo.snv.sort.vcf.gz"
        ),
        vcfgztemp=temp(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/{sample}.{alnr}.{ddup}.sentdhuo.snv.sort.temp.vcf.gz"
        ),
        vcfgztbi=touch(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/{sample}.{alnr}.{ddup}.sentdhuo.snv.sort.vcf.gz.tbi"
        ),
    threads: 64
    resources:
        vcpu=64,
        threads=64,
        partition="i192,i192mem,i128"
    priority: 47
    params:
        huref="/fsx/data/genomic_data/organism_references/H_sapiens/hg38_broad/Homo_sapiens_assembly38.fasta", #config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    resources:
        attempt_n=lambda wildcards, attempt:  (attempt + 0)
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuo.merge.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/log/{sample}.{alnr}.{ddup}.sentdhuo.snv.merge.sort.gatherered.log",
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
    clear_combined_sentdhuo_vcf,


rule clear_combined_sentdhuo_vcf:  # TARGET:  clear combined sentdhuo vcf so the chunks can be re-evaluated if needed.
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/{sample}.{alnr}.{ddup}.sentdhuo.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=ALIGNERS_UG,
            ddup=DDUP,
        ),
    threads: 2
    priority: 42
    shell:
        """
        rm {input}*  1> /dev/null  2> /dev/null ) || echo 'file not found for deletion: {input}';
        """


localrules:
    produce_sentdhuo_vcf,


rule produce_sentdhuo_vcf:  # TARGET: sentieon dnascope vcf
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/{sample}.{alnr}.{ddup}.sentdhuo.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS_UG,
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdhuo",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdhuo.log",
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """


localrules:
    prep_sentdhuo_chunkdirs,


rule prep_sentdhuo_chunkdirs:
    input:
        ug_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        ug_crai=MDIR + "{sample}/align/{alnr}/{sample}.cram.crai",
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
        ont_crai=MDIR + "{sample}/align/ont/{sample}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhuo/vcfs/{dchrm}/{{sample}}.ready",
            dchrm=SENTDHUO_CHRMS,
        ),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_UG)
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuo/logs/{sample}.{alnr}.{ddup}.chunkdirs.log",
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
