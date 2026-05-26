"""
Sentieon DNAscope Hybrid Workflow: Illumina + PacBio (CLI-based)

This workflow uses sentieon-cli dnascope-hybrid to combine:
- Illumina short-read FASTQ data
- PacBio long-read aligned CRAM data

Target: produce_sentdhip_vcf
"""
import sys
import os

ALIGNERS_PB = ["sentmm2"]

rule sentdhip_snv:
    input:
        cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.cram.crai",
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        r1=getR1s,
        r2=getR2s,
        d=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhip/vcfs/{dchrm}/{sample}.ready",
    output:
        vcf=MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdhip/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhip.{dchrm}.snv.sort.vcf.gz",
        tbi=MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdhip/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhip.{dchrm}.snv.sort.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_PB)
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhip/log/vcfs/{sample}.{alnr}.{ddup}.sentdhip.{dchrm}.snv.log",
    threads: config['sentdhip']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    priority: 45
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhip.{dchrm}.bench.tsv",
            0
            if "bench_repeat" not in config["sentdhip"]
            else config["sentdhip"]["bench_repeat"],
        )
    resources:
        attempt_n=lambda wildcards, attempt:  (attempt + 0),
        partition=config['sentdhip']['partition'],
        threads=config['sentdhip']['threads'],
        vcpu=config['sentdhip']['threads'],
        mem_mb=config['sentdhip']['mem_mb'],
    params:
        schrm_mod=get_dchrm_day,
        use_threads=config["sentdhip"]["use_threads"],
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhip"]["dna_scope_snv_model"],
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
        cluster_sample=ret_sample,
        diploid_bed=get_diploid_bed_arg,
    shell:
        """
        export PATH=$PATH:/fsx/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S)_$$;
        export TMPDIR=/fsx/tmp/sentdhip_tmp_$timestamp;
        export SENTIEON_TMPDIR=$TMPDIR;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        if [ -z "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE not set." >> {log} 2>&1;
            exit 3;
        fi

        if [ ! -f "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE file does not exist." >> {log} 2>&1;
            exit 4;
        fi

        TOKEN=$(curl -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type);
        echo "INSTANCE TYPE: $itype" > {log};
        start_time=$(date +%s);

        ulimit -n 65536 || echo "ulimit mod failed" >> {log} 2>&1;

        # Validate PacBio CRAM
        echo "Validating PacBio CRAM: {input.cram}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.cram} >> {log} 2>&1; then
            echo "ERROR: CRAM failed integrity check" | tee -a {log};
            exit 10;
        fi

        # Find jemalloc
        jemalloc_path="";
        for _dir in "$CONDA_PREFIX/lib" "$CONDA_PREFIX/lib64"; do
            if [[ -d "$_dir" ]]; then
                _candidate=$(find "$_dir" -maxdepth 1 -name "libjemalloc*.so*" 2>/dev/null | head -n 1);
                if [[ -n "$_candidate" ]]; then
                    jemalloc_path="$_candidate";
                    break;
                fi
            fi
        done

        if [[ -n "$jemalloc_path" ]]; then
            export LD_PRELOAD="$jemalloc_path";
            export MALLOC_CONF=background_thread:true,metadata_thp:auto,dirty_decay_ms:5000,muzzy_decay_ms:5000;
        else
            echo "libjemalloc not found" >> {log};
            exit 3;
        fi

        export cram_sid=$(samtools view -H {input.cram} | grep '^@RG' | tr '\\t' '\\n' | grep '^SM:' | cut -f2 -d':' | sort | uniq)

        LD_PRELOAD=$LD_PRELOAD sentieon-cli -v dnascope-hybrid \\
            -t {params.use_threads} \\
            -r {params.huref} \\
            --sr_r1_fastq {input.r1} \\
            --sr_r2_fastq {input.r2} \\
            --sr_readgroups "@RG\\tID:${{cram_sid}}-1\\tSM:${{cram_sid}}\\tLB:${{cram_sid}}-LB-1\\tPL:ILLUMINA" \\
            --lr_aln {input.cram} \\
            --lr_align_input \\
            --lr_input_ref {params.huref} \\
            -d "{params.pop_vcf}" \\
            --skip_svs \\
            --skip_mosdepth \\
            --skip_cnv \\
            --skip_multiqc \\
            -m {params.model} \\
            {params.diploid_bed} {output.vcf} >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\\t$itype\\t$elapsed_time" >> {log} 2>&1;
        """

localrules:
    sentdhip_concat_fofn,


rule sentdhip_concat_fofn:
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhip/vcfs/{ochm}/{{sample}}.{{alnr}}.{{ddup}}.sentdhip.{ochm}.snv.sort.vcf.gz.tbi",
                ochm=SENTDHIP_CHRMS,
            ),
            key=lambda x: float(
                str(x.replace("~", ".").replace(":", "."))
                .split("vcfs/")[1]
                .split("/")[0]
                .split("-")[0]
            ),
        ),
    priority: 44
    output:
        fin_fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhip/{sample}.{alnr}.{ddup}.sentdhip.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhip/{sample}.{alnr}.{ddup}.sentdhip.snv.concat.vcf.gz.fofn.tmp",
    threads: 1
    resources:
        threads=1
    params:
        fn_stub="{sample}.{alnr}.{ddup}.sentdhip."
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhip.concat.fofn.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhip/log/{sample}.{alnr}.{ddup}.sentdhip.concat.fofn.log",
    shell:
        """
        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\\.tbi$//g'; );
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.sentdhip. {output.fin_fofn}) >> {log} 2>&1;
        """


rule sentdhip_concat_index_chunks:
    input:
        fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhip/{sample}.{alnr}.{ddup}.sentdhip.snv.concat.vcf.gz.fofn",
    output:
        vcfgz=touch(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhip/{sample}.{alnr}.{ddup}.sentdhip.snv.sort.vcf.gz"
        ),
        vcfgztemp=temp(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhip/{sample}.{alnr}.{ddup}.sentdhip.snv.sort.temp.vcf.gz"
        ),
        vcfgztbi=touch(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdhip/{sample}.{alnr}.{ddup}.sentdhip.snv.sort.vcf.gz.tbi"
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
        attempt_n=lambda wildcards, attempt: (attempt + 0)
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhip.merge.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhip/log/{sample}.{alnr}.{ddup}.sentdhip.snv.merge.sort.gathered.log",
    shell:
        """
        touch {log};
        mkdir -p $(dirname {log});
        bcftools concat -a -d all --threads {threads} -f {input.fofn} -O z -o {output.vcfgztemp} >> {log} 2>&1;
        export oldname=$(bcftools query -l {output.vcfgztemp} | head -n1) >> {log} 2>&1;
        echo -e "${{oldname}}\\t{params.cluster_sample}" > {output.vcfgz}.rename.txt
        bcftools reheader -s {output.vcfgz}.rename.txt -o {output.vcfgz} {output.vcfgztemp} >> {log} 2>&1;
        bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;
        rm -rf $(dirname {output.vcfgz})/vcfs >> {log} 2>&1;
        """


localrules:
    produce_sentdhip_vcf,


rule produce_sentdhip_vcf:  # TARGET: sentieon dnascope hybrid illumina+pacbio vcf
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdhip/{sample}.{alnr}.{ddup}.sentdhip.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS_PB,
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdhip",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdhip.log",
    shell:
        """( touch {output} ;
        ls {output} ) >> {log} 2>&1;
        """


localrules:
    prep_sentdhip_chunkdirs,


rule prep_sentdhip_chunkdirs:
    input:
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        r1=getR1s,
        r2=getR2s,
        cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhip/vcfs/{dchrm}/{{sample}}.ready",
            dchrm=SENTDHIP_CHRMS
        ),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_PB)
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhip/logs/{sample}.{alnr}.{ddup}.chunkdirs.log",
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """

