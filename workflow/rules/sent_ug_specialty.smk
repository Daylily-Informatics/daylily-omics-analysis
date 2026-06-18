"""Ultima-only Sentieon specialty callers.

These experimental targets consume the normalized Ultima CRAM at
``align/ug/{sample}.cram`` and write ``sentdug`` specialty outputs.  Sentieon
SV is intentionally blocked until a supported Ultima-only SV algorithm is
verified; the existing Sentieon SV implementation is LongReadSV-based and
requires ONT or PacBio input.
"""

from snakemake.exceptions import WorkflowError


SENTDUG_SPECIALTY_CFG = config["sentdug"]


def _sentdug_required_config(key):
    value = str(SENTDUG_SPECIALTY_CFG.get(key, "") or "").strip()
    if not value:
        raise WorkflowError(f"sentdug.{key} is required for Ultima specialty callers.")
    return value


def _sentdug_int_config(key):
    value = SENTDUG_SPECIALTY_CFG.get(key)
    try:
        return int(value)
    except (TypeError, ValueError) as exc:
        raise WorkflowError(f"sentdug.{key} must be an integer; observed {value!r}.") from exc


def _sentdug_segdup_genes():
    genes = [
        gene.strip()
        for gene in _sentdug_required_config("segdup_genes").split(",")
        if gene.strip()
    ]
    if not genes:
        raise WorkflowError("sentdug.segdup_genes must contain at least one gene.")
    return genes


def _sentdug_segdup_result_gene(gene):
    return "GBA1" if gene == "GBA" else gene


def _sentdug_bool_config(key):
    return str(SENTDUG_SPECIALTY_CFG.get(key, "false")).strip().lower() in {
        "1",
        "true",
        "yes",
        "y",
    }


def _sentdug_sv_target_inputs(wildcards):
    if not _sentdug_bool_config("sv_supported"):
        reason = str(
            SENTDUG_SPECIALTY_CFG.get(
                "sv_block_reason",
                "Sentieon Ultima-only SV support has not been verified.",
            )
        ).strip()
        raise WorkflowError(f"produce_sentdug_sv is intentionally blocked: {reason}")
    algorithm = _sentdug_required_config("sv_algorithm")
    raise WorkflowError(
        "produce_sentdug_sv has no implemented Ultima-only Sentieon SV command "
        f"for sentdug.sv_algorithm={algorithm!r}. Add a supported command before "
        "enabling this target."
    )


SENTDUG_SEGDUP_GENES = _sentdug_segdup_genes()
SENTDUG_SPECIALTY_THREADS = _sentdug_int_config("specialty_threads")
SENTDUG_SPECIALTY_USE_THREADS = _sentdug_int_config("specialty_use_threads")
SENTDUG_SPECIALTY_MEM_MB = _sentdug_int_config("specialty_mem_mb")
SENTDUG_CNV_THREADS = _sentdug_int_config("cnv_threads")
SENTDUG_CNV_USE_THREADS = _sentdug_int_config("cnv_use_threads")
SENTDUG_CNV_MEM_MB = _sentdug_int_config("cnv_mem_mb")
SENTDUG_SEGDUP_THREADS = _sentdug_int_config("segdup_threads")
SENTDUG_SEGDUP_MEM_MB = _sentdug_int_config("segdup_mem_mb")
SENTDUG_MITO_THREADS = _sentdug_int_config("mito_threads")
SENTDUG_MITO_USE_THREADS = _sentdug_int_config("mito_use_threads")
SENTDUG_MITO_MEM_MB = _sentdug_int_config("mito_mem_mb")


rule sentdug_specialty_bam:
    """Materialize a temporary coordinate BAM from the normalized Ultima CRAM."""
    input:
        cram=MDIR + "{sample}/align/ug/{sample}.cram",
        crai=MDIR + "{sample}/align/ug/{sample}.cram.crai",
    output:
        bam=temp(
            MDIR
            + "{sample}/align/ug/na/sentieon_specialty/{sample}.ug.na.sentdug.specialty.bam"
        ),
        bai=temp(
            MDIR
            + "{sample}/align/ug/na/sentieon_specialty/{sample}.ug.na.sentdug.specialty.bam.bai"
        ),
    log:
        MDIR + "{sample}/align/ug/na/sentieon_specialty/logs/{sample}.ug.na.sentdug.specialty_bam.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.ug.na.sentdug.specialty_bam.bench.tsv"
    threads: SENTDUG_SPECIALTY_THREADS
    conda:
        SENTDUG_SPECIALTY_CFG["env_yaml"]
    resources:
        partition=SENTDUG_SPECIALTY_CFG["specialty_partition"],
        threads=SENTDUG_SPECIALTY_THREADS,
        vcpu=SENTDUG_SPECIALTY_THREADS,
        mem_mb=SENTDUG_SPECIALTY_MEM_MB,
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        use_threads=SENTDUG_SPECIALTY_USE_THREADS,
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        mkdir -p $(dirname {output.bam:q}) $(dirname {log:q})
        : > {log:q}
        test -s {input.cram:q}
        test -s {input.crai:q}
        test -s {params.huref:q}
        samtools quickcheck {input.cram:q} >> {log:q} 2>&1
        samtools view -@ {params.use_threads} -T {params.huref:q} \
          -b -o {output.bam:q} {input.cram:q} >> {log:q} 2>&1
        test -s {output.bam:q}
        samtools index -@ {params.use_threads} {output.bam:q} {output.bai:q} >> {log:q} 2>&1
        test -s {output.bai:q}
        samtools quickcheck {output.bam:q} >> {log:q} 2>&1
        """


rule sentdug_call_cnvs:
    """Call Ultima-only Sentieon CNVs with CNVscope and CNVModelApply."""
    input:
        cram=MDIR + "{sample}/align/ug/{sample}.cram",
        crai=MDIR + "{sample}/align/ug/{sample}.cram.crai",
    output:
        cnv_vcf=MDIR + "{sample}/align/ug/na/cnv/sentdug/{sample}.ug.na.sentdug.cnv.vcf.gz",
        cnv_tbi=MDIR + "{sample}/align/ug/na/cnv/sentdug/{sample}.ug.na.sentdug.cnv.vcf.gz.tbi",
    log:
        MDIR + "{sample}/align/ug/na/cnv/sentdug/logs/{sample}.ug.na.sentdug.cnv.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.ug.na.sentdug.cnv.bench.tsv"
    threads: SENTDUG_CNV_THREADS
    conda:
        SENTDUG_SPECIALTY_CFG["env_yaml"]
    resources:
        partition=SENTDUG_SPECIALTY_CFG["specialty_partition"],
        threads=SENTDUG_CNV_THREADS,
        vcpu=SENTDUG_CNV_THREADS,
        mem_mb=SENTDUG_CNV_MEM_MB,
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cnv_model=_sentdug_required_config("cnv_model"),
        use_threads=SENTDUG_CNV_USE_THREADS,
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/
        mkdir -p $(dirname {output.cnv_vcf:q}) $(dirname {log:q})
        : > {log:q}
        test -s {input.cram:q}
        test -s {input.crai:q}
        test -s {params.huref:q}
        test -s {params.cnv_model:q}
        samtools quickcheck {input.cram:q} >> {log:q} 2>&1

        timestamp=$(date +%Y%m%d%H%M%S)_$$
        tmp_parent="${{TMPDIR:-/tmp}}"
        test -d "$tmp_parent"
        test -w "$tmp_parent"
        export TMPDIR=$(mktemp -d "${{tmp_parent%/}}/sentdug_cnv_${{timestamp}}.XXXXXX")
        export SENTIEON_TMPDIR="$TMPDIR"
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT

        tmp_cnv_vcf="$TMPDIR/cnvscope_tmp.vcf.gz"
        bin/dayoa_sentieon driver -r {params.huref:q} -t {params.use_threads} \
          --temp_dir "$TMPDIR" \
          -i {input.cram:q} \
          --algo CNVscope \
          --model {params.cnv_model:q} \
          "$tmp_cnv_vcf" >> {log:q} 2>&1
        test -s "$tmp_cnv_vcf"

        bin/dayoa_sentieon driver -r {params.huref:q} -t {params.use_threads} \
          --temp_dir "$TMPDIR" \
          --algo CNVModelApply \
          --model {params.cnv_model:q} \
          -v "$tmp_cnv_vcf" \
          {output.cnv_vcf:q} >> {log:q} 2>&1
        test -s {output.cnv_vcf:q}
        bcftools index -t -f {output.cnv_vcf:q} >> {log:q} 2>&1
        test -s {output.cnv_tbi:q}
        bcftools view -h {output.cnv_vcf:q} >/dev/null
        """


rule sentdug_call_segdup_gene:
    """Call one segmental-duplication gene from Ultima short-read data."""
    input:
        cram=MDIR + "{sample}/align/ug/{sample}.cram",
        crai=MDIR + "{sample}/align/ug/{sample}.cram.crai",
        segdup_population_vcf=_sentdug_required_config("segdup_population_vcf"),
    output:
        vcf=MDIR
        + "{sample}/align/ug/na/segdup/sentdug/results/{gene}/{sample}.{gene}.result.vcf.gz",
        tbi=MDIR
        + "{sample}/align/ug/na/segdup/sentdug/results/{gene}/{sample}.{gene}.result.vcf.gz.tbi",
        yaml=MDIR
        + "{sample}/align/ug/na/segdup/sentdug/results/{gene}/{sample}.{gene}.yaml",
        done=MDIR
        + "{sample}/align/ug/na/segdup/sentdug/{sample}.ug.na.sentdug.segdup.{gene}.done",
    wildcard_constraints:
        gene="|".join(SENTDUG_SEGDUP_GENES),
    log:
        MDIR + "{sample}/align/ug/na/segdup/sentdug/logs/{sample}.ug.na.sentdug.segdup.{gene}.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.ug.na.sentdug.segdup.{gene}.bench.tsv"
    threads: SENTDUG_SEGDUP_THREADS
    conda:
        "../envs/segdup_v0.2.yaml"
    resources:
        partition=SENTDUG_SPECIALTY_CFG["specialty_partition"],
        threads=SENTDUG_SEGDUP_THREADS,
        vcpu=SENTDUG_SEGDUP_THREADS,
        mem_mb=SENTDUG_SEGDUP_MEM_MB,
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        sr_model=_sentdug_required_config("segdup_sr_model"),
        outdir=lambda wildcards: (
            f"{MDIR}{wildcards.sample}/align/ug/na/segdup/sentdug/results/{wildcards.gene}"
        ),
        caller_yaml=lambda wildcards: (
            f"{MDIR}{wildcards.sample}/align/ug/na/segdup/sentdug/results/"
            f"{wildcards.gene}/{wildcards.sample}.yaml"
        ),
        result_gene=lambda wildcards: _sentdug_segdup_result_gene(wildcards.gene),
        caller_vcf=lambda wildcards: (
            f"{MDIR}{wildcards.sample}/align/ug/na/segdup/sentdug/results/"
            f"{wildcards.gene}/{wildcards.sample}."
            f"{_sentdug_segdup_result_gene(wildcards.gene)}.result.vcf.gz"
        ),
        caller_tbi=lambda wildcards: (
            f"{MDIR}{wildcards.sample}/align/ug/na/segdup/sentdug/results/"
            f"{wildcards.gene}/{wildcards.sample}."
            f"{_sentdug_segdup_result_gene(wildcards.gene)}.result.vcf.gz.tbi"
        ),
        sample_sex=lambda wildcards: sample_sex_for_required_tool(
            wildcards, "Sentieon segdup"
        ),
        sex_assumption_log=lambda wildcards: sample_sex_assumption_log(
            wildcards, "Sentieon segdup"
        ),
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/
        mkdir -p {params.outdir:q} $(dirname {log:q})
        : > {log:q}
        rm -f {output.done:q} {output.vcf:q} {output.tbi:q} {output.yaml:q} {params.caller_yaml:q} {params.caller_vcf:q} {params.caller_tbi:q}
        test -s {input.cram:q}
        test -s {input.crai:q}
        samtools quickcheck {input.cram:q} >> {log:q} 2>&1
        test -s {input.segdup_population_vcf:q}
        test -s {input.segdup_population_vcf:q}.tbi
        test -s {params.huref:q}
        test -e {params.sr_model:q}
        if ! command -v segdup-caller >/dev/null 2>&1; then
          echo "ERROR: segdup-caller not found in pinned conda env" >> {log:q}
          exit 127
        fi
        if [ -n {params.sex_assumption_log:q} ]; then
          printf '%s' {params.sex_assumption_log:q} >> {log:q}
        fi
        gzip -t {input.segdup_population_vcf:q}
        bcftools view -h {input.segdup_population_vcf:q} >/dev/null

        SEGDUP_PACKAGE_POP_VCF=$("$CONDA_PREFIX/bin/python" - <<'INNERPY'
import importlib.resources as ir

path = ir.files("genecaller").joinpath(
    "data",
    "pop_vcfs",
    "segdup_pop-population-hprc-v2.0_gnomad-v4.1.0-20251216.vcf.gz",
)
print(path)
INNERPY
)
        mkdir -p "$(dirname "$SEGDUP_PACKAGE_POP_VCF")"
        (
          flock 9
          if [ ! -s "$SEGDUP_PACKAGE_POP_VCF" ] || [ ! -s "$SEGDUP_PACKAGE_POP_VCF.tbi" ]; then
            tmp_vcf="$SEGDUP_PACKAGE_POP_VCF.$$"
            tmp_tbi="$SEGDUP_PACKAGE_POP_VCF.tbi.$$"
            cp -f {input.segdup_population_vcf:q} "$tmp_vcf"
            cp -f {input.segdup_population_vcf:q}.tbi "$tmp_tbi"
            mv -f "$tmp_vcf" "$SEGDUP_PACKAGE_POP_VCF"
            mv -f "$tmp_tbi" "$SEGDUP_PACKAGE_POP_VCF.tbi"
          fi
          gzip -t "$SEGDUP_PACKAGE_POP_VCF"
          bcftools view -h "$SEGDUP_PACKAGE_POP_VCF" >/dev/null
        ) 9>"$SEGDUP_PACKAGE_POP_VCF.lock"

        segdup-caller \
          --short {input.cram:q} \
          --sr_model {params.sr_model:q} \
          --reference {params.huref:q} \
          --genes {wildcards.gene:q} \
          --sample_name {params.cluster_sample:q} \
          --sex {params.sample_sex:q} \
          --outdir {params.outdir:q} \
          --keep_temp \
          --threads {threads} \
          --workers 1 >> {log:q} 2>&1

        test -s {params.caller_yaml:q}
        mv {params.caller_yaml:q} {output.yaml:q}
        test -s {output.yaml:q}
        grep -Eq '^[[:space:]]*{params.result_gene}:' {output.yaml:q}
        if [ {params.caller_vcf:q} != {output.vcf:q} ]; then
          mv {params.caller_vcf:q} {output.vcf:q}
        fi
        if [ {params.caller_tbi:q} != {output.tbi:q} ]; then
          mv {params.caller_tbi:q} {output.tbi:q}
        fi
        test -s {output.vcf:q}
        test -s {output.tbi:q}
        gzip -t {output.vcf:q}
        bcftools view -h {output.vcf:q} >/dev/null
        bcftools view -H {output.vcf:q} >/dev/null
        touch {output.done:q}
        """


rule sentdug_call_segdup:
    input:
        expand(
            MDIR
            + "{{sample}}/align/ug/na/segdup/sentdug/{{sample}}.ug.na.sentdug.segdup.{gene}.done",
            gene=SENTDUG_SEGDUP_GENES,
        ),
    output:
        done=MDIR + "{sample}/align/ug/na/segdup/sentdug/{sample}.ug.na.sentdug.segdup.done",
    log:
        MDIR + "{sample}/align/ug/na/segdup/sentdug/logs/{sample}.ug.na.sentdug.segdup.gather.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.ug.na.sentdug.segdup.gather.bench.tsv"
    threads: 1
    shell:
        "touch {log:q}; touch {output.done:q}"


rule sentdug_mito_call:
    """Call mitochondrial variants from Ultima short-read data."""
    input:
        cram=MDIR + "{sample}/align/ug/{sample}.cram",
        crai=MDIR + "{sample}/align/ug/{sample}.cram.crai",
    output:
        mito_vcf=MDIR + "{sample}/align/ug/na/mito/sentdug/{sample}.ug.na.sentdug.mito.vcf.gz",
        mito_tbi=MDIR + "{sample}/align/ug/na/mito/sentdug/{sample}.ug.na.sentdug.mito.vcf.gz.tbi",
    log:
        MDIR + "{sample}/align/ug/na/mito/sentdug/logs/{sample}.ug.na.sentdug.mito.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.ug.na.sentdug.mito.bench.tsv"
    threads: SENTDUG_MITO_THREADS
    conda:
        SENTDUG_SPECIALTY_CFG["mito_env_yaml"]
    resources:
        partition=SENTDUG_SPECIALTY_CFG["specialty_partition"],
        threads=SENTDUG_MITO_THREADS,
        vcpu=SENTDUG_MITO_THREADS,
        mem_mb=SENTDUG_MITO_MEM_MB,
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        mt_fasta=_sentdug_required_config("mt_fasta"),
        mt_shifted_fasta=_sentdug_required_config("mt_shifted_fasta"),
        mt_shift_back_chain=_sentdug_required_config("mt_shift_back_chain"),
        mt_blacklist_bed=_sentdug_required_config("mt_blacklist_bed"),
        use_threads=SENTDUG_MITO_USE_THREADS,
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/
        outdir=$(dirname {output.mito_vcf:q})
        mkdir -p "$outdir" $(dirname {log:q})
        : > {log:q}
        sample={params.cluster_sample:q}
        nt={params.use_threads}
        test -s {input.cram:q}
        test -s {input.crai:q}
        test -s {params.huref:q}
        test -s {params.mt_fasta:q}
        test -s {params.mt_shifted_fasta:q}
        test -s {params.mt_shift_back_chain:q}
        test -s {params.mt_blacklist_bed:q}
        samtools quickcheck {input.cram:q} >> {log:q} 2>&1

        timestamp=$(date +%Y%m%d%H%M%S)_$$
        tmp_parent="${{TMPDIR:-/tmp}}"
        test -d "$tmp_parent"
        test -w "$tmp_parent"
        tmpdir=$(mktemp -d "${{tmp_parent%/}}/sentdug_mito_${{timestamp}}.XXXXXX")
        trap 'rm -rf "$tmpdir" 2>/dev/null || true' EXIT

        chrM_records=$(samtools view -T {params.huref:q} -F 0x4 {input.cram:q} chrM | wc -l)
        if [ "$chrM_records" -lt 1 ]; then
          echo "FATAL: No mapped chrM reads extracted from {input.cram:q}" >> {log:q}
          exit 1
        fi
        echo "chrM mapped read records: $chrM_records" >> {log:q}

        chrM_paired_records=$(samtools view -T {params.huref:q} -F 0x4 -F 0x8 {input.cram:q} chrM | \
          awk '$7 == "=" || $7 == "chrM" {{n++}} END {{print n+0}}')
        echo "chrM same-contig paired read records: $chrM_paired_records" >> {log:q}

        if [ "$chrM_paired_records" -gt 0 ]; then
          mito_read_mode=paired
          samtools view -T {params.huref:q} -F 0x4 -F 0x8 -h {input.cram:q} chrM 2>>{log:q} | \
            awk '$0~/^@/ || $7 == "=" || $7 == "chrM" {{print}}' | \
            samtools collate -O - "$tmpdir/collate_$$" 2>>{log:q} | \
            samtools fastq -N \
              -1 "$tmpdir/${{sample}}.chrM.R1.fastq" \
              -2 "$tmpdir/${{sample}}.chrM.R2.fastq" - 2>>{log:q}
          r1_lines=$(head -4 "$tmpdir/${{sample}}.chrM.R1.fastq" | wc -l)
          if [ "$r1_lines" -lt 4 ]; then
            echo "FATAL: No chrM paired FASTQ records extracted from {input.cram:q}" >> {log:q}
            exit 1
          fi
        else
          mito_read_mode=single
          samtools view -T {params.huref:q} -F 0x4 -h {input.cram:q} chrM 2>>{log:q} | \
            samtools fastq -N -0 "$tmpdir/${{sample}}.chrM.single.fastq" -s /dev/null - 2>>{log:q}
          single_lines=$(head -4 "$tmpdir/${{sample}}.chrM.single.fastq" | wc -l)
          if [ "$single_lines" -lt 4 ]; then
            echo "FATAL: No chrM single-end FASTQ records extracted from {input.cram:q}" >> {log:q}
            exit 1
          fi
        fi

        align_and_call() {{
          local ref="$1" interval="$2" prefix="$3"
          if [ "$mito_read_mode" = "paired" ]; then
            read_args=("$tmpdir/${{sample}}.chrM.R1.fastq" "$tmpdir/${{sample}}.chrM.R2.fastq")
          else
            read_args=("$tmpdir/${{sample}}.chrM.single.fastq")
          fi
          bin/dayoa_sentieon bwa mem \
            -R "@RG\\tID:${{sample}}\\tSM:${{sample}}\\tPL:ULTIMA" \
            -K 100000000 -v 3 -t "$nt" -Y "$ref" \
            "${{read_args[@]}}" 2>>{log:q} | \
          bin/dayoa_sentieon util sort -t "$nt" -i - --sam2bam \
            -o "$tmpdir/${{prefix}}.sorted.bam" >> {log:q} 2>&1

          bin/dayoa_sentieon driver -t "$nt" \
            -i "$tmpdir/${{prefix}}.sorted.bam" \
            --algo LocusCollector --fun score_info \
            "$tmpdir/${{prefix}}.score.txt" >> {log:q} 2>&1

          bin/dayoa_sentieon driver -t "$nt" \
            -i "$tmpdir/${{prefix}}.sorted.bam" \
            --algo Dedup --score_info "$tmpdir/${{prefix}}.score.txt" \
            --metrics "$tmpdir/${{prefix}}.dedup_metrics.txt" \
            "$tmpdir/${{prefix}}.deduped.bam" >> {log:q} 2>&1

          bin/dayoa_sentieon driver -t "$nt" \
            -i "$tmpdir/${{prefix}}.deduped.bam" \
            -r "$ref" --interval "$interval" \
            --algo TNscope --tumor_sample "$sample" \
            --min_tumor_allele_frac 0.005 --prune_factor 20 \
            --disable_detector sv --resample_depth 100000 \
            "$tmpdir/${{prefix}}.raw.tnscope.vcf.gz" >> {log:q} 2>&1
        }}

        align_and_call {params.mt_fasta:q} "chrM:576-16024" "MT" &
        pid_mt=$!
        align_and_call {params.mt_shifted_fasta:q} "chrM:8025-9144" "ShiftedMT" &
        pid_shifted=$!
        mt_rc=0; wait "$pid_mt" || mt_rc=$?
        shifted_rc=0; wait "$pid_shifted" || shifted_rc=$?
        if [ "$mt_rc" -ne 0 ] || [ "$shifted_rc" -ne 0 ]; then
          echo "FATAL: align_and_call failed: MT=$mt_rc ShiftedMT=$shifted_rc" >> {log:q}
          exit 1
        fi

        test -s "$tmpdir/MT.raw.tnscope.vcf.gz"
        test -s "$tmpdir/ShiftedMT.raw.tnscope.vcf.gz"
        picard LiftoverVcf \
          I="$tmpdir/ShiftedMT.raw.tnscope.vcf.gz" \
          O="$tmpdir/ShiftedMT.shifted_back.vcf.gz" \
          R={params.mt_fasta:q} \
          CHAIN={params.mt_shift_back_chain:q} \
          REJECT="$tmpdir/ShiftedMT.rejected.vcf" >> {log:q} 2>&1

        picard MergeVcfs \
          I="$tmpdir/ShiftedMT.shifted_back.vcf.gz" \
          I="$tmpdir/MT.raw.tnscope.vcf.gz" \
          O="$tmpdir/all.tnscope.vcf.gz" >> {log:q} 2>&1

        bcftools view -T ^{params.mt_blacklist_bed:q} "$tmpdir/all.tnscope.vcf.gz" 2>>{log:q} | \
          bcftools filter -s "Strand_bias" -e "INFO/SOR>=10" 2>>{log:q} | \
          bin/dayoa_sentieon util vcfconvert - {output.mito_vcf:q} >> {log:q} 2>&1

        test -s {output.mito_vcf:q}
        bcftools index -t -f {output.mito_vcf:q} >> {log:q} 2>&1
        test -s {output.mito_tbi:q}
        bcftools view -h {output.mito_vcf:q} >/dev/null
        """


localrules:
    sentdug_call_segdup,
    produce_sentdug_mito,
    produce_sentdug_segdup,
    produce_sentdug_cnv,
    produce_sentdug_sv,


rule produce_sentdug_mito:  # TARGET: experimental Ultima-only Sentieon mito caller
    input:
        expand(
            MDIR + "{sample}/align/ug/na/mito/sentdug/{sample}.ug.na.sentdug.mito.vcf.gz.tbi",
            sample=SSAMPS,
        ),
    output:
        "gatheredall.sentdug.mito",
    log:
        "gatheredall.sentdug.mito.log",
    benchmark:
        "logs/benchmarks/produce_sentdug_mito.bench.tsv"
    threads: 1
    shell:
        "touch {log:q}; touch {output:q}"


rule produce_sentdug_segdup:  # TARGET: experimental Ultima-only Sentieon segdup caller
    input:
        expand(
            MDIR + "{sample}/align/ug/na/segdup/sentdug/{sample}.ug.na.sentdug.segdup.done",
            sample=SSAMPS,
        ),
    output:
        "gatheredall.sentdug.segdup",
    log:
        "gatheredall.sentdug.segdup.log",
    benchmark:
        "logs/benchmarks/produce_sentdug_segdup.bench.tsv"
    threads: 1
    shell:
        "touch {log:q}; touch {output:q}"


rule produce_sentdug_cnv:  # TARGET: experimental Ultima-only Sentieon CNV caller
    input:
        expand(
            MDIR + "{sample}/align/ug/na/cnv/sentdug/{sample}.ug.na.sentdug.cnv.vcf.gz.tbi",
            sample=SSAMPS,
        ),
    output:
        "gatheredall.sentdug.cnv",
    log:
        "gatheredall.sentdug.cnv.log",
    benchmark:
        "logs/benchmarks/produce_sentdug_cnv.bench.tsv"
    threads: 1
    shell:
        "touch {log:q}; touch {output:q}"


rule produce_sentdug_sv:  # TARGET: experimental blocked Ultima-only Sentieon SV caller
    input:
        _sentdug_sv_target_inputs
    output:
        "gatheredall.sentdug.sv",
    log:
        "gatheredall.sentdug.sv.log",
    benchmark:
        "logs/benchmarks/produce_sentdug_sv.bench.tsv"
    threads: 1
    shell:
        "touch {log:q}; touch {output:q}"
