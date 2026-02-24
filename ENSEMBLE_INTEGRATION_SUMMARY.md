# Ensemble Workflow Integration Summary

## Overview

The `hyb_ensemble_multi_platform.smk` workflow has been successfully integrated with the existing daylily concordance workflow. The ensemble workflow now follows the same conventions as other SNV callers like `sentdhio`, `sentdhuo`, `deep19`, etc.

## Changes Made

### 1. **Output Path Alignment** ✅

The ensemble workflow now outputs VCFs to the standard daylily path:
```
results/day/{genome_build}/{sample}/align/{alnr}/{ddup}/snv/ensemble/{sample}.{alnr}.{ddup}.ensemble.snv.sort.vcf.gz
```

Where:
- `{genome_build}`: hg38, hg38_broad, or b37
- `{sample}`: Sample name from samples.tsv
- `{alnr}`: Long-read aligner (ont, pb, or sentmm2)
- `{ddup}`: Deduplication method (dppl, dppl_sent, etc.)

### 2. **Input VCF Sources from units.tsv** ✅

The workflow now reads VCF paths from `units.tsv` instead of hardcoded config:

**New columns added to units.tsv:**
- `SR_VCF_PATH`: Path to short-read VCF (supports `{sample}` placeholder)
- `LR_VCF_PATH`: Path to long-read VCF (supports `{sample}` placeholder)

**Example:**
```tsv
SR_VCF_PATH	LR_VCF_PATH
results/day/hg38/{sample}/align/bwa2a/dppl/snv/deep19/{sample}.bwa2a.dppl.deep19.snv.sort.vcf.gz	results/day/hg38/{sample}/align/ont/snv/sentdont/{sample}.ont.sentdont.snv.sort.vcf.gz
```

### 3. **Concordance Integration** ✅

The ensemble VCF is fully compatible with `produce_snv_concordances`:

```bash
dy-r produce_snv_concordances -p -k -j 10 \
  --config aligners=['ont'] dedupers=['dppl'] snv_callers=['ensemble']
```

Concordance outputs will be generated at:
```
results/day/{genome_build}/{sample}/align/{alnr}/{ddup}/snv/ensemble/concordance/concordance.done
```

### 4. **Wildcard Constraints** ✅

Added appropriate wildcard constraints:
- `alnr`: Constrained to `["ont", "pb", "sentmm2"]` (ALIGNERS_ENSEMBLE)
- Registered in `_SNV_CALLER_VALID_ALIGNERS` dictionary in `common.smk`

### 5. **Target Rules** ✅

Created two new target rules:

**`produce_ensemble_vcf`**: Generate ensemble VCFs only
```bash
dy-r produce_ensemble_vcf -p -k -j 10 \
  --config aligners=['ont'] dedupers=['dppl'] snv_callers=['ensemble']
```

**`produce_ensemble_concordances`**: Generate ensemble VCFs + concordance
```bash
dy-r produce_ensemble_concordances -p -k -j 10 \
  --config aligners=['ont'] dedupers=['dppl'] snv_callers=['ensemble']
```

## File Changes

### Modified Files

1. **workflow/rules/hyb_ensemble_multi_platform.smk**
   - Refactored to use units.tsv for VCF paths
   - Updated output paths to standard daylily convention
   - Added wildcard constraints
   - Created target rules
   - Improved logging and benchmarking

2. **workflow/rules/common.smk**
   - Added `"ensemble": ["ont", "pb", "sentmm2"]` to `_SNV_CALLER_VALID_ALIGNERS`

3. **workflow/schemas/units.schema.yaml**
   - Added `SR_VCF_PATH` and `LR_VCF_PATH` properties

### New Files

1. **.test_data/data/ensemble/README.md**
   - Comprehensive documentation for ensemble workflow
   - Usage examples
   - Configuration guide

2. **.test_data/data/ensemble/units.tsv**
   - Example units.tsv with SR_VCF_PATH and LR_VCF_PATH columns

3. **.test_data/data/ensemble/samples.tsv**
   - Example samples.tsv for ensemble workflow

## Workflow Structure

The ensemble workflow consists of 4 main rules:

1. **hyb_norm_vcfs**: Normalize input VCFs with bcftools
2. **hyb_rescue_regions**: Identify discordant regions between platforms
3. **hyb_ensemble_merge**: Merge shared variants + rescue long-read variants
4. **hyb_ensemble_sort**: Sort and finalize the ensemble VCF

## Configuration

The workflow supports two modes via `config/global.yaml`:

### Mode A (Conservative - Default)
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
```yaml
hyb_ensemble:
  mode: "D"
  thresholds:
    D:
      ont_qual_min_snv: 30
      ont_qual_min_indel: 50
      allow_ont_snv: true
```

## Usage Example

### Step 1: Generate Input VCFs

```bash
# Generate short-read VCF
dy-r produce_snv_concordances -p -k -j 10 \
  --config aligners=['bwa2a'] dedupers=['dppl'] snv_callers=['deep19']

# Generate long-read VCF
dy-r produce_sentdont_vcf -p -k -j 10
```

### Step 2: Configure units.tsv

Add SR_VCF_PATH and LR_VCF_PATH columns pointing to the generated VCFs.

### Step 3: Run Ensemble Workflow

```bash
# Generate ensemble VCFs + concordance
dy-r produce_ensemble_concordances -p -k -j 10 \
  --config aligners=['ont'] dedupers=['dppl'] snv_callers=['ensemble']
```

## Testing

To test the integration:

```bash
# Copy example config
cp .test_data/data/ensemble/samples.tsv config/samples.tsv
cp .test_data/data/ensemble/units.tsv config/units.tsv

# Dry run
dy-r produce_ensemble_vcf -p -k -j 2 \
  --config aligners=['ont'] dedupers=['dppl'] snv_callers=['ensemble'] -n
```

## Next Steps

1. Test the workflow with real data
2. Validate concordance integration
3. Add provenance INFO fields (currently stubbed out)
4. Consider adding multi-caller consensus within each platform
5. Add benchmarking and performance optimization

