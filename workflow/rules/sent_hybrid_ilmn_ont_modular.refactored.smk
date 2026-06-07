"""
Modular Sentieon DNAscope Hybrid Workflow: Illumina + ONT

This file decomposes the monolithic bin/dayoa_sentieon_cli dnascope-hybrid call into
discrete Snakemake rules for better restart capability, debuggability, and
observability.

Pipeline stages:
  1. SR alignment (bwa mem) - Illuminate FASTQs → sorted BAM
  2. Pass 1 calling (DNAscope) - Combined LR+SR variant calling
  3. Hybrid select - Region selection from pass-1 VCF
  4. MAPQ0 detection - Find low-quality mapping regions
  5. BED merging - Combine selected + MAPQ0 regions
  6. Stage 1 - Insertion detection + haplotype assembly → bwa realign
  7. Stage 2 - Generate unmap/alt BAMs and refined BED
  8. Stage 3 - Re-alignment with stage2 outputs
  9. Pass 2 calling - Second-pass on refined regions
  10. Subset + concat - Merge pass1 complement with pass2
  11. Annotation - Hybrid-specific annotations
  12. Transfer - Optional annotation transfer from population VCF
  13. Model apply - Optional DNAModelApply ML filtering
  14. Final norm - bcftools normalization → output VCF

Uses model bundle: HybridIlluminaONT2.0.bundle
"""

import os
import sys

from snakemake.exceptions import WorkflowError

# Ensure config keys exist for shell-block {config[sentdhiomr][...]} access
if "sentdhiomr" not in config:
    config["sentdhiomr"] = {}
config["sentdhiomr"].setdefault("sample_sm", "hybrid_sample")
config["sentdhiomr"].setdefault("lr_read_filter", "")
config["sentdhiomr"].setdefault("sr_read_filter", "")

# Intermediate file retention flags (default: do NOT retain → clean up after final VCF)
config["sentdhiomr"].setdefault("keep_sr_alignment", False)
config["sentdhiomr"].setdefault("keep_tmp_dirs", False)

# SegDup caller defaults
config["sentdhiomr"].setdefault("segdup_sr_model", "")
config["sentdhiomr"].setdefault("segdup_lr_model", "")
config["sentdhiomr"].setdefault("segdup_genes", "")

# Parse segdup genes into a list for per-gene rule expansion
SEGDUP_GENES = [g.strip() for g in config["sentdhiomr"]["segdup_genes"].split(",") if g.strip()]

# Mitochondrial pipeline defaults
config["sentdhiomr"].setdefault("mt_fasta", "")
config["sentdhiomr"].setdefault("mt_shifted_fasta", "")
config["sentdhiomr"].setdefault("mt_shift_back_chain", "")
config["sentdhiomr"].setdefault("mt_blacklist_bed", "")

# Long-read aligner selection for HioMR. Mounted ONT FASTQ rows must first build
# the sentmm2ont CRAM; pre-aligned ONT CRAM rows keep the legacy ont path.
def _sentdhiomr_clean(value):
    return str(value or "").strip().lower()


def _sentdhiomr_has_ont_fastq_input(row):
    ont_r1_path = _sentdhiomr_clean(row.get("ONT_R1_PATH", ""))
    return _is_ont_fastq_unit(row) or ont_r1_path not in {"", "na", "none"}


def _sentdhiomr_row_longread_aligner(row):
    candidates = []
    if _sentdhiomr_has_ont_fastq_input(row):
        candidates.append("sentmm2ont")
    if _sentdhiomr_clean(row.get("ONT_BAM_ALIGNER", "")) == "sentmm2ont":
        candidates.append("sentmm2ont")

    ont_cram_aligner = _sentdhiomr_clean(row.get("ONT_CRAM_ALIGNER", ""))
    if ont_cram_aligner == "ont":
        candidates.append("ont")
    elif ont_cram_aligner not in {"", "na", "none"}:
        raise WorkflowError(
            f"sentdhiomr does not support ONT_CRAM_ALIGNER='{ont_cram_aligner}' "
            f"for sample {row.get('sample_lane', row.get('sample', 'unknown'))}."
        )

    candidates = sorted(set(candidates))
    if len(candidates) > 1:
        raise WorkflowError(
            "sentdhiomr found multiple ONT long-read input modes for "
            f"sample {row.get('sample_lane', row.get('sample', 'unknown'))}: "
            f"{', '.join(candidates)}. Provide exactly one ONT FASTQ/uBAM or ONT CRAM source."
        )
    return candidates[0] if candidates else None


SENTDHIOMR_SAMPLE_ALIGNER_PAIRS = []
for _, _row in samples.iterrows():
    _alnr = _sentdhiomr_row_longread_aligner(_row)
    if _alnr:
        SENTDHIOMR_SAMPLE_ALIGNER_PAIRS.append((_row["sample_lane"], _alnr))

ALIGNERS_DHIOMR = sorted({alnr for _, alnr in SENTDHIOMR_SAMPLE_ALIGNER_PAIRS})
ALIGNERS_DHIOMR_REGEX = "|".join(ALIGNERS_DHIOMR) if ALIGNERS_DHIOMR else r"(?!x)x"
SENTDHIOMR_MISSING_LONGREAD_MARKER = MDIR + "logs/sentdhiomr_no_longread_source.required"


def _sentdhiomr_expected_aligner(sample):
    matches = [alnr for samp, alnr in SENTDHIOMR_SAMPLE_ALIGNER_PAIRS if samp == sample]
    if not matches:
        raise WorkflowError(
            "sentdhiomr requires an ONT long-read source for "
            f"sample {sample}: set ONT_R1_PATH/ONT_BAM for sentmm2ont or ONT_CRAM_ALIGNER=ont."
        )
    return matches[0]


def _sentdhiomr_require_aligner(wildcards):
    expected = _sentdhiomr_expected_aligner(wildcards.sample)
    if wildcards.alnr != expected:
        raise WorkflowError(
            f"sentdhiomr sample {wildcards.sample} is configured for {expected}, "
            f"but requested alnr={wildcards.alnr}."
        )
    return expected


def _sentdhiomr_lr_cram(wildcards):
    alnr = _sentdhiomr_require_aligner(wildcards)
    if alnr == "sentmm2ont":
        return MDIR + f"{wildcards.sample}/align/sentmm2ont/{wildcards.sample}.sentmm2ont.cram"
    if alnr == "ont":
        return MDIR + f"{wildcards.sample}/align/ont/{wildcards.sample}.cram"
    raise WorkflowError(f"Unsupported sentdhiomr long-read aligner: {alnr}")


def _sentdhiomr_lr_crai(wildcards):
    return _sentdhiomr_lr_cram(wildcards) + ".crai"


def _sentdhiomr_expand(pattern, **wildcards):
    if not SENTDHIOMR_SAMPLE_ALIGNER_PAIRS:
        return [SENTDHIOMR_MISSING_LONGREAD_MARKER]
    outputs = []
    for sample, alnr in SENTDHIOMR_SAMPLE_ALIGNER_PAIRS:
        values = dict(wildcards)
        values["sample"] = [sample]
        values["alnr"] = [alnr]
        outputs.extend(expand(pattern, **values))
    return outputs

# Base temp directory prefix for intermediate files
def _dhiomr_tmp(wildcards):
    return f"{MDIR}{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/snv/sentdhiomr/vcfs/{wildcards.dchrm}/tmp"

# ---------------------------------------------------------------------------
# Rule 1: SR Alignment - Align Illumina FASTQs with bin/dayoa_sentieon bwa mem
# ---------------------------------------------------------------------------
rule sentdhiomr_sr_align:
    """Align Illumina short-read FASTQs with bin/dayoa_sentieon bwa mem | util sort"""
    input:
        r1=getR1s,
        r2=getR2s,
        cram=_sentdhiomr_lr_cram,
        crai=_sentdhiomr_lr_crai,
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
    output:
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/tmp/sr_aligned.bam",
        bai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/tmp/sr_aligned.bam.bai",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.sr_align.log",
    threads: config['sentdhiomr']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.sr_align.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads'],
        vcpu=config['sentdhiomr']['threads'],
        mem_mb=config['sentdhiomr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        max_mem="130G"
        if "max_mem" not in config["sentieon"]
        else config["sentieon"]["max_mem"],
        model=config["sentdhiomr"]["dna_scope_snv_model"],
        use_threads=config["sentdhiomr"]["use_threads"],
        bwa_threads=config["sentieon"]["bwa_threads"],
        igz=config['sentieon']['igz'],
        mbuffer=config['sentieon']['mbuffer'],
        sort_thread_mem=config['sentieon']['sort_thread_mem'],
        sort_threads=config['sentieon']['sort_threads'],
        cluster_sample=ret_sample,
        trim_head=get_ilmn_trim_head,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhiomr_sr_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR" $(dirname {output.bam});
        if [ ! -d "$TMPDIR" ]; then
            echo "ERROR: Failed to create TMPDIR: $TMPDIR" >> {log} 2>&1;
            exit 5;
        fi
        export bwt_max_mem={params.max_mem} ;

        echo "TMPDIR created: $TMPDIR" >> {log} 2>&1;
        ls -ld "$TMPDIR" >> {log} 2>&1;
        df -h /dev/shm >> {log} 2>&1;
        export APPTAINER_HOME="$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        # License check
        if [ -z "$SENTIEON_LICENSE" ] || [ ! -f "$SENTIEON_LICENSE" ]; then
            echo "ERROR: SENTIEON_LICENSE not set or file not found" >> {log}
            exit 3
        fi

        echo "Starting SR alignment at $(date)" >> {log}

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

        # Use cluster_sample for consistent @RG SM tag across entire pipeline
        # This matches the pattern used in sentieon_bwa_sort and other alignment rules
        epocsec=$(date +%s)
        echo "Using cluster_sample: {params.cluster_sample}" >> {log}

        # Build R1 and R2 file lists
        R1_FILES="{input.r1}"
        R2_FILES="{input.r2}"

        # Align with bwa mem → util sort
        LD_PRELOAD=$LD_PRELOAD bin/dayoa_sentieon bwa mem \
            -R "@RG\\tID:{params.cluster_sample}-$epocsec\\tSM:{params.cluster_sample}\\tLB:{params.cluster_sample}-LB-1\\tPL:ILLUMINA" \
            -t {params.bwa_threads} \
            -x {params.model}/bwa.model \
            -K 100000000 \
            {params.huref} \
             <( {params.igz} -q  {input.r1} {params.trim_head} )   \
             <( {params.igz} -q  {input.r2} {params.trim_head} )   \
             {params.mbuffer}  2>> {log} | \
        bin/dayoa_sentieon util sort \
            -i - \
            -t {params.use_threads} \
            --reference {params.huref} \
            --sortblock_thread_count {params.sort_threads} \
            -o {output.bam} \
            --intermediate_compress_level 1  \
            --temp_dir $TMPDIR \
            --block_size {params.sort_thread_mem} \
            --sam2bam --bam_compression 1 >> {log} 2>&1

        # Index the BAM
        samtools index -@ {threads} {output.bam} >> {log} 2>&1

        echo "SR alignment completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 2: Pass 1 - Combined LR+SR variant calling (DNAscope)
# ---------------------------------------------------------------------------
rule sentdhiomr_pass1:
    """First-pass combined variant calling (DNAscope) on LR+SR"""
    input:
        sr_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/tmp/sr_dedup.bam",
        sr_bai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/tmp/sr_dedup.bam.bai",
        lr_cram=_sentdhiomr_lr_cram,
        lr_crai=_sentdhiomr_lr_crai,
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/initial.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/initial.vcf.gz.tbi",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.pass1.log",
    threads: config['sentdhiomr']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.pass1.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads'],
        vcpu=config['sentdhiomr']['threads'],
        mem_mb=config['sentdhiomr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhiomr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_path,
        schrm_mod=get_dchrm_day,
        use_threads=config["sentdhiomr"]["use_threads"],
        cluster_sample=ret_sample,
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhiomr_p1_${{timestamp}}_$$";
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

        ulimit -n 65536 || echo "ulimit mod failed" > {log} 2>&1;

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

        echo "Starting Pass 1 DNAscope at $(date)" >> {log}

        scoped_diploid_bed="$TMPDIR/scoped_diploid.bed"
        python workflow/scripts/make_scoped_diploid_bed.py \
            --regions "{params.schrm_mod}" \
            --diploid-bed "{params.diploid_bed}" \
            --fai "{params.huref}.fai" \
            --output "$scoped_diploid_bed" >> {log} 2>&1

        # Guard: check if ONT CRAM is valid (non-empty with a proper header)
        ONT_SIZE=$(stat -c%s {input.lr_cram} 2>/dev/null || echo 0)
        if [ "$ONT_SIZE" -eq 0 ]; then
            echo "ERROR: ONT CRAM {input.lr_cram} is empty (0 bytes). This sample has no ONT data." >> {log}
            echo "Cannot run hybrid Illumina+ONT pipeline without ONT reads. Failing explicitly." >> {log}
            exit 1
        fi

        # Build --replace_rg args: LR reads get LR:1 tag (critical for hybrid.model
        # to distinguish long reads from short reads, especially for indel calling).
        # SR reads get SM-only replacement to unify sample names. Matches CLI behavior.
        RGIDS=$(samtools view -H {input.lr_cram} | awk '
            $1=="@RG"{{
                for(i=1;i<=NF;i++){{
                    if($i~/^ID:/){{
                        sub(/^ID:/,"",$i);
                        print $i
                    }}
                }}
            }}')

        LR_RG_ARGS=""
        for rgid in $RGIDS; do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done

        # Build --replace_rg args for SR reads: cluster_sample SM (no LR:1 tag)
        SR_RGIDS=$(samtools view -H {input.sr_bam} | awk '
            $1=="@RG"{{
                for(i=1;i<=NF;i++){{
                    if($i~/^ID:/){{
                        sub(/^ID:/,"",$i);
                        print $i
                    }}
                }}
            }}')

        SR_RG_ARGS=""
        for rgid in $SR_RGIDS; do
            SR_RG_ARGS="$SR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}"
        done

        bin/dayoa_sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            $LR_RG_ARGS $SR_RG_ARGS -i {input.lr_cram} \
            -i {input.sr_bam} \
            --interval "$scoped_diploid_bed" \
            --algo DNAscope \
            -d {params.pop_vcf} \
            --model {params.model}/hybrid.model \
            --pcr_indel_model none \
            {output.vcf} >> {log} 2>&1

        # Create VCF index with tabix (required for hybrid_select)
        echo "Creating VCF index with tabix" >> {log}
        tabix -f -p vcf -@ {threads} {output.vcf} >> {log} 2>&1


        echo "Pass 1 completed at $(date)" >> {log}
        """

rule sentdhiomr_sr_markdup:
    input:
        bam = MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/tmp/sr_aligned.bam"
    output:
        bam = MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/tmp/sr_dedup.bam",
        bai = MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/tmp/sr_dedup.bam.bai"
    params:
        huref = config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        use_threads = config["sentdhiomr"]["use_threads"],
        tmp_base="/dev/shm",
        cluster_sample=ret_sample,
    threads: config['sentdhiomr']['threads']
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.sr_markdup.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads'],
        vcpu=config['sentdhiomr']['threads'],
        mem_mb=config['sentdhiomr']['mem_mb'],
    conda:
        "../envs/sentieon_v0.3.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.sr_markdup.log"
    shell:
        """
        set -euo pipefail;
        touch {log};

        if [ -z "${{SENTIEON_LICENSE:-}}" ]; then
            echo "SENTIEON_LICENSE not set. Please export the license path or server." >> {log} 2>&1;
            exit 3;
        fi;
        if [[ ! "$SENTIEON_LICENSE" =~ : ]] && [ ! -f "$SENTIEON_LICENSE" ]; then
            echo "The file referenced by SENTIEON_LICENSE ('$SENTIEON_LICENSE') does not exist." >> {log} 2>&1;
            exit 4;
        fi;

        TOKEN=$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600');
        itype=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type || echo "unknown");
        echo "INSTANCE TYPE: $itype" > {log};
        echo "INSTANCE TYPE: $itype";
        start_time=$(date +%s);

        ulimit -n 65536 || echo "ulimit mod failed" >> {log} 2>&1;

        timestamp=$(date +%Y%m%d%H%M%S)_$$;
        export TMPDIR={params.tmp_base}/smd_sentieon_$timestamp;
        mkdir -p "$TMPDIR";
        export SENTIEON_TMPDIR=$TMPDIR;
        export APPTAINER_HOME=$TMPDIR;
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        score_file=$TMPDIR/{wildcards.sample}.{wildcards.alnr}.score.txt;
        metrics_tmp=$TMPDIR/{wildcards.sample}.{wildcards.alnr}.metrics.txt;

        read_name=$(samtools view {input.bam} | head -n 1 | cut -f1 || true);

        jemalloc_path=$(find "$CONDA_PREFIX" \( -name "libjemalloc*.so*" -o -name "libjemalloc*.dylib" \) | head -n 1 || true);
        if [[ -n "$jemalloc_path" ]]; then
            export LD_PRELOAD="$jemalloc_path";
            echo "LD_PRELOAD set to: $LD_PRELOAD" >> {log};
        else
            echo "libjemalloc not found in the active conda environment $CONDA_PREFIX." >> {log};
            exit 5;
        fi;

        LD_PRELOAD=$LD_PRELOAD bin/dayoa_sentieon driver \
        -r {params.huref} \
        -t {threads} \
        -i {input.bam} \
        --algo LocusCollector --fun score_info "$score_file" >> {log} 2>&1;

        LD_PRELOAD=$LD_PRELOAD bin/dayoa_sentieon driver \
        -r {params.huref} \
        -t {threads} \
        -i {input.bam} \
        --algo Dedup \
        --score_info "$score_file" \
        --metrics "$metrics_tmp" \
        {output.bam} >> {log} 2>&1;

        samtools index -@ {threads} {output.bam} {output.bai} >> {log} 2>&1;
        """

# ---------------------------------------------------------------------------
# Rule 3: Hybrid Select - Region selection from pass-1 VCF
# ---------------------------------------------------------------------------
rule sentdhiomr_hybrid_select:
    """Select regions for hybrid re-analysis based on pass-1 variants.

    This replicates the sentieon-cli hybrid_select pipeline:
    1. hybrid_select.py filters VCF based on long/short read confidence
    2. bcftools view filters for PASS variants
    3. bcftools query converts to BED format
    4. bedtools slop adds 1000bp padding
    """
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/initial.vcf.gz",
        ref_fai=config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/selected.bed",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.hybrid_select.log",
    threads: config['sentdhiomr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.hybrid_select.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads_light'],
        vcpu=config['sentdhiomr']['threads_light'],
        mem_mb=config['sentdhiomr']['mem_mb_light'],
    params:
        use_threads=config["sentdhiomr"]["use_threads_light"],
        cluster_sample=ret_sample,
        slop_size=1000,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting hybrid_select pipeline at $(date)" >> {log}

        (
            echo "DEBUG hybrid_select env at $(date)"
            echo "DEBUG pwd=$PWD"
            echo "DEBUG PATH=$PATH"
            echo "DEBUG CONDA_PREFIX=$(printenv CONDA_PREFIX || true)"
            echo "DEBUG PYTHONPATH=$(printenv PYTHONPATH || true)"
            echo "DEBUG LD_LIBRARY_PATH=$(printenv LD_LIBRARY_PATH || true)"
            echo "DEBUG command -v python=$(command -v python || true)"
            echo "DEBUG which python=$(which python || true)"
            echo "DEBUG which -a python:"
            which -a python || true
            echo "DEBUG PATH python -V:"
            python -V || true
            echo "DEBUG rule env python -V:"
            "$CONDA_PREFIX/bin/python" -V || true
            echo "DEBUG rule env python import probe:"
            "$CONDA_PREFIX/bin/python" -c "import os, sys; print('DEBUG sys.executable=' + sys.executable); print('DEBUG sys.prefix=' + sys.prefix); print('DEBUG sys.path=' + repr(sys.path)); print('DEBUG env_CONDA_PREFIX=' + str(os.environ.get('CONDA_PREFIX'))); import importlib.resources as resources; print('DEBUG importlib.resources_file=' + str(getattr(resources, '__file__', None))); from importlib.resources import files; print('DEBUG hybrid_select=' + str(files('sentieon_cli.scripts').joinpath('hybrid_select.py')))" || true
        ) >> {log} 2>&1

        # Find hybrid_select.py script
        HYBRID_SELECT=$("$CONDA_PREFIX/bin/python" -c "from importlib.resources import files; print(files('sentieon_cli.scripts').joinpath('hybrid_select.py'))")

        # Pipeline: hybrid_select.py -> bcftools view -> bcftools query -> bedtools slop
        # This replicates sentieon-cli's cmd_pyexec_hybrid_select() function
        bin/dayoa_sentieon pyexec "$HYBRID_SELECT" \
            -v {input.vcf} \
            -t {params.use_threads} \
            - 2>> {log} \
        | bcftools view --threads {threads} -f 'PASS,.' - 2>> {log} \
        | bcftools query -f '%CHROM\t%POS0\t%END\n' - 2>> {log} \
        | bedtools slop -b {params.slop_size} -g {input.ref_fai} -i - \
        > {output.bed} 2>> {log}

        echo "hybrid_select pipeline completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 4: MAPQ0 Detection - Find low-quality mapping regions
# ---------------------------------------------------------------------------
rule sentdhiomr_mapq0_bed:
    """Detect MAPQ0 regions with HybridStage2 region model"""
    input:
        sr_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/tmp/sr_dedup.bam",
        lr_cram=_sentdhiomr_lr_cram,
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_mapq0.bed",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.mapq0_bed.log",
    threads: config['sentdhiomr']['threads_medium']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.mapq0_bed.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads_medium'],
        vcpu=config['sentdhiomr']['threads_medium'],
        mem_mb=config['sentdhiomr']['mem_mb_medium'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhiomr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_path,
        schrm_mod=get_dchrm_day,
        use_threads=config["sentdhiomr"]["use_threads_medium"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhiomr_mq_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        echo "Starting MAPQ0 detection at $(date)" >> {log}

        scoped_diploid_bed="$TMPDIR/scoped_diploid.bed"
        python workflow/scripts/make_scoped_diploid_bed.py \
            --regions "{params.schrm_mod}" \
            --diploid-bed "{params.diploid_bed}" \
            --fai "{params.huref}.fai" \
            --output "$scoped_diploid_bed" >> {log} 2>&1

        # Build --replace_rg args: LR reads get LR:1 tag for hybrid model
        RGIDS=$(samtools view -H {input.lr_cram} | awk '
            $1=="@RG"{{
                for(i=1;i<=NF;i++){{
                    if($i~/^ID:/){{
                        sub(/^ID:/,"",$i);
                        print $i
                    }}
                }}
            }}')

        LR_RG_ARGS=""
        for rgid in $RGIDS; do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done

        # Build --replace_rg args for SR reads: cluster_sample SM (no LR:1 tag)
        SR_RGIDS=$(samtools view -H {input.sr_bam} | awk '
            $1=="@RG"{{
                for(i=1;i<=NF;i++){{
                    if($i~/^ID:/){{
                        sub(/^ID:/,"",$i);
                        print $i
                    }}
                }}
            }}')

        SR_RG_ARGS=""
        for rgid in $SR_RGIDS; do
            SR_RG_ARGS="$SR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}"
        done

        bin/dayoa_sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            $LR_RG_ARGS $SR_RG_ARGS -i {input.lr_cram} \
            -i {input.sr_bam} \
            --interval "$scoped_diploid_bed" \
            --algo HybridStage2 \
            --model {params.model}/HybridStage2_region.model \
            --all_bed {output.bed} >> {log} 2>&1

        echo "MAPQ0 detection completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 5: MAPQ0 Slop - Extend MAPQ0 regions by 1000bp
# ---------------------------------------------------------------------------
rule sentdhiomr_mapq0_slop:
    """Extend MAPQ0 regions by 1000 bp using bedtools slop"""
    input:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_mapq0.bed",
        ref_fai=config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_mapq0.ex1000.bed",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.mapq0_slop.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{dchrm}.sentdhiomr_mapq0_slop.bench.tsv"
    threads: 2
    conda:
        "../envs/vanilla_v0.1.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=2,
        vcpu=2,
        mem_mb=4000,
    params:
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        echo "Extending MAPQ0 regions by 1000bp at $(date)" >> {log}
        bedtools slop -b 1000 -g {input.ref_fai} -i {input.bed} > {output.bed} 2>> {log}
        echo "MAPQ0 slop completed at $(date)" >> {log}
        """



# ---------------------------------------------------------------------------
# Rule 6: Merge BEDs - Combine selected + MAPQ0 regions
# ---------------------------------------------------------------------------
rule sentdhiomr_merge_beds:
    """Cat, sort, merge selected.bed + mapq0.ex1000.bed → merged_diff.bed"""
    input:
        selected=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/selected.bed",
        mapq0=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_mapq0.ex1000.bed",
        ref_fai=config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/merged_diff.bed",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.merge_beds.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{dchrm}.sentdhiomr_merge_beds.bench.tsv"
    threads: 2
    conda:
        "../envs/vanilla_v0.1.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=2,
        vcpu=2,
        mem_mb=4000,
    params:
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        echo "Merging selected + MAPQ0 BEDs at $(date)" >> {log}
        cat {input.selected} {input.mapq0} | \
        bedtools sort -faidx {input.ref_fai} -i - | \
        bedtools merge > {output.bed} 2>> {log}
        echo "BED merge completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 7: Stage 1 - Insertion detection + haplotype assembly → bwa realign
# ---------------------------------------------------------------------------
rule sentdhiomr_stage1:
    """Stage1: insertion detection + haplotype assembly piped through bwa"""
    input:
        lr_cram=_sentdhiomr_lr_cram,
        diff_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/merged_diff.bed",
    output:
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_stage1.bam",
        hap_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage1_hap.bam",
        hap_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage1_hap.bed",
        hap_vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage1_hap.vcf",
        ins_fa=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage1_ins.fa",
        ins_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage1_ins.bed",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.stage1.log",
    threads: config['sentdhiomr']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.stage1.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads'],
        vcpu=config['sentdhiomr']['threads'],
        mem_mb=config['sentdhiomr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhiomr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_path,
        schrm_mod=get_dchrm_day,
        use_threads=config["sentdhiomr"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S)
        export TMPDIR="/dev/shm/sentdhiomr_s1_${{timestamp}}_$$"
        export SENTIEON_TMPDIR="$TMPDIR"
        mkdir -p "$TMPDIR"
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT

        echo "Starting Stage1 at $(date)" >> {log}

        scoped_diploid_bed="$TMPDIR/scoped_diploid.bed"
        python workflow/scripts/make_scoped_diploid_bed.py \
            --regions "{params.schrm_mod}" \
            --diploid-bed "{params.diploid_bed}" \
            --fai "{params.huref}.fai" \
            --output "$scoped_diploid_bed" >> {log} 2>&1

        # Build LR replace args (matches sentieon-cli RgInfo for LR inputs)
        RGIDS=$(samtools view -H {input.lr_cram} | awk '
            $1=="@RG"{{
                for(i=1;i<=NF;i++){{
                    if($i~/^ID:/){{
                        sub(/^ID:/,"",$i);
                        print $i
                    }}
                }}
            }}')

        LR_RG_ARGS=""
        for rgid in $RGIDS; do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done

        # Match sentieon-cli: remove bwt_max_mem from bwa env (noop if unset)
        unset bwt_max_mem || true

        # Match sentieon-cli hybrid_stage1():
        #   Run HAP + INS drivers sequentially to temp files, then cat | bwa mem | util sort
        #   (sequential execution ensures set -euo pipefail catches driver failures;
        #    process substitution <(...) silently swallows failures)

        if [ ! -s {input.diff_bed} ]; then
            echo "WARNING: merged_diff.bed is empty - no haplotype regions to process" >> {log}
            echo "Creating empty hap_bam with clean header plus empty hap_bed and hap_vcf" >> {log}
            touch {output.hap_bed} {output.hap_vcf}
            samtools view -H {input.lr_cram} \
            | grep -E '^@(HD|SQ|RG)' \
            | samtools view -bo {output.hap_bam} - 2>> {log}
            samtools index {output.hap_bam} >> {log} 2>&1

            echo "Starting INS driver for scoped shard at $(date)" >> {log}
            bin/dayoa_sentieon driver \
                $LR_RG_ARGS --input {input.lr_cram} \
                --reference {params.huref} \
                --thread_count {params.use_threads} \
                --interval "$scoped_diploid_bed" \
                --algo HybridStage1 \
                --model {params.model}/HybridStage1_ins.model \
                --fa_file {output.ins_fa} \
                --bed_file {output.ins_bed} \
                - 2>> {log} > "$TMPDIR/ins_stdout.sam"
            echo "INS driver finished at $(date)" >> {log}

            cat "$TMPDIR/ins_stdout.sam" \
            | bin/dayoa_sentieon bwa mem \
                -R "@RG\\tID:hybrid-18893\\tSM:{params.cluster_sample}" \
                -t {params.use_threads} \
                -x {params.model}/HybridStage1_bwa.model \
                {params.huref} \
                - 2>> {log} \
            | bin/dayoa_sentieon util sort \
                -i - \
                -t {params.use_threads} \
                -o {output.bam} \
                --sam2bam >> {log} 2>&1

            for f in {output.ins_fa} {output.ins_bed}; do
                if [[ ! -e "$f" ]]; then
                    echo "No insertion output produced for empty merged_diff shard; creating empty expected file: $f" >> {log}
                    : > "$f"
                fi
            done

            samtools quickcheck {output.hap_bam} >> {log} 2>&1 || \
                (echo "ERROR: stage1_hap.bam failed integrity check - file may be truncated" >> {log} && exit 1)
            samtools quickcheck {output.bam} >> {log} 2>&1 || \
                (echo "ERROR: hybrid_stage1.bam failed integrity check - file may be truncated" >> {log} && exit 1)
        else
            echo "Processing $(wc -l < {input.diff_bed}) regions from merged_diff.bed" >> {log}

            # 1. Haplotype assembly driver → stdout to temp file, side-outputs written directly
            echo "Starting HAP driver at $(date)" >> {log}
            bin/dayoa_sentieon driver \
                $LR_RG_ARGS --input {input.lr_cram} \
                --reference {params.huref} \
                --thread_count {params.use_threads} \
                --interval {input.diff_bed} \
                --algo HybridStage1 \
                --model {params.model}/HybridStage1.model \
                --hap_bam {output.hap_bam} \
                --hap_bed {output.hap_bed} \
                --hap_vcf {output.hap_vcf} \
                - 2>> {log} > "$TMPDIR/hap_stdout.sam"
            echo "HAP driver finished at $(date)" >> {log}

            # 2. Insertion detection driver → stdout to temp file, side-outputs written directly
            echo "Starting INS driver at $(date)" >> {log}
            bin/dayoa_sentieon driver \
                $LR_RG_ARGS --input {input.lr_cram} \
                --reference {params.huref} \
                --thread_count {params.use_threads} \
                --interval {input.diff_bed} \
                --algo HybridStage1 \
                --model {params.model}/HybridStage1_ins.model \
                --fa_file {output.ins_fa} \
                --bed_file {output.ins_bed} \
                - 2>> {log} > "$TMPDIR/ins_stdout.sam"
            echo "INS driver finished at $(date)" >> {log}

            # 3. Cat both driver outputs → bwa mem → util sort
            cat "$TMPDIR/hap_stdout.sam" "$TMPDIR/ins_stdout.sam" \
            | bin/dayoa_sentieon bwa mem \
                -R "@RG\\tID:hybrid-18893\\tSM:{params.cluster_sample}" \
                -t {params.use_threads} \
                -x {params.model}/HybridStage1_bwa.model \
                {params.huref} \
                - 2>> {log} \
            | bin/dayoa_sentieon util sort \
                -i - \
                -t {params.use_threads} \
                -o {output.bam} \
                --sam2bam >> {log} 2>&1

            # 4. Validate all expected outputs exist and are non-empty
            sync
            for f in {output.hap_bam} {output.hap_bed} {output.hap_vcf} {output.ins_fa} {output.ins_bed} {output.bam}; do
                if [[ ! -s "$f" ]]; then
                    echo "ERROR: Missing or empty output: $f" >> {log}
                    exit 1
                fi
            done

            # 5. Index hap BAM for downstream rules
            samtools index {output.hap_bam} >> {log} 2>&1
        fi

        # All stage1 BAMs must be readable before downstream rules consume them.
        samtools quickcheck {output.hap_bam} {output.bam} >> {log} 2>&1 || \
            (echo "ERROR: Stage1 BAM integrity check failed" >> {log} && exit 1)

        for f in {output.hap_bam} {output.bam}; do
            if [[ ! -s "$f" ]]; then
                echo "ERROR: Missing or empty output: $f" >> {log}
                exit 1
            fi
        done
        for f in {output.hap_bed} {output.hap_vcf} {output.ins_fa} {output.ins_bed}; do
            if [[ ! -e "$f" ]]; then
                echo "ERROR: Missing output: $f" >> {log}
                exit 1
            fi
        done

        echo "Stage1 completed at $(date)" >> {log}
        """


rule sentdhiomr_stage2:
    """Stage2: generate unmap BAM, alt BAM, and refined BED"""
    input:
        stage1_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_stage1.bam",
        hap_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage1_hap.bam",
        hap_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage1_hap.bed",
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
        unmap_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_stage2_unmap.bam",
        alt_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_stage2_alt.bam",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.stage2.log",
    threads: config['sentdhiomr']['threads_medium']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.stage2.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads_medium'],
        vcpu=config['sentdhiomr']['threads_medium'],
        mem_mb=config['sentdhiomr']['mem_mb_medium'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhiomr"]["dna_scope_snv_model"],
        use_threads=config["sentdhiomr"]["use_threads_medium"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhiomr_s2_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        echo "Starting Stage 2 at $(date)" >> {log}

        bin/dayoa_sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            -i {input.stage1_bam} -i {input.hap_bam} \
            --algo HybridStage2 \
            --model {params.model}/HybridStage2.model \
            --hap_bed {input.hap_bed} \
            --unmap_bam {output.unmap_bam} \
            --alt_bam {output.alt_bam} \
            --all_bed {output.bed} >> {log} 2>&1

        echo "Stage 2 completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 9: Stage 3 - Re-alignment with stage2 outputs
# ---------------------------------------------------------------------------
rule sentdhiomr_stage3:
    """Stage3: HybridStage3 on all reads + stage2 BAMs → sorted BAM"""
    input:
        sr_bam = MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/tmp/sr_dedup.bam",
        lr_cram=_sentdhiomr_lr_cram,
        unmap_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_stage2_unmap.bam",
        alt_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_stage2_alt.bam",
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
    output:
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_stage3.bam",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.stage3.log",
    threads: config['sentdhiomr']['threads']  # Full node: stage3 pipes driver → util sort (2 concurrent processes)
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.stage3.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads'],
        vcpu=config['sentdhiomr']['threads'],
        mem_mb=config['sentdhiomr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhiomr"]["dna_scope_snv_model"],
        use_threads=config["sentdhiomr"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhiomr_s3_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        echo "Starting Stage 3 at $(date)" >> {log}

        if [ ! -s {input.bed} ]; then
            echo "WARNING: hybrid_stage2.bed is empty - no Stage 3 realignment regions; creating empty BAM" >> {log}
            (
                samtools view -H {input.lr_cram} | awk -v sample="{params.cluster_sample}" '
                    $1=="@HD" || $1=="@SQ" {{ print }}
                    $1=="@RG" {{
                        id="";
                        for (i=1; i<=NF; i++) {{
                            if ($i ~ /^ID:/) {{
                                id=$i;
                                sub(/^ID:/, "", id)
                            }}
                        }}
                        if (id != "") print "@RG\tID:" id "\tSM:" sample "\tLR:1"
                    }}'
                samtools view -H {input.sr_bam} | awk -v sample="{params.cluster_sample}" '
                    $1=="@RG" {{
                        id="";
                        for (i=1; i<=NF; i++) {{
                            if ($i ~ /^ID:/) {{
                                id=$i;
                                sub(/^ID:/, "", id)
                            }}
                        }}
                        if (id != "") print "@RG\tID:" id "\tSM:" sample
                    }}'
            ) | samtools view -bo {output.bam} - 2>> {log}
            samtools quickcheck {output.bam} >> {log} 2>&1 || \
                (echo "ERROR: empty Stage3 BAM failed integrity check" >> {log} && exit 1)
            echo "Stage 3 completed with empty input regions at $(date)" >> {log}
            exit 0
        fi

        # NOTE: Input ONT BAM must have clean @PG headers (no broken PP chain).
        # Use bin/util/fix_ont_cram_headers.sh to pre-process if needed.

        # Build --replace_rg args: LR reads get LR:1 tag for hybrid model
        RGIDS=$(samtools view -H {input.lr_cram} | awk '
            $1=="@RG"{{
                for(i=1;i<=NF;i++){{
                    if($i~/^ID:/){{
                        sub(/^ID:/,"",$i);
                        print $i
                    }}
                }}
            }}')

        LR_RG_ARGS=""
        for rgid in $RGIDS; do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done

        # Build --replace_rg args for SR reads: cluster_sample SM (no LR:1 tag)
        SR_RGIDS=$(samtools view -H {input.sr_bam} | awk '
            $1=="@RG"{{
                for(i=1;i<=NF;i++){{
                    if($i~/^ID:/){{
                        sub(/^ID:/,"",$i);
                        print $i
                    }}
                }}
            }}')

        SR_RG_ARGS=""
        for rgid in $SR_RGIDS; do
            SR_RG_ARGS="$SR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}"
        done

        bin/dayoa_sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            $LR_RG_ARGS $SR_RG_ARGS -i {input.lr_cram} \
            -i {input.sr_bam} \
            -i {input.unmap_bam} \
            -i {input.alt_bam} \
            --interval {input.bed} \
            --algo HybridStage3 \
            --model {params.model}/HybridStage3.model \
            - 2>> {log} | \
        bin/dayoa_sentieon util sort \
            -i - -t {params.use_threads} \
            --temp_dir $TMPDIR \
            -o {output.bam} >> {log} 2>&1

        echo "Stage 3 completed at $(date)" >> {log}
        """

# ---------------------------------------------------------------------------
# Rule 10: Pass 2 - Second-pass variant calling on refined regions
# ---------------------------------------------------------------------------
rule sentdhiomr_pass2:
    """Second-pass variant calling on stage3 BAM + LR reads"""
    input:
        lr_cram=_sentdhiomr_lr_cram,
        stage3_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_stage3.bam",
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
        initial_vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/initial.vcf.gz",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz.tbi",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.pass2.log",
    threads: config['sentdhiomr']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.pass2.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads'],
        vcpu=config['sentdhiomr']['threads'],
        mem_mb=config['sentdhiomr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhiomr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_interval_arg,  # Use --interval for bin/dayoa_sentieon driver
        use_threads=config["sentdhiomr"]["use_threads"],
        cluster_sample=ret_sample,
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhiomr_p2_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        echo "Starting Pass 2 DNAscope at $(date)" >> {log}

        if [ ! -s {input.bed} ]; then
            echo "WARNING: hybrid_stage2.bed is empty - no Pass 2 regions; creating empty VCF" >> {log}
            bcftools view --threads {threads} -h {input.initial_vcf} | bgzip -c > {output.vcf}
            tabix -f -p vcf -@ {threads} {output.vcf} >> {log} 2>&1
            echo "Pass 2 completed with empty input regions at $(date)" >> {log}
            exit 0
        fi

        # Build --replace_rg args: LR reads get LR:1 tag for hybrid model.
        # This also unifies SM tags across lr_cram and stage3_bam so sentieon
        # driver sees a single sample (stage3_bam inherits LR RGs from ONT input).
        RGIDS=$(samtools view -H {input.lr_cram} | awk '
            $1=="@RG"{{
                for(i=1;i<=NF;i++){{
                    if($i~/^ID:/){{
                        sub(/^ID:/,"",$i);
                        print $i
                    }}
                }}
            }}')

        LR_RG_ARGS=""
        for rgid in $RGIDS; do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done

        bin/dayoa_sentieon driver \
            --temp_dir $TMPDIR \
            $LR_RG_ARGS --input {input.lr_cram} \
            --input {input.stage3_bam} \
            --reference {params.huref} \
            --thread_count {params.use_threads} \
            --interval {input.bed} \
            --algo DNAscope \
            -d {params.pop_vcf} \
            --model {params.model}/hybrid.model \
            --pcr_indel_model none \
            {output.vcf} >> {log} 2>&1

        echo "Pass 2 completed at $(date)" >> {log}
        """



# ---------------------------------------------------------------------------
# Rule 11: Subset - Subset pass-1 VCF to complement of stage2 regions
# ---------------------------------------------------------------------------
rule sentdhiomr_subset:
    """Subset pass-1 VCF to complement of stage2 regions"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/initial.vcf.gz",
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/mix_subset.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/mix_subset.vcf.gz.tbi",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.subset.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{dchrm}.sentdhiomr_subset.bench.tsv"
    threads: config['sentdhiomr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads_light'],
        vcpu=config['sentdhiomr']['threads_light'],
        mem_mb=config['sentdhiomr']['mem_mb_light'],
    params:
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Subsetting pass-1 VCF at $(date)" >> {log}

        # If stage2 BED is empty, just copy; otherwise subset
        if [ -s {input.bed} ]; then
            bcftools view --threads {threads} -T ^{input.bed} {input.vcf} 2>> {log} | \
            bin/dayoa_sentieon util vcfconvert -t {threads} - {output.vcf} >> {log} 2>&1
        else
            bin/dayoa_sentieon util vcfconvert -t {threads} {input.vcf} {output.vcf} >> {log} 2>&1
        fi

        # Ensure index exists (bin/dayoa_sentieon util vcfconvert should create it, but verify)
        if [ ! -f {output.tbi} ]; then
            tabix -p vcf -@ {threads} {output.vcf} >> {log} 2>&1
        fi

        echo "Subset completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 12: Concat Pass - Concatenate subset + pass2 VCFs
# ---------------------------------------------------------------------------
rule sentdhiomr_concat_pass:
    """Concatenate subset + pass2 VCFs"""
    input:
        subset=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/mix_subset.vcf.gz",
        subset_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/mix_subset.vcf.gz.tbi",
        pass2=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz",
        pass2_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz.tbi",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/combined_tmp.vcf.gz",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.concat_pass.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{dchrm}.sentdhiomr_concat_pass.bench.tsv"
    threads: config['sentdhiomr']['threads_light']
    conda:
        "../envs/vanilla_v0.1.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads_light'],
        vcpu=config['sentdhiomr']['threads_light'],
        mem_mb=config['sentdhiomr']['mem_mb_light'],
    params:
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        echo "Concatenating subset + pass2 VCFs at $(date)" >> {log}
        bcftools concat --threads {threads} -W=tbi --output {output.vcf} -aD {input.subset} {input.pass2} >> {log} 2>&1
        echo "Concat completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 13: Annotation - Hybrid-specific annotations
# ---------------------------------------------------------------------------
rule sentdhiomr_anno:
    """Annotate VCF with hybrid-specific annotations"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/combined_tmp.vcf.gz",
        hap_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage1_hap.bed",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/combined_tmp_anno.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/combined_tmp_anno.vcf.gz.tbi",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.anno.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{dchrm}.sentdhiomr_anno.bench.tsv"
    threads: config['sentdhiomr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads_light'],
        vcpu=config['sentdhiomr']['threads_light'],
        mem_mb=config['sentdhiomr']['mem_mb_light'],
    params:
        use_threads=config["sentdhiomr"]["use_threads_light"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting hybrid annotation at $(date)" >> {log}

        # Find hybrid_anno.py script
        HYBRID_ANNO=$("$CONDA_PREFIX/bin/python" -c "from importlib.resources import files; print(files('sentieon_cli.scripts').joinpath('hybrid_anno.py'))")

        bin/dayoa_sentieon pyexec "$HYBRID_ANNO" \
            -v {input.vcf} \
            -b {input.hap_bed} \
            -t {params.use_threads} \
            {output.vcf} >> {log} 2>&1

        tabix -f -p vcf {output.vcf} >> {log} 2>&1

        echo "Annotation completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 14: Transfer - Annotation transfer from population VCF (per-chromosome sharded)
# ---------------------------------------------------------------------------
# The transfer step is sharded per-chromosome for parallel execution.
# Input comes from the whole-genome anno VCF (dchrm="1-24"), and each shard
# processes a single chromosome using bcftools merge --regions.
# A gather rule (sentdhiomr_transfer_merge) concatenates shards before model_apply.
# ---------------------------------------------------------------------------
rule sentdhiomr_transfer:
    """Transfer annotations from population VCF using bcftools merge + trimalt pipe (per-chromosome shard)"""
    input:
        anno_vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/combined_tmp_anno.vcf.gz",
        anno_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/combined_tmp_anno.vcf.gz.tbi",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/transfer_shards/transfer.{tchrm}.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/transfer_shards/transfer.{tchrm}.vcf.gz.tbi",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX,
        tchrm="|".join(SENTDHIOMR_CHRMS_TRANSFER),
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.transfer.{tchrm}.log",
    threads: config['sentdhiomr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.transfer.{tchrm}.bench.tsv"
    resources:
        partition="i192mem,i192bigmem,i192",
        threads=config['sentdhiomr']['threads_light'],
        vcpu=config['sentdhiomr']['threads_light'],
        mem_mb=config['sentdhiomr']['mem_mb_light'],
    params:
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
        regions=lambda wildcards: get_dchrm_day(type('obj', (object,), {'dchrm': wildcards.tchrm})()),
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting annotation transfer shard {wildcards.tchrm} (regions: {params.regions}) at $(date)" >> {log}

        TMPDIR=$(dirname {output.vcf})
        mkdir -p "$TMPDIR"

        # Reheader anno_vcf to use cluster_sample name (use old\tnew format)
        anno_old_sample=$(bcftools query -l {input.anno_vcf} | head -n1)
        echo "Anno VCF original sample: $anno_old_sample, target sample: {params.cluster_sample}" >> {log}
        echo -e "${{anno_old_sample}}\t{params.cluster_sample}" > "$TMPDIR/anno_rename.{wildcards.tchrm}.txt"
        bcftools reheader --threads {threads} -s "$TMPDIR/anno_rename.{wildcards.tchrm}.txt" -o "$TMPDIR/anno_reheadered.{wildcards.tchrm}.vcf.gz" {input.anno_vcf} >> {log} 2>&1
        bcftools index --threads {threads} -t "$TMPDIR/anno_reheadered.{wildcards.tchrm}.vcf.gz" >> {log} 2>&1

        # pop_vcf is required for transfer
        if [ -z "{params.pop_vcf}" ] || [ ! -f "{params.pop_vcf}" ]; then
            echo "ERROR: pop_vcf is not set or file not found: '{params.pop_vcf}'" >> {log}
            exit 1
        fi

        TRIM_SCRIPT=$("$CONDA_PREFIX/bin/python" -c "from importlib.resources import files; print(files('sentieon_cli.scripts').joinpath('trimalt.py'))")

        subset_bed="$TMPDIR/transfer.{wildcards.tchrm}.bed"
        awk -v contig="{params.regions}" 'BEGIN {{FS=OFS="\\t"}} $1 == contig {{print $1, 0, $2; found=1}} END {{if (!found) exit 2}}' \
            "{params.huref}.fai" > "$subset_bed"

        MERGE_RULES=$(bcftools view -h {params.pop_vcf} 2>> {log} | "$CONDA_PREFIX/bin/python" -c '
import re
import sys
ids = []
for line in sys.stdin:
    if not line.startswith("##INFO") or ",Number=A" not in line:
        continue
    match = re.search(r"ID=([^,>]+)", line)
    if match:
        ids.append(match.group(1) + ":sum")
if not ids:
    raise SystemExit("No Number=A INFO fields found in population VCF header")
print(",".join(ids))
' 2>> {log})

        echo "Transferring annotations from pop_vcf: {params.pop_vcf} for regions-file: $subset_bed" >> {log}

        if bcftools view -h {params.pop_vcf} 2>> {log} | grep -q "^##contig=<ID={params.regions}[,>]"; then
            # Match sentieon-cli v1.6.1 transfer: regions-file + dynamic Number=A INFO merge rules.
            bcftools merge --threads {threads} --no-version --regions-overlap pos -m all \
                --regions-file "$subset_bed" \
                -i "$MERGE_RULES" \
                "$TMPDIR/anno_reheadered.{wildcards.tchrm}.vcf.gz" {params.pop_vcf} 2>> {log} | \
            bin/dayoa_sentieon pyexec "$TRIM_SCRIPT" 2>> {log} | \
            bcftools view --threads {threads} --no-version -W=tbi -O z -o {output.vcf} - 2>> {log}
        else
            echo "Population VCF lacks contig {params.regions}; carrying raw annotations for this shard" >> {log}
            bcftools view --threads {threads} --no-version -W=tbi -O z -o {output.vcf} \
                --regions-file "$subset_bed" \
                "$TMPDIR/anno_reheadered.{wildcards.tchrm}.vcf.gz" >> {log} 2>&1
        fi

        test -s {output.vcf}
        test -s {output.tbi}

        # Cleanup temp files
        rm -f "$TMPDIR/anno_reheadered.{wildcards.tchrm}.vcf.gz" \
              "$TMPDIR/anno_reheadered.{wildcards.tchrm}.vcf.gz.tbi" \
              "$TMPDIR/anno_rename.{wildcards.tchrm}.txt"

        echo "Transfer shard {wildcards.tchrm} completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 14b: Transfer Merge - Gather per-chromosome transfer shards
# ---------------------------------------------------------------------------
rule sentdhiomr_transfer_merge:
    """Concatenate per-chromosome transfer shards into single VCF for model_apply"""
    input:
        shards=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhiomr/vcfs/{{dchrm}}/tmp/transfer_shards/transfer.{tchrm}.vcf.gz",
                tchrm=SENTDHIOMR_CHRMS_TRANSFER,
            ),
            key=lambda x: int(x.rsplit("transfer.", 1)[1].split(".vcf.gz")[0])
            if x.rsplit("transfer.", 1)[1].split(".vcf.gz")[0].isdigit()
            else 99,
        ),
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/combined_tmp_transfer.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/combined_tmp_transfer.vcf.gz.tbi",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.transfer_merge.log",
    threads: config['sentdhiomr']['threads_light']
    conda:
        "../envs/vanilla_v0.1.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.transfer_merge.bench.tsv"
    resources:
        partition="i192mem,i192bigmem,i192",
        threads=config['sentdhiomr']['threads_light'],
        vcpu=config['sentdhiomr']['threads_light'],
        mem_mb=config['sentdhiomr']['mem_mb_light'],
    params:
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        echo "Merging transfer shards at $(date)" >> {log}

        bcftools concat --threads {threads} -a -d all -O z -o {output.vcf} {input.shards} >> {log} 2>&1
        bcftools index --threads {threads} -t {output.vcf} >> {log} 2>&1

        echo "Transfer merge completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 15: Model Apply - DNAModelApply ML filtering
# ---------------------------------------------------------------------------
rule sentdhiomr_model_apply:
    """Apply ML model to called variants"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/combined_tmp_transfer.vcf.gz",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/combined_apply.vcf.gz",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.model_apply.log",
    threads: config['sentdhiomr']['threads_medium']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.model_apply.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads_medium'],
        vcpu=config['sentdhiomr']['threads_medium'],
        mem_mb=config['sentdhiomr']['mem_mb_medium'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhiomr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_path,
        schrm_mod=get_dchrm_day,
        use_threads=config["sentdhiomr"]["use_threads_medium"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhiomr_ma_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        echo "Starting DNAModelApply at $(date)" >> {log}

        scoped_diploid_bed="$TMPDIR/scoped_diploid.bed"
        python workflow/scripts/make_scoped_diploid_bed.py \
            --regions "{params.schrm_mod}" \
            --diploid-bed "{params.diploid_bed}" \
            --fai "{params.huref}.fai" \
            --output "$scoped_diploid_bed" >> {log} 2>&1

        bin/dayoa_sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            --interval "$scoped_diploid_bed" \
            --algo DNAModelApply \
            --model {params.model}/hybrid.model \
            --vcf {input.vcf} \
            {output.vcf} >> {log} 2>&1

        echo "Model apply completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 16: Final Norm - bcftools normalization → output VCF
# ---------------------------------------------------------------------------
rule sentdhiomr_final_norm:
    """Trim, normalize, and produce final output VCF"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/combined_apply.vcf.gz",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.snv.sort.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.snv.sort.vcf.gz.tbi",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.{dchrm}.final_norm.log",
    threads: config['sentdhiomr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.final_norm.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads_light'],
        vcpu=config['sentdhiomr']['threads_light'],
        mem_mb=config['sentdhiomr']['mem_mb_light'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting final normalization at $(date)" >> {log}

        bcftools view --threads {threads} -a -e 'GT="0/0"' {input.vcf} 2>> {log} | \
        bcftools norm --threads {threads} -f {params.huref} 2>> {log} | \
        bin/dayoa_sentieon util vcfconvert -t {threads} - {output.vcf} >> {log} 2>&1

        echo "Final normalization completed at $(date)" >> {log}
        """


# ===========================================================================
# DOWNSTREAM RULES: FOFN, Concat, Target rules (similar to original)
# ===========================================================================

localrules:
    sentdhiomr_concat_fofn,


rule sentdhiomr_concat_fofn:
    """Build file-of-filenames for chromosome chunks"""
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhiomr/vcfs/{ochm}/{{sample}}.{{alnr}}.{{ddup}}.sentdhiomr.{ochm}.snv.sort.vcf.gz.tbi",
                ochm=SENTDHIOMR_CHRMS,
            ),
            key=lambda x: float(
                str(x.replace("~", ".").replace(":", "."))
                .split("vcfs/")[1]
                .split("/")[0]
                .split("-")[0]
            ),
        ),
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    priority: 44
    output:
        fin_fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.snv.concat.vcf.gz.fofn.tmp",
    threads: 1
    resources:
        threads=1
    params:
        fn_stub="{sample}.{alnr}.{ddup}.sentdhiomr.",
        cluster_sample=ret_sample,
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.concat.fofn.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.sentdhiomr.concat.fofn.log",
    shell:
        """
        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\\.tbi$//g'; );
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.sentdhiomr. {output.fin_fofn}) >> {log} 2>&1;
        """


rule sentdhiomr_concat_index_chunks:
    """Concatenate chromosome chunks and index final VCF"""
    input:
        fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.snv.concat.vcf.gz.fofn",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.snv.sort.vcf.gz",
        vcfgztemp=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.snv.sort.temp.vcf.gz",
        vcfgztbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.snv.sort.vcf.gz.tbi",
    threads: config['sentdhiomr']['threads_light']
    resources:
        vcpu=config['sentdhiomr']['threads_light'],
        threads=config['sentdhiomr']['threads_light'],
        partition="i192mem,i192bigmem",
        mem_mb=config['sentdhiomr']['mem_mb_light'],
    priority: 47
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.merge.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.sentdhiomr.snv.merge.sort.gathered.log",
    shell:
        """
        touch {log};
        mkdir -p $(dirname {log});

        bcftools concat -a -d all --threads {threads} -f {input.fofn} -O z -o {output.vcfgztemp} >> {log} 2>&1;

        export oldname=$(bcftools query -l {output.vcfgztemp} | head -n1) >> {log} 2>&1;
        echo -e "${{oldname}}\\t{params.cluster_sample}" > {output.vcfgz}.rename.txt
        bcftools reheader --threads {threads} -s {output.vcfgz}.rename.txt -o {output.vcfgz} {output.vcfgztemp} >> {log} 2>&1;
        bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;

        # Conditional cleanup of per-chunk tmp dirs (controlled by keep_tmp_dirs config flag)
        KEEP_TMP="{config[sentdhiomr][keep_tmp_dirs]}"
        if [ "$KEEP_TMP" = "False" ] || [ "$KEEP_TMP" = "false" ]; then
            echo "Cleaning up chunk tmp dirs under $(dirname {output.vcfgz})/vcfs/" >> {log} 2>&1;
            rm -rf $(dirname {output.vcfgz})/vcfs/*/tmp >> {log} 2>&1 || true;
        else
            echo "Retaining chunk tmp dirs (keep_tmp_dirs=true)" >> {log} 2>&1;
        fi
        """



localrules:
    clear_combined_sentdhiomr_vcf,


rule clear_combined_sentdhiomr_vcf:  # TARGET: clear combined sentdhiomr vcf so chunks can be re-evaluated if needed.
    input:
        _sentdhiomr_expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.snv.sort.vcf.gz",
            ddup=DDUP,
        ),
    log:
        MDIR + "logs/clear_combined_sentdhiomr_vcf.log"
    threads: 2
    priority: 42
    shell:
        """
        echo "skipping cleanup of {input}"
        ## rm {input}*  1> /dev/null  2> /dev/null ) || echo 'file not found for deletion: {input}';
        """


localrules:
    produce_sentdhiomr_vcf,


rule produce_sentdhiomr_vcf:  # TARGET: sentieon dnascope hybrid modular vcf
    input:
        _sentdhiomr_expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.snv.sort.vcf.gz.tbi",
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdhiomr",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdhiomr.log",
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """


# ===========================================================================
# SV CALLING: LongReadSV structural variant calling (whole-genome, not chunked)
# ===========================================================================

rule sentdhiomr_call_svs:
    """Call structural variants using LongReadSV on ONT long reads"""
    input:
        lr_cram=_sentdhiomr_lr_cram,
        lr_crai=_sentdhiomr_lr_crai,
    output:
        sv_vcf=MDIR + "{sample}/align/{alnr}/{ddup}/sv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sv.vcf.gz",
        sv_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/sv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sv.vcf.gz.tbi",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/sv/sentdhiomr/log/{sample}.{alnr}.{ddup}.sentdhiomr.sv.log",
    threads: config['sentdhiomr']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.sv.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads'],
        vcpu=config['sentdhiomr']['threads'],
        mem_mb=config['sentdhiomr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhiomr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_interval_arg,
        use_threads=config["sentdhiomr"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhiomr_sv_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        mkdir -p $(dirname {log})
        echo "Starting LongReadSV at $(date)" >> {log}

        # Build LR readgroup replacement args: LR reads get LR:1 tag
        RGIDS=$(samtools view -H {input.lr_cram} | awk '
            $1=="@RG"{{
                for(i=1;i<=NF;i++){{
                    if($i~/^ID:/){{
                        sub(/^ID:/,"",$i);
                        print $i
                    }}
                }}
            }}')

        LR_RG_ARGS=""
        for rgid in $RGIDS; do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done

        bin/dayoa_sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            $LR_RG_ARGS -i {input.lr_cram} \
            {params.diploid_bed} \
            --algo LongReadSV \
            --model {params.model}/longreadsv.model \
            {output.sv_vcf} >> {log} 2>&1

        bcftools index -t -f {output.sv_vcf} >> {log} 2>&1

        echo "LongReadSV completed at $(date)" >> {log}
        """


localrules:
    produce_sentdhiomr_sv,


rule produce_sentdhiomr_sv:  # TARGET: sentieon longreadsv hybrid ilmn+ont modular sv vcf
    input:
        _sentdhiomr_expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/sv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sv.vcf.gz.tbi",
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdhiomr.sv",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdhiomr.sv.log",
    shell:
        """( touch {output} ;
        ls {output} ) >> {log} 2>&1;
        """


# ===========================================================================
# CNV CALLING: Copy-number variant calling (whole-genome, not chunked)
# Uses bin/dayoa_sentieon driver --algo CNV with the model bundle's cnv.model
# ===========================================================================

rule sentdhiomr_call_cnvs:
    """Call copy-number variants using Sentieon CNVscope + CNVModelApply on SR data.

    CNVscope is a short-read-only WGS CNV caller. Two-step process:
      1. CNVscope: read-depth profiling → tmp VCF
      2. CNVModelApply: ML filtering → final VCF
    Ref: Hu et al. Front. Bioinform. 2026; PMC12813096
    """
    input:
        sr_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sr_merged.bam",
        sr_bai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sr_merged.bam.bai",
    output:
        cnv_vcf=MDIR + "{sample}/align/{alnr}/{ddup}/cnv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.cnv.vcf.gz",
        cnv_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/cnv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.cnv.vcf.gz.tbi",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/cnv/sentdhiomr/log/{sample}.{alnr}.{ddup}.sentdhiomr.cnv.log",
    threads: config['sentdhiomr']['threads_medium']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.cnv.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads_medium'],
        vcpu=config['sentdhiomr']['threads_medium'],
        mem_mb=config['sentdhiomr']['mem_mb_medium'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhiomr"]["dna_scope_snv_model"],
        use_threads=config["sentdhiomr"]["use_threads_medium"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhiomr_cnv_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        mkdir -p $(dirname {log})
        echo "Starting CNV calling (CNVscope) at $(date)" >> {log}

        TMP_CNV_VCF="$TMPDIR/cnvscope_tmp.vcf.gz"

        # Step 1: CNVscope - read-depth profiling on SR data
        bin/dayoa_sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            -i {input.sr_bam} \
            --algo CNVscope \
            --model {params.model}/cnv.model \
            "$TMP_CNV_VCF" >> {log} 2>&1

        echo "CNVscope step completed at $(date)" >> {log}

        # Step 2: CNVModelApply - ML-based filtering
        bin/dayoa_sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            --algo CNVModelApply \
            --model {params.model}/cnv.model \
            -v "$TMP_CNV_VCF" \
            {output.cnv_vcf} >> {log} 2>&1

        bcftools index -t -f {output.cnv_vcf} >> {log} 2>&1

        echo "CNV calling (CNVModelApply) completed at $(date)" >> {log}
        """


localrules:
    produce_sentdhiomr_cnv,


rule produce_sentdhiomr_cnv:  # TARGET: sentieon cnv hybrid ilmn+ont modular cnv vcf
    input:
        _sentdhiomr_expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/cnv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.cnv.vcf.gz.tbi",
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdhiomr.cnv",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdhiomr.cnv.log",
    shell:
        """( touch {output} ;
        ls {output} ) >> {log} 2>&1;
        """


# ===========================================================================
# SR ALIGNMENT EXPORT: export SR dedup BAM → CRAM when explicitly targeted
# ===========================================================================

rule sentdhiomr_export_sr_cram:
    """Export the shared SR dedup BAM to a retained CRAM file."""
    input:
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/tmp/sr_dedup.bam",
        bai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/tmp/sr_dedup.bam.bai",
    output:
        cram=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sr_dedup.cram",
        crai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sr_dedup.cram.crai",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.sr_export.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr_export_sr_cram.bench.tsv"
    threads: config['sentdhiomr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads_light'],
        vcpu=config['sentdhiomr']['threads_light'],
        mem_mb=config['sentdhiomr']['mem_mb_light'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail

        rm -f {output.cram} {output.crai}
        echo "Converting SR dedup BAM → CRAM at $(date)" >> {log}
        samtools view -@ {threads} -T {params.huref} -C -o {output.cram} {input.bam} >> {log} 2>&1
        samtools index -@ {threads} {output.cram} >> {log} 2>&1
        test -s {output.cram}
        test -s {output.crai}
        echo "SR CRAM export completed at $(date)" >> {log}
        """


localrules:
    prep_sentdhiomr_chunkdirs,


rule prep_sentdhiomr_chunkdirs:
    """Prepare chunk directories for modular hybrid workflow"""
    input:
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        r1=getR1s,
        r2=getR2s,
        cram=_sentdhiomr_lr_cram,
        crai=_sentdhiomr_lr_crai,
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhiomr/vcfs/{dchrm}/{{sample}}.ready",
            dchrm=SENTDHIOMR_CHRMS
        ),
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/logs/{sample}.{alnr}.{ddup}.chunkdirs.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.prep_sentdhiomr_chunkdirs.bench.tsv"
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """


# ===========================================================================
# SEGDUP CALLER: Targeted variant calling in segmental duplication regions
# Uses Sentieon segdup-caller CLI with merged SR BAM + LR CRAM
# ===========================================================================

rule sentdhiomr_merge_sr_bams:
    """Expose the shared whole-genome SR dedup BAM for segdup/mito."""
    input:
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/tmp/sr_dedup.bam",
        bai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/tmp/sr_dedup.bam.bai",
    output:
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sr_merged.bam",
        bai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sr_merged.bam.bai",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/log/{sample}.{alnr}.{ddup}.sr_merge.log",
    threads: config['sentdhiomr']['threads_medium']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.sr_merge.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhiomr']['threads_medium'],
        vcpu=config['sentdhiomr']['threads_medium'],
        mem_mb=config['sentdhiomr']['mem_mb_medium'],
    params:
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        echo "Linking shared SR dedup BAM for segdup/mito at $(date)" >> {log}

        mkdir -p $(dirname {output.bam})
        ln -sf "$(realpath {input.bam})" {output.bam}
        ln -sf "$(realpath {input.bai})" {output.bai}

        echo "SR BAM link completed at $(date)" >> {log}
        """


rule sentdhiomr_call_segdup_gene:
    """Call variants in a single segmental duplication gene using segdup-caller CLI.
    Each gene runs as an independent job for failure isolation and parallelism."""
    input:
        sr_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sr_merged.bam",
        sr_bai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sr_merged.bam.bai",
        lr_cram=_sentdhiomr_lr_cram,
        lr_crai=_sentdhiomr_lr_crai,
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/segdup/sentdhiomr/results/{sample}.{gene}.result.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/segdup/sentdhiomr/results/{sample}.{gene}.result.vcf.gz.tbi",
        done=MDIR + "{sample}/align/{alnr}/{ddup}/segdup/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.segdup.{gene}.done",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX,
        gene="|".join(SEGDUP_GENES),
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/segdup/sentdhiomr/log/{sample}.{alnr}.{ddup}.sentdhiomr.segdup.{gene}.log",
    threads: 48
    conda:
        "../envs/segdup_v0.2.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.segdup.{gene}.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=48,
        vcpu=48,
        mem_mb=config['sentdhiomr']['mem_mb_medium'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        sr_model=config["sentdhiomr"]["segdup_sr_model"],
        lr_model=config["sentdhiomr"]["segdup_lr_model"],
        outdir=lambda wildcards: f"{MDIR}{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/segdup/sentdhiomr/results",
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        mkdir -p $(dirname {log})
        mkdir -p {params.outdir}
        rm -f {output.done} {output.vcf} {output.tbi}
        echo "Starting segdup-caller for gene {wildcards.gene} at $(date)" >> {log}

        if ! command -v segdup-caller &>/dev/null; then
            echo "ERROR: segdup-caller not found in pinned conda env" >> {log}
            exit 127
        fi

        LR_ARGS=""
        if [ -n "{params.lr_model}" ]; then
            LR_ARGS="--long {input.lr_cram} --lr_model {params.lr_model}"
        fi

        segdup-caller \
            --short {input.sr_bam} \
            $LR_ARGS \
            --sr_model {params.sr_model} \
            --reference {params.huref} \
            --genes {wildcards.gene} \
            --sample_name "{params.cluster_sample}" \
            --outdir {params.outdir} \
            --threads {threads} \
            --workers 1 >> {log} 2>&1

        test -s {output.vcf}
        test -s {output.tbi}
        gzip -t {output.vcf}
        bcftools view -h {output.vcf} >/dev/null
        bcftools view -H {output.vcf} >/dev/null

        touch {output.done}
        echo "segdup-caller for gene {wildcards.gene} completed at $(date)" >> {log}
        """


rule sentdhiomr_call_segdup:
    """Gather per-gene segdup results into a single done sentinel."""
    input:
        expand(
            MDIR
            + "{{sample}}/align/{{alnr}}/{{ddup}}/segdup/sentdhiomr/{{sample}}.{{alnr}}.{{ddup}}.sentdhiomr.segdup.{gene}.done",
            gene=SEGDUP_GENES,
        ),
    output:
        done=MDIR + "{sample}/align/{alnr}/{ddup}/segdup/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.segdup.done",
    log:
        MDIR + "{sample}/logs/{sample}.{alnr}.{ddup}.sentdhiomr_call_segdup.log"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr_call_segdup.bench.tsv"
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    threads: 1
    shell:
        """
        touch {output.done}
        """


localrules:
    produce_sentdhiomr_segdup,
    sentdhiomr_call_segdup,


rule produce_sentdhiomr_segdup:  # TARGET: sentieon segdup hybrid ilmn+ont modular segdup
    input:
        _sentdhiomr_expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/segdup/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.segdup.done",
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdhiomr.segdup",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdhiomr.segdup.log",
    shell:
        """( touch {output} ;
        ls {output} ) >> {log} 2>&1;
        """



# ===========================================================================
# MITOCHONDRIAL CALLING: TNscope-based mito variant calling with shifted ref
# Replicates bin/sentieon_mitochondrial_pipeline.sh as Snakemake rules
# Uses dual-alignment (standard + shifted chrM ref) and liftover/merge
# ===========================================================================

rule sentdhiomr_mito_call:
    """Mitochondrial variant calling: extract chrM, align to standard+shifted refs, call with TNscope, liftover, merge, filter"""
    input:
        sr_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sr_merged.bam",
        sr_bai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sr_merged.bam.bai",
    output:
        mito_vcf=MDIR + "{sample}/align/{alnr}/{ddup}/mito/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.mito.vcf.gz",
        mito_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/mito/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.mito.vcf.gz.tbi",
    wildcard_constraints:
        alnr=ALIGNERS_DHIOMR_REGEX
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/mito/sentdhiomr/log/{sample}.{alnr}.{ddup}.sentdhiomr.mito.log",
    threads: config['sentdhiomr']['threads_medium']
    conda:
        "../envs/sentieon_v0.3b.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhiomr.mito.bench.tsv"
    resources:
        partition="i192mem,i192bigmem,i192",
        threads=config['sentdhiomr']['threads_medium'],
        vcpu=config['sentdhiomr']['threads_medium'],
        mem_mb=config['sentdhiomr']['mem_mb_medium'],
    params:
        mt_fasta=config["sentdhiomr"]["mt_fasta"],
        mt_shifted_fasta=config["sentdhiomr"]["mt_shifted_fasta"],
        mt_shift_back_chain=config["sentdhiomr"]["mt_shift_back_chain"],
        mt_blacklist_bed=config["sentdhiomr"]["mt_blacklist_bed"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.02/bin/

        OUTDIR=$(dirname {output.mito_vcf})
        mkdir -p "$OUTDIR" $(dirname {log})
        SAMPLE="{params.cluster_sample}"
        NT={threads}

        timestamp=$(date +%Y%m%d%H%M%S)
        TMPDIR="/dev/shm/sentdhiomr_mito_${{timestamp}}_$$"
        mkdir -p "$TMPDIR"
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT

        echo "Starting mitochondrial pipeline at $(date)" >> {log}

        # --- Step 1: Extract chrM paired reads → FASTQs ---
        # NOTE: Do NOT use -f (fast mode) on samtools collate — it produces
        # broken R1/R2 pairing on merged BAMs, causing BWA to report
        # "paired reads have different names" and output 0 aligned reads.
        samtools view -F 0x4 -F 0x8 -h {input.sr_bam} chrM 2>>{log} | \
            awk '$0~/^@/ || $7 == "=" {{print}}' | \
            samtools collate -O - "$TMPDIR/collate_$$" 2>>{log} | \
            samtools fastq -N \
                -1 "$TMPDIR/${{SAMPLE}}.chrM.R1.fastq" \
                -2 "$TMPDIR/${{SAMPLE}}.chrM.R2.fastq" - 2>>{log}

        # Validate that reads were actually extracted
        R1_LINES=$(head -4 "$TMPDIR/${{SAMPLE}}.chrM.R1.fastq" | wc -l)
        if [ "$R1_LINES" -lt 4 ]; then
            echo "FATAL: No chrM paired reads extracted from {input.sr_bam}" >> {log}
            exit 1
        fi
        echo "chrM reads extracted at $(date)" >> {log}

        # --- Helper: AlignAndCall on a chrM reference ---
        align_and_call() {{
            local ref="$1" interval="$2" prefix="$3"
            bin/dayoa_sentieon bwa mem \
                -R "@RG\\tID:${{SAMPLE}}\\tSM:${{SAMPLE}}\\tPL:Illumina" \
                -K 100000000 -v 3 -t $NT -Y "$ref" \
                "$TMPDIR/${{SAMPLE}}.chrM.R1.fastq" \
                "$TMPDIR/${{SAMPLE}}.chrM.R2.fastq" 2>>{log} | \
            bin/dayoa_sentieon util sort -t $NT -i - --sam2bam \
                -o "$TMPDIR/${{prefix}}.sorted.bam" >> {log} 2>&1

            bin/dayoa_sentieon driver -t $NT \
                -i "$TMPDIR/${{prefix}}.sorted.bam" \
                --algo LocusCollector --fun score_info \
                "$TMPDIR/${{prefix}}.score.txt" >> {log} 2>&1

            bin/dayoa_sentieon driver -t $NT \
                -i "$TMPDIR/${{prefix}}.sorted.bam" \
                --algo Dedup --score_info "$TMPDIR/${{prefix}}.score.txt" \
                --metrics "$TMPDIR/${{prefix}}.dedup_metrics.txt" \
                "$TMPDIR/${{prefix}}.deduped.bam" >> {log} 2>&1

            bin/dayoa_sentieon driver -t $NT \
                -i "$TMPDIR/${{prefix}}.deduped.bam" \
                -r "$ref" --interval "$interval" \
                --algo TNscope --tumor_sample "$SAMPLE" \
                --min_tumor_allele_frac 0.005 --prune_factor 20 \
                --disable_detector sv --resample_depth 100000 \
                "$TMPDIR/${{prefix}}.raw.tnscope.vcf.gz" >> {log} 2>&1
        }}

        # --- Step 2: Align+Call on standard and shifted refs in parallel ---
        align_and_call "{params.mt_fasta}" "chrM:576-16024" "MT" &
        PID_MT=$!
        align_and_call "{params.mt_shifted_fasta}" "chrM:8025-9144" "ShiftedMT" &
        PID_SHIFTED=$!

        # Wait for both and capture exit codes
        MT_RC=0; wait $PID_MT || MT_RC=$?
        SHIFTED_RC=0; wait $PID_SHIFTED || SHIFTED_RC=$?
        if [ $MT_RC -ne 0 ] || [ $SHIFTED_RC -ne 0 ]; then
            echo "FATAL: align_and_call failed — MT exit=$MT_RC, ShiftedMT exit=$SHIFTED_RC" >> {log}
            exit 1
        fi
        echo "TNscope calling completed at $(date)" >> {log}

        # Verify expected VCF outputs exist before liftover
        for VCF in "$TMPDIR/MT.raw.tnscope.vcf.gz" "$TMPDIR/ShiftedMT.raw.tnscope.vcf.gz"; do
            if [ ! -f "$VCF" ]; then
                echo "FATAL: Expected VCF not produced: $VCF" >> {log}
                exit 1
            fi
        done

        # --- Step 3: Liftover shifted VCF back to standard coords ---
        picard LiftoverVcf \
            I="$TMPDIR/ShiftedMT.raw.tnscope.vcf.gz" \
            O="$TMPDIR/ShiftedMT.shifted_back.vcf.gz" \
            R="{params.mt_fasta}" \
            CHAIN="{params.mt_shift_back_chain}" \
            REJECT="$TMPDIR/ShiftedMT.rejected.vcf" >> {log} 2>&1

        picard MergeVcfs \
            I="$TMPDIR/ShiftedMT.shifted_back.vcf.gz" \
            I="$TMPDIR/MT.raw.tnscope.vcf.gz" \
            O="$TMPDIR/all.tnscope.vcf.gz" >> {log} 2>&1

        echo "Liftover and merge completed at $(date)" >> {log}

        # --- Step 4: Blacklist filter + strand bias annotation ---
        bcftools view -T ^{params.mt_blacklist_bed} "$TMPDIR/all.tnscope.vcf.gz" 2>>{log} | \
            bcftools filter -s "Strand_bias" -e "INFO/SOR>=10" 2>>{log} | \
            bin/dayoa_sentieon util vcfconvert - {output.mito_vcf} >> {log} 2>&1

        bcftools index -t -f {output.mito_vcf} >> {log} 2>&1

        echo "Mitochondrial pipeline completed at $(date)" >> {log}
        """


localrules:
    produce_sentdhiomr_mito,


rule produce_sentdhiomr_mito:  # TARGET: sentieon mito hybrid ilmn+ont modular mito vcf
    input:
        _sentdhiomr_expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/mito/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.mito.vcf.gz.tbi",
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdhiomr.mito",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdhiomr.mito.log",
    shell:
        """( touch {output} ;
        ls {output} ) >> {log} 2>&1;
        """
