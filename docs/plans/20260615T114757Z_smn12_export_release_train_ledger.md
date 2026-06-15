# SMN12 Full-Depth Export And DayOA->DYEC Release Train Ledger

Date: 2026-06-15

## Objective

Export the completed full-depth ILMN chip1/2/4 SMN12 HiOMR results to S3, then commit and release the current DayOA changes, update DYEC to pin that DayOA release, and release DYEC.

## Scope

- DayOA repo: `/Users/jmajor/projects/lsmc/daylily-omics-analysis`
- DYEC repo: `/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster`
- Cluster: `dyecX4`
- AWS profile: `lsmc`
- Region: `us-west-2`
- Source analysis directory: `/fsx/analysis_results/dyecX4/smn12_full_ilmn_chip124_20260615T092300Z`
- Normalized export source: `/analysis_results/dyecX4/smn12_full_ilmn_chip124_20260615T092300Z/`
- Destination S3 URI: `s3://lsmc-ssf-sequencing-data/derived/analysis_results/hyb-only/dyecX4/smn12_full_ilmn_chip124_20260615T092300Z/`

## Gate 0: Inventory Freeze

- Ledger path: `docs/plans/20260615T114757Z_smn12_export_release_train_ledger.md`
- Export receipt/output directory: `docs/plans/20260615T114757Z_smn12_export_release_train/`
- DayOA branch/head: `jem-dev` at `42bcd877a1e27f087a3ce794d487505f4eddd4f0`, matching `origin/jem-dev`
- DYEC branch/head: `jem-dev` at `5d49b35a63c4b07ddd9ea443806a25e50ea430c0`, matching `origin/jem-dev`
- DayOA previous latest semver tag: `10.0.21`
- Planned DayOA release tag: `10.0.22`
- DYEC previous latest semver tag: `10.0.35`
- Planned DYEC release tag: `10.0.36`
- DayOA baseline dirty state: clean before ledger creation
- DYEC baseline dirty state: clean before DYEC pin edits
- DYEC DayOA pin baseline:
  - `pyproject.toml`: `daylily-omics-analysis @ git+https://github.com/lsmc-bio/daylily-omics-analysis.git@10.0.20`
  - `config/daylily_pipeline_command_catalog.yaml`: `default_ref`, `git_tag`, and `validated_version` entries still point at `10.0.20`
- Destination S3 preflight: prefix existed with 4 config objects and total size 68,443 bytes before live export; no full result tree was present in the tail summary.
- Export source/destination validation: DYEC `normalize_export_source_path` and `validate_export_destination_s3_uri` accepted the exact source and destination.

## Tracking Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| EXP-001 | DRA export | Export `smn12_full_ilmn_chip124_20260615T092300Z` from FSx to the matching S3 derived prefix without deleting source data. | SUCCESS | feature_implementation | Gate 5 | orchestrator | After approved detach of `dra-021b674814a92ea8f`, `dyec export --cluster-name dyecX4 ... --wait --timeout-seconds 7200` wrote `docs/plans/20260615T114757Z_smn12_export_release_train/fsx_export.yaml` with `status: success`, `task_id: task-07c35034d247459b6`, `task_lifecycle: SUCCEEDED`, and `detached: true`. S3 has 2,182 objects totaling 339,962,670,909 bytes. |  | Export completed; temporary export DRA `dra-0c522071163c37d65` detached with `DeleteDataInFileSystem: false`. |
| DAYOA-001 | DayOA release | Commit all DayOA new/changed/dirty files on `jem-dev`, push, annotate tag `10.0.22`, and push tag. | IN_PROGRESS | feature_implementation | Gate 5 | orchestrator | Export prerequisite complete; DayOA has new ledger and export receipt files. |  |  |
| DYEC-001 | DYEC pin update | Update DYEC DayOA pins from the prior release to DayOA `10.0.22`. | OPEN | config_or_startup_contract | Gate 2 | orchestrator | `pyproject.toml` and `config/daylily_pipeline_command_catalog.yaml` contain `10.0.20` pins. |  |  |
| DYEC-002 | DYEC release | Commit all DYEC new/changed/dirty files on `jem-dev`, push, annotate tag `10.0.36`, and push tag. | OPEN | feature_implementation | Gate 5 | orchestrator | DYEC remains clean before pin edits. |  |  |
| VERIFY-001 | Final verification | Verify export receipt, git clean state, pushed branch heads, and annotated tag objects for DayOA and DYEC. | OPEN | contract_test | Gate 5 | orchestrator | Export receipt and S3 count verified; release verification pending. |  |  |

## Live Log

- 2026-06-15T11:47:57Z: Created Gate 0 inventory and planned release tags.
- 2026-06-15T11:48:44Z: Started live `dyec export` with `--wait --timeout-seconds 7200`.
- 2026-06-15T11:48:46Z: Export failed during DRA creation. Receipt path: `docs/plans/20260615T114757Z_smn12_export_release_train/fsx_export.yaml`.
- 2026-06-15T11:49:00Z: Read-only FSx inventory showed 8 `AVAILABLE` DRAs on `fs-04960a3a07c091cf3`, including `/references/`, the fresh ILMN run mount used by this SMN12 run, older run mounts, and old control-data mounts.
- 2026-06-15T11:50:00Z: Destination S3 prefix still contained only 4 config objects totaling 68,443 bytes.
- 2026-06-15T11:51:28Z: Read-only headnode check showed no Slurm jobs and no active `dy-r`, `day_run`, `snakemake`, or `day-clone` processes. Existing tmux sessions are idle/persistent historical sessions.
- 2026-06-15T11:56:00Z: User approved detaching `dra-021b674814a92ea8f`.
- 2026-06-15T11:56:30Z: Pre-detach check showed no Slurm jobs and `dra-021b674814a92ea8f` still `AVAILABLE`.
- 2026-06-15T11:57:00Z: `dyec exports detach --association-id dra-021b674814a92ea8f --wait --timeout-seconds 900` completed with `Lifecycle: DELETED` and `DeleteDataInFileSystem: false`.
- 2026-06-15T11:58:28Z: Reran `dyec export` for the SMN12 full-depth result directory.
- 2026-06-15T12:01:35Z: Export task `task-07c35034d247459b6` started.
- 2026-06-15T12:09:09Z: Export task `task-07c35034d247459b6` reached `SUCCEEDED`.
- 2026-06-15T12:09:25Z: `dyec export` wrote success receipt with `detached: true`, `detach_lifecycle: DELETED`.
- 2026-06-15T12:10:00Z: Verification showed `task-07c35034d247459b6` had `TotalCount: 2178`, `SucceededCount: 2178`, `FailedCount: 0`; destination S3 prefix had 2,182 objects totaling 339,962,670,909 bytes.

## DRA Slot Cleanup Candidates

The completed SMN12 run used `/run_dir_mounts/ilmn-lh01121-b23ww2nlt4-fastq/`, so that association is not a preferred cleanup candidate even though no jobs are currently active.

Lower-risk candidates to free one DRA slot, pending explicit approval:

| Association ID | FSx path | S3 URI | Reason |
|---|---|---|---|
| `dra-021b674814a92ea8f` | `/control_data/ssf_derived/dyecX4/10.0.10/PR-evidence/input/20260609T193111Z/illumina_30x/NovaSeqX_WHGS_TruSeqPF_HG002-007/` | `s3://lsmc-ssf-sequencing-data/derived/dyecX4/10.0.10/PR-evidence/input/20260609T193111Z/illumina_30x/NovaSeqX_WHGS_TruSeqPF_HG002-007/` | Old 10.0.10 PR-evidence control-data mount; no active Slurm jobs or controller processes observed. |
| `dra-09a619392c7f2bdc0` | `/run_dir_mounts/602221-20260417_2346/` | `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/RUN602221/2026/602221-20260417_2346/` | Older run-mount; no active Slurm jobs or controller processes observed. |
| `dra-0c94f040d9917cdf4` | `/run_dir_mounts/20260513_ONT_HG003/` | `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/pca100/2026/20260513_ONT_HG003/` | Older ONT HG003 run-mount; no active Slurm jobs or controller processes observed. |

Candidate detach command shape, only after explicit approval:

```bash
AWS_PROFILE=lsmc dyec exports detach \
  --association-id <approved-association-id> \
  --region us-west-2 \
  --profile lsmc \
  --wait \
  --timeout-seconds 900
```
