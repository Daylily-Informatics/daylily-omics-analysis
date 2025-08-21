import sys
import os

##### deepsomatic
# ---------------------------

DVS_ALIGNER=["dvsom"]

def get_dvs_normal_cram(wildcards):
    try:
        nsamp = TN_PAIRS[wildcards.sample]
    except KeyError:
        raise ValueError(f"No matched normal sample for {wildcards.sample}")
    return MDIR + f"{nsamp}/align/{wildcards.alnr}/{nsamp}.{wildcards.alnr}.cram"

def get_dvs_normal_crai(wildcards):
    try:
        nsamp = TN_PAIRS[wildcards.sample]
    except KeyError:
        raise ValueError(f"No matched normal sample for {wildcards.sample}")
    return MDIR + f"{nsamp}/align/{wildcards.alnr}/{nsamp}.{wildcards.alnr}.cram.crai"

def get_dvs_tumor_cram(wildcards):
    return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.{wildcards.alnr}.cram"

def get_dvs_tumor_crai(wildcards):
    return MDIR + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.sample}.{wildcards.alnr}.cram.crai"


rule dvsom:
    wildcard_constraints:
        sample=VARNTUMORS_REGEX
    input:
        tumor_cram=get_dvs_tumor_cram,
        tumor_crai=get_dvs_tumor_crai,
        normal_cram=get_dvs_normal_cram,
        normal_crai=get_dvs_normal_crai,
        d=MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/{sample}.ready",
    output:
        vcf=temp(MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/{sample}.{alnr}.dvsom.{dvsomchrm}.som.vcf"),
    log:
        MDIR + "{sample}/align/{alnr}/snv/dvsom/log/{sample}.{alnr}.dvsom.{dvsomchrm}.som.log",
    threads: config['deepsomatic']['threads']
    container:
        config['deepsomatic']['container']
    priority: 45
    resources:
        vcpu=config['deepsomatic']['threads'],
        threads=config['deepsomatic']['threads'],
        partition=config['deepsomatic']['partition'],
        mem_mb=config['deepsomatic']['mem_mb'],
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.{alnr}.dvsom.{dvsomchrm}.bench.tsv",
            0 if "bench_repeat" not in config["deepsomatic"] else config["deepsomatic"]["bench_repeat"],
        )
    params:
        dchrm=get_dvsom_chrm_day,
        cluster_sample=ret_sample,
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mem_mb=config['deepsomatic']['mem_mb'],
        numa=config['deepsomatic']['numa'],
        cpre="" if "b37" == config['genome_build'] else "chr",
        deep_threads=config['deepsomatic']['deep_threads'],
        mito_code="MT" if "b37" == config['genome_build'] else "M",
        deep_model=get_deep_model,
        normal=get_normal_sample,
    shell:
        """
        TOKEN=$(curl -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type);
        echo "INSTANCE TYPE: $itype" > {log};

        ulimit -n 65536 || echo "ulimit mod failed" > {log} 2>&1;

        start_time=$(date +%s);
        echo "Start-Time-sec:$itype\t0" >> {log} 2>&1;

        dchr=$(echo {params.cpre}{params.dchrm} | sed 's/~/\:/g' | sed 's/23\:/X\:/' | sed 's/24\:/Y\:/' | sed 's/25\:/{params.mito_code}\:/');

        timestamp=$(date +%Y%m%d%H%M%S)_$(head /dev/urandom | tr -dc a-zA-Z0-9 | head -c 6)

        export TMPDIR=/dev/shm/deepsomatic_tmp_$timestamp;
        mkdir -p $TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap "rm -rf \"$TMPDIR\" || echo '$TMPDIR rm fails' >> {log} 2>&1" EXIT;
        echo "DCHRM: $dchr" >> {log} 2>&1;

        {params.numa} \
        /opt/deepsomatic/bin/run_deepsomatic \
        --model_type={params.deep_model} --ref={params.huref} \
        --reads_tumor={input.tumor_cram} \
        --reads_normal={input.normal_cram} \
        --regions=$dchr \
        --output_vcf={output.vcf} \
        --num_shards={params.deep_threads} \
        --logging_dir=$(dirname {log}) \
        --dry_run=false >> {log} 2>&1;

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));

        echo "Elapsed-Time-min:\t$itype\t$elapsed_time" >> {log} 2>&1;
        """


rule dvsom_sort_index_chunk_vcf:
    wildcard_constraints:
        sample=VARNTUMORS_REGEX
    input:
        vcf=MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/{sample}.{alnr}.dvsom.{dvsomchrm}.som.vcf",
    priority: 46
    output:
        vcfsort=MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/{sample}.{alnr}.dvsom.{dvsomchrm}.som.sort.vcf",
        vcfgz=MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/{sample}.{alnr}.dvsom.{dvsomchrm}.som.sort.vcf.gz",
        vcftbi=MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/{sample}.{alnr}.dvsom.{dvsomchrm}.som.sort.vcf.gz.tbi",
    conda:
        config['deepsomatic']['dvsom_conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/dvsom/vcfs/{dvsomchrm}/log/{sample}.{alnr}.dvsom.{dvsomchrm}.som.sort.vcf.gz.log",
    resources:
        vcpu=4,
        threads=4,
        partition=config['deepsomatic']['partition_other'],
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


rule dvsom_concat_fofn:
    wildcard_constraints:
        sample=VARNTUMORS_REGEX
    input:
        chunk_tbi=sorted(
            expand(
                MDIR + "{{sample}}/align/{{alnr}}/snv/dvsom/vcfs/{dchrm}/{{sample}}.{{alnr}}.dvsom.{dchrm}.som.sort.vcf.gz.tbi",
                dchrm=DVSOM_CHRMS,
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
        fin_fofn=MDIR + "{sample}/align/{alnr}/snv/dvsom/{sample}.{alnr}.dvsom.som.concat.vcf.gz.fofn",
        tmp_fofn=MDIR + "{sample}/align/{alnr}/snv/dvsom/{sample}.{alnr}.dvsom.som.concat.vcf.gz.fofn.tmp",
    threads: 2
    resources:
        vcpu=2,
        threads=2,
        partition="i192,i192mem",
    params:
        cluster_sample=ret_sample,
        fn_stub="{sample}.{alnr}.dvsom.",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.dvsom.concat.fofn.bench.tsv"
    conda:
        config['deepsomatic']['dvsom_conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/dvsom/log/{sample}.{alnr}.dvsom.concat.fofn.log",
    shell:
        """
        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\.tbi$//g');
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.dvsom. {output.fin_fofn}) >> {log} 2>&1;
        """


rule dvsom_concat_index_chunks:
    wildcard_constraints:
        sample=VARNTUMORS_REGEX
    input:
        fofn=MDIR + "{sample}/align/{alnr}/snv/dvsom/{sample}.{alnr}.dvsom.som.concat.vcf.gz.fofn",
        tmp_fofn=MDIR + "{sample}/align/{alnr}/snv/dvsom/{sample}.{alnr}.dvsom.som.concat.vcf.gz.fofn.tmp",
    output:
        vcfgz=touch(MDIR + "{sample}/align/{alnr}/snv/dvsom/{sample}.{alnr}.dvsom.som.sort.vcf.gz"),
        vcfgztemp=temp(MDIR + "{sample}/align/{alnr}/snv/dvsom/{sample}.{alnr}.dvsom.som.sort.temp.vcf.gz"),
        vcfgztbi=touch(MDIR + "{sample}/align/{alnr}/snv/dvsom/{sample}.{alnr}.dvsom.som.sort.vcf.gz.tbi"),
    threads: 4
    resources:
        vcpu=4,
        threads=4,
        partition=config['deepsomatic']['partition_other'],
    priority: 47
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    resources:
        attempt_n=lambda wildcards, attempt: (attempt + 0)
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.dvsom.merge.bench.tsv"
    conda:
        config['deepsomatic']['dvsom_conda']
    log:
        MDIR + "{sample}/align/{alnr}/snv/dvsom/log/{sample}.{alnr}.dvsom.som.merge.sort.gatherered.log",
    shell:
        """
        touch {log};
        mkdir -p $(dirname {log});
        bcftools concat -a -d all --threads {threads} -f {input.fofn} -O z -o {output.vcfgztemp} >> {log} 2>&1;
        export oldname=$(bcftools query -l {output.vcfgztemp} | head -n1) >> {log} 2>&1;
        echo -e "${oldname}\t{params.cluster_sample}" > {output.vcfgz}.rename.txt
        bcftools reheader -s {output.vcfgz}.rename.txt -o {output.vcfgz} {output.vcfgztemp} >> {log} 2>&1;
        bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;
        rm -rf $(dirname {output.vcfgz})/vcfs >> {log} 2>&1;
        """


rule clear_combined_dvsom_vcf:
    wildcard_constraints:
        sample=VARNTUMORS_REGEX
    input:
        vcf=expand(
            MDIR + "{sample}/align/{alnr}/snv/dvsom/{sample}.{alnr}.dvsom.som.sort.vcf.gz",
            sample=TUMOR_SAMPLES,
            alnr=DVS_ALIGNER,
        ),
    priority: 42
    conda:
        config['deepsomatic']['dvsom_conda']
    resources:
        vcpu=2,
        threads=2,
        partition="i192,i192mem",
    shell:
        "(rm {input.vcf}*   1> /dev/null  2> /dev/null ) || echo 'file not found for deletion: {input}';"


rule produce_dvsom_vcf:  # Target: produce deep-somatic
    wildcard_constraints:
        sample=VARNTUMORS_REGEX
    input:
        vcftb=expand(
            MDIR + "{sample}/align/{alnr}/snv/dvsom/{sample}.{alnr}.dvsom.som.sort.vcf.gz",
            sample=TUMOR_SAMPLES,
            alnr=DVS_ALIGNER,
        ),
        vcftbi=expand(
            MDIR + "{sample}/align/{alnr}/snv/dvsom/{sample}.{alnr}.dvsom.som.sort.vcf.gz.tbi",
            sample=TUMOR_SAMPLES,
            alnr=DVS_ALIGNER
        ),
    output:
        "gatheredall.dvsom",
    threads: 4
    priority: 48
    log:
        "gatheredall.dvsom.log",
    conda:
        config['deepsomatic']['dvsom_conda']
    shell:
        """
        for vcf in {input.vcftb}; do
            bcf="${{vcf%.vcf.gz}}.bcf";
            bcftools view -O b -o $bcf --threads {threads} $vcf && bcftools index --threads 4 $bcf;
        done;
        touch {output};
        {latency_wait};
        ls {output} >> {log} 2>&1;
        {latency_wait};
        ls {output}  >> {log} 2>&1;
        """


localrules:
    prep_dvsom_chunkdirs,


rule prep_dvsom_chunkdirs:
    wildcard_constraints:
        sample=VARNTUMORS_REGEX
    input:
        b=MDIR + "{sample}/align/{alnr}/{sample}.{alnr}.cram",
        n=lambda wildcards: MDIR + f"{TN_DICT[wildcards.sample]}/align/{wildcards.alnr}/{TN_DICT[wildcards.sample]}.{wildcards.alnr}.cram",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/snv/dvsom/vcfs/{dvsomchrm}/{{sample}}.ready",
            dvsomchrm=DVSOM_CHRMS,
        ),
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/snv/dvsom/log/{sample}.{alnr}.chunkdirs.log",
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
