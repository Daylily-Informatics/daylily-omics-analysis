"""
Sentieon DNAscope Hybrid Workflow: Ultima + PacBio (CLI-based)

This workflow uses sentieon-cli dnascope-hybrid to combine:
- Ultima Genomics short-read aligned CRAM data
- PacBio long-read aligned CRAM data

Target: produce_sentdhup_vcf
"""
import sys
import os

ALIGNERS_UG = ["ug"]

rule sentdhup_snv:
    input:
        ug_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        ug_crai=MDIR + "{sample}/align/{alnr}/{sample}.cram.crai",
        pb_cram=MDIR + "{sample}/align/sentmm2/{sample}.cram",
        pb_crai=MDIR + "{sample}/align/sentmm2/{sample}.cram.crai",
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        d=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/vcfs/{dchrm}/{sample}.ready",
    output:
        vcf=temp(MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhup.{dchrm}.snv.vcf.gz"),
        tvcf=touch(MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhup.{dchrm}.snv.vcf.tmp"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_UG)
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/log/vcfs/{sample}.{alnr}.{ddup}.sentdhup.{dchrm}.snv.log",
    threads: config['sentdhup']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    priority: 45
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhup.{dchrm}.bench.tsv",
            0
            if "bench_repeat" not in config["sentdhup"]
            else config["sentdhup"]["bench_repeat"],
        )
    resources:
        attempt_n=lambda wildcards, attempt: (attempt + 0),
        partition=config['sentdhup']['partition'],
        threads=config['sentdhup']['threads'],
        vcpu=config['sentdhup']['threads'],
        mem_mb=config['sentdhup']['mem_mb'],
    params:
        schrm_mod=get_dchrm_day,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhup"]["dna_scope_snv_model"],
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
        cluster_sample=ret_sample,
        diploid_bed=get_diploid_bed_arg,
        use_threads=config["sentdhup"]["use_threads"],
        alt_samp_name=get_alt_sample_name
    shell:
        """
        export PATH=$PATH:/fsx/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S)_$$;
        export TMPDIR=/fsx/tmp/sentdhup_tmp_$timestamp;
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

        # Validate Ultima CRAM
        echo "Validating Ultima CRAM: {input.ug_cram}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.ug_cram} >> {log} 2>&1; then
            echo "ERROR: Ultima CRAM failed integrity check" | tee -a {log};
            exit 10;
        fi

        # Validate PacBio CRAM
        echo "Validating PacBio CRAM: {input.pb_cram}" >> {log} 2>&1;
        if ! samtools quickcheck -v {input.pb_cram} >> {log} 2>&1; then
            echo "ERROR: PacBio CRAM failed integrity check" | tee -a {log};
            exit 12;
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

        LD_PRELOAD=$LD_PRELOAD sentieon-cli -v dnascope-hybrid \\
            -t {params.use_threads} \\
            -r {params.huref} \\
            --sr_aln {input.ug_cram} \\
            --lr_aln {input.pb_cram} \\
            -d "{params.pop_vcf}" \\
            -m {params.model} \\
            --skip_svs \\
            --skip_mosdepth \\
            --skip_cnv \\
            --skip_multiqc \\
            --rgsm {params.alt_samp_name} \\
            {params.diploid_bed} {output.vcf} >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\\t$itype\\t$elapsed_time" >> {log} 2>&1;
        """


rule sentdhup_sort_index_chunk_vcf:
    input:
        vcf=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhup.{dchrm}.snv.vcf.gz",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_UG)
    priority: 46
    output:
        vcfsort=touch(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhup.{dchrm}.snv.sort.vcf"),
        vcfgz=touch(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhup.{dchrm}.snv.sort.vcf.gz"),
        vcftbi=touch(MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhup.{dchrm}.snv.sort.vcf.gz.tbi"),
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/vcfs/{dchrm}/log/{sample}.{alnr}.{ddup}.sentdhup.{dchrm}.snv.sort.vcf.gz.log",
    resources:
        vcpu=1,
        threads=1,
        partition="i192,i192mem"
    params:
        cluster_sample=ret_sample,
    threads: 64
    shell:
        """
        # Input is already bgzipped (.vcf.gz) from sentieon-cli.
        # Copy directly to .sort.vcf.gz to avoid double-gzipping.
        cp {input.vcf} {output.vcfgz} 2>> {log};
        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1;
        touch {output.vcfsort};
        """


localrules:
    sentdhup_concat_fofn,


rule sentdhup_concat_fofn:
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhup/vcfs/{ochm}/{{sample}}.{{alnr}}.{{ddup}}.sentdhup.{ochm}.snv.sort.vcf.gz.tbi",
                ochm=SENTDHUP_CHRMS,
            ),
            key=lambda x: float(
                str(x.replace("~", ".").replace(":", "."))
                .split("vcfs/")[1]
                .split("/")[0]
                .split("-")[0]
            ),
        ),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_UG)
    priority: 44
    output:
        fin_fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/{sample}.{alnr}.{ddup}.sentdhup.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/{sample}.{alnr}.{ddup}.sentdhup.snv.concat.vcf.gz.fofn.tmp",
    threads: 1
    resources:
        threads=1
    params:
        fn_stub="{sample}.{alnr}.{ddup}.sentdhup."
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhup.concat.fofn.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/log/{sample}.{alnr}.{ddup}.sentdhup.concat.fofn.log",
    shell:
        """
        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\\.tbi$//g'; );
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.sentdhup. {output.fin_fofn}) >> {log} 2>&1;
        """


rule sentdhup_concat_index_chunks:
    input:
        fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/{sample}.{alnr}.{ddup}.sentdhup.snv.concat.vcf.gz.fofn",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_UG)
    output:
        vcfgz=touch(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/{sample}.{alnr}.{ddup}.sentdhup.snv.sort.vcf.gz"
        ),
        vcfgztemp=temp(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/{sample}.{alnr}.{ddup}.sentdhup.snv.sort.temp.vcf.gz"
        ),
        vcfgztbi=touch(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/{sample}.{alnr}.{ddup}.sentdhup.snv.sort.vcf.gz.tbi"
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
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhup.merge.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/log/{sample}.{alnr}.{ddup}.sentdhup.snv.merge.sort.gathered.log",
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
    produce_sentdhup_vcf,


rule produce_sentdhup_vcf:  # TARGET: sentieon dnascope hybrid ultima+pacbio vcf
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/{sample}.{alnr}.{ddup}.sentdhup.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS_UG,
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdhup",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdhup.log",
    shell:
        """( touch {output} ;
        ls {output} ) >> {log} 2>&1;
        """


localrules:
    prep_sentdhup_chunkdirs,


rule prep_sentdhup_chunkdirs:
    input:
        ug_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        ug_crai=MDIR + "{sample}/align/{alnr}/{sample}.cram.crai",
        pb_cram=MDIR + "{sample}/align/sentmm2/{sample}.cram",
        pb_crai=MDIR + "{sample}/align/sentmm2/{sample}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhup/vcfs/{dchrm}/{{sample}}.ready",
            dchrm=SENTDHUP_CHRMS,
        ),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_UG)
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhup/logs/{sample}.{alnr}.{ddup}.chunkdirs.log",
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """

