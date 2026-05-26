# Workflow Command Matrix

This file is a compact operator reference for common Daylily target sets. For launch mechanics, tmux hygiene, and log-debug order, use [`docs/remote_test_execution.md`](docs/remote_test_execution.md).

## Workset Pattern

On a prepared headnode:

```bash
cd /fsx/analysis_results/ubuntu
day-clone -t <git-ref-or-tag> -d <workset-code>
cd /fsx/analysis_results/ubuntu/<workset-code>/daylily-omics-analysis

cp <samples.tsv> config/samples.tsv
cp <units.tsv> config/units.tsv

source dyoainit
dy-a slurm <genome-build>
```

Dry-run first, then launch the same target set without `-n`.

## Single-Platform Targets

| Data type | Build | Targets | Typical config |
| --- | --- | --- | --- |
| Illumina FASTQ | `hg38` | `produce_snv_concordances produce_alignstats` | `--config aligners=[sent] dedupers=[smd] snv_callers=[sentd]` |
| Complete Genomics/MGI FASTQ | `hg38` | `produce_alignstats produce_cgt7p_vcf produce_snv_concordances` | `--config aligners=[sentcg] dedupers=[smd] snv_callers=[cgt7p]` |
| ONT | `hg38` | `produce_sentdont_vcf produce_alignstats produce_snv_concordances` | usually pre-aligned long-read inputs |
| PacBio | `hg38` | `produce_sentdpb_vcf produce_alignstats produce_snv_concordances` | usually pre-aligned long-read inputs |
| Ultima | `hg38_broad` | `produce_sentdug_vcf produce_alignstats produce_snv_concordances` | Ultima-specific inputs |
| Roche | `hg38` | `produce_deep19_r_vcf produce_alignstats produce_snv_concordances` | Roche-specific inputs |

Example Complete Genomics command:

```bash
dy-r produce_alignstats produce_cgt7p_vcf produce_snv_concordances \
  -p -j 20 -k -T 1 \
  --retries 0 --rerun-incomplete --keep-incomplete \
  --config aligners=[sentcg] dedupers=[smd] snv_callers=[cgt7p]
```

## Hybrid Targets

| Workflow | Build | Targets |
| --- | --- | --- |
| Illumina+ONT modular | `hg38` | `produce_sentdhiom_vcf produce_alignstats produce_snv_concordances` |
| Ultima+ONT modular | `hg38_broad` | `produce_sentdhuom_vcf produce_alignstats produce_snv_concordances` |
| Illumina+ONT CLI | `hg38` | `produce_sentdhio_vcf produce_alignstats produce_snv_concordances` |
| Ultima+ONT CLI | `hg38_broad` | `produce_sentdhuo_vcf produce_alignstats produce_snv_concordances` |

## Test Data

Small bundled smoke data:

```text
.test_data/data/0.01xwgs_HG002_hg38.samples.tsv
.test_data/data/0.01xwgs_HG002_hg38.units.tsv
```

Platform stress-test tables are under:

```text
.test_data/data/stress_tests/
```

Historical AGBT hybrid examples are under:

```text
.test_data/data/agbt_2026/
```

## Operational Rules

- Run dry-runs with `-n` before launching real Slurm jobs.
- Use `--retries 0 --rerun-incomplete --keep-incomplete` when debugging failures that should not auto-retry.
- Use `--keep-temp` when temporary intermediates such as `sentcg.sort.bam` must remain after successful downstream completion.
- Do not kill unrelated Slurm jobs while debugging a workset.
