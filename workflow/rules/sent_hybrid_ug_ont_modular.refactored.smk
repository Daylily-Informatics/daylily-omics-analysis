"""
Modular Sentieon DNAscope Hybrid Workflow: Ultima + ONT

This file decomposes the monolithic bin/dayoa_sentieon_cli dnascope-hybrid call into
discrete Snakemake rules for better observability, restartability, and debugging.

Caller code: sentdhuomr (Sentieon DNAscope Hybrid Ultima+ONT Modular)

Pipeline stages (21 discrete rules):
1. Pass 1: Initial DNAscope on combined Ultima + ONT reads
2. Hybrid Select: Region selection from pass-1 VCF
3. MAPQ0 Detection: Find low-quality mapping regions
4. MAPQ0 Slop: Extend MAPQ0 regions by 1000bp
5. Merge BEDs: Combine selected + MAPQ0 regions
6. Stage 1: Insertion detection + haplotype assembly → bwa realign
7. Stage 2: Generate unmap/alt BAMs and refined BED
8. Stage 3: Re-alignment with stage2 outputs
9. Pass 2: Second-pass variant calling on refined regions
10. Subset: Subset pass-1 VCF to complement of stage2 regions
11. Concat: Concatenate subset + pass2 VCFs
12. Anno: Hybrid-specific annotations
13. Transfer: Annotation transfer from population VCF (if pop_vcf set)
14. Model Apply: DNAModelApply ML filtering
15. Final Norm: bcftools normalization → output VCF

Key differences from Illumina+ONT (sentdhiom):
- Uses pre-aligned Ultima CRAM (`--sr_aln`) - NO FASTQ alignment step
- Uses ALIGNERS_DHUOMR = ["ug"] for wildcard constraints
- Uses get_alt_sample_name for sample name extraction
- Uses HybridUltimaONT model bundle
- References hg38_broad instead of standard hg38

References:
- sentieon-cli/workflow/Snakefile (lines 390-815)
- sentieon-cli/sentieon_cli/dnascope_hybrid.py (call_variants method)
- sentieon-cli/sentieon_cli/command_strings.py
"""

import sys
import os

# Aligner constraint for Ultima+ONT hybrid modular workflow
ALIGNERS_DHUOMR = ["ug"]


# ---------------------------------------------------------------------------
# Rule 1: Pass 1 - Initial DNAscope on combined Ultima + ONT reads
# ---------------------------------------------------------------------------
rule sentdhuomr_pass1:
    """First-pass DNAscope variant calling on combined Ultima + ONT reads"""
    input:
        ug_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        ug_crai=MDIR + "{sample}/align/{alnr}/{sample}.cram.crai",
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
        ont_crai=MDIR + "{sample}/align/ont/{sample}.cram.crai",
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        d=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/{sample}.ready",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/initial.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/initial.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.pass1.log",
    threads: config['sentdhuomr']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    priority: 45
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuomr.{dchrm}.pass1.bench.tsv"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=config['sentdhuomr']['threads'],
        vcpu=config['sentdhuomr']['threads'],
        mem_mb=config['sentdhuomr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuomr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_path,
        schrm_mod=get_dchrm_day,
        use_threads=config["sentdhuomr"]["use_threads"],
        cluster_sample=ret_sample,
        alt_samp_name=get_alt_sample_name,
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/scratch/sentdhuomr_p1_${{timestamp}}_$$";
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

        echo "Starting Pass 1 DNAscope (Ultima+ONT) at $(date)" >> {log}

        scoped_diploid_bed="$TMPDIR/scoped_diploid.bed"
        python workflow/scripts/make_scoped_diploid_bed.py \
            --regions "{params.schrm_mod}" \
            --diploid-bed "{params.diploid_bed}" \
            --fai "{params.huref}.fai" \
            --output "$scoped_diploid_bed" >> {log} 2>&1

        # Validate Ultima CRAM
        echo "Validating Ultima CRAM: {input.ug_cram}" >> {log} 2>&1
        samtools quickcheck -v {input.ug_cram} >> {log} 2>&1
        _sq_count=$(samtools view -H {input.ug_cram} 2>/dev/null | grep -c '^@SQ' || true)
        echo "Ultima CRAM @SQ header count: $_sq_count" >> {log} 2>&1

        # Validate ONT CRAM
        echo "Validating ONT CRAM: {input.ont_cram}" >> {log} 2>&1
        samtools quickcheck -v {input.ont_cram} >> {log} 2>&1
        _sq_count_ont=$(samtools view -H {input.ont_cram} 2>/dev/null | grep -c '^@SQ' || true)
        echo "ONT CRAM @SQ header count: $_sq_count_ont" >> {log} 2>&1

        # Build --replace_rg args: LR reads get LR:1 tag (critical for hybrid.model
        # to distinguish long reads from short reads, especially for indel calling).
        # SR reads get SM-only replacement to unify sample names. Matches CLI behavior.
        LR_RG_ARGS=""
        for rgid in $(samtools view -H {input.ont_cram} | grep '^@RG' | sed 's/.*ID:\([^\\t]*\).*/\\1/'); do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done
        SR_RG_ARGS=""
        for rgid in $(samtools view -H {input.ug_cram} | grep '^@RG' | sed 's/.*ID:\([^\\t]*\).*/\\1/'); do
            SR_RG_ARGS="$SR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}"
        done

        bin/dayoa_sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            $LR_RG_ARGS -i {input.ont_cram} \
            $SR_RG_ARGS -i {input.ug_cram} \
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
# Rule 2: Hybrid Select - Region selection from pass-1 VCF
# ---------------------------------------------------------------------------
rule sentdhuomr_hybrid_select:
    """Select regions for hybrid re-analysis based on pass-1 variants.

    This replicates the sentieon-cli hybrid_select pipeline:
    1. hybrid_select.py filters VCF based on long/short read confidence
    2. bcftools view filters for PASS variants
    3. bcftools query converts to BED format
    4. bedtools slop adds 1000bp padding
    """
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/initial.vcf.gz",
        ref_fai=config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/selected.bed",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.hybrid_select.log",
    threads: config['sentdhuomr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuomr.{dchrm}.hybrid_select.bench.tsv"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=config['sentdhuomr']['threads_light'],
        vcpu=config['sentdhuomr']['threads_light'],
        mem_mb=config['sentdhuomr']['mem_mb_light'],
    params:
        use_threads=config["sentdhuomr"]["use_threads_light"],
        cluster_sample=ret_sample,
        slop_size=1000,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/

        echo "Starting hybrid_select pipeline at $(date)" >> {log}

        : "${{CONDA_PREFIX:?CONDA_PREFIX is required for sentdhuomr_hybrid_select}}"
        {{
            echo "DEBUG hybrid_select env at $(date)"
            echo "DEBUG CONDA_PREFIX=$CONDA_PREFIX"
            echo "DEBUG which_python=$(command -v python || true)"
            "$CONDA_PREFIX/bin/python" -c "import os, sys; print('DEBUG sys.executable=' + sys.executable); print('DEBUG sys.prefix=' + sys.prefix); print('DEBUG env_CONDA_PREFIX=' + str(os.environ.get('CONDA_PREFIX'))); from importlib.resources import files; print('DEBUG hybrid_select=' + str(files('sentieon_cli.scripts').joinpath('hybrid_select.py')))"
        }} >> {log} 2>&1 || true

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
# Rule 3: MAPQ0 Detection - Find low-quality mapping regions
# ---------------------------------------------------------------------------
rule sentdhuomr_mapq0_bed:
    """Detect MAPQ0 regions with HybridStage2 region model"""
    input:
        ug_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_mapq0.bed",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.mapq0_bed.log",
    threads: config['sentdhuomr']['threads_medium']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuomr.{dchrm}.mapq0_bed.bench.tsv"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=config['sentdhuomr']['threads_medium'],
        vcpu=config['sentdhuomr']['threads_medium'],
        mem_mb=config['sentdhuomr']['mem_mb_medium'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuomr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_path,
        schrm_mod=get_dchrm_day,
        use_threads=config["sentdhuomr"]["use_threads_medium"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/scratch/sentdhuomr_mq_${{timestamp}}_$$";
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
        for rgid in $(samtools view -H {input.ont_cram} | grep '^@RG' | sed 's/.*ID:\([^\\t]*\).*/\\1/'); do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done
        SR_RG_ARGS=""
        for rgid in $(samtools view -H {input.ug_cram} | grep '^@RG' | sed 's/.*ID:\([^\\t]*\).*/\\1/'); do
            SR_RG_ARGS="$SR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}"
        done

        bin/dayoa_sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            $LR_RG_ARGS -i {input.ont_cram} \
            $SR_RG_ARGS -i {input.ug_cram} \
            --interval "$scoped_diploid_bed" \
            --algo HybridStage2 \
            --model {params.model}/HybridStage2_region.model \
            --all_bed {output.bed} >> {log} 2>&1

        echo "MAPQ0 detection completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 4: MAPQ0 Slop - Extend MAPQ0 regions by 1000bp
# ---------------------------------------------------------------------------
rule sentdhuomr_mapq0_slop:
    """Extend MAPQ0 regions by 1000 bp using bedtools slop"""
    input:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_mapq0.bed",
        ref_fai=config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_mapq0.ex1000.bed",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.mapq0_slop.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{dchrm}.sentdhuomr_mapq0_slop.bench.tsv"
    threads: 2
    conda:
        "../envs/vanilla_v0.1.yaml"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=2,
        vcpu=2,
        mem_mb=50000,
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
# Rule 5: Merge BEDs - Combine selected + MAPQ0 regions
# ---------------------------------------------------------------------------
rule sentdhuomr_merge_beds:
    """Cat, sort, merge selected.bed + mapq0.ex1000.bed → merged_diff.bed"""
    input:
        selected=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/selected.bed",
        mapq0=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_mapq0.ex1000.bed",
        ref_fai=config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/merged_diff.bed",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.merge_beds.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{dchrm}.sentdhuomr_merge_beds.bench.tsv"
    threads: 2
    conda:
        "../envs/vanilla_v0.1.yaml"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=2,
        vcpu=2,
        mem_mb=50000,
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
# Rule 6: Stage 1 - Insertion detection + haplotype assembly → bwa realign
# ---------------------------------------------------------------------------
rule sentdhuomr_stage1:
    """Stage1: insertion detection + haplotype assembly piped through bwa"""
    input:
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
        diff_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/merged_diff.bed",
    output:
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_stage1.bam",
        hap_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/stage1_hap.bam",
        hap_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/stage1_hap.bed",
        hap_vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/stage1_hap.vcf",
        ins_fa=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/stage1_ins.fa",
        ins_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/stage1_ins.bed",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.stage1.log",
    threads: config['sentdhuomr']['threads']  # Full node: stage1 runs 4 concurrent processes (HAP+INS+bwa+sort)
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuomr.{dchrm}.stage1.bench.tsv"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=config['sentdhuomr']['threads'],
        vcpu=config['sentdhuomr']['threads'],
        mem_mb=config['sentdhuomr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuomr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_path,
        schrm_mod=get_dchrm_day,
        use_threads=config["sentdhuomr"]["use_threads"],
        cluster_sample=ret_sample,
        alt_samp_name=get_alt_sample_name,
    shell:
        r"""
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/scratch/sentdhuomr_s1_${{timestamp}}_$$";
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

        echo "Starting Stage 1 at $(date)" >> {log}

        scoped_diploid_bed="$TMPDIR/scoped_diploid.bed"
        python workflow/scripts/make_scoped_diploid_bed.py \
            --regions "{params.schrm_mod}" \
            --diploid-bed "{params.diploid_bed}" \
            --fai "{params.huref}.fai" \
            --output "$scoped_diploid_bed" >> {log} 2>&1

        # Build LR replace args (matches sentieon-cli RgInfo for LR inputs).
        RGIDS=$(samtools view -H {input.ont_cram} | awk '
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

        # Match sentieon-cli: remove bwt_max_mem from bwa env (noop if unset).
        unset bwt_max_mem || true

        # Match sentieon-cli hybrid_stage1(): run HAP + INS drivers sequentially
        # to temp files, then cat | bwa mem | util sort. Process substitution
        # can hide driver failures and leave truncated BAMs.

        if [ ! -s {input.diff_bed} ]; then
            echo "WARNING: merged_diff.bed is empty - no haplotype regions to process" >> {log}
            echo "Creating empty hap_bam with clean header plus empty hap_bed and hap_vcf" >> {log}
            touch {output.hap_bed} {output.hap_vcf}
            samtools view -H {input.ont_cram} \
            | grep -E '^@(HD|SQ|RG)' \
            | samtools view -bo {output.hap_bam} - 2>> {log}
            samtools index {output.hap_bam}

            echo "Starting INS driver for scoped shard at $(date)" >> {log}
            bin/dayoa_sentieon driver \
                $LR_RG_ARGS --input {input.ont_cram} \
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

            # 1. Haplotype assembly driver -> stdout to temp file, side-outputs written directly.
            echo "Starting HAP driver at $(date)" >> {log}
            bin/dayoa_sentieon driver \
                $LR_RG_ARGS --input {input.ont_cram} \
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

            # 2. Insertion detection driver -> stdout to temp file, side-outputs written directly.
            echo "Starting INS driver at $(date)" >> {log}
            bin/dayoa_sentieon driver \
                $LR_RG_ARGS --input {input.ont_cram} \
                --reference {params.huref} \
                --thread_count {params.use_threads} \
                --interval {input.diff_bed} \
                --algo HybridStage1 \
                --model {params.model}/HybridStage1_ins.model \
                --fa_file {output.ins_fa} \
                --bed_file {output.ins_bed} \
                - 2>> {log} > "$TMPDIR/ins_stdout.sam"
            echo "INS driver finished at $(date)" >> {log}

            # 3. Cat both driver outputs -> bwa mem -> util sort.
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

            # 4. Validate all expected outputs exist and are non-empty.
            sync
            for f in {output.hap_bam} {output.hap_bed} {output.hap_vcf} {output.ins_fa} {output.ins_bed} {output.bam}; do
                if [[ ! -s "$f" ]]; then
                    echo "ERROR: Missing or empty output: $f" >> {log}
                    exit 1
                fi
            done

            # 5. Index hap BAM for downstream rules.
            samtools index {output.hap_bam} >> {log} 2>&1
        fi

        # All Stage1 BAMs must be readable before downstream rules consume them.
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

        echo "Stage 1 completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 7: Stage 2 - Generate unmap/alt BAMs and refined BED
# ---------------------------------------------------------------------------
rule sentdhuomr_stage2:
    """Stage2: generate unmap BAM, alt BAM, and refined BED"""
    input:
        stage1_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_stage1.bam",
        hap_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/stage1_hap.bam",
        hap_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/stage1_hap.bed",
    output:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
        unmap_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_stage2_unmap.bam",
        alt_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_stage2_alt.bam",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.stage2.log",
    threads: config['sentdhuomr']['threads_medium']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuomr.{dchrm}.stage2.bench.tsv"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=config['sentdhuomr']['threads_medium'],
        vcpu=config['sentdhuomr']['threads_medium'],
        mem_mb=config['sentdhuomr']['mem_mb_medium'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuomr"]["dna_scope_snv_model"],
        use_threads=config["sentdhuomr"]["use_threads_medium"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/scratch/sentdhuomr_s2_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        echo "Starting Stage 2 at $(date)" >> {log}

        if [ ! -s {input.hap_bed} ]; then
            echo "WARNING: stage1_hap.bed is empty - no target haplotypes for Stage 2; creating empty Stage 2 outputs" >> {log}
            : > {output.bed}
            samtools view -H {input.stage1_bam} \
            | grep -E '^@(HD|SQ|RG)' \
            | samtools view -bo {output.unmap_bam} - 2>> {log}
            samtools view -H {input.stage1_bam} \
            | grep -E '^@(HD|SQ|RG)' \
            | samtools view -bo {output.alt_bam} - 2>> {log}
            samtools quickcheck {output.unmap_bam} {output.alt_bam} >> {log} 2>&1 || \
                (echo "ERROR: empty Stage2 BAM failed integrity check" >> {log} && exit 1)
            echo "Stage 2 completed with empty target haplotypes at $(date)" >> {log}
            exit 0
        fi

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
# Rule 8: Stage 3 - Re-alignment with stage2 outputs
# ---------------------------------------------------------------------------
rule sentdhuomr_stage3:
    """Stage3: HybridStage3 on all reads + stage2 BAMs → sorted BAM"""
    input:
        ug_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
        unmap_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_stage2_unmap.bam",
        alt_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_stage2_alt.bam",
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
    output:
        bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_stage3.bam",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.stage3.log",
    threads: config['sentdhuomr']['threads']  # Full node: stage3 pipes driver → util sort (2 concurrent processes)
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuomr.{dchrm}.stage3.bench.tsv"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=config['sentdhuomr']['threads'],
        vcpu=config['sentdhuomr']['threads'],
        mem_mb=config['sentdhuomr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuomr"]["dna_scope_snv_model"],
        use_threads=config["sentdhuomr"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/scratch/sentdhuomr_s3_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        echo "Starting Stage 3 at $(date)" >> {log}

        if [ ! -s {input.bed} ]; then
            echo "WARNING: hybrid_stage2.bed is empty - no Stage 3 realignment regions; creating empty BAM" >> {log}
            (
                samtools view -H {input.ont_cram} | awk -v sample="{params.cluster_sample}" '
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
                samtools view -H {input.ug_cram} | awk -v sample="{params.cluster_sample}" '
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
        LR_RG_ARGS=""
        for rgid in $(samtools view -H {input.ont_cram} | grep '^@RG' | sed 's/.*ID:\([^\\t]*\).*/\\1/'); do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done
        SR_RG_ARGS=""
        for rgid in $(samtools view -H {input.ug_cram} | grep '^@RG' | sed 's/.*ID:\([^\\t]*\).*/\\1/'); do
            SR_RG_ARGS="$SR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}"
        done

        bin/dayoa_sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            $LR_RG_ARGS -i {input.ont_cram} \
            $SR_RG_ARGS -i {input.ug_cram} \
            $LR_RG_ARGS -i {input.unmap_bam} \
            $LR_RG_ARGS -i {input.alt_bam} \
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
# Rule 9: Pass 2 - Second-pass variant calling on refined regions
# ---------------------------------------------------------------------------
rule sentdhuomr_pass2:
    """Second-pass variant calling on stage3 BAM + ONT reads"""
    input:
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
        stage3_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_stage3.bam",
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
        initial_vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/initial.vcf.gz",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.pass2.log",
    threads: config['sentdhuomr']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuomr.{dchrm}.pass2.bench.tsv"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=config['sentdhuomr']['threads'],
        vcpu=config['sentdhuomr']['threads'],
        mem_mb=config['sentdhuomr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuomr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_interval_arg,  # Use --interval for bin/dayoa_sentieon driver
        use_threads=config["sentdhuomr"]["use_threads"],
        cluster_sample=ret_sample,
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/scratch/sentdhuomr_p2_${{timestamp}}_$$";
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
        # This also unifies SM tags across ont_cram and stage3_bam so sentieon
        # driver sees a single sample (stage3_bam inherits LR RGs from ONT input).
        LR_RG_ARGS=""
        for rgid in $(samtools view -H {input.ont_cram} | grep '^@RG' | sed 's/.*ID:\([^\\t]*\).*/\\1/'); do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done

        bin/dayoa_sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            $LR_RG_ARGS -i {input.ont_cram} \
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
# Rule 10: Subset - Subset pass-1 VCF to complement of stage2 regions
# ---------------------------------------------------------------------------
rule sentdhuomr_subset:
    """Subset pass-1 VCF to complement of stage2 regions"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/initial.vcf.gz",
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/mix_subset.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/mix_subset.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.subset.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{dchrm}.sentdhuomr_subset.bench.tsv"
    threads: config['sentdhuomr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=config['sentdhuomr']['threads_light'],
        vcpu=config['sentdhuomr']['threads_light'],
        mem_mb=config['sentdhuomr']['mem_mb_light'],
    params:
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/

        echo "Subsetting pass-1 VCF at $(date)" >> {log}

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
# Rule 11: Concat Pass - Concatenate subset + pass2 VCFs
# ---------------------------------------------------------------------------
rule sentdhuomr_concat_pass:
    """Concatenate subset + pass2 VCFs"""
    input:
        subset=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/mix_subset.vcf.gz",
        subset_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/mix_subset.vcf.gz.tbi",
        pass2=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz",
        pass2_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz.tbi",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/combined_tmp.vcf.gz",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.concat_pass.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{dchrm}.sentdhuomr_concat_pass.bench.tsv"
    threads: config['sentdhuomr']['threads_light']
    conda:
        "../envs/vanilla_v0.1.yaml"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=config['sentdhuomr']['threads_light'],
        vcpu=config['sentdhuomr']['threads_light'],
        mem_mb=config['sentdhuomr']['mem_mb_light'],
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
# Rule 12: Annotation - Hybrid-specific annotations
# ---------------------------------------------------------------------------
rule sentdhuomr_anno:
    """Annotate VCF with hybrid-specific annotations"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/combined_tmp.vcf.gz",
        hap_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/stage1_hap.bed",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/combined_tmp_anno.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/combined_tmp_anno.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.anno.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.{dchrm}.sentdhuomr_anno.bench.tsv"
    threads: config['sentdhuomr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=config['sentdhuomr']['threads_light'],
        vcpu=config['sentdhuomr']['threads_light'],
        mem_mb=config['sentdhuomr']['mem_mb_light'],
    params:
        use_threads=config["sentdhuomr"]["use_threads_light"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/

        echo "Starting hybrid annotation at $(date)" >> {log}

        : "${{CONDA_PREFIX:?CONDA_PREFIX is required for sentdhuomr_anno}}"
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
# Rule 13: Transfer - Annotation transfer from population VCF (per-chromosome sharded)
# ---------------------------------------------------------------------------
# The transfer step is sharded per-chromosome for parallel execution.
# Input comes from the whole-genome anno VCF (dchrm="1-24"), and each shard
# processes a single chromosome using bcftools merge --regions.
# A gather rule (sentdhuomr_transfer_merge) concatenates shards before model_apply.
# ---------------------------------------------------------------------------
rule sentdhuomr_transfer:
    """Transfer annotations from population VCF using bcftools merge + trimalt pipe (per-chromosome shard)"""
    input:
        anno_vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/combined_tmp_anno.vcf.gz",
        anno_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/combined_tmp_anno.vcf.gz.tbi",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/transfer_shards/transfer.{tchrm}.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/transfer_shards/transfer.{tchrm}.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR),
        tchrm="|".join(SENTDHUOMR_CHRMS_TRANSFER),
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.transfer.{tchrm}.log",
    threads: config['sentdhuomr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuomr.{dchrm}.transfer.{tchrm}.bench.tsv"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme,i192",
        threads=config['sentdhuomr']['threads_light'],
        vcpu=config['sentdhuomr']['threads_light'],
        mem_mb=config['sentdhuomr']['mem_mb_light'],
    params:
        pop_vcf=config["supporting_files"]["files"]["popvcf"]["name"],
        cluster_sample=ret_sample,
        regions=lambda wildcards: get_dchrm_day(type('obj', (object,), {'dchrm': wildcards.tchrm})()),
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/

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

        : "${{CONDA_PREFIX:?CONDA_PREFIX is required for sentdhuomr_transfer_anno_shards}}"
        TRIM_SCRIPT=$("$CONDA_PREFIX/bin/python" -c "from importlib.resources import files; print(files('sentieon_cli.scripts').joinpath('trimalt.py'))")

        echo "Transferring annotations from pop_vcf: {params.pop_vcf} for regions: {params.regions}" >> {log}

        bcftools merge --threads {threads} --no-version --regions-overlap pos -m all \
            --regions {params.regions} \
            "$TMPDIR/anno_reheadered.{wildcards.tchrm}.vcf.gz" {params.pop_vcf} 2>> {log} | \
        bin/dayoa_sentieon pyexec "$TRIM_SCRIPT" 2>> {log} | \
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
# Rule 13b: Transfer Merge - Gather per-chromosome transfer shards
# ---------------------------------------------------------------------------
rule sentdhuomr_transfer_merge:
    """Concatenate per-chromosome transfer shards into single VCF for model_apply"""
    input:
        shards=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhuomr/vcfs/{{dchrm}}/tmp/transfer_shards/transfer.{tchrm}.vcf.gz",
                tchrm=SENTDHUOMR_CHRMS_TRANSFER,
            ),
            key=lambda x: int(x.rsplit("transfer.", 1)[1].split(".vcf.gz")[0])
            if x.rsplit("transfer.", 1)[1].split(".vcf.gz")[0].isdigit()
            else 99,
        ),
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/combined_tmp_transfer.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/combined_tmp_transfer.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.transfer_merge.log",
    threads: config['sentdhuomr']['threads_light']
    conda:
        "../envs/vanilla_v0.1.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuomr.{dchrm}.transfer_merge.bench.tsv"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme,i192",
        threads=config['sentdhuomr']['threads_light'],
        vcpu=config['sentdhuomr']['threads_light'],
        mem_mb=config['sentdhuomr']['mem_mb_light'],
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
# Rule 14: Model Apply - DNAModelApply ML filtering
# ---------------------------------------------------------------------------
rule sentdhuomr_model_apply:
    """Apply ML model to called variants"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/combined_tmp_transfer.vcf.gz",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/combined_apply.vcf.gz",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.model_apply.log",
    threads: config['sentdhuomr']['threads_medium']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuomr.{dchrm}.model_apply.bench.tsv"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=config['sentdhuomr']['threads_medium'],
        vcpu=config['sentdhuomr']['threads_medium'],
        mem_mb=config['sentdhuomr']['mem_mb_medium'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuomr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_path,
        schrm_mod=get_dchrm_day,
        use_threads=config["sentdhuomr"]["use_threads_medium"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/scratch/sentdhuomr_ma_${{timestamp}}_$$";
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
# Rule 15: Final Norm - bcftools normalization → output VCF
# ---------------------------------------------------------------------------
rule sentdhuomr_final_norm:
    """Trim, normalize, and produce final output VCF"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/tmp/combined_apply.vcf.gz",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhuomr.{dchrm}.snv.sort.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhuomr.{dchrm}.snv.sort.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.{dchrm}.final_norm.log",
    threads: config['sentdhuomr']['threads_light']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuomr.{dchrm}.final_norm.bench.tsv"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=config['sentdhuomr']['threads_light'],
        vcpu=config['sentdhuomr']['threads_light'],
        mem_mb=config['sentdhuomr']['mem_mb_light'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/

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
    sentdhuomr_concat_fofn,


rule sentdhuomr_concat_fofn:
    """Build file-of-filenames for chromosome chunks"""
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhuomr/vcfs/{ochm}/{{sample}}.{{alnr}}.{{ddup}}.sentdhuomr.{ochm}.snv.sort.vcf.gz.tbi",
                ochm=SENTDHUOMR_CHRMS,
            ),
            key=lambda x: float(
                str(x.replace("~", ".").replace(":", "."))
                .split("vcfs/")[1]
                .split("/")[0]
                .split("-")[0]
            ),
        ),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    priority: 44
    output:
        fin_fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/{sample}.{alnr}.{ddup}.sentdhuomr.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/{sample}.{alnr}.{ddup}.sentdhuomr.snv.concat.vcf.gz.fofn.tmp",
    threads: 1
    resources:
        threads=1
    params:
        fn_stub="{sample}.{alnr}.{ddup}.sentdhuomr."
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuomr.concat.fofn.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.sentdhuomr.concat.fofn.log",
    shell:
        """
        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\\.tbi$//g'; );
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.sentdhuomr. {output.fin_fofn}) >> {log} 2>&1;
        """


rule sentdhuomr_concat_index_chunks:
    """Concatenate chromosome chunks and index final VCF"""
    input:
        fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/{sample}.{alnr}.{ddup}.sentdhuomr.snv.concat.vcf.gz.fofn",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    output:
        vcfgz=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/{sample}.{alnr}.{ddup}.sentdhuomr.snv.sort.vcf.gz",
        vcfgztemp=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/{sample}.{alnr}.{ddup}.sentdhuomr.snv.sort.temp.vcf.gz",
        vcfgztbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/{sample}.{alnr}.{ddup}.sentdhuomr.snv.sort.vcf.gz.tbi",
    threads: config['sentdhuomr']['threads_light']
    resources:
        vcpu=config['sentdhuomr']['threads_light'],
        threads=config['sentdhuomr']['threads_light'],
        partition="i192hugenvme,i192nvme,i384nvme",
        mem_mb=config['sentdhuomr']['mem_mb_light'],
    priority: 47
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuomr.merge.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/log/{sample}.{alnr}.{ddup}.sentdhuomr.snv.merge.sort.gathered.log",
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
    clear_combined_sentdhuomr_vcf,


rule clear_combined_sentdhuomr_vcf:  # TARGET: clear combined sentdhuomr vcf so chunks can be re-evaluated if needed.
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/{sample}.{alnr}.{ddup}.sentdhuomr.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=ALIGNERS_DHUOMR,
            ddup=DDUP,
        ),
    log:
        MDIR + "logs/clear_combined_sentdhuomr_vcf.log"
    benchmark:
        "logs/benchmarks/clear_combined_sentdhuomr_vcf.bench.tsv"
    threads: 2
    priority: 42
    shell:
        """
        rm {input}*  1> /dev/null  2> /dev/null ) || echo 'file not found for deletion: {input}';
        """


localrules:
    produce_sentdhuomr_vcf,


rule produce_sentdhuomr_vcf:  # TARGET: sentieon dnascope hybrid ultima+ont modular vcf
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/{sample}.{alnr}.{ddup}.sentdhuomr.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS_DHUOMR,
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdhuomr",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdhuomr.log",
    benchmark:
        "logs/benchmarks/produce_sentdhuomr_vcf.bench.tsv"
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """


# ===========================================================================
# SV CALLING: LongReadSV structural variant calling (whole-genome, not chunked)
# ===========================================================================

rule sentdhuomr_call_svs:
    """Call structural variants using LongReadSV on ONT long reads"""
    input:
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
        ont_crai=MDIR + "{sample}/align/ont/{sample}.cram.crai",
    output:
        sv_vcf=MDIR + "{sample}/align/{alnr}/{ddup}/sv/sentdhuomr/{sample}.{alnr}.{ddup}.sentdhuomr.sv.vcf.gz",
        sv_tbi=MDIR + "{sample}/align/{alnr}/{ddup}/sv/sentdhuomr/{sample}.{alnr}.{ddup}.sentdhuomr.sv.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/sv/sentdhuomr/log/{sample}.{alnr}.{ddup}.sentdhuomr.sv.log",
    threads: config['sentdhuomr']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuomr.sv.bench.tsv"
    resources:
        partition="i192hugenvme,i192nvme,i384nvme",
        threads=config['sentdhuomr']['threads'],
        vcpu=config['sentdhuomr']['threads'],
        mem_mb=config['sentdhuomr']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuomr"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_interval_arg,
        use_threads=config["sentdhuomr"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/scratch/sentdhuomr_sv_${{timestamp}}_$$";
        export SENTIEON_TMPDIR="$TMPDIR";
        mkdir -p "$TMPDIR";
        trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT;

        mkdir -p $(dirname {log})
        echo "Starting LongReadSV at $(date)" >> {log}

        # Build LR readgroup replacement args: LR reads get LR:1 tag
        LR_RG_ARGS=""
        for rgid in $(samtools view -H {input.ont_cram} | grep '^@RG' | sed 's/.*ID:\([^\t]*\).*/\1/'); do
            LR_RG_ARGS="$LR_RG_ARGS --replace_rg ${{rgid}}=ID:${{rgid}}\\tSM:{params.cluster_sample}\\tLR:1"
        done

        bin/dayoa_sentieon driver -r {params.huref} -t {params.use_threads} \
            --temp_dir $TMPDIR \
            $LR_RG_ARGS -i {input.ont_cram} \
            {params.diploid_bed} \
            --algo LongReadSV \
            --model {params.model}/longreadsv.model \
            {output.sv_vcf} >> {log} 2>&1

        bcftools index -t -f {output.sv_vcf} >> {log} 2>&1

        echo "LongReadSV completed at $(date)" >> {log}
        """


localrules:
    produce_sentdhuomr_sv,


rule produce_sentdhuomr_sv:  # TARGET: sentieon longreadsv hybrid ultima+ont modular sv vcf
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/sv/sentdhuomr/{sample}.{alnr}.{ddup}.sentdhuomr.sv.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS_DHUOMR,
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdhuomr.sv",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdhuomr.sv.log",
    benchmark:
        "logs/benchmarks/produce_sentdhuomr_sv.bench.tsv"
    shell:
        """( touch {output} ;
        ls {output} ) >> {log} 2>&1;
        """


localrules:
    prep_sentdhuomr_chunkdirs,


rule prep_sentdhuomr_chunkdirs:
    """Prepare chunk directories for modular hybrid workflow"""
    input:
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        ug_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        ug_crai=MDIR + "{sample}/align/{alnr}/{sample}.cram.crai",
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
        ont_crai=MDIR + "{sample}/align/ont/{sample}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhuomr/vcfs/{dchrm}/{{sample}}.ready",
            dchrm=SENTDHUOMR_CHRMS
        ),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOMR)
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuomr/logs/{sample}.{alnr}.{ddup}.chunkdirs.log",
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.prep_sentdhuomr_chunkdirs.bench.tsv"
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
