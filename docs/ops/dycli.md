# DY-CLI

The Daylily CLI provides a streamlined interface for running genomics workflows.

## Basic Workflow

```bash
# Initialize the dy-cli
. dyoainit --project <PROJECT>

# Activate execution environment and genome build
dy-a slurm hg38          # or: dy-a local hg38, dy-a slurm hg38_broad

# Run workflows using target names (tab-complete available)
dy-r produce_snv_concordances -p -k -j 20 -n   # dry-run
dy-r produce_snv_concordances -p -k -j 20      # execute

# Deactivate/reset environment
dy-d reset
```

## Common Targets

| Target | Description | Genome Build |
|--------|-------------|--------------|
| `produce_snv_concordances` | Illumina short-read SNV + concordance | hg38 |
| `produce_alignstats` | Alignment statistics | any |
| `produce_sentdont_vcf` | ONT long-read SNV calling | hg38 |
| `produce_sentdpb_vcf` | PacBio long-read SNV calling | hg38 |
| `produce_sentdug_vcf` | Ultima SNV calling | hg38_broad |
| `produce_sentdhio_vcf` | Hybrid Illumina+ONT CLI | hg38 |
| `produce_sentdhuo_vcf` | Hybrid Ultima+ONT CLI | hg38_broad |
| `produce_sentdhiom_vcf` | Hybrid Illumina+ONT Modular | hg38 |
| `produce_sentdhuom_vcf` | Hybrid Ultima+ONT Modular | hg38_broad |

## Tab Completion

- `dy-r <TAB>` - lists all available targets
- `dy-r target -<TAB>` - lists snakemake flags
- `dy-a <TAB>` - lists available profiles (local, slurm)


