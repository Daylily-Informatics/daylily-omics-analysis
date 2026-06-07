# 192 vs 384 Benchmark Comparison

Collector source files:
- `data/192_test/benchmarks_summary.tsv`
- `data/384_test/benchmarks_summary.tsv`

Note: global staging benchmark rows lacked the added sample column; this comparison normalizes them as `stage_supporting_data` and `workflow_staging`. Per-sample `prep_sentD_chunkdirs` rows had `NA` runtime metadata and zero task cost.

## Overall

| Run | Scope | Rows | Samples | Wall-h | CPU-h | Alloc vCPU-h | Cost | Wt threads | Max threads | Max RSS GiB | IO in GiB | IO out GiB |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 192_test | all | 45 | 4 | 4.33 | 76.98 | 536.98 | $8.69 | 124.02 | 192 | 440.51 | 273.66 | 366.00 |
| 192_test | sent_only | 40 | 4 | 4.33 | 76.98 | 536.98 | $8.69 | 124.03 | 192 | 440.51 | 273.66 | 366.00 |
| 192_test | global_non_sample | 5 | 1 | 0.00 | 0.00 | 0.00 | $0.00 | 1.04 | 2 | 0.02 | 0.00 | 0.00 |
| 384_test | all | 85 | 4 | 8.08 | 123.08 | 1404.58 | $14.04 | 173.94 | 384 | 458.86 | 509.56 | 571.91 |
| 384_test | sent_only | 40 | 4 | 3.60 | 67.01 | 449.34 | $4.46 | 124.69 | 192 | 437.49 | 342.32 | 373.73 |
| 384_test | bwa2a_only | 40 | 4 | 4.47 | 56.07 | 955.23 | $9.58 | 213.65 | 384 | 458.86 | 167.24 | 198.18 |
| 384_test | global_non_sample | 5 | 1 | 0.00 | 0.00 | 0.00 | $0.00 | 1.04 | 2 | 0.02 | 0.00 | 0.00 |

## Exact Rule Comparison

| Rule | 192 rows | 192 wall-h | 192 cost | 192 wt thr | 384 rows | 384 wall-h | 384 cost | 384 wt thr | Delta cost |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| alignstats_smmary_compile | 1 | 0.00 | $0.00 | 2.00 | 1 | 0.00 | $0.00 | 2.00 | $0.00 |
| alignstats_summary | 1 | 0.00 | $0.00 | 1.00 | 1 | 0.00 | $0.00 | 1.00 | $0.00 |
| bwa2a.alNsort |  |  |  |  | 4 | 1.75 | $6.77 | 384.00 |  |
| bwa2a.dmd.1-24.sentD_sort_index_chunk_vcf |  |  |  |  | 4 | 0.05 | $0.00 | 1.00 |  |
| bwa2a.dmd.alignstats |  |  |  |  | 4 | 0.48 | $0.44 | 96.00 |  |
| bwa2a.dmd.mrkdup |  |  |  |  | 4 | 0.55 | $1.08 | 192.00 |  |
| bwa2a.dmd.prep_sentD_chunkdirs |  |  |  |  | 4 | 0.00 | $0.00 | 0.00 |  |
| bwa2a.dmd.sentd.1-24 |  |  |  |  | 4 | 0.43 | $0.80 | 192.00 |  |
| bwa2a.dmd.sentd.concat.fofn |  |  |  |  | 4 | 0.00 | $0.00 | 1.00 |  |
| bwa2a.dmd.sentd.merge |  |  |  |  | 4 | 0.02 | $0.00 | 4.00 |  |
| bwa2a.na.alignstats |  |  |  |  | 4 | 0.48 | $0.45 | 96.00 |  |
| bwa2a.na.mrkdup |  |  |  |  | 4 | 0.72 | $0.04 | 4.00 |  |
| dirsetup | 1 | 0.00 | $0.00 | 1.00 | 1 | 0.00 | $0.00 | 1.00 | $0.00 |
| sent.alNsort | 4 | 1.00 | $3.22 | 192.00 | 4 | 0.86 | $1.65 | 192.00 | $-1.57 |
| sent.dmd.1-24.sentD_sort_index_chunk_vcf | 4 | 0.06 | $0.00 | 1.00 | 4 | 0.04 | $0.00 | 1.00 | $-0.00 |
| sent.dmd.alignstats | 4 | 0.71 | $1.03 | 96.00 | 4 | 0.48 | $0.43 | 96.00 | $-0.60 |
| sent.dmd.mrkdup | 4 | 0.58 | $1.88 | 192.00 | 4 | 0.59 | $1.13 | 192.00 | $-0.75 |
| sent.dmd.prep_sentD_chunkdirs | 4 | 0.00 | $0.00 | 0.00 | 4 | 0.00 | $0.00 | 0.00 | $0.00 |
| sent.dmd.sentd.1-24 | 4 | 0.49 | $1.42 | 192.00 | 4 | 0.39 | $0.75 | 192.00 | $-0.67 |
| sent.dmd.sentd.concat.fofn | 4 | 0.00 | $0.00 | 1.00 | 4 | 0.00 | $0.00 | 1.00 | $0.00 |
| sent.dmd.sentd.merge | 4 | 0.03 | $0.00 | 4.00 | 4 | 0.02 | $0.00 | 4.00 | $-0.00 |
| sent.na.alignstats | 4 | 0.71 | $1.11 | 96.00 | 4 | 0.48 | $0.47 | 96.00 | $-0.64 |
| sent.na.mrkdup | 4 | 0.75 | $0.04 | 4.00 | 4 | 0.73 | $0.04 | 4.00 | $-0.00 |
| stage_supporting_data | 1 | 0.00 | $0.00 | 1.00 | 1 | 0.00 | $0.00 | 1.00 | $0.00 |
| workflow_staging | 1 | 0.00 | $0.00 | 1.00 | 1 | 0.00 | $0.00 | 1.00 | $0.00 |

## Instance Cost By Rule

See `data/benchmark_rule_compare_192_vs_384.tsv` for per-rule instance-type cost breakdowns in `instances_192` and `instances_384`.
