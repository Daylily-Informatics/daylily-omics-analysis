# Sentieon pangenome short-read rules (Snakemake)

This drop-in module wraps the official `sentieon-cli pangenome` pipeline to produce:

- `align/pangenome/{sample}.vcf.gz` (SNV/indel VCF, model-applied)
- `align/pangenome/{sample}_pangenome-aligned.cram` (surjected + deduped GRCh38-aligned CRAM)
- `align/pangenome/{sample}_ploidy.json`
- `align/pangenome/{sample}_svs.vcf.gz` (SV calls from `vg call`)

## 1) What you need staged

### A) Linear reference (GRCh38 / hg38)
- FASTA: `hg38.fa`
- Index: `hg38.fa.fai` (required)

Example:
```bash
samtools faidx hg38.fa
```

### B) Pangenome graph bundle (Minigraph-Cactus, GRCh38 coordinate system)
Required files:
- `*.gbz`  (GBZ pangenome)
- `*.hapl` (haplotype file matching the GBZ)
- `*.xg`   (XG extracted from GBZ)
- `*.snarls` (snarls extracted from GBZ)

You can generate `.xg` and `.snarls` from the `.gbz`:
```bash
vg convert -x hprc-v2.0-mc-grch38.gbz > hprc-v2.0-mc-grch38.xg
vg snarls -T hprc-v2.0-mc-grch38.gbz > hprc-v2.0-mc-grch38.snarls
```

### C) Sentieon pangenome model bundle
The `sentieon-cli pangenome` code validates that the model bundle directory contains:
- `bwa.model`
- `cnv.model`
- `dnascope.model`

You will typically get this from Sentieon as something like:
- `dnaseq_pangenome3.0.bundle/`

Stage the entire bundle directory somewhere readable on all workers.

### D) Tools on PATH
`sentieon-cli pangenome` calls external tools. Minimum versions are enforced in Sentieon CLI:
- `sentieon driver` >= 202503.01
- `bcftools` >= 1.22
- `samtools` >= 1.16

You also need:
- `vg`
- `kmc`

## 2) How to fetch and stage HPRC graph data

Two practical options:

### Option 1: HPRC v2.0 (release2)
If you have AWS CLI:
```bash
# List the directory (no AWS creds required)
aws s3 ls s3://human-pangenomics/pangenomes/scratch/2025_02_28_minigraph_cactus/hprc-v2.0-mc-grch38/ --no-sign-request

# Copy the required files (names may be confirmed with the ls above)
aws s3 cp --no-sign-request \
  s3://human-pangenomics/pangenomes/scratch/2025_02_28_minigraph_cactus/hprc-v2.0-mc-grch38/hprc-v2.0-mc-grch38.gbz \
  ./pangenome/

aws s3 cp --no-sign-request \
  s3://human-pangenomics/pangenomes/scratch/2025_02_28_minigraph_cactus/hprc-v2.0-mc-grch38/hprc-v2.0-mc-grch38.hapl \
  ./pangenome/
```

Then generate:
```bash
vg convert -x ./pangenome/hprc-v2.0-mc-grch38.gbz > ./pangenome/hprc-v2.0-mc-grch38.xg
vg snarls -T ./pangenome/hprc-v2.0-mc-grch38.gbz > ./pangenome/hprc-v2.0-mc-grch38.snarls
```

### Option 2: HPRC v1.1 (freeze1)
If you prefer straight HTTPS downloads:
```bash
mkdir -p ./pangenome && cd ./pangenome
curl -L -O \
  https://human-pangenomics.s3.us-west-2.amazonaws.com/pangenomes/freeze/freeze1/minigraph-cactus/hprc-v1.1-mc-grch38/hprc-v1.1-mc-grch38.gbz
curl -L -O \
  https://human-pangenomics.s3.us-west-2.amazonaws.com/pangenomes/freeze/freeze1/minigraph-cactus/hprc-v1.1-mc-grch38/hprc-v1.1-mc-grch38.hapl

vg convert -x hprc-v1.1-mc-grch38.gbz > hprc-v1.1-mc-grch38.xg
vg snarls -T hprc-v1.1-mc-grch38.gbz > hprc-v1.1-mc-grch38.snarls
```

## 3) Config keys you must add

Add these (paths are examples):

```yaml
supporting_files:
  files:
    pangenome_gbz:
      name: /path/to/pangenome/hprc-v2.0-mc-grch38.gbz
    pangenome_hapl:
      name: /path/to/pangenome/hprc-v2.0-mc-grch38.hapl
    pangenome_xg:
      name: /path/to/pangenome/hprc-v2.0-mc-grch38.xg
    pangenome_snarls:
      name: /path/to/pangenome/hprc-v2.0-mc-grch38.snarls
    pangenome_model_bundle:
      name: /path/to/dnaseq_pangenome3.0.bundle

sentieon:
  pangenome_threads: 32
  pangenome_kmer_memory_gb: 30
  pangenome_skip_cnv: true
  pangenome_pcr_free: true
```

FASTQs are discovered via either:
- your global helper functions `getR1s(wildcards)` and `getR2s(wildcards)`, or
- `config['samples'][sample]['r1']` (+ optional `['r2']`), or
- a `units.tsv` path in `config['units_tsv']` (or `config['tables']['units_tsv']` / `['units']`)

Units parsing expects columns:
- `SAMPLEID`
- `ILMN_R1_PATH`
- `ILMN_R2_PATH` (optional for single-end)

## 4) Casting back to hg38 and concordance

This pipeline already surjects and deduplicates onto the linear GRCh38 reference you pass via `--reference`.
So the query VCF is in the same coordinate system as your hg38 truth sets, assuming contig naming matches.

A practical concordance run (hap.py example):
```bash
hap.py \
  /path/to/truth/HG003_truth.vcf.gz \
  {DIR}/tools/align/pangenome/HG003.vcf.gz \
  -f /path/to/truth/HG003_confident.bed \
  -r /path/to/hg38.fa \
  -o HG003_pangenome_concordance
```

If contig naming differs (example: `1` vs `chr1`), normalize one side with a rename map:
```bash
# Example: add "chr" prefix using bcftools rename-chrs map (build your map file explicitly)
bcftools annotate --rename-chrs chr_map.txt -Oz -o query.renamed.vcf.gz query.vcf.gz
tabix -p vcf query.renamed.vcf.gz
```

## 5) Include the module

In your main Snakefile:
```python
include: "sentieon_pangenome_shortreads.smk"
```

Then build:
```bash
snakemake -j 100 {DIR}/tools/align/pangenome/HG003.vcf.gz
```
