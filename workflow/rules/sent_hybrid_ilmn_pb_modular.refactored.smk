"""
Modular Sentieon DNAscope Hybrid Workflow: Illumina + PacBio

This file decomposes the monolithic sentieon-cli dnascope-hybrid call into
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

Uses model bundle: HybridIlluminaPacBio1.1.bundle
"""

import os
import sys

# Ensure config keys exist for shell-block {config[sentdhipmr][...]} access
if "sentdhipmr" not in config:
    config["sentdhipmr"] = {}
config["sentdhipmr"].setdefault("sample_sm", "hybrid_sample")
config["sentdhipmr"].setdefault("lr_read_filter", "")
config["sentdhipmr"].setdefault("sr_read_filter", "")

# Aligner constraint: sentmm2 for PacBio long reads
ALIGNERS_DHIPMR = ["sentmm2"]

# Base temp directory prefix for intermediate files
def _dhipmr_tmp(wildcards):
    return f"{MDIR}{wildcards.sample}/align/{wildcards.alnr}/{wildcards.ddup}/snv/sentdhipmr/vcfs/{wildcards.dchrm}/tmp"

# ---------------------------------------------------------------------------
# Rule 1: SR Alignment - Align Illumina FASTQs with sentieon bwa mem
# ---------------------------------------------------------------------------
rule sentdhipmr_sr_align:
    """Align Illumina short-read FASTQs with sentieon bwa mem | util sort"""
    input:
        r1=getR1s,
        r2=getR2s,
        cram=MDIR + "{sample}/align/{alnr}/{sample}.sentmm2.cram",  # PacBio CRAM must exist
        crai=MDIR + "{sample}/align/{alnr}/{sample}.sentmm2.cram.crai",
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
    output:
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/tmp/sr_aligned.bam",
        bai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/tmp/sr_aligned.bam.bai",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.sr_align.log",
    threads: config['sentdhipmr']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.sr_align.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads'],
        vcpu=config['sentdhipmr']['threads'],
        mem_mb=config['sentdhipmr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        max_mem="130G"
        if "max_mem" not in config["sentieon"]
        else config["sentieon"]["max_mem"],
        model=config["sentdhipmr"]["dna_scope_snv_model"],
        use_threads=config["sentdhipmr"]["use_threads"],
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
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhipmr_sr_${{timestamp}}_$$";
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
        LD_PRELOAD=$LD_PRELOAD sentieon bwa mem \
            -R "@RG\\tID:{params.cluster_sample}-$epocsec\\tSM:{params.cluster_sample}\\tLB:{params.cluster_sample}-LB-1\\tPL:ILLUMINA" \
            -t {params.bwa_threads} \
            -x {params.model}/bwa.model \
            -K 100000000 \
            {params.huref} \
             <( {params.igz} -q  {input.r1} {params.trim_head} )   \
             <( {params.igz} -q  {input.r2} {params.trim_head} )   \
             {params.mbuffer}  2>> {log} | \
        sentieon util sort \
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

        mv $TMPDIR ./
        echo "SR alignment completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 1b: SR Markdup - Deduplication of Illumina short reads
# ---------------------------------------------------------------------------
rule sentdhipmr_sr_markdup:
    input:
        bam = MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/tmp/sr_aligned.bam"
    output:
        bam = MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/tmp/sr_dedup.bam",
        bai = MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/tmp/sr_dedup.bam.bai"
    params:
        huref = config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        use_threads = config["sentdhipmr"]["use_threads"],
        tmp_base="/dev/shm",
        cluster_sample=ret_sample,
    threads: config['sentdhipmr']['threads']
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.sr_markdup.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads'],
        vcpu=config['sentdhipmr']['threads'],
        mem_mb=config['sentdhipmr']['mem_mb'],
    conda:
        "../envs/sentieon_v0.3.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.sr_markdup.log"
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

        jemalloc_path=$(find "$CONDA_PREFIX" \\( -name "libjemalloc*.so*" -o -name "libjemalloc*.dylib" \\) | head -n 1 || true);
        if [[ -n "$jemalloc_path" ]]; then
            export LD_PRELOAD="$jemalloc_path";
            echo "LD_PRELOAD set to: $LD_PRELOAD" >> {log};
        else
            echo "libjemalloc not found in the active conda environment $CONDA_PREFIX." >> {log};
            exit 5;
        fi;

        LD_PRELOAD=$LD_PRELOAD sentieon driver \
        -r {params.huref} \
        -t {threads} \
        -i {input.bam} \
        --algo LocusCollector --fun score_info "$score_file" >> {log} 2>&1;

        LD_PRELOAD=$LD_PRELOAD sentieon driver \
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
# Rule 2: Pass 1 - Combined LR+SR variant calling (DNAscope)
# ---------------------------------------------------------------------------
rule sentdhipmr_pass1:
    """First-pass combined variant calling (DNAscope) on LR+SR"""
    input:
        sr_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/tmp/sr_dedup.bam",
        sr_bai=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/tmp/sr_dedup.bam.bai",
        lr_cram=MDIR + "{sample}/align/{alnr}/{sample}.sentmm2.cram",
        lr_crai=MDIR + "{sample}/align/{alnr}/{sample}.sentmm2.cram.crai",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/initial.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/initial.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.pass1.log",
    threads: config['sentdhipmr']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.{dchrm}.pass1.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads'],
        vcpu=config['sentdhipmr']['threads'],
        mem_mb=config['sentdhipmr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhipmr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_path,
        schrm_mod=get_dchrm_day,
        use_threads=config["sentdhipmr"]["use_threads"],
        cluster_sample=ret_sample,
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhipmr_p1_${{timestamp}}_$$";
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

        echo "Starting Pass 1 DNAscope at $(date)" >> {log}

        scoped_diploid_bed="$TMPDIR/scoped_diploid.bed"
        python workflow/scripts/make_scoped_diploid_bed.py \
            --regions "{params.schrm_mod}" \
            --diploid-bed "{params.diploid_bed}" \
            --fai "{params.huref}.fai" \
            --output "$scoped_diploid_bed" >> {log} 2>&1

        # Build --replace_rg args: LR reads get LR:1 tag (critical for hybrid.model
        # to distinguish long reads from short reads, especially for indel calling).
        # SR reads get SM-only replacement to unify sample names. Matches CLI behavior.
        LR_RG_ARGS=""
        for rgid in $(samtools view -H {input.lr_cram} | grep '^@RG' | sed 's/.*ID:\([^\\t]*\).*/\\1/'); do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done

        sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            $LR_RG_ARGS -i {input.lr_cram} \
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


# ---------------------------------------------------------------------------
# Rule 3: Hybrid Select - Region selection from pass-1 VCF
# ---------------------------------------------------------------------------
rule sentdhipmr_hybrid_select:
    """Select regions for hybrid re-analysis based on pass-1 variants.

    This replicates the sentieon-cli hybrid_select pipeline:
    1. hybrid_select.py filters VCF based on long/short read confidence
    2. bcftools view filters for PASS variants
    3. bcftools query converts to BED format
    4. bedtools slop adds 1000bp padding
    """
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/initial.vcf.gz",
        ref_fai=config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/selected.bed",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.hybrid_select.log",
    threads: config['sentdhipmr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.{dchrm}.hybrid_select.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads_light'],
        vcpu=config['sentdhipmr']['threads_light'],
        mem_mb=config['sentdhipmr']['mem_mb_light'],
    params:
        use_threads=config["sentdhipmr"]["use_threads_light"],
        cluster_sample=ret_sample,
        slop_size=1000,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting hybrid_select pipeline at $(date)" >> {log}

        # Find hybrid_select.py script
        HYBRID_SELECT=$(python -c "from importlib.resources import files; print(files('sentieon_cli.scripts').joinpath('hybrid_select.py'))")

        # Pipeline: hybrid_select.py -> bcftools view -> bcftools query -> bedtools slop
        # This replicates sentieon-cli's cmd_pyexec_hybrid_select() function
        sentieon pyexec "$HYBRID_SELECT" \
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
rule sentdhipmr_mapq0_bed:
    """Detect MAPQ0 regions with HybridStage2 region model"""
    input:
        sr_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/tmp/sr_aligned.bam",
        lr_cram=MDIR + "{sample}/align/{alnr}/{sample}.sentmm2.cram",
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_mapq0.bed",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.mapq0_bed.log",
    threads: config['sentdhipmr']['threads_medium']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.{dchrm}.mapq0_bed.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads_medium'],
        vcpu=config['sentdhipmr']['threads_medium'],
        mem_mb=config['sentdhipmr']['mem_mb_medium'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhipmr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_path,
        schrm_mod=get_dchrm_day,
        use_threads=config["sentdhipmr"]["use_threads_medium"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhipmr_mq_${{timestamp}}_$$";
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
        LR_RG_ARGS=""
        for rgid in $(samtools view -H {input.lr_cram} | grep '^@RG' | sed 's/.*ID:\([^\\t]*\).*/\\1/'); do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done

        sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            $LR_RG_ARGS -i {input.lr_cram} \
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
rule sentdhipmr_mapq0_slop:
    """Extend MAPQ0 regions by 1000 bp using bedtools slop"""
    input:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_mapq0.bed",
        ref_fai=config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_mapq0.ex1000.bed",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.mapq0_slop.log",
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
rule sentdhipmr_merge_beds:
    """Cat, sort, merge selected.bed + mapq0.ex1000.bed → merged_diff.bed"""
    input:
        selected=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/selected.bed",
        mapq0=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_mapq0.ex1000.bed",
        ref_fai=config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/merged_diff.bed",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.merge_beds.log",
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
rule sentdhipmr_stage1:
    """Stage1: insertion detection + haplotype assembly piped through bwa"""
    input:
        lr_cram=MDIR + "{sample}/align/{alnr}/{sample}.sentmm2.cram",
        diff_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/merged_diff.bed",
    output:
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_stage1.bam",
        hap_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/stage1_hap.bam",
        hap_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/stage1_hap.bed",
        hap_vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/stage1_hap.vcf",
        ins_fa=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/stage1_ins.fa",
        ins_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/stage1_ins.bed",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.stage1.log",
    threads: config['sentdhipmr']['threads']  # Full node: stage1 runs 4 concurrent processes (HAP+INS+bwa+sort)
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.{dchrm}.stage1.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads'],
        vcpu=config['sentdhipmr']['threads'],
        mem_mb=config['sentdhipmr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhipmr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_path,
        schrm_mod=get_dchrm_day,
        use_threads=config["sentdhipmr"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        r"""
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhipmr_s1_${{timestamp}}_$$";
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

        echo "Starting Stage 1 at $(date)" >> {log}

        scoped_diploid_bed="$TMPDIR/scoped_diploid.bed"
        python workflow/scripts/make_scoped_diploid_bed.py \
            --regions "{params.schrm_mod}" \
            --diploid-bed "{params.diploid_bed}" \
            --fai "{params.huref}.fai" \
            --output "$scoped_diploid_bed" >> {log} 2>&1

        # Use cluster_sample for consistent @RG SM tag across entire pipeline
        # This matches the pattern used in sentieon_bwa_sort and other alignment rules
        epocsec=$(date +%s)

        # Check if merged_diff.bed is empty - if so, skip HAP_CMD and create empty outputs
        if [ ! -s {input.diff_bed} ]; then
            echo "WARNING: merged_diff.bed is empty - no haplotype regions to process" >> {log}
            echo "Creating empty hap_bam (with clean header), hap_bed, hap_vcf files" >> {log}
            # Create empty BED and VCF
            touch {output.hap_bed} {output.hap_vcf}
            # Create proper empty BAM with clean header: @HD, @SQ, and @RG lines only (no @PG)
            # Include @RG because sentieon driver requires it
            # Exclude @PG to avoid PP chain references to non-existent programs
            samtools view -H {input.lr_cram} | grep -E '^@(HD|SQ|RG)' | samtools view -bo {output.hap_bam} -
            samtools index {output.hap_bam}

            # Only run insertion detection in the requested shard interval
            INS_CMD="sentieon driver -r {params.huref} -t {params.use_threads} \
                --temp_dir $TMPDIR \
                -i {input.lr_cram} --interval "$scoped_diploid_bed" \
                --algo HybridStage1 \
                --model {params.model}/HybridStage1_ins.model \
                --fa_file {output.ins_fa} \
                --bed_file {output.ins_bed} \
                -"

            $INS_CMD 2>> {log} | \
            sentieon bwa mem \
                -R "@RG\\tID:{params.cluster_sample}-$epocsec\\tSM:{params.cluster_sample}\\tLB:{params.cluster_sample}-LB-1\\tPL:HYBRID" \
                -t {params.use_threads} \
                -x {params.model}/HybridStage1_bwa.model \
                {params.huref} - 2>> {log} | \
            sentieon util sort \
                -i - -t {params.use_threads} \
                --temp_dir $TMPDIR \
                -o {output.bam} --sam2bam >> {log} 2>&1
        else
            echo "Processing $(wc -l < {input.diff_bed}) regions from merged_diff.bed" >> {log}

            # Haplotype assembly driver command
            HAP_CMD="sentieon driver -r {params.huref} -t {params.use_threads} \
                --temp_dir $TMPDIR \
                -i {input.lr_cram} --interval {input.diff_bed} \
                --algo HybridStage1 \
                --model {params.model}/HybridStage1.model \
                --hap_bam {output.hap_bam} \
                --hap_bed {output.hap_bed} \
                --hap_vcf {output.hap_vcf} \
                -"

            # Insertion detection driver command
            INS_CMD="sentieon driver -r {params.huref} -t {params.use_threads} \
                --temp_dir $TMPDIR \
                -i {input.lr_cram} --interval {input.diff_bed} \
                --algo HybridStage1 \
                --model {params.model}/HybridStage1_ins.model \
                --fa_file {output.ins_fa} \
                --bed_file {output.ins_bed} \
                -"

            # Cat both FASTQ streams → bwa mem → util sort
            cat <($HAP_CMD 2>> {log}) <($INS_CMD 2>> {log}) | \
            sentieon bwa mem \
                -R "@RG\\tID:{params.cluster_sample}-$epocsec\\tSM:{params.cluster_sample}\\tLB:{params.cluster_sample}-LB-1\\tPL:HYBRID" \
                -t {params.use_threads} \
                -x {params.model}/HybridStage1_bwa.model \
                {params.huref} - 2>> {log} | \
            sentieon util sort \
                -i - -t {params.use_threads} \
                --temp_dir $TMPDIR \
                -o {output.bam} --sam2bam >> {log} 2>&1

            # Wait for process substitutions to fully complete (ensures hap_bam is finalized)
            wait
            sync

            # Verify hap_bam integrity before indexing
            samtools quickcheck {output.hap_bam} >> {log} 2>&1 || \
                (echo "ERROR: stage1_hap.bam failed integrity check - file may be truncated" >> {log} && exit 1)

            # Index the hap BAM produced by HybridStage1 - required by stage2
            samtools index {output.hap_bam} >> {log} 2>&1
        fi

        echo "Stage 1 completed at $(date)" >> {log}
        """



# ---------------------------------------------------------------------------
# Rule 8: Stage 2 - Generate unmap/alt BAMs and refined BED
# ---------------------------------------------------------------------------
rule sentdhipmr_stage2:
    """Stage2: generate unmap BAM, alt BAM, and refined BED"""
    input:
        stage1_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_stage1.bam",
        hap_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/stage1_hap.bam",
        hap_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/stage1_hap.bed",
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
        unmap_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_stage2_unmap.bam",
        alt_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_stage2_alt.bam",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.stage2.log",
    threads: config['sentdhipmr']['threads_medium']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.{dchrm}.stage2.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads_medium'],
        vcpu=config['sentdhipmr']['threads_medium'],
        mem_mb=config['sentdhipmr']['mem_mb_medium'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhipmr"]["dna_scope_snv_model"],
        use_threads=config["sentdhipmr"]["use_threads_medium"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhipmr_s2_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        echo "Starting Stage 2 at $(date)" >> {log}

        sentieon driver -r {params.huref} -t {params.use_threads} \
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
rule sentdhipmr_stage3:
    """Stage3: HybridStage3 on all reads + stage2 BAMs → sorted BAM"""
    input:
        sr_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/tmp/sr_aligned.bam",
        lr_cram=MDIR + "{sample}/align/{alnr}/{sample}.sentmm2.cram",
        unmap_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_stage2_unmap.bam",
        alt_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_stage2_alt.bam",
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
    output:
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_stage3.bam",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.stage3.log",
    threads: config['sentdhipmr']['threads']  # Full node: stage3 pipes driver → util sort (2 concurrent processes)
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.{dchrm}.stage3.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads'],
        vcpu=config['sentdhipmr']['threads'],
        mem_mb=config['sentdhipmr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhipmr"]["dna_scope_snv_model"],
        use_threads=config["sentdhipmr"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhipmr_s3_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        echo "Starting Stage 3 at $(date)" >> {log}

        # NOTE: Input PB CRAM must have clean @PG headers (no broken PP chain).

        # Build --replace_rg args: LR reads get LR:1 tag for hybrid model
        LR_RG_ARGS=""
        for rgid in $(samtools view -H {input.lr_cram} | grep '^@RG' | sed 's/.*ID:\([^\\t]*\).*/\\1/'); do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done

        sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            $LR_RG_ARGS -i {input.lr_cram} \
            -i {input.sr_bam} \
            $LR_RG_ARGS -i {input.unmap_bam} \
            $LR_RG_ARGS -i {input.alt_bam} \
            --interval {input.bed} \
            --algo HybridStage3 \
            --model {params.model}/HybridStage3.model \
            - 2>> {log} | \
        sentieon util sort \
            -i - -t {params.use_threads} \
            --temp_dir $TMPDIR \
            -o {output.bam} >> {log} 2>&1

        echo "Stage 3 completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 10: Pass 2 - Second-pass variant calling on refined regions
# ---------------------------------------------------------------------------
rule sentdhipmr_pass2:
    """Second-pass variant calling on stage3 BAM + LR reads"""
    input:
        lr_cram=MDIR + "{sample}/align/{alnr}/{sample}.sentmm2.cram",
        stage3_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_stage3.bam",
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.pass2.log",
    threads: config['sentdhipmr']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.{dchrm}.pass2.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads'],
        vcpu=config['sentdhipmr']['threads'],
        mem_mb=config['sentdhipmr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhipmr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_interval_arg,  # Use --interval for sentieon driver
        use_threads=config["sentdhipmr"]["use_threads"],
        cluster_sample=ret_sample,
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhipmr_p2_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        echo "Starting Pass 2 DNAscope at $(date)" >> {log}

        # Build --replace_rg args: LR reads get LR:1 tag for hybrid model.
        # This also unifies SM tags across lr_cram and stage3_bam so sentieon
        # driver sees a single sample (stage3_bam inherits LR RGs from PB input).
        LR_RG_ARGS=""
        for rgid in $(samtools view -H {input.lr_cram} | grep '^@RG' | sed 's/.*ID:\([^\\t]*\).*/\\1/'); do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done

        sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            $LR_RG_ARGS -i {input.lr_cram} \
            -i {input.stage3_bam} \
            --interval {input.bed} \
            {params.diploid_bed} \
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
rule sentdhipmr_subset:
    """Subset pass-1 VCF to complement of stage2 regions"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/initial.vcf.gz",
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/mix_subset.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/mix_subset.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.subset.log",
    threads: config['sentdhipmr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads_light'],
        vcpu=config['sentdhipmr']['threads_light'],
        mem_mb=config['sentdhipmr']['mem_mb_light'],
    params:
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Subsetting pass-1 VCF at $(date)" >> {log}

        # If stage2 BED is empty, just copy; otherwise subset
        if [ -s {input.bed} ]; then
            bcftools view --threads {threads} -T ^{input.bed} {input.vcf} 2>> {log} | \
            sentieon util vcfconvert -t {threads} - {output.vcf} >> {log} 2>&1
        else
            sentieon util vcfconvert -t {threads} {input.vcf} {output.vcf} >> {log} 2>&1
        fi

        # Ensure index exists (sentieon util vcfconvert should create it, but verify)
        if [ ! -f {output.tbi} ]; then
            tabix -p vcf -@ {threads} {output.vcf} >> {log} 2>&1
        fi

        echo "Subset completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 12: Concat Pass - Concatenate subset + pass2 VCFs
# ---------------------------------------------------------------------------
rule sentdhipmr_concat_pass:
    """Concatenate subset + pass2 VCFs"""
    input:
        subset=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/mix_subset.vcf.gz",
        subset_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/mix_subset.vcf.gz.tbi",
        pass2=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz",
        pass2_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz.tbi",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/combined_tmp.vcf.gz",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.concat_pass.log",
    threads: config['sentdhipmr']['threads_light']
    conda:
        "../envs/vanilla_v0.1.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads_light'],
        vcpu=config['sentdhipmr']['threads_light'],
        mem_mb=config['sentdhipmr']['mem_mb_light'],
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
rule sentdhipmr_anno:
    """Annotate VCF with hybrid-specific annotations"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/combined_tmp.vcf.gz",
        hap_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/stage1_hap.bed",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/combined_tmp_anno.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/combined_tmp_anno.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.anno.log",
    threads: config['sentdhipmr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads_light'],
        vcpu=config['sentdhipmr']['threads_light'],
        mem_mb=config['sentdhipmr']['mem_mb_light'],
    params:
        use_threads=config["sentdhipmr"]["use_threads_light"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting hybrid annotation at $(date)" >> {log}

        # Find hybrid_anno.py script
        HYBRID_ANNO=$(python -c "from importlib.resources import files; print(files('sentieon_cli.scripts').joinpath('hybrid_anno.py'))")

        sentieon pyexec "$HYBRID_ANNO" \
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
# A gather rule (sentdhipmr_transfer_merge) concatenates shards before model_apply.
# ---------------------------------------------------------------------------
rule sentdhipmr_transfer:
    """Transfer annotations from population VCF using bcftools merge + trimalt pipe (per-chromosome shard)"""
    input:
        anno_vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/combined_tmp_anno.vcf.gz",
        anno_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/combined_tmp_anno.vcf.gz.tbi",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/transfer_shards/transfer.{tchrm}.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/transfer_shards/transfer.{tchrm}.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR),
        tchrm="|".join(SENTDHIPMR_CHRMS_TRANSFER),
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.transfer.{tchrm}.log",
    threads: config['sentdhipmr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.{dchrm}.transfer.{tchrm}.bench.tsv"
    resources:
        partition="i192mem,i192bigmem,i192",
        threads=config['sentdhipmr']['threads_light'],
        vcpu=config['sentdhipmr']['threads_light'],
        mem_mb=config['sentdhipmr']['mem_mb_light'],
    params:
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
        cluster_sample=ret_sample,
        regions=lambda wildcards: get_dchrm_day(type('obj', (object,), {'dchrm': wildcards.tchrm})()),
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

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

        TRIM_SCRIPT=$(python -c "from importlib.resources import files; print(files('sentieon_cli.scripts').joinpath('trimalt.py'))")

        echo "Transferring annotations from pop_vcf: {params.pop_vcf} for regions: {params.regions}" >> {log}

        # bcftools merge transfers INFO annotations from sites-only pop_vcf to sample VCF
        # --regions restricts to this chromosome shard
        # Then trimalt processes the merged output (CLI-equivalent single-pipe pattern)
        bcftools merge --threads {threads} --no-version --regions-overlap pos -m all \
            --regions {params.regions} \
            "$TMPDIR/anno_reheadered.{wildcards.tchrm}.vcf.gz" {params.pop_vcf} 2>> {log} | \
        sentieon pyexec "$TRIM_SCRIPT" 2>> {log} | \
        bgzip -c -@ {threads} > {output.vcf} 2>> {log}

        # Create tabix index
        bcftools index --threads {threads} -t {output.vcf} >> {log} 2>&1

        # Cleanup temp files
        rm -f "$TMPDIR/anno_reheadered.{wildcards.tchrm}.vcf.gz" \
              "$TMPDIR/anno_reheadered.{wildcards.tchrm}.vcf.gz.tbi" \
              "$TMPDIR/anno_rename.{wildcards.tchrm}.txt"

        echo "Transfer shard {wildcards.tchrm} completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 14b: Transfer Merge - Gather per-chromosome transfer shards
# ---------------------------------------------------------------------------
rule sentdhipmr_transfer_merge:
    """Concatenate per-chromosome transfer shards into single VCF for model_apply"""
    input:
        shards=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhipmr/vcfs/{{dchrm}}/tmp/transfer_shards/transfer.{tchrm}.vcf.gz",
                tchrm=SENTDHIPMR_CHRMS_TRANSFER,
            ),
            key=lambda x: int(x.rsplit("transfer.", 1)[1].split(".vcf.gz")[0])
            if x.rsplit("transfer.", 1)[1].split(".vcf.gz")[0].isdigit()
            else 99,
        ),
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/combined_tmp_transfer.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/combined_tmp_transfer.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.transfer_merge.log",
    threads: config['sentdhipmr']['threads_light']
    conda:
        "../envs/vanilla_v0.1.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.{dchrm}.transfer_merge.bench.tsv"
    resources:
        partition="i192mem,i192bigmem,i192",
        threads=config['sentdhipmr']['threads_light'],
        vcpu=config['sentdhipmr']['threads_light'],
        mem_mb=config['sentdhipmr']['mem_mb_light'],
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
rule sentdhipmr_model_apply:
    """Apply ML model to called variants"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/combined_tmp_transfer.vcf.gz",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/combined_apply.vcf.gz",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.model_apply.log",
    threads: config['sentdhipmr']['threads_medium']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.{dchrm}.model_apply.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads_medium'],
        vcpu=config['sentdhipmr']['threads_medium'],
        mem_mb=config['sentdhipmr']['mem_mb_medium'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhipmr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_path,
        schrm_mod=get_dchrm_day,
        use_threads=config["sentdhipmr"]["use_threads_medium"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhipmr_ma_${{timestamp}}_$$";
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

        sentieon driver -r {params.huref} -t {params.use_threads} \
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
rule sentdhipmr_final_norm:
    """Trim, normalize, and produce final output VCF"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/tmp/combined_apply.vcf.gz",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhipmr.{dchrm}.snv.sort.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhipmr.{dchrm}.snv.sort.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.{dchrm}.final_norm.log",
    threads: config['sentdhipmr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.{dchrm}.final_norm.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads_light'],
        vcpu=config['sentdhipmr']['threads_light'],
        mem_mb=config['sentdhipmr']['mem_mb_light'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting final normalization at $(date)" >> {log}

        bcftools view --threads {threads} -a -e 'GT="0/0"' {input.vcf} 2>> {log} | \
        bcftools norm --threads {threads} -f {params.huref} 2>> {log} | \
        sentieon util vcfconvert -t {threads} - {output.vcf} >> {log} 2>&1

        echo "Final normalization completed at $(date)" >> {log}
        """


# ===========================================================================
# DOWNSTREAM RULES: FOFN, Concat, Target rules (similar to original)
# ===========================================================================

localrules:
    sentdhipmr_concat_fofn,


rule sentdhipmr_concat_fofn:
    """Build file-of-filenames for chromosome chunks"""
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhipmr/vcfs/{ochm}/{{sample}}.{{alnr}}.{{ddup}}.sentdhipmr.{ochm}.snv.sort.vcf.gz.tbi",
                ochm=SENTDHIPMR_CHRMS,
            ),
            key=lambda x: float(
                str(x.replace("~", ".").replace(":", "."))
                .split("vcfs/")[1]
                .split("/")[0]
                .split("-")[0]
            ),
        ),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    priority: 44
    output:
        fin_fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/{sample}.{alnr}.{ddup}.sentdhipmr.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/{sample}.{alnr}.{ddup}.sentdhipmr.snv.concat.vcf.gz.fofn.tmp",
    threads: 1
    resources:
        threads=1
    params:
        fn_stub="{sample}.{alnr}.{ddup}.sentdhipmr."
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.concat.fofn.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.sentdhipmr.concat.fofn.log",
    shell:
        """
        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\\.tbi$//g'; );
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.sentdhipmr. {output.fin_fofn}) >> {log} 2>&1;
        """


rule sentdhipmr_concat_index_chunks:
    """Concatenate chromosome chunks and index final VCF"""
    input:
        fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/{sample}.{alnr}.{ddup}.sentdhipmr.snv.concat.vcf.gz.fofn",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/{sample}.{alnr}.{ddup}.sentdhipmr.snv.sort.vcf.gz",
        vcfgztemp=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/{sample}.{alnr}.{ddup}.sentdhipmr.snv.sort.temp.vcf.gz",
        vcfgztbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/{sample}.{alnr}.{ddup}.sentdhipmr.snv.sort.vcf.gz.tbi",
    threads: config['sentdhipmr']['threads_light']
    resources:
        vcpu=config['sentdhipmr']['threads_light'],
        threads=config['sentdhipmr']['threads_light'],
        partition="i192mem,i192bigmem",
        mem_mb=config['sentdhipmr']['mem_mb_light'],
    priority: 47
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.merge.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/log/{sample}.{alnr}.{ddup}.sentdhipmr.snv.merge.sort.gathered.log",
    shell:
        """
        touch {log};
        mkdir -p $(dirname {log});

        bcftools concat -a -d all --threads {threads} -f {input.fofn} -O z -o {output.vcfgztemp} >> {log} 2>&1;

        export oldname=$(bcftools query -l {output.vcfgztemp} | head -n1) >> {log} 2>&1;
        echo -e "${{oldname}}\\t{params.cluster_sample}" > {output.vcfgz}.rename.txt
        bcftools reheader --threads {threads} -s {output.vcfgz}.rename.txt -o {output.vcfgz} {output.vcfgztemp} >> {log} 2>&1;
        bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;

        rm -rf $(dirname {output.vcfgz})/vcfs >> {log} 2>&1;
        """



localrules:
    clear_combined_sentdhipmr_vcf,


rule clear_combined_sentdhipmr_vcf:  # TARGET: clear combined sentdhipmr vcf so chunks can be re-evaluated if needed.
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/{sample}.{alnr}.{ddup}.sentdhipmr.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=ALIGNERS_DHIPMR,
            ddup=DDUP,
        ),
    threads: 2
    priority: 42
    shell:
        """
        rm {input}*  1> /dev/null  2> /dev/null ) || echo 'file not found for deletion: {input}';
        """


localrules:
    produce_sentdhipmr_vcf,


rule produce_sentdhipmr_vcf:  # TARGET: sentieon dnascope hybrid modular vcf
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/{sample}.{alnr}.{ddup}.sentdhipmr.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS_DHIPMR,
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdhipmr",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdhipmr.log",
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """


# ===========================================================================
# SV CALLING: LongReadSV structural variant calling (whole-genome, not chunked)
# ===========================================================================

rule sentdhipmr_call_svs:
    """Call structural variants using LongReadSV on PacBio long reads"""
    input:
        lr_cram=MDIR + "{sample}/align/{alnr}/{sample}.sentmm2.cram",
        lr_crai=MDIR + "{sample}/align/{alnr}/{sample}.sentmm2.cram.crai",
    output:
        sv_vcf=MDIR + "{sample}/align/{alnr}/{ddup}/sv/sentdhipmr/{sample}.{alnr}.{ddup}.sentdhipmr.sv.vcf.gz",
        sv_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/sv/sentdhipmr/{sample}.{alnr}.{ddup}.sentdhipmr.sv.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/sv/sentdhipmr/log/{sample}.{alnr}.{ddup}.sentdhipmr.sv.log",
    threads: config['sentdhipmr']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhipmr.sv.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=config['sentdhipmr']['threads'],
        vcpu=config['sentdhipmr']['threads'],
        mem_mb=config['sentdhipmr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhipmr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_interval_arg,
        use_threads=config["sentdhipmr"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhipmr_sv_${{timestamp}}_$$";
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

        sentieon driver -r {params.huref} -t {params.use_threads} \
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
    produce_sentdhipmr_sv,


rule produce_sentdhipmr_sv:  # TARGET: sentieon longreadsv hybrid ilmn+pb modular sv vcf
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/sv/sentdhipmr/{sample}.{alnr}.{ddup}.sentdhipmr.sv.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS_DHIPMR,
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdhipmr.sv",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdhipmr.sv.log",
    shell:
        """( touch {output} ;
        ls {output} ) >> {log} 2>&1;
        """


localrules:
    prep_sentdhipmr_chunkdirs,


rule prep_sentdhipmr_chunkdirs:
    """Prepare chunk directories for modular hybrid workflow"""
    input:
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        r1=getR1s,
        r2=getR2s,
        cram=MDIR + "{sample}/align/{alnr}/{sample}.sentmm2.cram",
        crai=MDIR + "{sample}/align/{alnr}/{sample}.sentmm2.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhipmr/vcfs/{dchrm}/{{sample}}.ready",
            dchrm=SENTDHIPMR_CHRMS
        ),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHIPMR)
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhipmr/logs/{sample}.{alnr}.{ddup}.chunkdirs.log",
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
