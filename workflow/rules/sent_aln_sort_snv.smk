import os

####### Sentieon Pangenome – align + sort + call in one step
#
# Uses bin/dayoa_sentieon_cli dnascope-pangenome which performs pangenome-aware
# alignment (via graph reference) and variant calling for Illumina
# paired-end WGS data.  Outputs a single VCF.gz with SNVs/indels.
#


def _sent_aln_sort_snv_model(wildcards):
    section = "sent_aln_sort_snv"
    mode = str(config.get(f"{section}_model_mode", config[section]["model_mode"])).lower()
    if mode == "current":
        return config[section]["model"]
    if mode == "prior":
        return config[section]["prior_model"]
    raise ValueError(f"{section}_model_mode must be 'current' or 'prior', got {mode!r}")


def _sent_aln_sort_snv_pop_vcf(wildcards):
    section = "sent_aln_sort_snv"
    mode = str(config.get(f"{section}_model_mode", config[section]["model_mode"])).lower()
    if mode == "current":
        return config[section]["pop_vcf"]
    if mode == "prior":
        return config[section]["prior_pop_vcf"]
    raise ValueError(f"{section}_model_mode must be 'current' or 'prior', got {mode!r}")


def _sent_aln_sort_snv_threads(wildcards):
    section = "sent_aln_sort_snv"
    if str(config.get("force_partition", "") or "").strip() == "dragen":
        return int(config[section]["dragen_threads"])
    return int(config[section]["threads"])


def _dragen_pangenome_model(wildcards):
    section = "dragen_pangenome"
    mode = str(config.get(f"{section}_model_mode", config[section]["model_mode"])).lower()
    if mode == "current":
        return config[section]["model"]
    if mode == "prior":
        return config[section]["prior_model"]
    raise ValueError(f"{section}_model_mode must be 'current' or 'prior', got {mode!r}")


def _dragen_pangenome_pop_vcf(wildcards):
    section = "dragen_pangenome"
    mode = str(config.get(f"{section}_model_mode", config[section]["model_mode"])).lower()
    if mode == "current":
        return config[section]["pop_vcf"]
    if mode == "prior":
        return config[section]["prior_pop_vcf"]
    raise ValueError(f"{section}_model_mode must be 'current' or 'prior', got {mode!r}")


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
    threads: _sent_aln_sort_snv_threads
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
        partition=derive_partition_order(config["sent_aln_sort_snv"]["partition"]),
        threads=_sent_aln_sort_snv_threads,
        vcpu=_sent_aln_sort_snv_threads,
        mem_mb=config["sent_aln_sort_snv"]["mem_mb"],
        constraint=config["sent_aln_sort_snv"]["constraint"],
        distribution=config["sent_aln_sort_snv"]["distribution"],
        exclude=config["sent_aln_sort_snv"]["exclude"],
        include=config["sent_aln_sort_snv"]["include"],
        exclusive=config["sent_aln_sort_snv"]["exclusive"],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        hapl=config["sent_aln_sort_snv"]["hapl"],
        gbz=config["sent_aln_sort_snv"]["gbz"],
        model=_sent_aln_sort_snv_model,
        pop_vcf=_sent_aln_sort_snv_pop_vcf,
        canonical_bed=config["sent_aln_sort_snv"]["canonical_bed"],
        dbsnp=config["sent_aln_sort_snv"]["dbsnp"],
        pcr_free=config["sent_aln_sort_snv"]["pcr_free"],
        cli_threads=lambda wildcards: min(_sent_aln_sort_snv_threads(wildcards), 128),
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
        export TMPDIR="/scratch/sentpg_tmp_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        if [ ! -d "$TMPDIR" ]; then
            echo "ERROR: Failed to create TMPDIR: $TMPDIR" >> {log} 2>&1;
            exit 5;
        fi
        echo "TMPDIR created: $TMPDIR" >> {log} 2>&1;
        ls -ld "$TMPDIR" >> {log} 2>&1;
        df -h /scratch >> {log} 2>&1;
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

        # --- bin/dayoa_sentieon_cli dnascope-pangenome ---
        cli_out="$TMPDIR/{wildcards.sample}.sentpg";

        echo "bin/dayoa_sentieon_cli dnascope-pangenome starting" >> {log} 2>&1;
        echo "  model={params.model}" >> {log} 2>&1;
        echo "  hapl={params.hapl}" >> {log} 2>&1;
        echo "  gbz={params.gbz}" >> {log} 2>&1;
        set +e;
        bin/dayoa_sentieon_cli dnascope-pangenome \
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
            -t {params.cli_threads} \
            "${{cli_out}}.vcf.gz" >> {log} 2>&1;
        cli_rc=$?;
        set -e;
        echo "sentieon-cli exit code: $cli_rc" >> {log} 2>&1;
        if [ $cli_rc -ne 0 ]; then
            echo "ERROR: bin/dayoa_sentieon_cli dnascope-pangenome failed with exit code $cli_rc" >> {log} 2>&1;
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


rule dragen_aln_sort_snv:
    """DRAGEN-coded pangenome: align + sort + variant call (Illumina PE FASTQ -> VCF)."""
    input:
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        f1=getR1s,
        f2=getR2s,
    output:
        vcfgz=MDIR
        + "{sample}/align/drbwa/snv/drgpg/{sample}.drbwa.drgpg.snv.sort.vcf.gz",
        vcfgztbi=MDIR
        + "{sample}/align/drbwa/snv/drgpg/{sample}.drbwa.drgpg.snv.sort.vcf.gz.tbi",
    log:
        MDIR
        + "{sample}/align/drbwa/snv/drgpg/log/{sample}.drbwa.drgpg.snv.log",
    threads: config["dragen_pangenome"]["threads"]
    conda:
        config["dragen_pangenome"]["env_yaml"]
    priority: 5
    benchmark:
        repeat(
            MDIR + "{sample}/benchmarks/{sample}.drbwa.drgpg.bench.tsv",
            0
            if "bench_repeat" not in config["dragen_pangenome"]
            else config["dragen_pangenome"]["bench_repeat"],
        )
    resources:
        attempt_n=lambda wildcards, attempt: (attempt + 0),
        partition=derive_partition_order(config["dragen_pangenome"]["partition"]),
        threads=config["dragen_pangenome"]["threads"],
        vcpu=config["dragen_pangenome"]["threads"],
        mem_mb=config["dragen_pangenome"]["mem_mb"],
        constraint=config["dragen_pangenome"]["constraint"],
        distribution=config["dragen_pangenome"]["distribution"],
        exclude=config["dragen_pangenome"]["exclude"],
        include=config["dragen_pangenome"]["include"],
        exclusive=config["dragen_pangenome"]["exclusive"],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        hapl=config["dragen_pangenome"]["hapl"],
        gbz=config["dragen_pangenome"]["gbz"],
        model=_dragen_pangenome_model,
        pop_vcf=_dragen_pangenome_pop_vcf,
        canonical_bed=config["dragen_pangenome"]["canonical_bed"],
        dbsnp=config["dragen_pangenome"]["dbsnp"],
        pcr_free=config["dragen_pangenome"]["pcr_free"],
        cli_threads=lambda wildcards: min(int(config["dragen_pangenome"]["threads"]), 128),
        cluster_sample=ret_sample,
        rgpl="ILLUMINA",
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
        export TMPDIR="/scratch/drgpg_tmp_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        if [ ! -d "$TMPDIR" ]; then
            echo "ERROR: Failed to create TMPDIR: $TMPDIR" >> {log} 2>&1;
            exit 5;
        fi
        echo "TMPDIR created: $TMPDIR" >> {log} 2>&1;
        ls -ld "$TMPDIR" >> {log} 2>&1;
        df -h /scratch >> {log} 2>&1;
        export APPTAINER_HOME="$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

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

        pcr_flag="";
        if [[ "{params.pcr_free}" == "true" ]]; then
            pcr_flag="--pcr_free";
        fi

        cli_out="$TMPDIR/{wildcards.sample}.drgpg";

        echo "DRAGEN-coded pangenome align+call starting" >> {log} 2>&1;
        echo "  model={params.model}" >> {log} 2>&1;
        echo "  hapl={params.hapl}" >> {log} 2>&1;
        echo "  gbz={params.gbz}" >> {log} 2>&1;
        set +e;
        bin/dayoa_sentieon_cli dnascope-pangenome \
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
            -t {params.cli_threads} \
            "${{cli_out}}.vcf.gz" >> {log} 2>&1;
        cli_rc=$?;
        set -e;
        echo "sentieon-cli exit code: $cli_rc" >> {log} 2>&1;
        if [ $cli_rc -ne 0 ]; then
            echo "ERROR: bin/dayoa_sentieon_cli dnascope-pangenome failed with exit code $cli_rc" >> {log} 2>&1;
            exit $cli_rc;
        fi

        if [ -f "${{cli_out}}.vcf.gz" ]; then
            oldname=$(bcftools query -l "${{cli_out}}.vcf.gz" | head -n1);
            echo -e "${{oldname}}\\t{params.cluster_sample}" > "$TMPDIR/rename.txt";
            bcftools reheader -s "$TMPDIR/rename.txt" -o {output.vcfgz} "${{cli_out}}.vcf.gz" >> {log} 2>&1;
            bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;
        else
            echo "ERROR: VCF not produced by DRAGEN-coded pangenome rule" >> {log} 2>&1;
            exit 20;
        fi

        end_time=$(date +%s);
        elapsed_time=$((($end_time - $start_time) / 60));
        echo "Elapsed-Time-min:\\t$itype\\t$elapsed_time" >> {log} 2>&1;

        """


localrules:
    clear_combined_sentpg_vcf,
    clear_combined_drgpg_vcf,


rule clear_combined_sentpg_vcf:  # TARGET: clear combined sentpg vcf
    input:
        expand(
            MDIR + "{sample}/align/sent/snv/sentpg/{sample}.sent.sentpg.snv.sort.vcf.gz",
            sample=SAMPS,
        ),
    log:
        MDIR + "logs/clear_combined_sentpg_vcf.log"
    benchmark:
        "logs/benchmarks/clear_combined_sentpg_vcf.bench.tsv"
    threads: 2
    priority: 42
    shell:
        """
        rm {input}*  1> /dev/null  2> /dev/null || echo 'file not found for deletion: {input}';
        """


rule clear_combined_drgpg_vcf:  # TARGET: clear combined drgpg vcf
    input:
        expand(
            MDIR + "{sample}/align/drbwa/snv/drgpg/{sample}.drbwa.drgpg.snv.sort.vcf.gz",
            sample=SAMPS,
        ),
    log:
        MDIR + "logs/clear_combined_drgpg_vcf.log"
    benchmark:
        "logs/benchmarks/clear_combined_drgpg_vcf.bench.tsv"
    threads: 2
    priority: 42
    shell:
        """
        rm {input}*  1> /dev/null  2> /dev/null || echo 'file not found for deletion: {input}';
        """


localrules:
    produce_sentpg_vcf,
    produce_drgpg_vcf,


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
    benchmark:
        "logs/benchmarks/produce_sentpg_vcf.bench.tsv"
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """


rule produce_drgpg_vcf:  # TARGET: explicit DRAGEN pangenome vcf
    input:
        expand(
            MDIR
            + "{sample}/align/drbwa/snv/drgpg/{sample}.drbwa.drgpg.snv.sort.vcf.gz.tbi",
            sample=SAMPS,
        ),
    output:
        "gatheredall.drgpg",
    priority: 48
    threads: 1
    log:
        "gatheredall.drgpg.log",
    benchmark:
        "logs/benchmarks/produce_drgpg_vcf.bench.tsv"
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """
