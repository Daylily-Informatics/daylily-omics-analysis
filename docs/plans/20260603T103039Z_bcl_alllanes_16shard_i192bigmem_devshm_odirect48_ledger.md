# BCL Convert All-Lanes 16-Shard Ledger

Created: `2026-06-03T10:30:39Z`

## Objective

Run the full `20260514_LH01106_0009_B23TVLGLT4` flowcell through DayOA BCL Convert with all lanes enabled, `16` tile shards per lane, `/dev/shm` staging, O_DIRECT output enabled, and `dy-r ... -j 300`.

## Gate 0 Inventory

| Field | Value |
|---|---|
| Cluster | `dyec0602bcl` |
| Region | `us-west-2` |
| Headnode | `i-0c36c39770c533c8e` |
| Headnode hostname | `ip-10-0-0-235` |
| AWS profile | `lsmc` |
| Run directory | `/fsx/run_dir_mounts/20260514_LH01106_0009_B23TVLGLT4` |
| Sample sheet | `/fsx/run_dir_mounts/20260514_LH01106_0009_B23TVLGLT4/SampleSheet.csv` |
| Lanes observed | `L001,L002,L003,L004,L005,L006,L007,L008` |
| `/fsx` available | `6122330521600` bytes |
| Prior L003 output size | `601951490190` bytes |
| Estimated 8-lane output | `~4.8T` |
| Destination | `/fsx/run_dir_mounts/20260514_LH01106_0009_B23TVLGLT4/fasts_from_bclconvert_alllanes_16shard_i192bigmem_devshm_odirect48_20260603T103039Z` |

## Execution Contract

| Setting | Value |
|---|---|
| Wrapper | `dy-r` only |
| Target | `produce_bclconvert_fastqs` |
| Jobs | `-j 300` |
| Retries | `-T 0` |
| Partition | `i192bigmem` |
| Tile shards | `16` per lane |
| Lane filter | empty, all lanes |
| Shard threads | `48` |
| Shard memory | `500000 MB` |
| Slurm exclusive | empty |
| Staging root | `/dev/shm/dayoa_bclconvert` |
| TMPDIR | `/dev/shm/dayoa_bclconvert_tmp` |
| Scratch minimum | `100000000000` bytes |
| O_DIRECT | `shared_thread_odirect_output: true` |
| Merge tile FASTQs | `false` |
| Merge lane FASTQs | `false` |

## Status Ledger

| Row | Status | Evidence |
|---|---|---|
| Gate 0 `/fsx` space check | `PASS` | `/fsx` available `6122330521600` bytes |
| Gate 0 run-dir check | `PASS` | all `L001`-`L008` directories and `SampleSheet.csv` present |
| Local DayOA tests for default/profile changes | `PASS` | `python -m pytest tests/test_bclconvert_multiqc.py -q`: `13 passed` |
| Fresh headnode workset | `PASS` | `/fsx/analysis_results/dyec0602bcl/bcl_alllanes_16shard_i192bigmem_devshm_odirect48_20260603T103039Z/daylily-omics-analysis` at `ddb3db6` |
| Config written | `PASS` | `config/bclconvert_alllanes_16shard_i192bigmem_devshm_odirect48_20260603T103039Z.yaml` |
| DayOA init retry with explicit license | `PASS` | `SENTIEON_LICENSE=/fsx/references/runtime_assets/cached_envs/Life_Sciences_Manufacturing_Corporation_eval.lic` after initial stale `x.lic` config blocker |
| Headnode Daylily global license config | `PASS` | corrected `~/.config/daylily/daylily_cli_global.yaml` from missing `x.lic` to existing eval license; timestamped backup preserved |
| Dry-run | `PASS` | `RC=0`; `128` `run_bclconvert_tile_shard`, `8` `merge_bclconvert_tile_shards`, `0` `run_bclconvert_lane`; `16` shards each for `L001`-`L008` |
| Live run initial attempt | `FAILED` | `RC=1`; no compute jobs submitted; `PermissionError` creating new DRA output dir under root-owned run dir |
| DRA output dir precreate | `PASS` | `sudo mkdir -p` and `sudo chown ubuntu:ubuntu` for the new empty destination only |
| Live run retry 1 | `FAILED` | `RC=1`; no compute jobs submitted; `bclconvert_validate_inputs` failed because all-lane SampleSheet IDs were absent from default one-row `samples.tsv` |
| All-lane samples.tsv | `PASS` | wrote `42` sample rows: default `ANA0-HG002` plus `41` BCLConvert SampleSheet IDs; previous file backed up as `config/samples.tsv.before_alllanes_20260603T103039Z` |
| Live run retry 2 | `FAILED` | `RC=1`; no compute jobs submitted; stale Snakemake lock after prior failed local attempts |
| Workdir unlock | `PASS` | `dy-r --unlock --configfile ...`, `RC=0`; no same-workset controller process before unlock |
| Live run retry 3 | `SUBMITTED` | same `dy-r` command; `128` `i192bigmem` shard jobs submitted; snapshot: `4 CONFIGURING`, `124 PENDING`; log `live_bclconvert_alllanes_16shard_retry3_20260603T103039Z.log` |
| Acceptance | `PENDING` |  |

## Non-Intervention Boundary

Do not cancel, requeue, drain/resume, restart Slurm services, or alter partitions while this run is pending or running unless explicitly approved in the current thread.
