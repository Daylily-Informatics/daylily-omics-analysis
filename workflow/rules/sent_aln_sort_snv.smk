import os

####### Sentieon Pangenome – align + sort + call in one step
#
# Uses sentieon-cli sentieon-pangenome which performs pangenome-aware
# alignment (via graph reference) and variant calling for Illumina
# paired-end WGS data.  Outputs a single VCF.gz with SNVs/indels.
#


rule sent_aln_sort_snv:
    """Sentieon pangenome: align + sort + variant call (Illumina PE FASTQ → VCF)."""
    input:
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        f1=getR1s,
        f2=getR2s,
    output:
        vcfgz=MDIR
        + "{sample}/align/sent/snv/sentpg/{sample}.sent.sentpg.snv.sort.vcf.gz",
        vcfgztbi=MDIR
        + "{sample}/align/sent/snv/sentpg/{sample}.sent.sentpg.snv.sort.vcf.gz.tbi",
    log:
        MDIR
        + "{sample}/align/sent/snv/sentpg/log/{sample}.sent.sentpg.snv.log",
    threads: config["sent_aln_sort_snv"]["threads"]
    conda:
        config["sent_aln_sort_snv"]["env_yaml"]
    priority: 5
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.sent.sentpg.bench.tsv",
            0
            if "bench_repeat" not in config["sent_aln_sort_snv"]
            else config["sent_aln_sort_snv"]["bench_repeat"],
        )
    resources:
        attempt_n=lambda wildcards, attempt: (attempt + 0),
        partition=config["sent_aln_sort_snv"]["partition"],
        threads=config["sent_aln_sort_snv"]["threads"],
        vcpu=config["sent_aln_sort_snv"]["threads"],
        mem_mb=config["sent_aln_sort_snv"]["mem_mb"],
        constraint=config["sent_aln_sort_snv"]["constraint"],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        hapl=config["sent_aln_sort_snv"]["hapl"],
        gbz=config["sent_aln_sort_snv"]["gbz"],
        model=config["sent_aln_sort_snv"]["model"],
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
        canonical_bed=config["sent_aln_sort_snv"]["canonical_bed"],
        dbsnp=config["sent_aln_sort_snv"]["dbsnp"],
        pcr_free=config["sent_aln_sort_snv"]["pcr_free"],
        cluster_sample=ret_sample,
        rgpl="ILLUMINA",
        rgpu="presumedCombinedLanes",
        rgsm=ret_sample,
        rgid=ret_sample,
        rglb="_presumedNoAmpWGS",
        rgcn="CenterName",
        rgpg="sentieonPangenome",
    shell:
        """

        if [ -z "$SENTIEON_LICENSE" ]; then
            echo "SENTIEON_LICENSE not set. Please set the SENTIEON_LICENSE environment variable to the license file path & make this update to your dyinit file as well." >> {log} 2>&1;
            exit 3;
        fi

        if [ ! -f "$SENTIEON_LICENSE" ]; then
            echo "The file referenced by SENTIEON_LICENSE ('$SENTIEON_LICENSE') does not exist. Please provide a valid file path." >> {log} 2>&1;
            exit 4;
        fi

        TOKEN=$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type);
        echo "INSTANCE TYPE: $itype" > {log};
        start_time=$(date +%s);
        epocsec=$(date +'%s');

        ulimit -n 65536 || echo "ulimit mod failed" >> {log} 2>&1;

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentpg_tmp_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        if [ ! -d "$TMPDIR" ]; then
            echo "ERROR: Failed to create TMPDIR: $TMPDIR" >> {log} 2>&1;
            exit 5;
        fi
        echo "TMPDIR created: $TMPDIR" >> {log} 2>&1;
        ls -ld "$TMPDIR" >> {log} 2>&1;
        df -h /dev/shm >> {log} 2>&1;
        export APPTAINER_HOME="$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

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

        if [[ -n "$jemalloc_path" ]]; then
            export LD_PRELOAD="$jemalloc_path";
            export MALLOC_CONF=background_thread:true,metadata_thp:auto,dirty_decay_ms:5000,muzzy_decay_ms:5000;
            echo "LD_PRELOAD set to: $LD_PRELOAD" >> {log};
            echo "MALLOC_CONF set to: $MALLOC_CONF" >> {log};
        else
            echo "WARNING: libjemalloc not found in CONDA_PREFIX=$CONDA_PREFIX" >> {log};
        fi

        # --- Build optional flags ---
        pcr_flag="";
        if [[ "{params.pcr_free}" == "true" ]]; then
            pcr_flag="--pcr_free";
        fi

        # --- sentieon-cli sentieon-pangenome ---
        cli_out="$TMPDIR/{wildcards.sample}.sentpg";

        echo "sentieon-cli sentieon-pangenome starting" >> {log} 2>&1;
        echo "  model={params.model}" >> {log} 2>&1;
        echo "  hapl={params.hapl}" >> {log} 2>&1;
        echo "  gbz={params.gbz}" >> {log} 2>&1;
        set +e;
        sentieon-cli sentieon-pangenome \
            -r {params.huref} \
            --hapl "{params.hapl}" \
            --gbz "{params.gbz}" \
            -m "{params.model}" \
            --pop_vcf "{params.pop_vcf}" \
            --r1_fastq {input.f1} \
            --r2_fastq {input.f2} \
            --readgroup "@RG\\tID:{params.cluster_sample}-$epocsec\\tSM:{params.cluster_sample}\\tLB:{params.cluster_sample}-LB-1\\tPL:{params.rgpl}" \
            -b "{params.canonical_bed}" \
            --dbsnp "{params.dbsnp}" \
            $pcr_flag \
            -t {threads} \
            "${{cli_out}}.vcf.gz" >> {log} 2>&1;
        cli_rc=$?;
        set -e;
        echo "sentieon-cli exit code: $cli_rc" >> {log} 2>&1;
        if [ $cli_rc -ne 0 ]; then
            echo "ERROR: sentieon-cli sentieon-pangenome failed with exit code $cli_rc" >> {log} 2>&1;
            exit $cli_rc;
        fi

        # --- Reheader VCF: rename sample to cluster_sample ---
        if [ -f "${{cli_out}}.vcf.gz" ]; then
            oldname=$(bcftools query -l "${{cli_out}}.vcf.gz" | head -n1);
            echo -e "${{oldname}}\\t{params.cluster_sample}" > "$TMPDIR/rename.txt";
            bcftools reheader -s "$TMPDIR/rename.txt" -o {output.vcfgz} "${{cli_out}}.vcf.gz" >> {log} 2>&1;
            bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;
        else
            echo "ERROR: VCF not produced by sentieon-cli" >> {log} 2>&1;
            exit 20;
        fi

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\\t$itype\\t$elapsed_time" >> {log} 2>&1;

        """


localrules:
    clear_combined_sentpg_vcf,


rule clear_combined_sentpg_vcf:  # TARGET: clear combined sentpg vcf
    input:
        expand(
            MDIR + "{sample}/align/sent/snv/sentpg/{sample}.sent.sentpg.snv.sort.vcf.gz",
            sample=SAMPS,
        ),
    log:
        MDIR + "logs/clear_combined_sentpg_vcf.log"
    threads: 2
    priority: 42
    shell:
        """
        rm {input}*  1> /dev/null  2> /dev/null || echo 'file not found for deletion: {input}';
        """


localrules:
    produce_sentpg_vcf,


rule produce_sentpg_vcf:  # TARGET: sentieon pangenome vcf
    input:
        expand(
            MDIR
            + "{sample}/align/sent/snv/sentpg/{sample}.sent.sentpg.snv.sort.vcf.gz.tbi",
            sample=SAMPS,
        ),
    output:
        "gatheredall.sentpg",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentpg.log",
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """

