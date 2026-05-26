# Directory And File Scheme

Daylily writes analysis outputs under the analysis clone. The primary result root is build-scoped:

```text
results/day/<genome_build>/
```

Common genome builds are `hg38`, `hg38_broad`, and `b37`.

## Top-Level Result Layout

```text
results/day/<build>/
├── <sample>/                         # per-sample analysis products
├── other_reports/                    # aggregate TSVs and MultiQC-compatible reports
└── reports/                          # final reports and benchmark summaries
```

Important aggregate outputs:

| File | Meaning |
| --- | --- |
| `results/day/<build>/other_reports/alignstats_combo_mqc.tsv` | Combined alignment statistics. |
| `results/day/<build>/other_reports/giab_concordance_mqc.tsv` | Combined GIAB/RTG concordance table. |
| `results/day/<build>/reports/benchmarks_summary.tsv` | Per-rule runtime/resource/cost benchmark summary. |

## Per-Sample Layout

The common short-read naming pattern is:

```text
results/day/<build>/<sample>/align/<aligner>/<deduper>/snv/<caller>/
```

Examples:

```text
results/day/hg38/HG003/align/sent/smd/snv/sentd/
results/day/hg38/HG003/align/sentcg/smd/snv/cgt7p/
results/day/hg38_broad/HG003/align/ug/smd/snv/sentdug/
```

Alignment-level outputs live under:

```text
results/day/<build>/<sample>/align/<aligner>/
```

Deduplicated outputs live under:

```text
results/day/<build>/<sample>/align/<aligner>/<deduper>/
```

SNV outputs live under:

```text
results/day/<build>/<sample>/align/<aligner>/<deduper>/snv/<caller>/
```

Concordance outputs live under:

```text
results/day/<build>/<sample>/align/<aligner>/<deduper>/snv/<caller>/concordance/
```

## Logs

| Location | Use |
| --- | --- |
| `.snakemake/log/*.snakemake.log` | Master workflow log; read first. |
| `logs/slurm/<rule>/*.{out,err}` | Slurm executor stdout/stderr. |
| `results/day/<build>/<sample>/.../logs/` | Stable rule-specific logs. |
| `day_cmd.log` | `dy-r` command history. |

When rules are retried or relaunched, Slurm job IDs can change. Use file modification time to find the current per-rule logs.

## Temp Outputs

Some intermediate files are declared as Snakemake `temp()` outputs and can be removed after successful downstream completion. For example, the Complete Genomics `sentcg.sort.bam` is an alignment intermediate; the durable downstream products are the `smd` CRAM/CRAI and `cgt7p` VCF/TBI.

Use `--keep-temp` through `dy-r` when a diagnostic run needs these temporary intermediates retained.
