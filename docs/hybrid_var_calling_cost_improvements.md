# Hybrid Variant Calling Cost Improvements

Date: 2026-06-07

## Scope

This note records the benchmark-based cost comparison for the hyb-only hybrid
variant-calling changes that were tested on the two SMN/SMA-positive samples
(`NA00232`, `NA09677`) using 20x Illumina data plus ONT chip1+chip2 data.

It also records the follow-up ILMN-only 20x dry-run shape used to inspect the
short-read alignment, doppelmark dedup, Sentieon DNAscope, and BWA-MEM2 aligner
cost surface before launching live work.

## Benchmark Method

Use the collected benchmark reports with the authoritative `sample` column:

```text
results/day/hg38_broad/reports/benchmarks_summary.tsv
```

Aggregation rules:

| Metric | Calculation |
|---|---|
| Task wall time | `sum(s)` |
| Observed CPU time | `sum(cpu_time)` |
| Allocated vCPU-hours | `sum(s * snakemake_threads / 3600)` |
| Task cost | `sum(task_cost)` |

Do not substitute proxy AWS pricing when `task_cost` is present. Keep benchmark
task cost separate from cluster startup, Slurm pending/configuring time, and
controller wall clock unless broader accounting is explicitly requested.

## Compared Runs

| Run | Scope | Rows | Task wall-h | CPU-h | Alloc vCPU-h | Cost | Weighted avg threads | Max threads |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| NEW | 2 NAs, 20x ILMN, ONT chip1+2, optimized | 1465 | 44.62 | 305.21 | 1823.00 | $30.52 | 40.9 | 192 |
| OLD primary | Same 2 NAs, chip1+2 from old 4NA run, incomplete | 661 | 22.06 | 281.68 | 2640.62 | $48.55 | 119.7 | 192 |
| OLD secondary | Same 2 NAs, 20x ILMN, ONT chip1 only | 1461 | 37.38 | 269.31 | 2333.78 | $43.40 | 62.4 | 192 |

## Interpretation

| Comparison | Result |
|---|---|
| NEW vs OLD primary | NEW completed for $30.52; OLD had already burned $48.55 before terminal completion. NEW was already $18.03 cheaper, with 31% lower allocated vCPU-hours. |
| NEW vs OLD secondary | NEW used more ONT input than the chip1-only OLD run but still cost $12.88 less, was 29.7% cheaper, and used 21.9% fewer allocated vCPU-hours. |

## What Changed

The new run was cheaper primarily because resource allocation was tuned down for
the rules that were not efficiently using large reservations.

| Area | Older behavior | New behavior |
|---|---|---|
| Hybrid SNV stage | Many SNV-stage jobs reserved high thread counts even when observed CPU use was lower. | `sentdhiomr` SNV-stage jobs use lower thread tiers such as 96/32/4 depending on stage weight. |
| Segdup jobs | Segdup jobs could reserve far more CPU than they used. | Segdup is capped to smaller resource settings, including `segdup_threads: 8`. |
| SR markdup utility stage | Short-read helper stages could reserve whole-node-scale CPU. | SR markdup uses reduced settings such as `sr_markdup_threads: 64`. |
| Instance mix | OLD primary incurred meaningful cost on `r7i.48xlarge` and `r7i.metal-48xl`. | NEW mostly ran on `m7i.metal-48xl`, with little `r7i` cost. |
| 384-vCPU partition | The 384 partition was not observed in benchmarked task execution. | `bcl2fq-i384-nvme-test` was present in some Slurm partition candidate lists, but priced benchmark rows still showed `nproc=192`. |

## Instance Cost Evidence

NEW priced benchmark rows by instance:

| Instance type | nproc | Rows | Task cost |
|---|---:|---:|---:|
| `m7i.metal-48xl` | 192 | 1457 | $29.25 |
| `c7i.48xlarge` | 192 | 1 | $0.77 |
| `r7i.metal-48xl` | 192 | 2 | $0.50 |
| `r7i.8xlarge` | 32 | 3 | $0.00 |

OLD primary priced benchmark rows by instance:

| Instance type | nproc | Rows | Task wall-h | Alloc vCPU-h | Task cost |
|---|---:|---:|---:|---:|---:|
| `m7i.metal-48xl` | 192 | 350 | 12.74 | 1688.06 | $28.22 |
| `r7i.48xlarge` | 192 | 153 | 4.61 | 754.46 | $16.74 |
| `r7i.metal-48xl` | 192 | 27 | 0.87 | 103.30 | $2.07 |
| `c7i.48xlarge` | 192 | 129 | 3.85 | 94.80 | $1.52 |

## Follow-up ILMN 20x Dry-run

The follow-up short-read-only dry-run should use the four 20x ILMN NA samples:

- `NA00232`
- `NA09677`
- `NA03986`
- `NA05164`

The command shape is:

```bash
source dyoainit
dy-a slurm hg38_broad
dy-r produce_alignstats produce_sent_align produce_bwa2a_align produce_sentd_snv_vcf produce_dmd_dedup_cram \
  --config 'aligners=["sent","bwa2a"]' 'dedupers=["dmd"]' 'snv_callers=["sentd"]' \
  -j 200 -p -k -n
bash bin/util/benchmarks/collect_day_benchmark_data.sh hg38_broad
```

`produce_dmd_dedup_cram` is the current target for doppelmark/dmd dedup. The
deprecated `dedup_doppelmark` target and legacy `dppl` deduper spelling are not
the preferred command surface.

