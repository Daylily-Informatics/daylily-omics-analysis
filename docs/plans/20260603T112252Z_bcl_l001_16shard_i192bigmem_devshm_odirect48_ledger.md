# L001 16-Shard BCL Convert Ledger

## Objective

Run lane `L001` from `/fsx/run_dir_mounts/20260514_LH01106_0009_B23TVLGLT4` using DayOA through `dy-r`, with 16 tile shards on `i192bigmem`, 48 threads per shard, O_DIRECT enabled, `/dev/shm` staging, and DRA-backed final output.

Final output:

`/fsx/run_dir_mounts/20260514_LH01106_0009_B23TVLGLT4/fasts_from_bclconvert_l001_16shard_i192bigmem_devshm_odirect48_20260603T112252Z`

## Failure Finding From Prior All-Lane Attempt

| Item | Evidence | State |
| --- | --- | --- |
| all-lane workset | `/fsx/analysis_results/dyec0602bcl/bcl_alllanes_16shard_i192bigmem_devshm_odirect48_20260603T103039Z/daylily-omics-analysis` | inspected |
| rule logs | `logs/run_bclconvert.L*.log` were `0` bytes | BCL shell block did not start |
| Slurm stderr | `logs/slurm/run_bclconvert_tile_shard/*.err` | 128 shard jobs failed during DAG rebuild |
| concrete error | `AttributeError: 'NoneType' object has no attribute 'keys'` in `rule.get_wildcards(targetfile)` | root cause candidate confirmed |
| cause | compute-side file targets had `BCL_TARGET_REQUESTED=false`; with `tile_shard_lanes: ""`, lane discovery was skipped and `BCL_TILE_SHARD_ROWS=[]` | fixed in source |

## Code Change

| File | Change | State |
| --- | --- | --- |
| `workflow/rules/bclconvert.smk` | add `BCL_REQUESTED_TARGETS`; rediscover lanes for configured BCL file targets when `tile_shard_lanes` is empty | implemented |
| `tests/test_bclconvert_multiqc.py` | add regression assertions for compute-side lane rediscovery contract | implemented |

Validation:

```text
python -m pytest tests/test_bclconvert_multiqc.py tests/test_slurm_profile.py
14 passed
```

## L001 Config

```yaml
bootstrap_bclconvert: true

bclconvert:
  run_dir: /fsx/run_dir_mounts/20260514_LH01106_0009_B23TVLGLT4
  sample_sheet: /fsx/run_dir_mounts/20260514_LH01106_0009_B23TVLGLT4/SampleSheet.csv
  output_root: /fsx/run_dir_mounts/20260514_LH01106_0009_B23TVLGLT4
  run_id: fasts_from_bclconvert_l001_16shard_i192bigmem_devshm_odirect48_20260603T112252Z

  partition: i192bigmem
  constraint: ""
  exclusive: ""
  threads: 48
  mem_mb: 500000

  tmpdir: /dev/shm/dayoa_bclconvert_tmp
  scratch_output_root: /dev/shm/dayoa_bclconvert
  scratch_available_bytes_min: 100000000000

  parallel_tiles: 8
  conversion_threads: 2
  compression_threads: 24
  decompression_threads: 8

  tile_shard_level: 16
  tile_shard_lanes: "1"
  tile_shard_tile_limit: 0
  tile_shard_tile_names: ""
  tile_shard_threads: 48
  tile_shard_mem_mb: 500000
  tile_parallel_tiles: 8
  tile_conversion_threads: 2
  tile_compression_threads: 24
  tile_decompression_threads: 8

  merge_lane_fastqs: false
  merge_tile_fastqs: false
  shared_thread_odirect_output: true
  fastq_gzip_compression_level: 1
  output_legacy_stats: true
  num_unknown_barcodes_reported: 1000
  strict_mode: false
  first_tile_only: false
  sampleproject_subdirectories: false
  keep_undetermined_fastqs: true
  barcode_mismatches_index1: 0
  barcode_mismatches_index2: 0
```

## Execution Rows

| Row | Agent | Action | Evidence | State |
| --- | --- | --- | --- | --- |
| 0 | Orchestrator | confirm `/fsx` capacity | `df -h /fsx`: `6.6T` size, `985G` used, `5.6T` available, `15%` | PASS |
| 1 | Repo/DayOA | patch source repo and focused tests | `14 passed` | PASS |
| 2 | Headnode | create fresh L001 workset and mirror patched files | `/fsx/analysis_results/dyec0602bcl/bcl_l001_16shard_i192bigmem_devshm_odirect48_20260603T112252Z/daylily-omics-analysis`; dirty files match source patch/config/ledger | PASS |
| 3 | Headnode | write L001 config and SampleSheet-derived `samples.tsv` | `config/samples.tsv`: 42 lines, 41 SampleSheet IDs plus header; destination empty | PASS |
| 4 | Runner | `dy-r ... -n -T 0` dry-run via tmux | `__DRY_L001_RC__0`; 16 `run_bclconvert_tile_shard` rules; 0 full-lane rules; 0 L002-L008 wildcards | PASS |
| 5 | Runner | live `dy-r ... -T 0` via tmux | submitted Slurm jobs `209-224` from `dayoa_bcl_l001_16shard_48devshm_20260603` | RUNNING |
| 6 | Monitor | record `squeue`, tmux tail, logs, benchmark state | first snapshot: jobs `209-212` `CONFIGURING`, jobs `213-224` `PENDING`; no rule logs/benchmarks yet | RUNNING |
| 7 | Acceptance | confirm 16 L001 shard outputs or terminal blocker | pending | PENDING |

## Live Snapshot 2026-06-03T11:32Z

| Check | Value |
| --- | --- |
| tmux session | `dayoa_bcl_l001_16shard_48devshm_20260603` |
| workset | `/fsx/analysis_results/dyec0602bcl/bcl_l001_16shard_i192bigmem_devshm_odirect48_20260603T112252Z/daylily-omics-analysis` |
| dry-run result | `__DRY_L001_RC__0` |
| live command | `dy-r produce_bclconvert_fastqs -p -k -j 300 -T 0 --rerun-triggers mtime --configfile config/bclconvert_l001_16shard_i192bigmem_devshm_odirect48_20260603T112252Z.yaml` |
| submitted jobs | `209-224` |
| first `squeue` state | `209-212 CONFIGURING`, `213 PENDING(Resources)`, `214-224 PENDING(Priority)` |
| output count | `done=0`, `bench=0`, `fastq_lists=0` |
| first Slurm stderr | none yet |

## DayOA Contract

Use persistent tmux session as `ubuntu`:

`dayoa_bcl_l001_16shard_48devshm_20260603`

Commands must be sent separately:

```bash
cd /fsx/analysis_results/dyec0602bcl/bcl_l001_16shard_i192bigmem_devshm_odirect48_20260603T112252Z/daylily-omics-analysis
source dyoainit
dy-a slurm hg38
dy-r produce_bclconvert_fastqs -p -k -j 300 -T 0 --rerun-triggers mtime --configfile config/bclconvert_l001_16shard_i192bigmem_devshm_odirect48_20260603T112252Z.yaml -n
dy-r produce_bclconvert_fastqs -p -k -j 300 -T 0 --rerun-triggers mtime --configfile config/bclconvert_l001_16shard_i192bigmem_devshm_odirect48_20260603T112252Z.yaml
```

## Boundaries

- Do not cancel or modify existing jobs.
- Do not invoke raw Snakemake.
- Do not change Slurm partitions, nodes, services, drains, resumes, or retries.
- Use `-T 0` for this and future BCL Convert runs unless explicitly changed.
