# DHIOMR Workflow Research Report

**Workflow:** DNAscope Hybrid Illumina + ONT Modular Refactored  
**File:** `workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk`  
**Date:** 2025-01-20

---

## 1. Tools Inventory

### 1.1 Short-Read (SR) Processing Tools

#### `sentieon bwa mem` + `sentieon util sort`
- **Rule:** `sentdhiomr_sr_align`
- **Purpose:** Align Illumina short reads to reference genome and sort by coordinate
- **Inputs:** 
  - R1/R2 FASTQ files
  - Reference genome (`huref`)
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/sr_aligned.bam`
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_heavy']`
  - Memory: `config['sentdhiomr']['mem_mb_heavy']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** Unknown (no benchmark files found in excerpts)
- **Estimated Cost:** High (alignment is compute-intensive; exact cost depends on FASTQ size)

#### `sentieon driver --algo LocusCollector` + `--algo Dedup`
- **Rule:** `sentdhiomr_sr_dedup`
- **Purpose:** Mark/remove PCR and optical duplicates from SR alignment
- **Inputs:**
  - `sr_aligned.bam`
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/sr_dedup.bam`
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/dedup_metrics.txt`
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_medium']`
  - Memory: `config['sentdhiomr']['mem_mb_medium']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** Medium (depends on BAM size)
- **Estimated Cost:** Medium

---

### 1.2 Hybrid Variant Calling Tools

#### `sentieon driver --algo HybridStage1`
- **Rule:** `sentdhiomr_stage1`
- **Purpose:** Identify insertion candidates from long reads (ONT) for hybrid calling
- **Inputs:**
  - LR CRAM: `{sample}/align/{alnr}/{sample}.cram`
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage1_ins.fa`
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage1_ins.bed`
- **Model:** `{model}/HybridStage1_ins.model`
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_heavy']`
  - Memory: `config['sentdhiomr']['mem_mb_heavy']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** High (processes entire LR CRAM)
- **Estimated Cost:** High

#### `sentieon bwa mem` (Stage2: SR realignment to insertions)
- **Rule:** `sentdhiomr_stage2`
- **Purpose:** Realign short reads to insertion sequences identified in Stage1
- **Inputs:**
  - R1/R2 FASTQ files
  - `stage1_ins.fa` (insertion reference)
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage2.bam`
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_heavy']`
  - Memory: `config['sentdhiomr']['mem_mb_heavy']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** Medium-High
- **Estimated Cost:** Medium-High

#### `sentieon driver --algo HybridStage3`
- **Rule:** `sentdhiomr_stage3`
- **Purpose:** Merge Stage2 realignments with original SR alignment for hybrid calling
- **Inputs:**
  - `sr_dedup.bam`
  - `stage2.bam`
  - `stage1_ins.bed`
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage3.bam`
- **Model:** `{model}/HybridStage3.model`
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_heavy']`
  - Memory: `config['sentdhiomr']['mem_mb_heavy']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** Medium
- **Estimated Cost:** Medium

#### `sentieon driver --algo DNAscope` (Pass1: Initial variant calling)
- **Rule:** `sentdhiomr_pass1`
- **Purpose:** Initial hybrid variant calling using LR + SR data
- **Inputs:**
  - LR CRAM: `{sample}/align/{alnr}/{sample}.cram`
  - SR BAM: `sr_dedup.bam`
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/initial.vcf.gz`
- **Model:** `{model}/hybrid.model`
- **Population VCF:** `config["supporting_files"]["files"]["popvcf"]["name"]`
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_heavy']`
  - Memory: `config['sentdhiomr']['mem_mb_heavy']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** Very High (main variant calling step)
- **Estimated Cost:** Very High

---

### 1.3 Variant Filtering and Selection Tools

#### `sentieon pyexec hybrid_select.py`
- **Rule:** `sentdhiomr_hybrid_select`
- **Purpose:** Filter VCF based on long/short read confidence, convert to BED with padding
- **Inputs:**
  - `initial.vcf.gz`
  - Reference FAI
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/selected.bed`
- **Processing:**
  1. `hybrid_select.py` filters VCF
  2. `bcftools view` filters for PASS variants
  3. `bcftools query` converts to BED
  4. `bedtools slop` adds 1000bp padding
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_light']`
  - Memory: `config['sentdhiomr']['mem_mb_light']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** Low
- **Estimated Cost:** Low

---

### 1.4 Refinement and Final Calling Tools

#### `sentieon driver --algo DNAscope` (Pass2: Refined calling on selected regions)
- **Rule:** `sentdhiomr_pass2`
- **Purpose:** Re-call variants on high-confidence regions from Pass1
- **Inputs:**
  - LR CRAM
  - `stage3.bam`
  - `selected.bed` (interval file)
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/raw.vcf.gz`
- **Model:** `{model}/hybrid.model`
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_heavy']`
  - Memory: `config['sentdhiomr']['mem_mb_heavy']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** High
- **Estimated Cost:** High

#### `sentieon driver --algo DNAscope` (MAPQ0 calling)
- **Rule:** `sentdhiomr_mapq0_bed`
- **Purpose:** Call variants in MAPQ=0 regions (multi-mapping reads)
- **Inputs:**
  - LR CRAM
  - `sr_dedup.bam`
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/mapq0.bed`
- **Read Filters:**
  - LR: `{lr_read_filter}` (if configured)
  - SR: `{sr_read_filter}` (if configured)
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_medium']`
  - Memory: `config['sentdhiomr']['mem_mb_medium']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** Medium
- **Estimated Cost:** Medium

#### `bcftools concat` + `bcftools view`
- **Rule:** `sentdhiomr_merge_mapq0`
- **Purpose:** Merge raw VCF with MAPQ0 BED, filter for PASS variants
- **Inputs:**
  - `raw.vcf.gz`
  - `mapq0.bed`
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/merged.vcf.gz`
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_light']`
  - Memory: `config['sentdhiomr']['mem_mb_light']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** Low
- **Estimated Cost:** Low

---

### 1.5 Annotation and Transfer Tools

#### `sentieon pyexec hybrid_anno.py`
- **Rule:** `sentdhiomr_hybrid_anno`
- **Purpose:** Annotate VCF with haplotype information
- **Inputs:**
  - `merged.vcf.gz`
  - `selected.bed` (haplotype BED)
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/annotated.vcf.gz`
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_light']`
  - Memory: `config['sentdhiomr']['mem_mb_light']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** Low
- **Estimated Cost:** Low

#### `bcftools merge` + `bcftools view` + `trimalt` (per-shard transfer)
- **Rule:** `sentdhiomr_transfer_shard`
- **Purpose:** Transfer annotations from population VCF to called variants (per chromosome shard)
- **Inputs:**
  - `annotated.vcf.gz`
  - Population VCF (`popvcf`)
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/transfer_{tchrm}.vcf.gz`
- **Processing:**
  1. `bcftools merge` merges annotated VCF with population VCF
  2. `bcftools view` filters to specific regions
  3. `trimalt` removes unused ALT alleles
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_light']`
  - Memory: `config['sentdhiomr']['mem_mb_light']`
  - Partition: `i192mem,i192bigmem,i192`
- **Estimated Runtime:** Low (per shard)
- **Estimated Cost:** Low (per shard)

#### `bcftools concat`
- **Rule:** `sentdhiomr_transfer_concat`
- **Purpose:** Concatenate all transfer shards into final VCF
- **Inputs:**
  - All `transfer_{tchrm}.vcf.gz` files
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.snv.vcf.gz`
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.snv.vcf.gz.tbi`
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_light']`
  - Memory: `config['sentdhiomr']['mem_mb_light']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** Low
- **Estimated Cost:** Low

---

### 1.6 Structural Variant (SV) Calling Tools

#### `sentieon driver --algo LongReadSV`
- **Rule:** `sentdhiomr_sv`
- **Purpose:** Call structural variants (51bp - ~10Kbp) from long reads
- **Inputs:**
  - LR CRAM: `{sample}/align/{alnr}/{sample}.cram`
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/sv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sv.vcf.gz`
  - `{sample}/align/{alnr}/{ddup}/sv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sv.vcf.gz.tbi`
- **Model:** `{model}/LongReadSV.model`
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_heavy']`
  - Memory: `config['sentdhiomr']['mem_mb_heavy']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** High
- **Estimated Cost:** High

---

### 1.7 Copy Number Variant (CNV) Calling Tools

#### `sentieon driver --algo DNAscope` (CNV calling)
- **Rule:** `sentdhiomr_cnv`
- **Purpose:** Call copy number variants (>~10Kbp) from hybrid data
- **Inputs:**
  - LR CRAM
  - `stage3.bam`
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/cnv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.cnv.vcf.gz`
  - `{sample}/align/{alnr}/{ddup}/cnv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.cnv.vcf.gz.tbi`
- **Model:** `{model}/hybrid.model`
- **Algorithm:** `--algo DNAscope --var_type bnd`
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_heavy']`
  - Memory: `config['sentdhiomr']['mem_mb_heavy']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** High
- **Estimated Cost:** High

---

### 1.8 Optional SR Alignment Export

#### `samtools view` (CRAM conversion)
- **Rule:** `sentdhiomr_sr_export`
- **Purpose:** Convert SR dedup BAM to CRAM for long-term storage (optional)
- **Inputs:**
  - `sr_dedup.bam`
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sr.cram`
  - `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sr.cram.crai`
- **Controlled by:** `config['sentdhiomr']['keep_sr_alignment']` (default: false)
- **Resources:**
  - Threads: `config['sentdhiomr']['threads_light']`
  - Memory: `config['sentdhiomr']['mem_mb_light']`
  - Partition: `i192mem,i192bigmem`
- **Estimated Runtime:** Low
- **Estimated Cost:** Low

---

## 2. Comparison Workflows

### 2.1 Standard Sentieon Short-Read Pipeline (BWA + Doppelmark + DNAscope)

This is the baseline short-read-only workflow for comparison against DHIOMR.

#### `sentieon bwa mem` + `sentieon util sort`
- **Rule:** `sentieon_bwa_mem_sort` (from `workflow/rules/sentieon.smk`)
- **Purpose:** Align Illumina short reads and sort
- **Inputs:**
  - R1/R2 FASTQ files
  - Reference genome
- **Outputs:**
  - `{sample}/align/sentbwa/{sample}.sentbwa.sort.cram`
  - `{sample}/align/sentbwa/{sample}.sentbwa.sort.cram.crai`
- **Resources:**
  - Threads: `config['sentbwa']['threads']`
  - Memory: `config['sentbwa']['mem_mb']`
- **Estimated Runtime:** High
- **Estimated Cost:** High

#### `sentieon driver --algo LocusCollector` + `--algo Dedup`
- **Rule:** `doppelmark_sentieon_dups` (from `workflow/rules/sentieon_markdups.smk`)
- **Purpose:** Mark duplicates using Sentieon
- **Inputs:**
  - `{sample}/align/{alnr}/{sample}.{alnr}.sort.bam`
- **Outputs:**
  - `{sample}/align/{alnr}/smd/{sample}.{alnr}.smd.cram`
  - `{sample}/align/{alnr}/smd/{sample}.{alnr}.smd.cram.crai`
- **Resources:**
  - Threads: `config['doppel_sent']['threads']`
  - Memory: `config['doppel_sent']['mem_mb']`
- **Estimated Runtime:** Medium
- **Estimated Cost:** Medium

#### `sentieon driver --algo DNAscope` (Short-read only)
- **Rule:** `sent_DNAscope` (from `workflow/rules/sent_DNAscope.smk`)
- **Purpose:** Call SNVs/indels from short reads only
- **Inputs:**
  - `{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram`
  - Population VCF (`popvcf`)
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentd/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentd.{dchrm}.snv.vcf`
- **Model:** `config["sentD"]["dna_scope_snv_model"]`
- **Resources:**
  - Threads: `config['sentD']['threads']`
  - Memory: `config['sentD']['mem_mb']`
  - Partition: `config['sentD']['partition']`
- **Estimated Runtime:** Very High
- **Estimated Cost:** Very High
- **Note:** This rule does NOT emit SV or CNV VCFs by default

#### Merging DNAscope VCFs
- **Rule:** `sent_DNAscope_merge_sort` (from `workflow/rules/sent_DNAscope.smk`)
- **Purpose:** Merge per-chromosome VCFs into final sorted VCF
- **Inputs:**
  - All `{sample}.{alnr}.{ddup}.sentd.{dchrm}.snv.vcf` files
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/snv/sentd/{sample}.{alnr}.{ddup}.sentd.snv.sort.vcf.gz`
  - `{sample}/align/{alnr}/{ddup}/snv/sentd/{sample}.{alnr}.{ddup}.sentd.snv.sort.vcf.gz.tbi`
- **Resources:**
  - Threads: 4
  - Partition: `i192,i192mem`
- **Estimated Runtime:** Low
- **Estimated Cost:** Low

---

### 2.2 Third-Party SV Callers

#### Manta
- **Rule:** `manta` (from `workflow/rules/manta.smk`)
- **Purpose:** Call structural variants from short-read alignments
- **Inputs:**
  - `{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram`
  - `{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram.crai`
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/sv/manta/{sample}.{alnr}.{ddup}.manta.diploidSV.vcf.gz`
  - `{sample}/align/{alnr}/{ddup}/sv/manta/{sample}.{alnr}.{ddup}.manta.diploidSV.vcf.gz.tbi`
- **Resources:**
  - Threads: `config['manta']['threads']`
  - Memory: `config['manta']['mem_mb']`
- **Estimated Runtime:** High
- **Estimated Cost:** High
- **Known Issue:** Empty VCF files reported in current run (investigation needed)

#### TIDDIT
- **Rule:** `tiddit` (inferred from target `produce_tiddit`)
- **Purpose:** Call structural variants from short-read alignments
- **Inputs:**
  - `{sample}/align/{alnr}/{ddup}/{sample}.{alnr}.{ddup}.cram` (inferred)
- **Outputs:**
  - `{sample}/align/{alnr}/{ddup}/sv/tiddit/{sample}.{alnr}.{ddup}.tiddit.vcf.gz` (inferred)
  - `{sample}/align/{alnr}/{ddup}/sv/tiddit/{sample}.{alnr}.{ddup}.tiddit.vcf.gz.tbi` (inferred)
- **Resources:**
  - Unknown (rule file not in excerpts)
- **Estimated Runtime:** Unknown
- **Estimated Cost:** Unknown
- **Note:** Rule file not found in provided excerpts; may be in `workflow/rules/tiddit.smk`

---

## 3. File Manifest

### 3.1 DHIOMR Final Outputs (Retained)

| File Type | Path | Size Estimate | Description |
|-----------|------|---------------|-------------|
| SNV VCF | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.snv.vcf.gz` | 100-500 MB | Small variants (0-50bp) |
| SNV VCF Index | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.{dchrm}.snv.vcf.gz.tbi` | 1-5 MB | Tabix index |
| SV VCF | `{sample}/align/{alnr}/{ddup}/sv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sv.vcf.gz` | 10-100 MB | Structural variants (51bp-~10Kbp) |
| SV VCF Index | `{sample}/align/{alnr}/{ddup}/sv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sv.vcf.gz.tbi` | 100 KB - 1 MB | Tabix index |
| CNV VCF | `{sample}/align/{alnr}/{ddup}/cnv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.cnv.vcf.gz` | 1-50 MB | Copy number variants (>~10Kbp) |
| CNV VCF Index | `{sample}/align/{alnr}/{ddup}/cnv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.cnv.vcf.gz.tbi` | 10-100 KB | Tabix index |
| SR CRAM (optional) | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sr.cram` | 30-100 GB | Short-read alignment (if `keep_sr_alignment: true`) |
| SR CRAM Index (optional) | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/{sample}.{alnr}.{ddup}.sentdhiomr.sr.cram.crai` | 1-10 MB | CRAM index |

### 3.2 DHIOMR Intermediate Files (Deleted by Default)

| File Type | Path | Size Estimate | Description |
|-----------|------|---------------|-------------|
| SR Aligned BAM | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/sr_aligned.bam` | 50-150 GB | Initial SR alignment (pre-dedup) |
| SR Dedup BAM | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/sr_dedup.bam` | 30-100 GB | SR alignment after deduplication |
| Dedup Metrics | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/dedup_metrics.txt` | 1-10 KB | Duplicate marking statistics |
| Stage1 Insertions FA | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage1_ins.fa` | 1-100 MB | Insertion sequences from LR |
| Stage1 Insertions BED | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage1_ins.bed` | 100 KB - 10 MB | Insertion coordinates from LR |
| Stage2 BAM | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage2.bam` | 1-50 GB | SR realigned to insertions |
| Stage3 BAM | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/stage3.bam` | 30-100 GB | Merged SR alignment |
| Initial VCF | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/initial.vcf.gz` | 100-500 MB | Pass1 variant calls |
| Selected BED | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/selected.bed` | 10-100 MB | High-confidence regions |
| Raw VCF | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/raw.vcf.gz` | 100-500 MB | Pass2 variant calls |
| MAPQ0 BED | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/mapq0.bed` | 1-50 MB | MAPQ=0 variant calls |
| Merged VCF | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/merged.vcf.gz` | 100-500 MB | Raw + MAPQ0 merged |
| Annotated VCF | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/annotated.vcf.gz` | 100-500 MB | Haplotype-annotated VCF |
| Transfer Shards | `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/transfer_{tchrm}.vcf.gz` | 5-50 MB each | Per-chromosome transfer VCFs |

**Total Intermediate Storage (if retained):** ~200-600 GB per sample

---

### 3.3 Standard Sentieon Pipeline Outputs

| File Type | Path | Size Estimate | Description |
|-----------|------|---------------|-------------|
| Aligned CRAM | `{sample}/align/sentbwa/{sample}.sentbwa.sort.cram` | 30-100 GB | Initial alignment |
| CRAM Index | `{sample}/align/sentbwa/{sample}.sentbwa.sort.cram.crai` | 1-10 MB | CRAM index |
| Dedup CRAM | `{sample}/align/sentbwa/smd/{sample}.sentbwa.smd.cram` | 30-100 GB | After duplicate marking |
| Dedup CRAM Index | `{sample}/align/sentbwa/smd/{sample}.sentbwa.smd.cram.crai` | 1-10 MB | CRAM index |
| SNV VCF (per chr) | `{sample}/align/{alnr}/{ddup}/snv/sentd/vcfs/{dchrm}/{sample}.{alnr}.{ddup}.sentd.{dchrm}.snv.vcf` | 5-50 MB each | Per-chromosome SNV calls |
| SNV VCF (merged) | `{sample}/align/{alnr}/{ddup}/snv/sentd/{sample}.{alnr}.{ddup}.sentd.snv.sort.vcf.gz` | 100-500 MB | Final merged SNV VCF |
| SNV VCF Index | `{sample}/align/{alnr}/{ddup}/snv/sentd/{sample}.{alnr}.{ddup}.sentd.snv.sort.vcf.gz.tbi` | 1-5 MB | Tabix index |

**Note:** Standard DNAscope does NOT emit SV or CNV VCFs by default.

---

### 3.4 Third-Party SV Caller Outputs

#### Manta
| File Type | Path | Size Estimate | Description |
|-----------|------|---------------|-------------|
| SV VCF | `{sample}/align/{alnr}/{ddup}/sv/manta/{sample}.{alnr}.{ddup}.manta.diploidSV.vcf.gz` | 10-100 MB | Structural variants |
| SV VCF Index | `{sample}/align/{alnr}/{ddup}/sv/manta/{sample}.{alnr}.{ddup}.manta.diploidSV.vcf.gz.tbi` | 100 KB - 1 MB | Tabix index |
| Candidate SV VCF | `{sample}/align/{alnr}/{ddup}/sv/manta/{sample}.{alnr}.{ddup}.manta.candidateSV.vcf.gz` | 10-100 MB | Candidate SVs (pre-filter) |
| Candidate Index | `{sample}/align/{alnr}/{ddup}/sv/manta/{sample}.{alnr}.{ddup}.manta.candidateSV.vcf.gz.tbi` | 100 KB - 1 MB | Tabix index |

#### TIDDIT
| File Type | Path | Size Estimate | Description |
|-----------|------|---------------|-------------|
| SV VCF | `{sample}/align/{alnr}/{ddup}/sv/tiddit/{sample}.{alnr}.{ddup}.tiddit.vcf.gz` | 10-100 MB | Structural variants |
| SV VCF Index | `{sample}/align/{alnr}/{ddup}/sv/tiddit/{sample}.{alnr}.{ddup}.tiddit.vcf.gz.tbi` | 100 KB - 1 MB | Tabix index |

---

### 3.5 Benchmark and Log Files

| File Type | Path Pattern | Size Estimate | Description |
|-----------|--------------|---------------|-------------|
| Benchmark (per rule) | `{sample}/benchmarks/{sample}.{alnr}.{ddup}.{caller}.{chrm}.{rule}.bench.tsv` | 1-10 KB | Runtime/resource metrics |
| Log (per rule) | `{sample}/align/{alnr}/{ddup}/snv/{caller}/log/{sample}.{alnr}.{ddup}.{caller}.{chrm}.log` | 10 KB - 10 MB | Stdout/stderr logs |
| MultiQC Report | `results/day/{genome_build}/multiqc/DAY_final_multiqc.html` | 5-50 MB | Aggregated QC report |
| GIAB Concordance | `other_reports/giab_concordance_mqc.tsv` | 10-100 KB | Concordance metrics (if GIAB sample) |

---

### 3.6 Input Files (Required)

| File Type | Path Pattern | Size Estimate | Description |
|-----------|--------------|---------------|-------------|
| SR FASTQ R1 | `{sample}/fastq/{sample}_R1.fastq.gz` | 20-100 GB | Short-read R1 |
| SR FASTQ R2 | `{sample}/fastq/{sample}_R2.fastq.gz` | 20-100 GB | Short-read R2 |
| LR CRAM (ONT) | `{sample}/align/{alnr}/{sample}.cram` | 30-150 GB | Long-read alignment (ONT) |
| LR CRAM Index | `{sample}/align/{alnr}/{sample}.cram.crai` | 1-10 MB | CRAM index |
| Reference Genome | `refs/hg38.fa` | 3 GB | Human reference (hg38) |
| Reference FAI | `refs/hg38.fa.fai` | 100 KB | FASTA index |
| Reference DICT | `refs/hg38.dict` | 100 KB | Sequence dictionary |
| Population VCF | `refs/popvcf.vcf.gz` | 10-50 GB | Population allele frequencies |
| Population VCF Index | `refs/popvcf.vcf.gz.tbi` | 10-100 MB | Tabix index |
| Diploid BED | `refs/diploid.bed` | 1-10 MB | Diploid regions (optional) |
| Haploid BED | `refs/haploid.bed` | 100 KB - 1 MB | Haploid regions (optional) |
| Sentieon Models | `models/{model_name}.bundle/` | 100 MB - 1 GB | Model bundles (hybrid.model, etc.) |

---

### 3.7 Total Storage Requirements (Per Sample)

| Workflow | Intermediate Files | Final Outputs | Total |
|----------|-------------------|---------------|-------|
| DHIOMR (delete intermediates) | 0 GB | 1-2 GB | 1-2 GB |
| DHIOMR (keep intermediates) | 200-600 GB | 1-2 GB | 201-602 GB |
| Standard Sentieon | 30-100 GB | 100-500 MB | 30-100 GB |
| Manta | 1-10 GB | 20-200 MB | 1-10 GB |
| TIDDIT | 1-10 GB | 20-200 MB | 1-10 GB |

**Combined (all workflows, delete intermediates):** ~2-5 GB per sample  
**Combined (all workflows, keep intermediates):** ~230-710 GB per sample

---

## 4. Validation Reports

### 4.1 Automatically Generated Reports

#### GIAB Concordance Reports
- **Generated by:** `workflow/rules/giab_concordance.smk` (inferred from MultiQC config)
- **File Path:** `other_reports/giab_concordance_mqc.tsv`
- **Format:** TSV (MultiQC custom content)
- **Metrics:**
  - Precision, Recall, F1-score for SNVs and INDELs
  - Comparison against GIAB truth sets (if sample is GIAB reference)
- **Triggered by:** `produce_snv_concordances` target
- **MultiQC Integration:** Yes (via `sp.giab_concordance` in `config/external_tools/multiqc_config.yaml`)

#### Benchmark Summary Reports
- **Generated by:** Snakemake benchmark directive (per rule)
- **File Paths:** 
  - `{sample}/benchmarks/{sample}.{alnr}.{ddup}.{caller}.{chrm}.{rule}.bench.tsv`
- **Format:** TSV
- **Metrics:**
  - `s` (runtime in seconds)
  - `h:m:s` (human-readable runtime)
  - `max_rss` (max resident set size in MB)
  - `max_vms` (max virtual memory size in MB)
  - `max_uss` (max unique set size in MB)
  - `max_pss` (max proportional set size in MB)
  - `io_in` (MB read from disk)
  - `io_out` (MB written to disk)
  - `mean_load` (average CPU load)
  - `cpu_time` (total CPU time in seconds)
- **MultiQC Integration:** Yes (via `sp.rules_benchmark_data` in `config/external_tools/multiqc_config.yaml`)

#### MultiQC Final Report
- **Generated by:** `produce_multiqc_final_wgs` target
- **File Path:** `results/day/{genome_build}/multiqc/DAY_final_multiqc.html`
- **Format:** HTML
- **Metrics:** Aggregates all QC metrics from:
  - FastQC (read quality)
  - FastQ Screen (contamination)
  - Samtools stats (alignment metrics)
  - Picard metrics (duplicate rates, insert sizes)
  - Mosdepth (coverage distribution)
  - Sentieon metrics (dedup metrics, variant stats)
  - GIAB concordance (if applicable)
  - Benchmark data (runtime/resource usage)
  - Custom content (alignment stats, coverage evenness)
- **Triggered by:** Final workflow target
- **Configuration:** `config/external_tools/multiqc_config.yaml`

---

### 4.2 Intermediate QC Files (Not Automatically Reported)

#### Deduplication Metrics
- **File Path:** `{sample}/align/{alnr}/{ddup}/snv/sentdhiomr/vcfs/{dchrm}/tmp/dedup_metrics.txt`
- **Format:** Text
- **Metrics:**
  - Total reads
  - Duplicate reads
  - Duplicate rate
  - Optical duplicates
- **Generated by:** `sentdhiomr_sr_dedup` rule
- **MultiQC Integration:** Potentially (if Sentieon module parses this file)

#### VCF Statistics
- **Generated by:** `bcftools stats` (if invoked separately)
- **File Path:** Not automatically generated by DHIOMR workflow
- **Format:** Text
- **Metrics:**
  - SNV/INDEL counts
  - Ti/Tv ratio
  - Depth distribution
  - Quality distribution
- **MultiQC Integration:** Yes (if generated)

---

### 4.3 Validation Reports NOT Generated by DHIOMR

The following validation reports are **NOT** automatically produced by the DHIOMR workflow but may be generated by other rules:

1. **Peddy Reports** (sex check, ancestry, relatedness)
   - Configured in MultiQC but not generated by DHIOMR
   - Requires separate `peddy` rule execution

2. **VerifyBAMID Reports** (sample contamination)
   - Configured in MultiQC but not generated by DHIOMR
   - Requires separate `verifybamid` rule execution

3. **Somalier Reports** (sample relatedness, ancestry)
   - Configured in MultiQC but not generated by DHIOMR
   - Requires separate `somalier` rule execution

4. **Qualimap Reports** (alignment quality)
   - Configured in MultiQC but not generated by DHIOMR
   - Requires separate `qualimap` rule execution

---

## 5. Configuration Flags for Retention

**Note:** The excerpts do not show explicit configuration flags for retaining intermediate files. The CLI documentation mentions:

> "All of the intermediate files which are currently deleted have a flag setting which will retain them."

**Action Required:** Research Sentieon CLI documentation or `sentieon-cli` source code to identify:
- Flag names for retaining intermediate files
- Flag names for retaining temporary directories
- How to configure these in the modular workflow

**Likely locations:**
- `config/config.yaml` under `sentdhiomr:` section
- Sentieon driver `--temp_dir` behavior (may auto-delete unless flagged)
- Sentieon CLI `--keep_temp` or similar flags

**Current Known Flags:**
- `config['sentdhiomr']['keep_sr_alignment']` (default: false) — retains SR CRAM if true

---

## 6. Cost and Runtime Estimates

**Note:** Actual costs depend on:
- Instance types (i192mem, i192bigmem, i192)
- Spot vs. On-Demand pricing
- AWS region
- Input data size (FASTQ/CRAM size)

### 6.1 DHIOMR Relative Cost Ranking (High → Low)

1. `sentdhiomr_pass1` (DNAscope initial calling) — **Very High**
2. `sentdhiomr_stage1` (HybridStage1 insertion detection) — **High**
3. `sentdhiomr_sr_align` (BWA alignment) — **High**
4. `sentdhiomr_pass2` (DNAscope refined calling) — **High**
5. `sentdhiomr_sv` (LongReadSV calling) — **High**
6. `sentdhiomr_cnv` (CNV calling) — **High**
7. `sentdhiomr_stage2` (SR realignment to insertions) — **Medium-High**
8. `sentdhiomr_stage3` (HybridStage3 merge) — **Medium**
9. `sentdhiomr_sr_dedup` (Deduplication) — **Medium**
10. All other steps (annotation, transfer, concat) — **Low**

### 6.2 Standard Sentieon Pipeline Relative Cost Ranking

1. `sent_DNAscope` (DNAscope calling) — **Very High**
2. `sentieon_bwa_mem_sort` (BWA alignment) — **High**
3. `doppelmark_sentieon_dups` (Deduplication) — **Medium**
4. `sent_DNAscope_merge_sort` (VCF merge) — **Low**

### 6.3 Third-Party SV Callers Relative Cost Ranking

1. `manta` (Manta SV calling) — **High**
2. `tiddit` (TIDDIT SV calling) — **Medium-High** (estimated)

### 6.4 Benchmark Data Availability

- Benchmark files are generated per rule (`.bench.tsv`)
- Check `{sample}/benchmarks/` directory for actual runtime/resource data
- Example paths from excerpts:
  - `.tmp_get_hiomr_benchmarks.sh` shows benchmark file discovery
  - `.tmp_get_hiomr_bench2.sh` shows benchmark aggregation

---

## 7. Recommendations

### 7.1 Missing Documentation
1. **Sentieon Model Versions:** Document which model versions are used (`hybrid.model`, `HybridStage1_ins.model`, etc.)
2. **Read Filter Specifications:** Document default values for `lr_read_filter` and `sr_read_filter`
3. **Retention Flags:** Identify and document flags to retain intermediate files
4. **Benchmark Aggregation:** Create automated benchmark summary report
5. **TIDDIT Rule:** Locate and document `workflow/rules/tiddit.smk` (not in excerpts)

### 7.2 Validation Gaps
1. **No VCF Statistics:** Consider adding `bcftools stats` to generate Ti/Tv, depth, quality metrics
2. **No Sample QC:** DHIOMR does not run Peddy, VerifyBAMID, or Somalier
3. **No Alignment QC:** DHIOMR does not run Qualimap or detailed alignment statistics
4. **Manta Empty VCFs:** Investigate why Manta is producing empty VCF files (current issue)

### 7.3 Observability Improvements
1. **Add Checkpoint Rules:** Add explicit checkpoint rules between major stages for easier restart
2. **Separate Logs:** Each rule logs to separate file; consider aggregating critical errors
3. **Resource Monitoring:** Benchmark files exist but are not automatically summarized
4. **Disk Usage Tracking:** Add disk usage monitoring for intermediate files (200-600 GB per sample)

### 7.4 Feature Requests (From User Notes)

1. **Retain Intermediate Files:** Add configuration flags to keep all intermediate files and directories
2. **Emit All VCF Types:** Ensure SNV, SV, and CNV VCFs are all emitted (CNV currently has issues)
3. **SegDup Caller Integration:** Add Sentieon SegDup caller for SMN, PMS2, etc. (https://github.com/Sentieon/segdup-caller)
4. **Mitochondrial Calling:** Add pre-release mitochondrial caller (`bin/sentieon_mitochondrial_pipeline.sh`)
5. **Read Support Annotations:** Document which VCF INFO fields indicate SR vs. LR read support

---

## 8. References

- **Workflow File:** `workflow/rules/sent_hybrid_ilmn_ont_modular.refactored.smk`
- **MultiQC Config:** `config/external_tools/multiqc_config.yaml`
- **Sentieon Models:** https://github.com/Sentieon/sentieon-models
- **Sentieon SegDup Caller:** https://github.com/Sentieon/segdup-caller
- **GIAB Truth Sets:** https://www.nist.gov/programs-projects/genome-bottle
- **Manta Documentation:** https://github.com/Illumina/manta
- **TIDDIT Documentation:** https://github.com/SciLifeLab/TIDDIT

---

**End of Report**