##### Sentieon DNAscope for Complete Genomics / MGI WGS
# ------------------------------------------------------
# caller code: cgt7p
#
# This caller intentionally reuses the existing short-read Sentieon BWA MEM
# alignment and configured deduper outputs, then swaps only the DNAscope model.

CGT7P_DNASCOPE_MODEL = config["cgt7p"]["dna_scope_snv_model"]
# Expected production model:
# /fsx/data/cached_envs/sentieon-genomics-202503.02/bundles/DNAscopeMGIWGS2.1.bundle


rule cgt7p_DNAscope:
    input:
        c=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
        d=MDIR + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/vcfs/{dchrm}/{sample}.ready",
    output:
        vcf=temp(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.cgt7p.{dchrm}.snv.vcf"
        ),
        tvcf=temp(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.cgt7p.{dchrm}.snv.vcf.tmp"
        ),
    wildcard_constraints:
        alnr="sent",
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/log/vcfs/{sample}.{alnr}.{ddup}.cgt7p.{dchrm}.snv.log",
    threads: config["cgt7p"]["threads"]
    conda:
        config["cgt7p"]["env_yaml"]
    priority: 45
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.cgt7p.{dchrm}.bench.tsv",
            config["cgt7p"]["bench_repeat"],
        )
    resources:
        attempt_n=lambda wildcards, attempt: (attempt + 0),
        partition=config["cgt7p"]["partition"],
        threads=config["cgt7p"]["threads"],
        vcpu=config["cgt7p"]["threads"],
        mem_mb=config["cgt7p"]["mem_mb"],
    params:
        schrm_mod=get_dchrm_day,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=CGT7P_DNASCOPE_MODEL,
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
        cluster_sample=ret_sample,
        max_mem=config["cgt7p"]["max_mem"],
    shell:
        """
        export bwt_max_mem={params.max_mem};
        timestamp=$(date +%Y%m%d%H%M%S)_$$;
        export TMPDIR=/dev/shm/cgt7p_tmp_$timestamp;
        export SENTIEON_TMPDIR=$TMPDIR;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;

        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;
        tdir=$TMPDIR;
        ulimit -n 65536 || echo "ulimit mod failed" > {log} 2>&1;

        if [ -z "${{SENTIEON_LICENSE:-}}" ]; then
            echo "SENTIEON_LICENSE not set. Please set the SENTIEON_LICENSE environment variable to the license file path & make this update to your dyinit file as well." >> {log} 2>&1;
            exit 3;
        fi

        if [[ ! "$SENTIEON_LICENSE" =~ : ]] && [ ! -f "$SENTIEON_LICENSE" ]; then
            echo "The file referenced by SENTIEON_LICENSE ('$SENTIEON_LICENSE') does not exist. Please provide a valid file path." >> {log} 2>&1;
            exit 4;
        fi

        TOKEN=$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type || echo "unknown");
        echo "INSTANCE TYPE: $itype" > {log};
        echo "INSTANCE TYPE: $itype";
        start_time=$(date +%s);

        /fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon driver --thread_count {threads} \
        --interval {params.schrm_mod} --reference {params.huref} --input {input.c} \
        --algo DNAscope -d {params.pop_vcf} --pcr_indel_model none --emit_mode variant \
        --model {params.model} {output.tvcf} >> {log} 2>&1;

        /fsx/data/cached_envs/sentieon-genomics-202503.02/bin/sentieon driver -t {threads} \
        -r {params.huref} --algo DNAModelApply --model {params.model} -v {output.tvcf} {output.vcf} >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time";
        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;

        touch {output.vcf};
        """


rule cgt7p_sort_index_chunk_vcf:
    input:
        vcf=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.cgt7p.{dchrm}.snv.vcf",
    priority: 46
    output:
        vcfsort=temp(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.cgt7p.{dchrm}.snv.sort.vcf"
        ),
        vcfgz=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.cgt7p.{dchrm}.snv.sort.vcf.gz",
        vcftbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.cgt7p.{dchrm}.snv.sort.vcf.gz.tbi",
    wildcard_constraints:
        alnr="sent",
    conda:
        config["cgt7p"]["sentD_gather_env"]
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/vcfs/{dchrm}/log/{sample}.{alnr}.{ddup}.cgt7p.{dchrm}.snv.sort.vcf.gz.log",
    resources:
        vcpu=1,
        threads=1,
        partition=config["cgt7p"]["partition"],
    params:
        cluster_sample=ret_sample,
    threads: 1
    shell:
        """
        bedtools sort -header -i {input.vcf} > {output.vcfsort} 2> {log};
        bgzip -f -c {output.vcfsort} > {output.vcfgz} 2>> {log};
        tabix -f -p vcf {output.vcfgz} >> {log} 2>&1;
        """


localrules:
    cgt7p_concat_fofn,


rule cgt7p_concat_fofn:
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/cgt7p/vcfs/{ochm}/{{sample}}.{{alnr}}.{{ddup}}.cgt7p.{ochm}.snv.sort.vcf.gz.tbi",
                ochm=CGT7P_CHRMS,
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
        + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/{sample}.{alnr}.{ddup}.cgt7p.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/{sample}.{alnr}.{ddup}.cgt7p.snv.concat.vcf.gz.fofn.tmp",
    wildcard_constraints:
        alnr="sent",
    threads: 1
    resources:
        threads=1
    params:
        fn_stub="{sample}.{alnr}.{ddup}.cgt7p.",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.cgt7p.concat.fofn.bench.tsv"
    conda:
        config["cgt7p"]["sentD_gather_env"]
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/log/{sample}.{alnr}.{ddup}.cgt7p.concat.fofn.log",
    shell:
        """
        rm -f {output.tmp_fofn};
        for i in {input.chunk_tbi}; do
            ii=$(echo "$i" | perl -pe 's/\\.tbi$//g');
            echo "$ii" >> {output.tmp_fofn};
        done;
        workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.cgt7p. {output.fin_fofn} >> {log} 2>&1;
        """


rule cgt7p_concat_index_chunks:
    input:
        fofn=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/{sample}.{alnr}.{ddup}.cgt7p.snv.concat.vcf.gz.fofn",
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/{sample}.{alnr}.{ddup}.cgt7p.snv.sort.vcf.gz",
        vcfgztemp=temp(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/{sample}.{alnr}.{ddup}.cgt7p.snv.sort.temp.vcf.gz"
        ),
        vcfgztbi=MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/{sample}.{alnr}.{ddup}.cgt7p.snv.sort.vcf.gz.tbi",
    wildcard_constraints:
        alnr="sent",
    threads: config["cgt7p"]["gather_threads"]
    resources:
        attempt_n=lambda wildcards, attempt: (attempt + 0),
        vcpu=config["cgt7p"]["gather_threads"],
        threads=config["cgt7p"]["gather_threads"],
        partition=config["cgt7p"]["partition"],
        mem_mb=config["cgt7p"]["gather_mem_mb"],
    priority: 47
    params:
        cluster_sample=ret_sample,
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.cgt7p.merge.bench.tsv"
    conda:
        config["cgt7p"]["sentD_gather_env"]
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/log/{sample}.{alnr}.{ddup}.cgt7p.snv.merge.sort.gathered.log",
    shell:
        """
        touch {log};
        mkdir -p $(dirname {log});

        bcftools concat -a -d all --threads {threads} -f {input.fofn} -O z -o {output.vcfgztemp} >> {log} 2>&1;

        oldname=$(bcftools query -l {output.vcfgztemp} | head -n1) >> {log} 2>&1;
        echo -e "${{oldname}}\t{params.cluster_sample}" > {output.vcfgz}.rename.txt;
        bcftools reheader -s {output.vcfgz}.rename.txt -o {output.vcfgz} {output.vcfgztemp} >> {log} 2>&1;
        bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;

        rm -rf $(dirname {output.vcfgz})/vcfs >> {log} 2>&1;
        """


localrules:
    clear_combined_cgt7p_vcf,


rule clear_combined_cgt7p_vcf:  # TARGET: clear combined cgt7p vcf so chunks can be re-evaluated if needed.
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/{sample}.{alnr}.{ddup}.cgt7p.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=["sent"],
            ddup=DDUP,
        ),
    threads: 2
    priority: 42
    shell:
        """
        rm -f {input}* 1> /dev/null 2> /dev/null || true;
        """


localrules:
    produce_cgt7p_vcf,


rule produce_cgt7p_vcf:  # TARGET: Complete Genomics MGI Sentieon DNAscope VCF
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/{sample}.{alnr}.{ddup}.cgt7p.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=["sent"],
            ddup=DDUP,
        ),
    output:
        "gatheredall.cgt7p",
    priority: 48
    threads: 1
    log:
        "gatheredall.cgt7p.log",
    shell:
        """( touch {output};
        ls {output} ) >> {log} 2>&1;
        """


localrules:
    prep_cgt7p_chunkdirs,


rule prep_cgt7p_chunkdirs:
    input:
        c=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram",
        i=MDIR + "{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/cgt7p/vcfs/{dchrm}/{{sample}}.ready",
            dchrm=CGT7P_CHRMS,
        ),
    wildcard_constraints:
        alnr="sent",
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/cgt7p/logs/{sample}.{alnr}.chunkdirs.log",
    shell:
        """
        ( echo {output};
        mkdir -p $(dirname {output});
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
