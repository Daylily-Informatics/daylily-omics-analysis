"""
Modular Sentieon DNAscope Hybrid Workflow: Ultima + ONT

This file decomposes the monolithic sentieon-cli dnascope-hybrid call into
discrete Snakemake rules for better observability, restartability, and debugging.

Caller code: sentdhuom (Sentieon DNAscope Hybrid Ultima+ONT Modular)

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
- Uses ALIGNERS_DHUOM = ["ug"] for wildcard constraints
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
ALIGNERS_DHUOM = ["ug"]


# ---------------------------------------------------------------------------
# Rule 1: Pass 1 - Initial DNAscope on combined Ultima + ONT reads
# ---------------------------------------------------------------------------
rule sentdhuom_pass1:
    """First-pass DNAscope variant calling on combined Ultima + ONT reads"""
    input:
        ug_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        ug_crai=MDIR + "{sample}/align/{alnr}/{sample}.cram.crai",
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
        ont_crai=MDIR + "{sample}/align/ont/{sample}.cram.crai",
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        d=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/{sample}.ready",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/initial.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/initial.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.pass1.log",
    threads: config['sentdhuo']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    priority: 45
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuom.{dchrm}.pass1.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuo"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_interval_arg,  # Use --interval for sentieon driver
        use_threads=config["sentdhuo"]["use_threads"],
        cluster_sample=ret_sample,
        alt_samp_name=get_alt_sample_name,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhuom_p1_${{timestamp}}_$$";
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
        trap "rm -rf \\"$TMPDIR\\" || echo 'TMPDIR rm fails' >> {log} 2>&1" EXIT;

        echo "Starting Pass 1 DNAscope (Ultima+ONT) at $(date)" >> {log}

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

        sentieon driver -r {params.huref} -t {params.use_threads} \
            -i {input.ont_cram} -i {input.ug_cram} \
            {params.diploid_bed} \
            --algo DNAscope \
            --model {params.model}/hybrid.model \
            --pcr_indel_model none \
            {output.vcf} >> {log} 2>&1

        # Create VCF index with tabix (required for hybrid_select)
        echo "Creating VCF index with tabix" >> {log}
        tabix -f -p vcf {output.vcf} >> {log} 2>&1

        echo "Pass 1 completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 2: Hybrid Select - Region selection from pass-1 VCF
# ---------------------------------------------------------------------------
rule sentdhuom_hybrid_select:
    """Select regions for hybrid re-analysis based on pass-1 variants.

    This replicates the sentieon-cli hybrid_select pipeline:
    1. hybrid_select.py filters VCF based on long/short read confidence
    2. bcftools view filters for PASS variants
    3. bcftools query converts to BED format
    4. bedtools slop adds 1000bp padding
    """
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/initial.vcf.gz",
        ref_fai=config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        bed=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/selected.bed"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.hybrid_select.log",
    threads: config['sentdhuo']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuom.{dchrm}.hybrid_select.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
    params:
        use_threads=config["sentdhuo"]["use_threads"],
        cluster_sample=ret_sample,
        slop_size=1000,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting hybrid_select pipeline at $(date)" >> {log}

        # Find hybrid_select.py script
        HYBRID_SELECT=$(python -c "from importlib_resources import files; print(files('sentieon_cli.scripts').joinpath('hybrid_select.py'))")

        # Pipeline: hybrid_select.py -> bcftools view -> bcftools query -> bedtools slop
        # This replicates sentieon-cli's cmd_pyexec_hybrid_select() function
        sentieon pyexec "$HYBRID_SELECT" \
            -v {input.vcf} \
            -t {params.use_threads} \
            - 2>> {log} \
        | bcftools view -f 'PASS,.' - 2>> {log} \
        | bcftools query -f '%CHROM\t%POS0\t%END\n' - 2>> {log} \
        | bedtools slop -b {params.slop_size} -g {input.ref_fai} -i - \
        > {output.bed} 2>> {log}

        echo "hybrid_select pipeline completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 3: MAPQ0 Detection - Find low-quality mapping regions
# ---------------------------------------------------------------------------
rule sentdhuom_mapq0_bed:
    """Detect MAPQ0 regions with HybridStage2 region model"""
    input:
        ug_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
    output:
        bed=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_mapq0.bed"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.mapq0_bed.log",
    threads: config['sentdhuo']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuom.{dchrm}.mapq0_bed.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuo"]["dna_scope_snv_model"],
        use_threads=config["sentdhuo"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting MAPQ0 detection at $(date)" >> {log}

        sentieon driver -r {params.huref} -t {params.use_threads} \
            -i {input.ont_cram} -i {input.ug_cram} \
            --algo HybridStage2 \
            --model {params.model}/HybridStage2_region.model \
            --all_bed {output.bed} >> {log} 2>&1

        echo "MAPQ0 detection completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 4: MAPQ0 Slop - Extend MAPQ0 regions by 1000bp
# ---------------------------------------------------------------------------
rule sentdhuom_mapq0_slop:
    """Extend MAPQ0 regions by 1000 bp using bedtools slop"""
    input:
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_mapq0.bed",
        ref_fai=config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        bed=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_mapq0.ex1000.bed"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.mapq0_slop.log",
    threads: 2
    conda:
        "../envs/vanilla_v0.1.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
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
rule sentdhuom_merge_beds:
    """Cat, sort, merge selected.bed + mapq0.ex1000.bed → merged_diff.bed"""
    input:
        selected=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/selected.bed",
        mapq0=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_mapq0.ex1000.bed",
        ref_fai=config["supporting_files"]["files"]["huref"]["fasta"]["name"] + ".fai",
    output:
        bed=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/merged_diff.bed"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.merge_beds.log",
    threads: 2
    conda:
        "../envs/vanilla_v0.1.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
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
rule sentdhuom_stage1:
    """Stage1: insertion detection + haplotype assembly piped through bwa"""
    input:
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
        diff_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/merged_diff.bed",
    output:
        bam=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_stage1.bam"),
        hap_bam=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/stage1_hap.bam"),
        hap_bed=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/stage1_hap.bed"),
        hap_vcf=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/stage1_hap.vcf"),
        ins_fa=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/stage1_ins.fa"),
        ins_bed=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/stage1_ins.bed"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.stage1.log",
    threads: config['sentdhuo']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuom.{dchrm}.stage1.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuo"]["dna_scope_snv_model"],
        use_threads=config["sentdhuo"]["use_threads"],
        cluster_sample=ret_sample,
        alt_samp_name=get_alt_sample_name,
    shell:
        r"""
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        timestamp=$(date +%Y%m%d%H%M%S);
        export TMPDIR="/dev/shm/sentdhuom_s1_${{timestamp}}_$$";
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
        trap "rm -rf \\"$TMPDIR\\" || echo 'TMPDIR rm fails' >> {log} 2>&1" EXIT;

        echo "Starting Stage 1 at $(date)" >> {log}

        # Get sample ID for read group
        cram_sid=$(samtools view -H {input.ont_cram} | grep '^@RG' | tr '\t' '\n' | grep '^SM:' | cut -f2 -d':' | sort -u | head -1)

        # Check if merged_diff.bed is empty - if so, skip HAP_CMD and create empty outputs
        if [ ! -s {input.diff_bed} ]; then
            echo "WARNING: merged_diff.bed is empty - no haplotype regions to process" >> {log}
            echo "Creating empty hap_bam (with minimal header), hap_bed, hap_vcf files" >> {log}
            # Create empty BED and VCF
            touch {output.hap_bed} {output.hap_vcf}
            # Create proper empty BAM with minimal header (only @HD and @SQ lines, no @PG/@RG)
            # This avoids issues with PP chain references to non-existent programs
            samtools view -H {input.ont_cram} | grep -E '^@(HD|SQ)' | samtools view -bo {output.hap_bam} -
            samtools index {output.hap_bam}

            # Only run insertion detection (no interval restriction)
            INS_CMD="sentieon driver -r {params.huref} -t {params.use_threads} \
                -i {input.ont_cram} \
                --algo HybridStage1 \
                --model {params.model}/HybridStage1_ins.model \
                --fa_file {output.ins_fa} \
                --bed_file {output.ins_bed} \
                -"

            $INS_CMD 2>> {log} | \
            sentieon bwa mem \
                -R "@RG\tID:hybrid-${{cram_sid}}\tSM:${{cram_sid}}" \
                -t {params.use_threads} \
                -x {params.model}/HybridStage1_bwa.model \
                {params.huref} - 2>> {log} | \
            sentieon util sort \
                -i - -t {params.use_threads} \
                -o {output.bam} --sam2bam >> {log} 2>&1
        else
            echo "Processing $(wc -l < {input.diff_bed}) regions from merged_diff.bed" >> {log}

            # Haplotype assembly driver command
            HAP_CMD="sentieon driver -r {params.huref} -t {params.use_threads} \
                -i {input.ont_cram} --interval {input.diff_bed} \
                --algo HybridStage1 \
                --model {params.model}/HybridStage1.model \
                --hap_bam {output.hap_bam} \
                --hap_bed {output.hap_bed} \
                --hap_vcf {output.hap_vcf} \
                -"

            # Insertion detection driver command
            INS_CMD="sentieon driver -r {params.huref} -t {params.use_threads} \
                -i {input.ont_cram} \
                --algo HybridStage1 \
                --model {params.model}/HybridStage1_ins.model \
                --fa_file {output.ins_fa} \
                --bed_file {output.ins_bed} \
                -"

            # Cat both FASTQ streams → bwa mem → util sort
            cat <($HAP_CMD 2>> {log}) <($INS_CMD 2>> {log}) | \
            sentieon bwa mem \
                -R "@RG\tID:hybrid-${{cram_sid}}\tSM:${{cram_sid}}" \
                -t {params.use_threads} \
                -x {params.model}/HybridStage1_bwa.model \
                {params.huref} - 2>> {log} | \
            sentieon util sort \
                -i - -t {params.use_threads} \
                -o {output.bam} --sam2bam >> {log} 2>&1
        fi

        echo "Stage 1 completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 7: Stage 2 - Generate unmap/alt BAMs and refined BED
# ---------------------------------------------------------------------------
rule sentdhuom_stage2:
    """Stage2: generate unmap BAM, alt BAM, and refined BED"""
    input:
        stage1_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_stage1.bam",
        hap_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/stage1_hap.bam",
        hap_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/stage1_hap.bed",
    output:
        bed=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_stage2.bed"),
        unmap_bam=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_stage2_unmap.bam"),
        alt_bam=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_stage2_alt.bam"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.stage2.log",
    threads: config['sentdhuo']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuom.{dchrm}.stage2.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuo"]["dna_scope_snv_model"],
        use_threads=config["sentdhuo"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting Stage 2 at $(date)" >> {log}

        sentieon driver -r {params.huref} -t {params.use_threads} \
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
rule sentdhuom_stage3:
    """Stage3: HybridStage3 on all reads + stage2 BAMs → sorted BAM"""
    input:
        ug_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
        unmap_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_stage2_unmap.bam",
        alt_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_stage2_alt.bam",
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
    output:
        bam=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_stage3.bam"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.stage3.log",
    threads: config['sentdhuo']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuom.{dchrm}.stage3.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuo"]["dna_scope_snv_model"],
        use_threads=config["sentdhuo"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting Stage 3 at $(date)" >> {log}

        sentieon driver -r {params.huref} -t {params.use_threads} \
            -i {input.ont_cram} -i {input.ug_cram} \
            -i {input.unmap_bam} -i {input.alt_bam} \
            --interval {input.bed} \
            --algo HybridStage3 \
            --model {params.model}/HybridStage3.model \
            - 2>> {log} | \
        sentieon util sort \
            -i - -t {params.use_threads} \
            -o {output.bam} >> {log} 2>&1

        echo "Stage 3 completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 9: Pass 2 - Second-pass variant calling on refined regions
# ---------------------------------------------------------------------------
rule sentdhuom_pass2:
    """Second-pass variant calling on stage3 BAM + ONT reads"""
    input:
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
        stage3_bam=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_stage3.bam",
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
    output:
        vcf=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz"),
        tbi=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz.tbi"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.pass2.log",
    threads: config['sentdhuo']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuom.{dchrm}.pass2.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuo"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_interval_arg,  # Use --interval for sentieon driver
        use_threads=config["sentdhuo"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting Pass 2 DNAscope at $(date)" >> {log}

        sentieon driver -r {params.huref} -t {params.use_threads} \
            -i {input.ont_cram} -i {input.stage3_bam} \
            --interval {input.bed} \
            {params.diploid_bed} \
            --algo DNAscope \
            --model {params.model}/hybrid.model \
            --pcr_indel_model none \
            {output.vcf} >> {log} 2>&1

        echo "Pass 2 completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 10: Subset - Subset pass-1 VCF to complement of stage2 regions
# ---------------------------------------------------------------------------
rule sentdhuom_subset:
    """Subset pass-1 VCF to complement of stage2 regions"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/initial.vcf.gz",
        bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_stage2.bed",
    output:
        vcf=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/mix_subset.vcf.gz"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.subset.log",
    threads: 4
    conda:
        "../envs/sentieon_v0.3.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
    params:
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Subsetting pass-1 VCF at $(date)" >> {log}

        if [ -s {input.bed} ]; then
            bcftools view -T ^{input.bed} {input.vcf} 2>> {log} | \
            sentieon util vcfconvert - {output.vcf} >> {log} 2>&1
        else
            sentieon util vcfconvert {input.vcf} {output.vcf} >> {log} 2>&1
        fi

        echo "Subset completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 11: Concat Pass - Concatenate subset + pass2 VCFs
# ---------------------------------------------------------------------------
rule sentdhuom_concat_pass:
    """Concatenate subset + pass2 VCFs"""
    input:
        subset=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/mix_subset.vcf.gz",
        pass2=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/hybrid_pass2.vcf.gz",
    output:
        vcf=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/combined_tmp.vcf.gz"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.concat_pass.log",
    threads: 4
    conda:
        "../envs/vanilla_v0.1.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
    params:
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        echo "Concatenating subset + pass2 VCFs at $(date)" >> {log}
        bcftools concat -W=tbi --output {output.vcf} -aD {input.subset} {input.pass2} >> {log} 2>&1
        echo "Concat completed at $(date)" >> {log}
        """



# ---------------------------------------------------------------------------
# Rule 12: Annotation - Hybrid-specific annotations
# ---------------------------------------------------------------------------
rule sentdhuom_anno:
    """Annotate VCF with hybrid-specific annotations"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/combined_tmp.vcf.gz",
        hap_bed=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/stage1_hap.bed",
    output:
        vcf=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/combined_tmp_anno.vcf.gz"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.anno.log",
    threads: config['sentdhuo']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
    params:
        use_threads=config["sentdhuo"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting hybrid annotation at $(date)" >> {log}

        HYBRID_ANNO=$(python -c "from importlib_resources import files; print(files('sentieon_cli.scripts').joinpath('hybrid_anno.py'))")

        sentieon pyexec "$HYBRID_ANNO" \
            -v {input.vcf} \
            -b {input.hap_bed} \
            -t {params.use_threads} \
            -o {output.vcf} >> {log} 2>&1

        echo "Annotation completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 13: Transfer - Annotation transfer from population VCF (if pop_vcf set)
# ---------------------------------------------------------------------------
rule sentdhuom_transfer:
    """Transfer annotations from population VCF using bcftools merge"""
    input:
        anno_vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/combined_tmp_anno.vcf.gz",
    output:
        vcf=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/combined_tmp_transfer.vcf.gz"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.transfer.log",
    threads: config['sentdhuo']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
    params:
        pop_vcf=config["sentdhuo"]["pop_vcf"],
        use_threads=config["sentdhuo"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting annotation transfer at $(date)" >> {log}

        if [ -n "{params.pop_vcf}" ] && [ -f "{params.pop_vcf}" ]; then
            TRIM_SCRIPT=$(python -c "from importlib_resources import files; print(files('sentieon_cli.scripts').joinpath('trimalt.py'))")

            bcftools merge --no-version --regions-overlap pos -m all \
                {input.anno_vcf} {params.pop_vcf} 2>> {log} | \
            sentieon pyexec "$TRIM_SCRIPT" 2>> {log} | \
            bcftools concat -W=tbi --output {output.vcf} \
                --no-version --threads {params.use_threads} -aD - >> {log} 2>&1
        else
            echo "No pop_vcf configured, copying anno VCF directly" >> {log}
            cp {input.anno_vcf} {output.vcf}
            bcftools index -t {output.vcf} >> {log} 2>&1
        fi

        echo "Transfer completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 14: Model Apply - DNAModelApply ML filtering
# ---------------------------------------------------------------------------
rule sentdhuom_model_apply:
    """Apply ML model to called variants"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/combined_tmp_transfer.vcf.gz",
    output:
        vcf=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/combined_apply.vcf.gz"),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.model_apply.log",
    threads: config['sentdhuo']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuom.{dchrm}.model_apply.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        model=config["sentdhuo"]["dna_scope_snv_model"],
        diploid_bed=get_diploid_bed_interval_arg,  # Use --interval for sentieon driver
        use_threads=config["sentdhuo"]["use_threads"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting DNAModelApply at $(date)" >> {log}

        sentieon driver -r {params.huref} -t {params.use_threads} \
            {params.diploid_bed} \
            --algo DNAModelApply \
            --model {params.model}/hybrid.model \
            --vcf {input.vcf} \
            {output.vcf} >> {log} 2>&1

        echo "Model apply completed at $(date)" >> {log}
        """


# ---------------------------------------------------------------------------
# Rule 15: Final Norm - bcftools normalization → output VCF
# ---------------------------------------------------------------------------
rule sentdhuom_final_norm:
    """Trim, normalize, and produce final output VCF"""
    input:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/tmp/combined_apply.vcf.gz",
    output:
        vcf=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhuom.{dchrm}.snv.sort.vcf.gz",
        tbi=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentdhuom.{dchrm}.snv.sort.vcf.gz.tbi",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.{dchrm}.final_norm.log",
    threads: config['sentdhuo']['threads']
    conda:
        "../envs/sentieon_v0.3.yaml"
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuom.{dchrm}.final_norm.bench.tsv"
    resources:
        partition="i192mem,i192bigmem",
        threads=192,
        vcpu=192,
        mem_mb=config['sentdhuo']['mem_mb'],
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    shell:
        """
        set -euo pipefail
        export PATH=$PATH:/fsx/data/cached_envs/sentieon-genomics-202503.02/bin/

        echo "Starting final normalization at $(date)" >> {log}

        bcftools view -a -e 'GT="0/0"' {input.vcf} 2>> {log} | \
        bcftools norm -f {params.huref} 2>> {log} | \
        sentieon util vcfconvert - {output.vcf} >> {log} 2>&1

        echo "Final normalization completed at $(date)" >> {log}
        """



# ===========================================================================
# DOWNSTREAM RULES: FOFN, Concat, Target rules (similar to original)
# ===========================================================================

localrules:
    sentdhuom_concat_fofn,


rule sentdhuom_concat_fofn:
    """Build file-of-filenames for chromosome chunks"""
    input:
        chunk_tbi=sorted(
            expand(
                MDIR
                + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhuom/vcfs/{ochm}/{{sample}}.{{alnr}}.{{ddup}}.sentdhuom.{ochm}.snv.sort.vcf.gz.tbi",
                ochm=SENTDHUO_CHRMS,
            ),
            key=lambda x: float(
                str(x.replace("~", ".").replace(":", "."))
                .split("vcfs/")[1]
                .split("/")[0]
                .split("-")[0]
            ),
        ),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    priority: 44
    output:
        fin_fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/{sample}.{alnr}.{ddup}.sentdhuom.snv.concat.vcf.gz.fofn",
        tmp_fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/{sample}.{alnr}.{ddup}.sentdhuom.snv.concat.vcf.gz.fofn.tmp",
    threads: 1
    resources:
        threads=1
    params:
        fn_stub="{sample}.{alnr}.{ddup}.sentdhuom."
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuom.concat.fofn.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.sentdhuom.concat.fofn.log",
    shell:
        """
        for i in {input.chunk_tbi}; do
            ii=$(echo $i | perl -pe 's/\\.tbi$//g'; );
            echo $ii >> {output.tmp_fofn};
        done;
        (workflow/scripts/sort_concat_chrm_list.py {output.tmp_fofn} {wildcards.sample}.{wildcards.alnr}.{wildcards.ddup}.sentdhuom. {output.fin_fofn}) >> {log} 2>&1;
        """


rule sentdhuom_concat_index_chunks:
    """Concatenate chromosome chunks and index final VCF"""
    input:
        fofn=MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/{sample}.{alnr}.{ddup}.sentdhuom.snv.concat.vcf.gz.fofn",
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    output:
        vcfgz=touch(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/{sample}.{alnr}.{ddup}.sentdhuom.snv.sort.vcf.gz"),
        vcfgztemp=temp(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/{sample}.{alnr}.{ddup}.sentdhuom.snv.sort.temp.vcf.gz"),
        vcfgztbi=touch(MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/{sample}.{alnr}.{ddup}.sentdhuom.snv.sort.vcf.gz.tbi"),
    threads: 192
    resources:
        vcpu=192,
        threads=192,
        partition="i192mem,i192bigmem",
        mem_mb=config['sentdhuo']['mem_mb'],
    priority: 47
    params:
        huref=config["supporting_files"]["files"]["huref"]["fasta"]["name"],
        cluster_sample=ret_sample,
    benchmark:
        MDIR + "{sample}/benchmarks/{sample}.{alnr}.{ddup}.sentdhuom.merge.bench.tsv"
    conda:
        "../envs/vanilla_v0.1.yaml"
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/log/{sample}.{alnr}.{ddup}.sentdhuom.snv.merge.sort.gathered.log",
    shell:
        """
        touch {log};
        mkdir -p $(dirname {log});

        bcftools concat -a -d all --threads {threads} -f {input.fofn} -O z -o {output.vcfgztemp} >> {log} 2>&1;

        export oldname=$(bcftools query -l {output.vcfgztemp} | head -n1) >> {log} 2>&1;
        echo -e "${{oldname}}\\t{params.cluster_sample}" > {output.vcfgz}.rename.txt
        bcftools reheader -s {output.vcfgz}.rename.txt -o {output.vcfgz} {output.vcfgztemp} >> {log} 2>&1;
        bcftools index -f -t --threads {threads} -o {output.vcfgztbi} {output.vcfgz} >> {log} 2>&1;

        rm -rf $(dirname {output.vcfgz})/vcfs >> {log} 2>&1;
        """


localrules:
    clear_combined_sentdhuom_vcf,


rule clear_combined_sentdhuom_vcf:  # TARGET: clear combined sentdhuom vcf so chunks can be re-evaluated if needed.
    input:
        expand(
            MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/{sample}.{alnr}.{ddup}.sentdhuom.snv.sort.vcf.gz",
            sample=SSAMPS,
            alnr=ALIGNERS_DHUOM,
            ddup=DDUP,
        ),
    threads: 2
    priority: 42
    shell:
        """
        rm {input}*  1> /dev/null  2> /dev/null ) || echo 'file not found for deletion: {input}';
        """


localrules:
    produce_sentdhuom_vcf,


rule produce_sentdhuom_vcf:  # TARGET: sentieon dnascope hybrid ultima+ont modular vcf
    input:
        expand(
            MDIR
            + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/{sample}.{alnr}.{ddup}.sentdhuom.snv.sort.vcf.gz.tbi",
            sample=SSAMPS,
            alnr=ALIGNERS_DHUOM,
            ddup=DDUP,
        ),
    output:
        "gatheredall.sentdhuom",
    priority: 48
    threads: 1
    log:
        "gatheredall.sentdhuom.log",
    shell:
        """( touch {output} ;

        ls {output} ) >> {log} 2>&1;
        """


localrules:
    prep_sentdhuom_chunkdirs,


rule prep_sentdhuom_chunkdirs:
    """Prepare chunk directories for modular hybrid workflow"""
    input:
        DR=MDIR + "{sample}/{sample}.dirsetup.ready",
        ug_cram=MDIR + "{sample}/align/{alnr}/{sample}.cram",
        ug_crai=MDIR + "{sample}/align/{alnr}/{sample}.cram.crai",
        ont_cram=MDIR + "{sample}/align/ont/{sample}.cram",
        ont_crai=MDIR + "{sample}/align/ont/{sample}.cram.crai",
    output:
        expand(
            MDIR + "{{sample}}/align/{{alnr}}/{{ddup}}/snv/sentdhuom/vcfs/{dchrm}/{{sample}}.ready",
            dchrm=SENTDHUO_CHRMS
        ),
    wildcard_constraints:
        alnr="|".join(ALIGNERS_DHUOM)
    threads: 1
    log:
        MDIR + "{sample}/align/{alnr}/{ddup}/snv/sentdhuom/logs/{sample}.{alnr}.{ddup}.chunkdirs.log",
    shell:
        """
        ( echo {output}  ;
        mkdir -p $(dirname {output} );
        touch {output};
        ls {output}; ) > {log} 2>&1;
        """
