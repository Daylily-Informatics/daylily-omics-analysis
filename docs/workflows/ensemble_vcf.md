# Ensemble VCF Workflow

## Overview

The ensemble VCF workflow combines variant calls from multiple sequencing platforms (short-read + long-read) using a consensus-based approach with quality-based rescue of discordant variants.

## Quick Start

### 1. Generate Input VCFs

First, generate VCFs from your short-read and long-read data using standard daylily workflows:

```bash
# Example: ILMN short-read + DeepVariant
dy-r produce_snv_concordances -p -k -j 10 \
  --config aligners=['bwa2a'] dedupers=['dppl'] snv_callers=['deep19']

# Example: ONT long-read + Sentieon
dy-r produce_sentdont_vcf -p -k -j 10
```

### 2. Configure units.tsv

Add two columns to your `config/units.tsv`:

| Column | Description | Example |
|--------|-------------|---------|
| `SR_VCF_PATH` | Path to short-read VCF | `results/day/hg38/{sample}/align/bwa2a/dppl/snv/deep19/{sample}.bwa2a.dppl.deep19.snv.sort.vcf.gz` |
| `LR_VCF_PATH` | Path to long-read VCF | `results/day/hg38/{sample}/align/ont/snv/sentdont/{sample}.ont.sentdont.snv.sort.vcf.gz` |

**Note:** Use `{sample}` as a placeholder for the sample name.

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

### Mode A: Conservative (Default)
- Maximizes F1 score
- Only rescues high-quality indels from long-read platform
- **Recommended for clinical applications**

```yaml
hyb_ensemble:
  mode: "A"
  thresholds:
    A:
      ont_qual_min_snv: 60
      ont_qual_min_indel: 80
      allow_ont_snv: false
```

### Mode D: Sensitive
- Maximizes sensitivity
- Rescues both SNVs and indels from long-read platform
- **Recommended for research applications**

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

Ensemble VCFs are generated at the standard daylily path:

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

Where:
- `{genome_build}`: hg38, hg38_broad, or b37
- `{sample}`: Sample name
- `{alnr}`: Long-read aligner (ont, pb, or sentmm2)
- `{ddup}`: Deduplication method (dppl, dppl_sent, etc.)

## Concordance Integration

The ensemble VCF is fully compatible with the standard concordance workflow:

```bash
dy-r produce_snv_concordances -p -k -j 10 \
  --config aligners=['ont'] dedupers=['dppl'] snv_callers=['ensemble']
```

Concordance reports will be generated at:
```
results/day/{genome_build}/{sample}/align/{alnr}/{ddup}/snv/ensemble/concordance/
```

## Supported Platform Combinations

| Short-Read Platform | Long-Read Platform | Aligner Value |
|---------------------|-------------------|---------------|
| Illumina | ONT | `ont` |
| Illumina | PacBio | `pb` or `sentmm2` |
| Ultima | ONT | `ont` |
| Ultima | PacBio | `pb` or `sentmm2` |
| Roche | ONT | `ont` |
| Roche | PacBio | `pb` or `sentmm2` |

## Example Configuration

See `.test_data/data/ensemble/` for complete example configuration files:
- `samples.tsv`: Example samples configuration
- `units.tsv`: Example units configuration with SR_VCF_PATH and LR_VCF_PATH
- `README.md`: Detailed usage guide

## Workflow Steps

1. **Normalization**: Both input VCFs are normalized with bcftools
2. **Rescue Region Identification**: Identifies regions where platforms disagree
3. **Ensemble Merge**: Combines shared variants + quality-filtered rescued variants
4. **Sorting & Finalization**: Sorts and indexes the final ensemble VCF

## Troubleshooting

### VCF Path Not Found
Ensure the paths in `SR_VCF_PATH` and `LR_VCF_PATH` are correct and use `{sample}` placeholder.

### No Ensemble Output
Check that:
- Input VCFs exist at the specified paths
- `aligners` config includes the long-read aligner (ont, pb, or sentmm2)
- `snv_callers` config includes 'ensemble'

### Concordance Not Running
Ensure:
- Sample is listed in `CONCORDANCE_SAMPLES` (has `CONCORDANCE_CONTROL_PATH` in samples.tsv)
- Using `produce_ensemble_concordances` target (not `produce_ensemble_vcf`)

## See Also

- [`docs/ops/dir_and_file_scheme.md`](../ops/dir_and_file_scheme.md)
- [`docs/ops/config.md`](../ops/config.md)
- [`docs/ops/dycli.md`](../ops/dycli.md)
