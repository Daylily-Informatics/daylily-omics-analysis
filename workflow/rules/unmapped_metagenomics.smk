"""Quick metagenomic screen of pass-QC reads unmapped to the human reference."""

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
            "unmapped_metagenomics.max_reads values."
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


def unmapped_metagenomics_threads(wildcards):
    return _unmapped_metagenomics_positive_int("threads", minimum=16)


def unmapped_metagenomics_mem_mb(wildcards):
    return _unmapped_metagenomics_positive_int("mem_mb", minimum=1)


def unmapped_metagenomics_partition(wildcards):
    return str(_unmapped_metagenomics_required("partition"))


def unmapped_metagenomics_max_reads(wildcards):
    return _unmapped_metagenomics_positive_int("max_reads", minimum=1)


def unmapped_metagenomics_kraken2_db(wildcards):
    return str(_unmapped_metagenomics_required("kraken2_db"))


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
    dedupers = qc_alignment_dedupers()
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
    dedupers = qc_alignment_dedupers()
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


localrules:
    unmapped_metagenomics_summary,
    unmapped_metagenomics_multiqc,
    produce_unmapped_metagenomics_quick,


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
        ddup="|".join(qc_alignment_dedupers()) if qc_alignment_dedupers() else r"(?!x)x",
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
        max_reads=unmapped_metagenomics_max_reads,
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
        test {params.max_reads:q} -gt 0 || (echo "ERROR: unmapped_metagenomics.max_reads must be positive for quick runs." | tee -a {log:q}; exit 1)

        samtools quickcheck -v {input.alignment:q} >> {log:q} 2>&1
        samtools view \
            -@ {threads} \
            -T {params.huref_fasta:q} \
            -u \
            -f 4 \
            -F 0xB00 \
            {input.alignment:q} \
          | samtools fastq -@ {params.fastq_threads} -n - \
          | awk -v max_reads={params.max_reads:q} 'NR > max_reads * 4 {{ exit }} {{ print }}' \
          | gzip -c > {output.fastq:q}
        test -s {output.fastq:q} || (echo "ERROR: failed to write unmapped FASTQ: {output.fastq:q}" | tee -a {log:q}; exit 1)

        kraken2 \
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
            --max-reads {params.max_reads:q} \
            --unmapped-fastq {output.fastq:q} \
            --kraken-report {output.report:q} \
            --kraken-output {output.kraken:q} \
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
        config["multiqc"].get("env_yaml", "../envs/multiqc_v0.1.yaml")
    container:
        "docker://multiqc/multiqc:v1.35"
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


rule produce_unmapped_metagenomics_quick:  # TARGET: quick Kraken2 screen of pass-QC human-unmapped reads
    input:
        MDIR + "reports/unmapped_metagenomics.multiqc.html",
