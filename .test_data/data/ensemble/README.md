# Ensemble Workflow Example

This directory contains example configuration files for running the ensemble VCF workflow.

## Overview

The ensemble workflow combines VCFs from multiple platforms (short-read + long-read) using a consensus-based approach with quality-based rescue of discordant variants.

## Configuration

### units.tsv Columns

The ensemble workflow requires two additional columns in `units.tsv`:

- **SR_VCF_PATH**: Path to short-read VCF (ILMN/Ultima/Roche)
- **LR_VCF_PATH**: Path to long-read VCF (ONT/PacBio)

These paths can include `{sample}` placeholder which will be replaced with the sample name.

### Example units.tsv

```tsv
RUNID	SAMPLEID	EXPERIMENTID	LANEID	BARCODEID	LIBPREP	SEQ_VENDOR	SEQ_PLATFORM	SR_VCF_PATH	LR_VCF_PATH
R0	HG003	ensemble-test	0	D0	PCR-FREE	HYBRID	ENSEMBLE	results/day/hg38/{sample}/align/bwa2a/dppl/snv/deep19/{sample}.bwa2a.dppl.deep19.snv.sort.vcf.gz	results/day/hg38/{sample}/align/ont/snv/sentdont/{sample}.ont.sentdont.snv.sort.vcf.gz
```

## Running the Workflow

### 1. Generate Input VCFs

First, generate the input VCFs using standard daylily workflows:

```bash
# Generate short-read VCF (example: ILMN + DeepVariant)
dy-r produce_snv_concordances -p -k -j 10 \
  --config aligners=['bwa2a'] dedupers=['dppl'] snv_callers=['deep19']

# Generate long-read VCF (example: ONT + Sentieon)
dy-r produce_sentdont_vcf -p -k -j 10
```

### 2. Configure units.tsv

Update `config/units.tsv` with the SR_VCF_PATH and LR_VCF_PATH columns pointing to the generated VCFs.

### 3. Run Ensemble Workflow

```bash
# Generate ensemble VCFs only
dy-r produce_ensemble_vcf -p -k -j 10 \
  --config aligners=['ont'] dedupers=['dppl'] snv_callers=['ensemble']

# Generate ensemble VCFs + concordance
dy-r produce_ensemble_concordances -p -k -j 10 \
  --config aligners=['ont'] dedupers=['dppl'] snv_callers=['ensemble']
```

## Ensemble Modes

The workflow supports two modes (configured in `config/global.yaml` or via command line):

### Mode A (Conservative)
- Maximizes F1 score
- Only rescues high-quality indels from long-read platform
- Recommended for clinical applications

```yaml
hyb_ensemble:
  mode: "A"
  thresholds:
    A:
      ont_qual_min_snv: 60
      ont_qual_min_indel: 80
      allow_ont_snv: false
```

### Mode D (Sensitive)
- Maximizes sensitivity
- Rescues both SNVs and indels from long-read platform
- Recommended for research applications

```yaml
hyb_ensemble:
  mode: "D"
  thresholds:
    D:
      ont_qual_min_snv: 30
      ont_qual_min_indel: 50
      allow_ont_snv: true
```

## Output Structure

Ensemble VCFs follow the standard daylily path convention:

```
results/day/{genome_build}/{sample}/align/{alnr}/{ddup}/snv/ensemble/
├── {sample}.{alnr}.{ddup}.ensemble.snv.sort.vcf.gz
├── {sample}.{alnr}.{ddup}.ensemble.snv.sort.vcf.gz.tbi
├── log/
│   ├── {sample}.{alnr}.{ddup}.norm.log
│   ├── {sample}.{alnr}.{ddup}.rescue.log
│   ├── {sample}.{alnr}.{ddup}.merge.log
│   └── {sample}.{alnr}.{ddup}.sort.log
└── tmp/
    ├── sr.norm.vcf.gz
    ├── lr.norm.vcf.gz
    └── rescue_regions.bed
```

Where `{alnr}` is the long-read aligner (ont, pb, or sentmm2).

## Integration with Concordance

The ensemble VCF can be used with the standard concordance workflow:

```bash
dy-r produce_snv_concordances -p -k -j 10 \
  --config aligners=['ont'] dedupers=['dppl'] snv_callers=['ensemble']
```

This will generate concordance reports at:
```
results/day/{genome_build}/{sample}/align/ont/dppl/snv/ensemble/concordance/
```

