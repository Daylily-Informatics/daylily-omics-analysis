"""Fast metagenomic screen of pass-QC reads unmapped to the human reference."""

from snakemake.exceptions import WorkflowError


def _unmapped_metagenomics_config():
    cfg = config.get("unmapped_metagenomics")
    if not isinstance(cfg, dict):
        raise WorkflowError(
            "produce_unmapped_metagenomics_quick requires an "
            "unmapped_metagenomics config block with explicit "
            "unmapped_metagenomics.kraken2_db, "
            "unmapped_metagenomics.threads, "
            "unmapped_metagenomics.mem_mb, "
            "unmapped_metagenomics.partition, and "
            "unmapped_metagenomics.read_limit='all' values."
        )
    return cfg


def _unmapped_metagenomics_required(key):
    cfg = _unmapped_metagenomics_config()
    value = cfg.get(key)
    if value in [None, "", "None", "na", "NA"]:
        raise WorkflowError(
            f"produce_unmapped_metagenomics_quick requires explicit "
            f"unmapped_metagenomics.{key}."
        )
    return value


def _unmapped_metagenomics_positive_int(key, *, minimum=1):
    value = int(_unmapped_metagenomics_required(key))
    if value < minimum:
        raise WorkflowError(
            f"unmapped_metagenomics.{key} must be >= {minimum}; saw {value}."
        )
    return value


def _unmapped_metagenomics_bool(key, *, default):
    cfg = _unmapped_metagenomics_config()
    value = cfg.get(key, default)
    if isinstance(value, bool):
        return value
    normalized = str(value).strip().lower()
    if normalized == "true":
        return True
    if normalized == "false":
        return False
    raise WorkflowError(
        f"unmapped_metagenomics.{key} must be true or false; saw {value!r}."
    )


def unmapped_metagenomics_threads(wildcards):
    return _unmapped_metagenomics_positive_int("threads", minimum=16)


def unmapped_metagenomics_mem_mb(wildcards):
    return _unmapped_metagenomics_positive_int("mem_mb", minimum=1)


def unmapped_metagenomics_partition(wildcards):
    return str(_unmapped_metagenomics_required("partition"))


def unmapped_metagenomics_read_limit(wildcards):
    cfg = _unmapped_metagenomics_config()
    value = cfg.get("read_limit", "all")
    if str(value).strip() != "all":
        raise WorkflowError(
            "unmapped_metagenomics.read_limit must be 'all'; capped "
            "unmapped-read Kraken2 screening is no longer supported."
        )
    return "all"


def unmapped_metagenomics_memory_mapping_flag(wildcards):
    if _unmapped_metagenomics_bool("memory_mapping", default=False):
        return "--memory-mapping"
    return ""


def unmapped_metagenomics_kraken2_db(wildcards):
    return str(_unmapped_metagenomics_required("kraken2_db"))


def _unmapped_metagenomics_ganon2_config():
    cfg = config.get("unmapped_metagenomics")
    if not isinstance(cfg, dict):
        raise WorkflowError(
            "produce_unmapped_metagenomics_ganon2_quick requires an "
            "unmapped_metagenomics config block with explicit "
            "unmapped_metagenomics.ganon2_db_prefixes, "
            "unmapped_metagenomics.threads, "
            "unmapped_metagenomics.mem_mb, "
            "unmapped_metagenomics.partition, and "
            "unmapped_metagenomics.read_limit='all' values."
        )
    return cfg


def _unmapped_metagenomics_ganon2_required(key):
    cfg = _unmapped_metagenomics_ganon2_config()
    value = cfg.get(key)
    if value in [None, "", "None", "na", "NA"]:
        raise WorkflowError(
            f"produce_unmapped_metagenomics_ganon2_quick requires explicit "
            f"unmapped_metagenomics.{key}."
        )
    return value


def _unmapped_metagenomics_ganon2_positive_int(key, *, minimum=1):
    value = int(_unmapped_metagenomics_ganon2_required(key))
    if value < minimum:
        raise WorkflowError(
            f"unmapped_metagenomics.{key} must be >= {minimum}; saw {value}."
        )
    return value


def unmapped_metagenomics_ganon2_threads(wildcards):
    return _unmapped_metagenomics_ganon2_positive_int("threads", minimum=16)


def unmapped_metagenomics_ganon2_mem_mb(wildcards):
    return _unmapped_metagenomics_ganon2_positive_int("mem_mb", minimum=1)


def unmapped_metagenomics_ganon2_partition(wildcards):
    return str(_unmapped_metagenomics_ganon2_required("partition"))


def unmapped_metagenomics_ganon2_read_limit(wildcards):
    cfg = _unmapped_metagenomics_ganon2_config()
    value = cfg.get("read_limit")
    if str(value).strip() != "all":
        raise WorkflowError(
            "unmapped_metagenomics.read_limit must be explicitly set to 'all'; "
            "capped unmapped-read Ganon2 screening is not supported."
        )
    return "all"


def _unmapped_metagenomics_ganon2_db_prefixes():
    value = _unmapped_metagenomics_ganon2_required("ganon2_db_prefixes")
    prefixes = _as_config_list(value)
    bad = [str(prefix) for prefix in prefixes if str(prefix).strip() in {"", "None", "na", "NA"}]
    if not prefixes or bad:
        raise WorkflowError(
            "produce_unmapped_metagenomics_ganon2_quick requires explicit "
            "non-empty unmapped_metagenomics.ganon2_db_prefixes."
        )
    return [str(prefix) for prefix in prefixes]


def unmapped_metagenomics_ganon2_db_prefixes(wildcards):
    return _unmapped_metagenomics_ganon2_db_prefixes()


def unmapped_metagenomics_ganon2_database_label(wildcards):
    return ";".join(_unmapped_metagenomics_ganon2_db_prefixes())


def _unmapped_metagenomics_sourmash_config():
    cfg = config.get("unmapped_metagenomics")
    if not isinstance(cfg, dict):
        raise WorkflowError(
            "produce_unmapped_metagenomics_sourmash_gather requires an "
            "unmapped_metagenomics config block with explicit "
            "unmapped_metagenomics.sourmash_databases, "
            "unmapped_metagenomics.sourmash_ksize, "
            "unmapped_metagenomics.sourmash_scaled, "
            "unmapped_metagenomics.sourmash_moltype, "
            "unmapped_metagenomics.sourmash_threshold_bp, "
            "unmapped_metagenomics.threads, "
            "unmapped_metagenomics.mem_mb, "
            "unmapped_metagenomics.partition, and "
            "unmapped_metagenomics.read_limit='all' values."
        )
    return cfg


def _unmapped_metagenomics_sourmash_required(key):
    cfg = _unmapped_metagenomics_sourmash_config()
    value = cfg.get(key)
    if value in [None, "", "None", "na", "NA"]:
        raise WorkflowError(
            f"produce_unmapped_metagenomics_sourmash_gather requires explicit "
            f"unmapped_metagenomics.{key}."
        )
    return value


def _unmapped_metagenomics_sourmash_positive_int(key, *, minimum=1):
    value = int(_unmapped_metagenomics_sourmash_required(key))
    if value < minimum:
        raise WorkflowError(
            f"unmapped_metagenomics.{key} must be >= {minimum}; saw {value}."
        )
    return value


def unmapped_metagenomics_sourmash_threads(wildcards):
    return _unmapped_metagenomics_sourmash_positive_int("threads", minimum=16)


def unmapped_metagenomics_sourmash_mem_mb(wildcards):
    return _unmapped_metagenomics_sourmash_positive_int("mem_mb", minimum=1)


def unmapped_metagenomics_sourmash_partition(wildcards):
    return str(_unmapped_metagenomics_sourmash_required("partition"))


def unmapped_metagenomics_sourmash_read_limit(wildcards):
    cfg = _unmapped_metagenomics_sourmash_config()
    value = cfg.get("read_limit")
    if str(value).strip() != "all":
        raise WorkflowError(
            "unmapped_metagenomics.read_limit must be explicitly set to 'all'; "
            "capped unmapped-read sourmash gather fingerprinting is not supported."
        )
    return "all"


def _unmapped_metagenomics_sourmash_databases():
    value = _unmapped_metagenomics_sourmash_required("sourmash_databases")
    databases = _as_config_list(value)
    bad = [
        str(database)
        for database in databases
        if str(database).strip() in {"", "None", "na", "NA"}
    ]
    if not databases or bad:
        raise WorkflowError(
            "produce_unmapped_metagenomics_sourmash_gather requires explicit "
            "non-empty unmapped_metagenomics.sourmash_databases."
        )
    return [str(database) for database in databases]


def unmapped_metagenomics_sourmash_databases(wildcards):
    return _unmapped_metagenomics_sourmash_databases()


def unmapped_metagenomics_sourmash_database_label(wildcards):
    return ";".join(_unmapped_metagenomics_sourmash_databases())


def unmapped_metagenomics_sourmash_ksize(wildcards):
    return _unmapped_metagenomics_sourmash_positive_int("sourmash_ksize", minimum=1)


def unmapped_metagenomics_sourmash_scaled(wildcards):
    return _unmapped_metagenomics_sourmash_positive_int("sourmash_scaled", minimum=1)


def unmapped_metagenomics_sourmash_threshold_bp(wildcards):
    return _unmapped_metagenomics_sourmash_positive_int(
        "sourmash_threshold_bp", minimum=0
    )


def unmapped_metagenomics_sourmash_moltype(wildcards):
    value = str(_unmapped_metagenomics_sourmash_required("sourmash_moltype")).strip()
    if value.upper() != "DNA":
        raise WorkflowError(
            "unmapped_metagenomics.sourmash_moltype must be explicitly set to 'DNA' "
            f"for sourmash gather over human-unmapped sequencing reads; saw {value!r}."
        )
    return "DNA"


def unmapped_metagenomics_ganon2_fastq_threads(wildcards):
    return max(1, min(4, unmapped_metagenomics_ganon2_threads(wildcards)))


def unmapped_metagenomics_sourmash_fastq_threads(wildcards):
    return max(1, min(4, unmapped_metagenomics_sourmash_threads(wildcards)))


def unmapped_metagenomics_fastq_threads(wildcards):
    return max(1, min(4, unmapped_metagenomics_threads(wildcards)))


def unmapped_metagenomics_alignment(wildcards):
    suffix = "bam" if wildcards.alnr in BAM_ALIGNERS else "cram"
    return (
        MDIR
        + f"{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/"
        + f"{wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.{suffix}"
    )


def unmapped_metagenomics_alignment_index(wildcards):
    return unmapped_metagenomics_alignment(wildcards) + (
        ".bai" if wildcards.alnr in BAM_ALIGNERS else ".crai"
    )


def unmapped_metagenomics_stage_mqcs(wildcards):
    aligners = sorted(ALL_ALIGNERS)
    dedupers = qc_contamination_dedupers()
    if not aligners:
        raise WorkflowError(
            "produce_unmapped_metagenomics_quick requires at least one active "
            "aligner via config aligners=[...] or a canonical aligner target."
        )
    if not dedupers:
        raise WorkflowError(
            "produce_unmapped_metagenomics_quick requires at least one active "
            "deduper via config dedupers=[...] or a canonical deduper target."
        )
    return expand(
        MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.unmapped_metagenomics_mqc.tsv",
        sample=SSAMPS,
        alnr=aligners,
        ddup=dedupers,
    )


def unmapped_metagenomics_kraken_reports(wildcards):
    aligners = sorted(ALL_ALIGNERS)
    dedupers = qc_contamination_dedupers()
    if not aligners or not dedupers:
        return []
    return expand(
        MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.kraken2.quick.report.txt",
        sample=SSAMPS,
        alnr=aligners,
        ddup=dedupers,
    )


def unmapped_metagenomics_ganon2_stage_mqcs(wildcards):
    aligners = sorted(ALL_ALIGNERS)
    dedupers = qc_contamination_dedupers()
    if not aligners:
        raise WorkflowError(
            "produce_unmapped_metagenomics_ganon2_quick requires at least one active "
            "aligner via config aligners=[...] or a canonical aligner target."
        )
    if not dedupers:
        raise WorkflowError(
            "produce_unmapped_metagenomics_ganon2_quick requires at least one active "
            "deduper via config dedupers=[...] or a canonical deduper target."
        )
    return expand(
        MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.unmapped_metagenomics_ganon2_mqc.tsv",
        sample=SSAMPS,
        alnr=aligners,
        ddup=dedupers,
    )


def unmapped_metagenomics_ganon2_reports(wildcards):
    aligners = sorted(ALL_ALIGNERS)
    dedupers = qc_contamination_dedupers()
    if not aligners or not dedupers:
        return []
    return expand(
        MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.ganon2.quick.tre",
        sample=SSAMPS,
        alnr=aligners,
        ddup=dedupers,
    )


def unmapped_metagenomics_sourmash_stage_mqcs(wildcards):
    aligners = sorted(ALL_ALIGNERS)
    dedupers = qc_contamination_dedupers()
    if not aligners:
        raise WorkflowError(
            "produce_unmapped_metagenomics_sourmash_gather requires at least one active "
            "aligner via config aligners=[...] or a canonical aligner target."
        )
    if not dedupers:
        raise WorkflowError(
            "produce_unmapped_metagenomics_sourmash_gather requires at least one active "
            "deduper via config dedupers=[...] or a canonical deduper target."
        )
    return expand(
        MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.unmapped_metagenomics_sourmash_mqc.tsv",
        sample=SSAMPS,
        alnr=aligners,
        ddup=dedupers,
    )


def unmapped_metagenomics_sourmash_gather_csvs(wildcards):
    aligners = sorted(ALL_ALIGNERS)
    dedupers = qc_contamination_dedupers()
    if not aligners or not dedupers:
        return []
    return expand(
        MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.sourmash.gather.csv",
        sample=SSAMPS,
        alnr=aligners,
        ddup=dedupers,
    )


localrules:
    unmapped_metagenomics_summary,
    unmapped_metagenomics_multiqc,
    produce_unmapped_metagenomics_quick,
    unmapped_metagenomics_ganon2_summary,
    unmapped_metagenomics_ganon2_multiqc,
    produce_unmapped_metagenomics_ganon2_quick,
    unmapped_metagenomics_sourmash_summary,
    unmapped_metagenomics_sourmash_multiqc,
    produce_unmapped_metagenomics_sourmash_gather,
    produce_metagenomics,


rule unmapped_metagenomics_kraken2_quick:
    input:
        alignment=unmapped_metagenomics_alignment,
        index=unmapped_metagenomics_alignment_index,
    output:
        fastq=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.human_unmapped.quick.fastq.gz",
        report=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.kraken2.quick.report.txt",
        kraken=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.kraken2.quick.output.tsv",
        mqc=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.unmapped_metagenomics_mqc.tsv",
    wildcard_constraints:
        alnr="|".join(ALL_ALIGNERS) if ALL_ALIGNERS else r"(?!x)x",
        ddup="|".join(qc_contamination_dedupers()) if qc_contamination_dedupers() else r"(?!x)x",
    threads: unmapped_metagenomics_threads
    resources:
        threads=unmapped_metagenomics_threads,
        vcpu=unmapped_metagenomics_threads,
        mem_mb=unmapped_metagenomics_mem_mb,
        partition=unmapped_metagenomics_partition,
    benchmark:
        MDIR
        + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.unmapped_metagenomics_kraken2_quick.bench.tsv"
    params:
        cluster_sample=ret_sample,
        huref_fasta=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        kraken2_db=unmapped_metagenomics_kraken2_db,
        read_limit=unmapped_metagenomics_read_limit,
        memory_mapping_flag=unmapped_metagenomics_memory_mapping_flag,
        fastq_threads=unmapped_metagenomics_fastq_threads,
        sample_id=lambda wildcards: day_stage_sample_id(
            wildcards.sample, wildcards.alnr, wildcards.ddup
        ),
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/logs/"
        + "{sample}.{alnr}.{ddup}.unmapped_metagenomics_kraken2_quick.log"
    conda:
        "../envs/unmapped_metagenomics_v0.1.yaml"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.fastq:q}) $(dirname {log:q})
        : > {log:q}

        test -s {input.alignment:q} || (echo "ERROR: missing alignment input: {input.alignment:q}" | tee -a {log:q}; exit 1)
        test -s {input.index:q} || (echo "ERROR: missing alignment index input: {input.index:q}" | tee -a {log:q}; exit 1)
        test -d {params.kraken2_db:q} || (echo "ERROR: unmapped_metagenomics.kraken2_db is not a directory: {params.kraken2_db:q}" | tee -a {log:q}; exit 1)
        test {params.read_limit:q} = all || (echo "ERROR: unmapped_metagenomics.read_limit must be 'all' for full-unmapped mode." | tee -a {log:q}; exit 1)

        samtools quickcheck -v {input.alignment:q} >> {log:q} 2>&1
	        samtools view \
	            -@ {threads} \
	            -T {params.huref_fasta:q} \
            -u \
            -f 4 \
            -F 0xB00 \
            {input.alignment:q} \
          | samtools fastq -@ {params.fastq_threads} -n - \
	          | gzip -c > {output.fastq:q}
	        test -s {output.fastq:q} || (echo "ERROR: failed to write unmapped FASTQ: {output.fastq:q}" | tee -a {log:q}; exit 1)
	        fastq_lines="$(gzip -cd {output.fastq:q} | wc -l | tr -d '[:space:]')"
	        if [ $((fastq_lines % 4)) -ne 0 ]; then
	            echo "ERROR: unmapped FASTQ line count is not divisible by four: {output.fastq:q}" | tee -a {log:q}
	            exit 1
	        fi
	        fastq_reads=$((fastq_lines / 4))
	        if [ "$fastq_reads" -eq 0 ]; then
	            echo "No human-unmapped reads; writing Kraken2 no_unmapped_reads sentinel outputs." | tee -a {log:q}
	            printf '0.00\t0\t0\tU\t0\tunclassified\n' > {output.report:q}
	            : > {output.kraken:q}
	            python workflow/scripts/summarize_unmapped_metagenomics.py \
	                --sample {params.sample_id:q} \
	                --base-sample {wildcards.sample:q} \
	                --aligner {wildcards.alnr:q} \
	                --deduper {wildcards.ddup:q} \
	                --database {params.kraken2_db:q} \
	                --read-limit {params.read_limit:q} \
	                --unmapped-fastq {output.fastq:q} \
	                --kraken-report {output.report:q} \
	                --kraken-output {output.kraken:q} \
	                --output {output.mqc:q} >> {log:q} 2>&1
	            test -s {output.report:q}
	            test -e {output.kraken:q}
	            test -s {output.mqc:q}
	            exit 0
	        fi

	        kraken2 \
            --quick \
            {params.memory_mapping_flag} \
            --db {params.kraken2_db:q} \
            --threads {threads} \
            --gzip-compressed \
            --report {output.report:q} \
            --output {output.kraken:q} \
            {output.fastq:q} >> {log:q} 2>&1
        test -s {output.report:q} || (echo "ERROR: Kraken2 report is empty: {output.report:q}" | tee -a {log:q}; exit 1)
        test -s {output.kraken:q} || (echo "ERROR: Kraken2 output is empty: {output.kraken:q}" | tee -a {log:q}; exit 1)

        python workflow/scripts/summarize_unmapped_metagenomics.py \
            --sample {params.sample_id:q} \
            --base-sample {wildcards.sample:q} \
            --aligner {wildcards.alnr:q} \
            --deduper {wildcards.ddup:q} \
            --database {params.kraken2_db:q} \
            --read-limit {params.read_limit:q} \
            --unmapped-fastq {output.fastq:q} \
            --kraken-report {output.report:q} \
            --kraken-output {output.kraken:q} \
            --output {output.mqc:q} >> {log:q} 2>&1
        test -s {output.mqc:q}
        """


rule unmapped_metagenomics_ganon2_quick:
    input:
        alignment=unmapped_metagenomics_alignment,
        index=unmapped_metagenomics_alignment_index,
    output:
        fastq=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.human_unmapped.ganon2.quick.fastq.gz",
        tre=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.ganon2.quick.tre",
        rep=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.ganon2.quick.rep",
        mqc=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.unmapped_metagenomics_ganon2_mqc.tsv",
    wildcard_constraints:
        alnr="|".join(ALL_ALIGNERS) if ALL_ALIGNERS else r"(?!x)x",
        ddup="|".join(qc_contamination_dedupers()) if qc_contamination_dedupers() else r"(?!x)x",
    threads: unmapped_metagenomics_ganon2_threads
    resources:
        threads=unmapped_metagenomics_ganon2_threads,
        vcpu=unmapped_metagenomics_ganon2_threads,
        mem_mb=unmapped_metagenomics_ganon2_mem_mb,
        partition=unmapped_metagenomics_ganon2_partition,
    benchmark:
        MDIR
        + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.unmapped_metagenomics_ganon2_quick.bench.tsv"
    params:
        cluster_sample=ret_sample,
        huref_fasta=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        ganon2_db_prefixes=unmapped_metagenomics_ganon2_db_prefixes,
        ganon2_database_label=unmapped_metagenomics_ganon2_database_label,
        read_limit=unmapped_metagenomics_ganon2_read_limit,
        fastq_threads=unmapped_metagenomics_ganon2_fastq_threads,
        output_prefix=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.ganon2.quick",
        sample_id=lambda wildcards: day_stage_sample_id(
            wildcards.sample, wildcards.alnr, wildcards.ddup
        ),
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/logs/"
        + "{sample}.{alnr}.{ddup}.unmapped_metagenomics_ganon2_quick.log"
    conda:
        "../envs/unmapped_metagenomics_ganon2_v0.1.yaml"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.fastq:q}) $(dirname {log:q})
        : > {log:q}

        test -s {input.alignment:q} || (echo "ERROR: missing alignment input: {input.alignment:q}" | tee -a {log:q}; exit 1)
        test -s {input.index:q} || (echo "ERROR: missing alignment index input: {input.index:q}" | tee -a {log:q}; exit 1)
        for prefix in {params.ganon2_db_prefixes:q}; do
            if [ ! -s "$prefix".hibf ] && [ ! -s "$prefix".ibf ]; then
                echo "ERROR: unmapped_metagenomics.ganon2_db_prefixes entry must point to a Ganon2 .hibf or .ibf database prefix: $prefix" | tee -a {log:q}
                exit 1
            fi
            test -s "$prefix".tax || (echo "ERROR: unmapped_metagenomics.ganon2_db_prefixes entry is missing required taxonomy file: $prefix.tax" | tee -a {log:q}; exit 1)
        done
        test {params.read_limit:q} = all || (echo "ERROR: unmapped_metagenomics.read_limit must be 'all' for full-unmapped Ganon2 mode." | tee -a {log:q}; exit 1)

        samtools quickcheck -v {input.alignment:q} >> {log:q} 2>&1
        samtools view \
            -@ {threads} \
            -T {params.huref_fasta:q} \
            -u \
            -f 4 \
            -F 0xB00 \
            {input.alignment:q} \
          | samtools fastq -@ {params.fastq_threads} -n - \
	          | gzip -c > {output.fastq:q}
	        test -s {output.fastq:q} || (echo "ERROR: failed to write unmapped FASTQ: {output.fastq:q}" | tee -a {log:q}; exit 1)
	        fastq_lines="$(gzip -cd {output.fastq:q} | wc -l | tr -d '[:space:]')"
	        if [ $((fastq_lines % 4)) -ne 0 ]; then
	            echo "ERROR: unmapped FASTQ line count is not divisible by four: {output.fastq:q}" | tee -a {log:q}
	            exit 1
	        fi
	        fastq_reads=$((fastq_lines / 4))
	        if [ "$fastq_reads" -eq 0 ]; then
	            echo "No human-unmapped reads; writing Ganon2 no_unmapped_reads sentinel outputs." | tee -a {log:q}
	            printf 'unclassified\tunclassified\t\tunclassified\t0\t0\t0\t0\t0.00000\n' > {output.tre:q}
	            printf '#total_classified\t0\n#total_unclassified\t0\n' > {output.rep:q}
	            python workflow/scripts/summarize_unmapped_ganon2.py \
	                --sample {params.sample_id:q} \
	                --base-sample {wildcards.sample:q} \
	                --aligner {wildcards.alnr:q} \
	                --deduper {wildcards.ddup:q} \
	                --database {params.ganon2_database_label:q} \
	                --read-limit {params.read_limit:q} \
	                --unmapped-fastq {output.fastq:q} \
	                --ganon2-report {output.tre:q} \
	                --ganon2-rep {output.rep:q} \
	                --output {output.mqc:q} >> {log:q} 2>&1
	            test -s {output.tre:q}
	            test -s {output.rep:q}
	            test -s {output.mqc:q}
	            exit 0
	        fi

	        ganon classify \
            --db-prefix {params.ganon2_db_prefixes:q} \
            --output-prefix {params.output_prefix:q} \
            --single-reads {output.fastq:q} \
            --threads {threads} >> {log:q} 2>&1
        test -s {output.tre:q} || (echo "ERROR: Ganon2 tree report is empty: {output.tre:q}" | tee -a {log:q}; exit 1)
        test -s {output.rep:q} || (echo "ERROR: Ganon2 rep output is empty: {output.rep:q}" | tee -a {log:q}; exit 1)

        python workflow/scripts/summarize_unmapped_ganon2.py \
            --sample {params.sample_id:q} \
            --base-sample {wildcards.sample:q} \
            --aligner {wildcards.alnr:q} \
            --deduper {wildcards.ddup:q} \
            --database {params.ganon2_database_label:q} \
            --read-limit {params.read_limit:q} \
            --unmapped-fastq {output.fastq:q} \
            --ganon2-report {output.tre:q} \
            --ganon2-rep {output.rep:q} \
            --output {output.mqc:q} >> {log:q} 2>&1
        test -s {output.mqc:q}
        """


rule unmapped_metagenomics_sourmash_gather:
    input:
        alignment=unmapped_metagenomics_alignment,
        index=unmapped_metagenomics_alignment_index,
    output:
        fastq=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.human_unmapped.sourmash.fastq.gz",
        sig=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.sourmash.sig",
        gather_csv=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.sourmash.gather.csv",
        mqc=MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/"
        + "{sample}.{alnr}.{ddup}.unmapped_metagenomics_sourmash_mqc.tsv",
    wildcard_constraints:
        alnr="|".join(ALL_ALIGNERS) if ALL_ALIGNERS else r"(?!x)x",
        ddup="|".join(qc_contamination_dedupers()) if qc_contamination_dedupers() else r"(?!x)x",
    threads: unmapped_metagenomics_sourmash_threads
    resources:
        threads=unmapped_metagenomics_sourmash_threads,
        vcpu=unmapped_metagenomics_sourmash_threads,
        mem_mb=unmapped_metagenomics_sourmash_mem_mb,
        partition=unmapped_metagenomics_sourmash_partition,
    benchmark:
        MDIR
        + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.unmapped_metagenomics_sourmash_gather.bench.tsv"
    params:
        cluster_sample=ret_sample,
        huref_fasta=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        sourmash_databases=unmapped_metagenomics_sourmash_databases,
        sourmash_database_label=unmapped_metagenomics_sourmash_database_label,
        sourmash_ksize=unmapped_metagenomics_sourmash_ksize,
        sourmash_scaled=unmapped_metagenomics_sourmash_scaled,
        sourmash_moltype=unmapped_metagenomics_sourmash_moltype,
        sourmash_threshold_bp=unmapped_metagenomics_sourmash_threshold_bp,
        read_limit=unmapped_metagenomics_sourmash_read_limit,
        fastq_threads=unmapped_metagenomics_sourmash_fastq_threads,
        sample_id=lambda wildcards: day_stage_sample_id(
            wildcards.sample, wildcards.alnr, wildcards.ddup
        ),
    log:
        MDIR
        + "{sample}/align/{alnr}/{ddup}/alignqc/unmapped_metagenomics/logs/"
        + "{sample}.{alnr}.{ddup}.unmapped_metagenomics_sourmash_gather.log"
    conda:
        "../envs/unmapped_metagenomics_sourmash_v0.1.yaml"
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.fastq:q}) $(dirname {log:q})
        : > {log:q}

        test -s {input.alignment:q} || (echo "ERROR: missing alignment input: {input.alignment:q}" | tee -a {log:q}; exit 1)
        test -s {input.index:q} || (echo "ERROR: missing alignment index input: {input.index:q}" | tee -a {log:q}; exit 1)
        for database in {params.sourmash_databases:q}; do
            if [ ! -s "$database" ] && [ ! -d "$database" ]; then
                echo "ERROR: unmapped_metagenomics.sourmash_databases entry is not a readable sourmash collection path: $database" | tee -a {log:q}
                exit 1
            fi
        done
        test {params.read_limit:q} = all || (echo "ERROR: unmapped_metagenomics.read_limit must be 'all' for full-unmapped sourmash gather mode." | tee -a {log:q}; exit 1)
        test {params.sourmash_moltype:q} = DNA || (echo "ERROR: unmapped_metagenomics.sourmash_moltype must be 'DNA'." | tee -a {log:q}; exit 1)

        samtools quickcheck -v {input.alignment:q} >> {log:q} 2>&1
        samtools view \
            -@ {threads} \
            -T {params.huref_fasta:q} \
            -u \
            -f 4 \
            -F 0xB00 \
            {input.alignment:q} \
          | samtools fastq -@ {params.fastq_threads} -n - \
	          | gzip -c > {output.fastq:q}
	        test -s {output.fastq:q} || (echo "ERROR: failed to write unmapped FASTQ: {output.fastq:q}" | tee -a {log:q}; exit 1)
	        fastq_lines="$(gzip -cd {output.fastq:q} | wc -l | tr -d '[:space:]')"
	        if [ $((fastq_lines % 4)) -ne 0 ]; then
	            echo "ERROR: unmapped FASTQ line count is not divisible by four: {output.fastq:q}" | tee -a {log:q}
	            exit 1
	        fi
	        fastq_reads=$((fastq_lines / 4))
	        if [ "$fastq_reads" -eq 0 ]; then
	            echo "No human-unmapped reads; writing sourmash no_unmapped_reads sentinel outputs." | tee -a {log:q}
	            printf '%s\n' '{{"class":"sourmash_signature","signatures":[],"dayoa_status":"no_unmapped_reads"}}' > {output.sig:q}
	            printf '%s\n' 'unique_intersect_bp,intersect_bp,f_unique_to_query,f_unique_weighted,filename,name,md5,gather_result_rank,query_bp,ksize,moltype,scaled,query_n_hashes' > {output.gather_csv:q}
	            python workflow/scripts/summarize_unmapped_sourmash.py \
	                --sample {params.sample_id:q} \
	                --base-sample {wildcards.sample:q} \
	                --aligner {wildcards.alnr:q} \
	                --deduper {wildcards.ddup:q} \
	                --database {params.sourmash_database_label:q} \
	                --read-limit {params.read_limit:q} \
	                --unmapped-fastq {output.fastq:q} \
	                --sourmash-signature {output.sig:q} \
	                --sourmash-gather-csv {output.gather_csv:q} \
	                --sourmash-ksize {params.sourmash_ksize} \
	                --sourmash-scaled {params.sourmash_scaled} \
	                --sourmash-moltype {params.sourmash_moltype:q} \
	                --sourmash-threshold-bp {params.sourmash_threshold_bp} \
	                --output {output.mqc:q} >> {log:q} 2>&1
	            test -s {output.sig:q}
	            test -s {output.gather_csv:q}
	            test -s {output.mqc:q}
	            exit 0
	        fi

	        sourmash --version >> {log:q} 2>&1
        sourmash sketch dna \
            --name {params.sample_id:q} \
            -p k={params.sourmash_ksize},scaled={params.sourmash_scaled},abund \
            -o {output.sig:q} \
            {output.fastq:q} >> {log:q} 2>&1
        test -s {output.sig:q} || (echo "ERROR: sourmash signature is empty: {output.sig:q}" | tee -a {log:q}; exit 1)

        sourmash gather \
            --threshold-bp {params.sourmash_threshold_bp} \
            -o {output.gather_csv:q} \
            {output.sig:q} \
            {params.sourmash_databases:q} >> {log:q} 2>&1
        test -s {output.gather_csv:q} || (echo "ERROR: sourmash gather CSV is empty: {output.gather_csv:q}" | tee -a {log:q}; exit 1)

        python workflow/scripts/summarize_unmapped_sourmash.py \
            --sample {params.sample_id:q} \
            --base-sample {wildcards.sample:q} \
            --aligner {wildcards.alnr:q} \
            --deduper {wildcards.ddup:q} \
            --database {params.sourmash_database_label:q} \
            --read-limit {params.read_limit:q} \
            --unmapped-fastq {output.fastq:q} \
            --sourmash-signature {output.sig:q} \
            --sourmash-gather-csv {output.gather_csv:q} \
            --sourmash-ksize {params.sourmash_ksize} \
            --sourmash-scaled {params.sourmash_scaled} \
            --sourmash-moltype {params.sourmash_moltype:q} \
            --sourmash-threshold-bp {params.sourmash_threshold_bp} \
            --output {output.mqc:q} >> {log:q} 2>&1
        test -s {output.mqc:q}
        """


rule unmapped_metagenomics_summary:
    input:
        mqcs=unmapped_metagenomics_stage_mqcs,
    output:
        mqc=MDIR + "other_reports/unmapped_metagenomics_mqc.tsv",
    log:
        MDIR + "other_reports/logs/unmapped_metagenomics_summary.log",
    benchmark:
        MDIR + "benchmarks/unmapped_metagenomics_summary.bench.tsv"
    container: None
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.mqc:q}) $(dirname {log:q})
        : > {log:q}
        first=1
        for mqc in {input.mqcs:q}; do
            test -s "$mqc" || (echo "ERROR: missing per-sample unmapped metagenomics MQC TSV: $mqc" | tee -a {log:q}; exit 1)
            if [ "$first" -eq 1 ]; then
                cat "$mqc" > {output.mqc:q}
                first=0
            else
                tail -n +2 "$mqc" >> {output.mqc:q}
            fi
        done
        test "$first" -eq 0 || (echo "ERROR: no unmapped metagenomics MQC inputs were available." | tee -a {log:q}; exit 1)
        test -s {output.mqc:q}
        """


rule unmapped_metagenomics_ganon2_summary:
    input:
        mqcs=unmapped_metagenomics_ganon2_stage_mqcs,
    output:
        mqc=MDIR + "other_reports/unmapped_metagenomics_ganon2_mqc.tsv",
    log:
        MDIR + "other_reports/logs/unmapped_metagenomics_ganon2_summary.log",
    benchmark:
        MDIR + "benchmarks/unmapped_metagenomics_ganon2_summary.bench.tsv"
    container: None
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.mqc:q}) $(dirname {log:q})
        : > {log:q}
        first=1
        for mqc in {input.mqcs:q}; do
            test -s "$mqc" || (echo "ERROR: missing per-sample unmapped Ganon2 MQC TSV: $mqc" | tee -a {log:q}; exit 1)
            if [ "$first" -eq 1 ]; then
                cat "$mqc" > {output.mqc:q}
                first=0
            else
                tail -n +2 "$mqc" >> {output.mqc:q}
            fi
        done
        test "$first" -eq 0 || (echo "ERROR: no unmapped Ganon2 MQC inputs were available." | tee -a {log:q}; exit 1)
        test -s {output.mqc:q}
        """


rule unmapped_metagenomics_sourmash_summary:
    input:
        mqcs=unmapped_metagenomics_sourmash_stage_mqcs,
    output:
        mqc=MDIR + "other_reports/unmapped_metagenomics_sourmash_mqc.tsv",
    log:
        MDIR + "other_reports/logs/unmapped_metagenomics_sourmash_summary.log",
    benchmark:
        MDIR + "benchmarks/unmapped_metagenomics_sourmash_summary.bench.tsv"
    container: None
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.mqc:q}) $(dirname {log:q})
        : > {log:q}
        first=1
        for mqc in {input.mqcs:q}; do
            test -s "$mqc" || (echo "ERROR: missing per-sample unmapped sourmash MQC TSV: $mqc" | tee -a {log:q}; exit 1)
            if [ "$first" -eq 1 ]; then
                cat "$mqc" > {output.mqc:q}
                first=0
            else
                tail -n +2 "$mqc" >> {output.mqc:q}
            fi
        done
        test "$first" -eq 0 || (echo "ERROR: no unmapped sourmash MQC inputs were available." | tee -a {log:q}; exit 1)
        test -s {output.mqc:q}
        """


rule unmapped_metagenomics_multiqc:
    input:
        summary=MDIR + "other_reports/unmapped_metagenomics_mqc.tsv",
        reports=unmapped_metagenomics_kraken_reports,
    output:
        html=MDIR + "reports/unmapped_metagenomics.multiqc.html",
        config=MDIR + "reports/unmapped_metagenomics_multiqc_config.yaml",
    threads: config["multiqc"]["threads"]
    resources:
        threads=config["multiqc"]["threads"],
        vcpu=config["multiqc"]["threads"],
        partition=config["multiqc"]["partition"],
    benchmark:
        MDIR + "benchmarks/all.unmapped_metagenomics_multiqc.bench.tsv"
    log:
        MDIR + "reports/logs/unmapped_metagenomics_multiqc.log"
    params:
        cluster_sample="unmapped_metagenomics_multiqc",
        odir=MDIR + "reports",
        filename="unmapped_metagenomics.multiqc.html",
    conda:
        "../envs/multiqc_v0.1.yaml"
    shell:
        """
        set -euo pipefail
        mkdir -p {params.odir:q} $(dirname {log:q})
        : > {log:q}
        test -s {input.summary:q} || (echo "ERROR: missing unmapped metagenomics summary: {input.summary:q}" | tee -a {log:q}; exit 1)

        printf '%s\n' 'custom_data:' > {output.config:q}
        printf '%s\n' '  unmapped_metagenomics:' >> {output.config:q}
        printf '%s\n' "    id: 'unmapped_metagenomics'" >> {output.config:q}
        printf '%s\n' "    section_name: 'Unmapped-read Metagenomics'" >> {output.config:q}
        printf '%s\n' "    description: 'Kraken2 classification summary for pass-QC human-unmapped reads'" >> {output.config:q}
        printf '%s\n' "    file_format: 'tsv'" >> {output.config:q}
        printf '%s\n' "    plot_type: 'table'" >> {output.config:q}
        printf '%s\n' '    pconfig:' >> {output.config:q}
        printf '%s\n' "      id: 'unmapped_metagenomics'" >> {output.config:q}
        printf '%s\n' 'sp:' >> {output.config:q}
        printf '%s\n' '  unmapped_metagenomics:' >> {output.config:q}
        printf '%s\n' '    fn: "other_reports/unmapped_metagenomics_mqc.tsv"' >> {output.config:q}
        printf '%s\n' 'module_order:' >> {output.config:q}
        printf '%s\n' '  - kraken' >> {output.config:q}
        printf '%s\n' '  - custom_content' >> {output.config:q}
        printf '%s\n' '  - unmapped_metagenomics' >> {output.config:q}

        multiqc --version >> {log:q} 2>&1 || true
        multiqc -f \
            -m kraken \
            -m custom_content \
            --config {output.config:q} \
            --filename {params.filename:q} \
            --outdir {params.odir:q} \
            --interactive \
            {MDIR:q} >> {log:q} 2>&1
        test -s {output.html:q}
        """


rule unmapped_metagenomics_ganon2_multiqc:
    input:
        summary=MDIR + "other_reports/unmapped_metagenomics_ganon2_mqc.tsv",
        reports=unmapped_metagenomics_ganon2_reports,
    output:
        html=MDIR + "reports/unmapped_metagenomics_ganon2.multiqc.html",
        config=MDIR + "reports/unmapped_metagenomics_ganon2_multiqc_config.yaml",
    threads: config["multiqc"]["threads"]
    resources:
        threads=config["multiqc"]["threads"],
        vcpu=config["multiqc"]["threads"],
        partition=config["multiqc"]["partition"],
    benchmark:
        MDIR + "benchmarks/all.unmapped_metagenomics_ganon2_multiqc.bench.tsv"
    log:
        MDIR + "reports/logs/unmapped_metagenomics_ganon2_multiqc.log"
    params:
        cluster_sample="unmapped_metagenomics_ganon2_multiqc",
        odir=MDIR + "reports",
        filename="unmapped_metagenomics_ganon2.multiqc.html",
    conda:
        "../envs/multiqc_v0.1.yaml"
    shell:
        """
        set -euo pipefail
        mkdir -p {params.odir:q} $(dirname {log:q})
        : > {log:q}
        test -s {input.summary:q} || (echo "ERROR: missing unmapped Ganon2 summary: {input.summary:q}" | tee -a {log:q}; exit 1)

        printf '%s\n' 'custom_data:' > {output.config:q}
        printf '%s\n' '  unmapped_metagenomics_ganon2:' >> {output.config:q}
        printf '%s\n' "    id: 'unmapped_metagenomics_ganon2'" >> {output.config:q}
        printf '%s\n' "    section_name: 'Unmapped-read Ganon2 Metagenomics'" >> {output.config:q}
        printf '%s\n' "    description: 'Ganon2 classification summary for pass-QC human-unmapped reads'" >> {output.config:q}
        printf '%s\n' "    file_format: 'tsv'" >> {output.config:q}
        printf '%s\n' "    plot_type: 'table'" >> {output.config:q}
        printf '%s\n' '    pconfig:' >> {output.config:q}
        printf '%s\n' "      id: 'unmapped_metagenomics_ganon2'" >> {output.config:q}
        printf '%s\n' 'sp:' >> {output.config:q}
        printf '%s\n' '  unmapped_metagenomics_ganon2:' >> {output.config:q}
        printf '%s\n' '    fn: "other_reports/unmapped_metagenomics_ganon2_mqc.tsv"' >> {output.config:q}
        printf '%s\n' 'module_order:' >> {output.config:q}
        printf '%s\n' '  - custom_content' >> {output.config:q}
        printf '%s\n' '  - unmapped_metagenomics_ganon2' >> {output.config:q}

        multiqc --version >> {log:q} 2>&1 || true
        multiqc -f \
            -m custom_content \
            --config {output.config:q} \
            --filename {params.filename:q} \
            --outdir {params.odir:q} \
            --interactive \
            {MDIR:q} >> {log:q} 2>&1
        test -s {output.html:q}
        """


rule unmapped_metagenomics_sourmash_multiqc:
    input:
        summary=MDIR + "other_reports/unmapped_metagenomics_sourmash_mqc.tsv",
        gather_csvs=unmapped_metagenomics_sourmash_gather_csvs,
    output:
        html=MDIR + "reports/unmapped_metagenomics_sourmash.multiqc.html",
        config=MDIR + "reports/unmapped_metagenomics_sourmash_multiqc_config.yaml",
    threads: config["multiqc"]["threads"]
    resources:
        threads=config["multiqc"]["threads"],
        vcpu=config["multiqc"]["threads"],
        partition=config["multiqc"]["partition"],
    benchmark:
        MDIR + "benchmarks/all.unmapped_metagenomics_sourmash_multiqc.bench.tsv"
    log:
        MDIR + "reports/logs/unmapped_metagenomics_sourmash_multiqc.log"
    params:
        cluster_sample="unmapped_metagenomics_sourmash_multiqc",
        odir=MDIR + "reports",
        filename="unmapped_metagenomics_sourmash.multiqc.html",
    conda:
        "../envs/multiqc_v0.1.yaml"
    shell:
        """
        set -euo pipefail
        mkdir -p {params.odir:q} $(dirname {log:q})
        : > {log:q}
        test -s {input.summary:q} || (echo "ERROR: missing unmapped sourmash summary: {input.summary:q}" | tee -a {log:q}; exit 1)

        printf '%s\n' 'custom_data:' > {output.config:q}
        printf '%s\n' '  unmapped_metagenomics_sourmash:' >> {output.config:q}
        printf '%s\n' "    id: 'unmapped_metagenomics_sourmash'" >> {output.config:q}
        printf '%s\n' "    section_name: 'Unmapped-read Sourmash Gather Fingerprint'" >> {output.config:q}
        printf '%s\n' "    description: 'sourmash gather secondary fingerprint summary for pass-QC human-unmapped reads'" >> {output.config:q}
        printf '%s\n' "    file_format: 'tsv'" >> {output.config:q}
        printf '%s\n' "    plot_type: 'table'" >> {output.config:q}
        printf '%s\n' '    pconfig:' >> {output.config:q}
        printf '%s\n' "      id: 'unmapped_metagenomics_sourmash'" >> {output.config:q}
        printf '%s\n' 'sp:' >> {output.config:q}
        printf '%s\n' '  unmapped_metagenomics_sourmash:' >> {output.config:q}
        printf '%s\n' '    fn: "other_reports/unmapped_metagenomics_sourmash_mqc.tsv"' >> {output.config:q}
        printf '%s\n' 'module_order:' >> {output.config:q}
        printf '%s\n' '  - custom_content' >> {output.config:q}
        printf '%s\n' '  - unmapped_metagenomics_sourmash' >> {output.config:q}

        multiqc --version >> {log:q} 2>&1 || true
        multiqc -f \
            -m custom_content \
            --config {output.config:q} \
            --filename {params.filename:q} \
            --outdir {params.odir:q} \
            --interactive \
            {MDIR:q} >> {log:q} 2>&1
        test -s {output.html:q}
        """


rule produce_unmapped_metagenomics_quick:  # TARGET: quick Kraken2 screen of pass-QC human-unmapped reads
    input:
        MDIR + "reports/unmapped_metagenomics.multiqc.html",


    log:
        MDIR + "logs/produce_unmapped_metagenomics_quick.log"
rule produce_unmapped_metagenomics_ganon2_quick:  # TARGET: quick Ganon2 screen of pass-QC human-unmapped reads
    input:
        MDIR + "reports/unmapped_metagenomics_ganon2.multiqc.html",


    log:
        MDIR + "logs/produce_unmapped_metagenomics_ganon2_quick.log"
rule produce_unmapped_metagenomics_sourmash_gather:  # TARGET: sourmash gather fingerprint of pass-QC human-unmapped reads
    input:
        MDIR + "reports/unmapped_metagenomics_sourmash.multiqc.html",


    log:
        MDIR + "logs/produce_unmapped_metagenomics_sourmash_gather.log"
rule produce_metagenomics:  # TARGET: run Kraken2, Ganon2, and sourmash gather metagenomics evidence
    input:
        MDIR + "reports/unmapped_metagenomics.multiqc.html",
        MDIR + "reports/unmapped_metagenomics_ganon2.multiqc.html",
        MDIR + "reports/unmapped_metagenomics_sourmash.multiqc.html",
    log:
        MDIR + "logs/produce_metagenomics.log"
