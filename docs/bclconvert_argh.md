# BCL Convert ARGH Notes

Last updated: `2026-06-03`

## Successful L003 16-Shard Profile

This records the successful full-lane `L003` BCL Convert run on cluster `dyec0602bcl` for run directory `20260514_LH01106_0009_B23TVLGLT4`.

| Field | Value |
|---|---|
| Run ID | `fasts_from_bclconvert_l003_16shard_i192bigmem_devshm_odirect48_20260603T085644Z` |
| DayOA commit | `e3aefaf` |
| Target | `produce_bclconvert_fastqs` |
| Execution wrapper | `dy-r` in persistent `ubuntu` tmux |
| Lane | `L003` |
| Shards | `16` tile shards |
| Partition | `i192bigmem` |
| Instance observed | `r7i.48xlarge` |
| Node observed | `i192bigmem-dy-all-1` |
| Threads per shard | `48` |
| Slurm exclusive | `""` |
| Memory per shard | `500000 MB` |
| Staging root | `/dev/shm/dayoa_bclconvert` |
| TMPDIR | `/dev/shm/dayoa_bclconvert_tmp` |
| Scratch minimum | `100000000000` bytes |
| O_DIRECT / ASIO | `shared_thread_odirect_output: true` |
| Parallel tiles | `8` |
| Conversion threads | `2` |
| Compression threads | `24` |
| Decompression threads | `8` |
| FASTQ gzip level | `1` |
| Merge tile FASTQs | `false` |
| Merge lane FASTQs | `false` |
| Barcode mismatches | `BarcodeMismatchesIndex1=0`, `BarcodeMismatchesIndex2=0` |

## Command Shape

```bash
dy-r produce_bclconvert_fastqs -p -k -j 10 -T 0 \
  --rerun-triggers mtime \
  --configfile config/bclconvert_l003_16shard_i192bigmem_devshm_odirect48_20260603T085644Z.yaml
```

## Output Acceptance

| Check | Result |
|---|---:|
| Live marker | `__LIVE_BCL16_48DEVSHM_RC__0` |
| Tile shards complete | `16/16` |
| Shard benchmark TSVs | `16/16` |
| FASTQs on DRA | `1344` |
| Tile done markers | `16` |
| Total done markers | `18` |
| DRA bytes | `601951490190` |
| S3 objects | `2111` |
| S3 FASTQs | `1344` |
| S3 bytes | `601947722894` |

## Benchmark Runtime And Cost

Values are from `benchmarks/run_bclconvert.L003.*.bench.tsv`.

| Metric | Value |
|---|---:|
| Shards | `16` |
| Sum wall seconds across shard jobs | `4931.1508 s` |
| Total vCPU seconds | `236695.2384` |
| Total vCPU hours | `65.748677` |
| Total task cost | `1.387946` |
| Fastest shard | `0009_tiles0393-0441` |
| Fastest runtime | `239.8524 s` / `0:03:59` |
| Median shard runtime | `320.8147 s` |
| Slowest shard | `0008_tiles0344-0392` |
| Slowest runtime | `371.6868 s` / `0:06:11` |

## Copy Back To DRA

Copy-back time is measured from `moving BCL Convert output from scratch to final output directory` to `run_bclconvert_lane L003 finished` in each shard log.

| Metric | Value |
|---|---:|
| Shards with copy timing | `16` |
| Sum copy-back seconds | `1705 s` |
| Median copy-back seconds | `111 s` |
| Fastest copy-back | `66 s` on `0009_tiles0393-0441` |
| Slowest copy-back | `129 s` on `0002_tiles0050-0098` |
| Typical rsync payload per shard | `37.23G` to `37.98G` sent |
| Observed rsync speeds | `289.51M` to `568.02M bytes/sec` |

## Per-Shard Benchmark TSV Summary

| Shard | Runtime | vCPU h | Cost | Copy s | Sent | Speed |
|---|---:|---:|---:|---:|---:|---:|
| `0001_tiles0001-0049` | `319.2079s` | `4.256105` | `0.089846` | `122` | `37.36G` | `304.97M/s` |
| `0002_tiles0050-0098` | `328.1770s` | `4.375693` | `0.092370` | `129` | `37.49G` | `289.51M/s` |
| `0003_tiles0099-0147` | `336.0275s` | `4.480367` | `0.094580` | `108` | `37.35G` | `344.21M/s` |
| `0004_tiles0148-0196` | `328.2730s` | `4.376973` | `0.092397` | `96` | `37.65G` | `390.16M/s` |
| `0005_tiles0197-0245` | `264.1276s` | `3.521701` | `0.074343` | `101` | `37.56G` | `373.76M/s` |
| `0006_tiles0246-0294` | `336.1772s` | `4.482363` | `0.094622` | `126` | `37.66G` | `297.72M/s` |
| `0007_tiles0295-0343` | `316.9392s` | `4.225856` | `0.089207` | `123` | `37.23G` | `301.45M/s` |
| `0008_tiles0344-0392` | `371.6868s` | `4.955824` | `0.104617` | `75` | `37.40G` | `495.39M/s` |
| `0009_tiles0393-0441` | `239.8524s` | `3.198032` | `0.067510` | `66` | `37.77G` | `568.02M/s` |
| `0010_tiles0442-0490` | `267.2953s` | `3.563937` | `0.075234` | `89` | `37.76G` | `421.96M/s` |
| `0011_tiles0491-0539` | `322.4214s` | `4.298952` | `0.090750` | `125` | `37.98G` | `302.63M/s` |
| `0012_tiles0540-0588` | `274.4196s` | `3.658928` | `0.077240` | `96` | `37.73G` | `390.96M/s` |
| `0013_tiles0589-0637` | `271.5039s` | `3.620052` | `0.076419` | `114` | `37.51G` | `327.57M/s` |
| `0014_tiles0638-0686` | `331.4295s` | `4.419060` | `0.093286` | `117` | `37.92G` | `322.73M/s` |
| `0015_tiles0687-0735` | `326.0536s` | `4.347381` | `0.091773` | `122` | `37.84G` | `308.90M/s` |
| `0016_tiles0736-0784` | `297.5589s` | `3.967452` | `0.083752` | `96` | `37.88G` | `392.51M/s` |

## Default Profile Decision

Use the successful profile as the Slurm default for BCL Convert:

```yaml
bclconvert:
  partition: "i192bigmem"
  exclusive: ""
  threads: 48
  mem_mb: 500000
  tmpdir: "/dev/shm/dayoa_bclconvert_tmp"
  scratch_output_root: "/dev/shm/dayoa_bclconvert"
  scratch_available_bytes_min: 100000000000
  tile_shard_level: "16"
  tile_shard_threads: 48
  tile_shard_mem_mb: 500000
  tile_parallel_tiles: 8
  tile_conversion_threads: 2
  tile_compression_threads: 24
  tile_decompression_threads: 8
  shared_thread_odirect_output: true
  merge_lane_fastqs: false
  merge_tile_fastqs: false
```
