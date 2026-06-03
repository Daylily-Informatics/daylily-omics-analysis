# Remaining Lanes BCL Convert Ledger

## Objective

After `L001` completes successfully, launch the not-yet-accepted remaining lanes `L002,L004,L005,L006,L007,L008` from `/fsx/run_dir_mounts/20260514_LH01106_0009_B23TVLGLT4` using DayOA through `dy-r`.

This ledger intentionally excludes `L003` because the accepted 16-shard L003 run already completed at:

`/fsx/run_dir_mounts/20260514_LH01106_0009_B23TVLGLT4/fasts_from_bclconvert_l003_16shard_i192bigmem_devshm_odirect48_20260603T085644Z`

Final output for this run:

`/fsx/run_dir_mounts/20260514_LH01106_0009_B23TVLGLT4/fasts_from_bclconvert_remaining_l002_l004_l008_16shard_i192bigmem_devshm_odirect48_20260603T113808Z`

## Gate

| Gate | Requirement | Current Evidence | State |
| --- | --- | --- | --- |
| G1 | L001 run reaches terminal success | failed shards `0002`, `0007`, `0012`, `0016` hit DRAGEN WatchDog `rc=134`; terminal success gate not met | BLOCKED |
| G2 | `/fsx` has capacity after L001 completes | `/fsx` had `4.9T` available at failure snapshot; accepted L003 output is `562G`; remaining 6-lane estimate is about `3.3T`, but launch blocked by G1 | BLOCKED |
| G3 | destination is absent or empty and writable | pending | PENDING |
| G4 | dry-run plans exactly 96 `run_bclconvert_tile_shard` jobs | pending | PENDING |

## Config

Saved config:

`docs/plans/20260603T113808Z_bcl_remaining_lanes_16shard_i192bigmem_devshm_odirect48_configs/bclconvert_remaining_l002_l004_l008_16shard_i192bigmem_devshm_odirect48_20260603T113808Z.yaml`

Key values:

| Key | Value |
| --- | --- |
| `tile_shard_lanes` | `"2,4,5,6,7,8"` |
| `tile_shard_level` | `16` |
| `expected shard jobs` | `96` |
| `partition` | `i192bigmem` |
| `threads` | `48` |
| `tile_shard_threads` | `48` |
| `tmpdir` | `/dev/shm/dayoa_bclconvert_tmp` |
| `scratch_output_root` | `/dev/shm/dayoa_bclconvert` |
| `shared_thread_odirect_output` | `true` |
| `merge_tile_fastqs` | `false` |
| `merge_lane_fastqs` | `false` |

## Execution Contract

Use a fresh workset and persistent tmux session as `ubuntu`:

| Item | Value |
| --- | --- |
| workset | `/fsx/analysis_results/dyec0602bcl/bcl_remaining_lanes_16shard_i192bigmem_devshm_odirect48_20260603T113808Z/daylily-omics-analysis` |
| tmux | `dayoa_bcl_remaining_lanes_16shard_48devshm_20260603` |
| config | `config/bclconvert_remaining_l002_l004_l008_16shard_i192bigmem_devshm_odirect48_20260603T113808Z.yaml` |

Commands, sent separately:

```bash
cd /fsx/analysis_results/dyec0602bcl/bcl_remaining_lanes_16shard_i192bigmem_devshm_odirect48_20260603T113808Z/daylily-omics-analysis
source dyoainit
dy-a slurm hg38
dy-r produce_bclconvert_fastqs -p -k -j 300 -T 0 --rerun-triggers mtime --configfile config/bclconvert_remaining_l002_l004_l008_16shard_i192bigmem_devshm_odirect48_20260603T113808Z.yaml -n
dy-r produce_bclconvert_fastqs -p -k -j 300 -T 0 --rerun-triggers mtime --configfile config/bclconvert_remaining_l002_l004_l008_16shard_i192bigmem_devshm_odirect48_20260603T113808Z.yaml
```

## Execution Rows

| Row | Action | Evidence | State |
| --- | --- | --- | --- |
| 0 | Wait for L001 terminal success | L001 failed with DRAGEN WatchDog `rc=134` on four shards | BLOCKED |
| 1 | Recheck `/fsx` free space and L001/L003 output sizes | `/fsx` `4.9T` available at failure snapshot; L001 partial output `237G`; L003 accepted output `562G` | BLOCKED |
| 2 | Prepare fresh workset and mirror current pushed branch/config | not run because G1 failed | BLOCKED |
| 3 | Generate SampleSheet-derived `config/samples.tsv` | not run because G1 failed | BLOCKED |
| 4 | Dry-run remaining lanes | not run because G1 failed | BLOCKED |
| 5 | Launch live run if G1-G4 pass | not launched | BLOCKED |
| 6 | Monitor Slurm and outputs | not launched | BLOCKED |

## Blocker 2026-06-03T12:07Z

Remaining-lanes launch was not attempted. L001 did not satisfy the success gate:

| Failed external job | Shard | Evidence |
| --- | --- | --- |
| `209` | `L001/0002_tiles0050-0098` | `DRAGEN WatchDog service has detected a fault`; scratch cleanup `rc=134` |
| `210` | `L001/0007_tiles0295-0343` | `DRAGEN WatchDog service has detected a fault`; scratch cleanup `rc=134` |
| `211` | `L001/0012_tiles0540-0588` | `DRAGEN WatchDog service has detected a fault`; scratch cleanup `rc=134` |
| `212` | `L001/0016_tiles0736-0784` | `DRAGEN WatchDog service has detected a fault`; scratch cleanup `rc=134` |

## Boundaries

- Do not cancel, requeue, drain/resume, or otherwise modify existing Slurm jobs.
- Do not invoke raw Snakemake.
- Do not launch if L001 fails.
- Do not launch if `/fsx` space is insufficient by the post-L001 estimate.
- Keep `-T 0`.
