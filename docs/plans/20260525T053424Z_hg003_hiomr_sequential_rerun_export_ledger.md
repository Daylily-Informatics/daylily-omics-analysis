# HG003 HIOMR Sequential Rerun, Per-Run DRA Export, And Cleanup Ledger

## Objective

Recover from the filled `/fsx` downsample HIOMR matrix attempt by deleting the current experiment workdirs under `/fsx/analysis_results/ubuntu`, then rerun the HG003 Altair Run 3 + ONT downsample HIOMR matrix one experiment at a time with `-j 234`. After each successful run, DRA-export that workdir to the previously used S3 destination, verify the export, delete only that completed workdir from `/fsx/analysis_results/ubuntu`, and continue to the next experiment.

## Gate 0: Live Baseline

- Ledger path: `docs/plans/20260525T053424Z_hg003_hiomr_sequential_rerun_export_ledger.md`
- Local repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- Local git status at Gate 0: `main...origin/main`; existing dirty/untracked report and plan docs from this HG003 campaign remain present.
- Cluster: `hyb-hg003`
- AWS profile/region: `lsmc`, `us-west-2`
- Headnode: `i-03f1a49bbc4e39d4b`
- FSx filesystem: `fs-04fb08a9a0d8a6752`
- DayOA tag for reruns: `1.0.21`
- DRA/S3 export destination: `s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/analysis_results/`
- Staged manifest root: `/fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z`
- Staged sample-data root: `/fsx/analysis_results/johnm/staged_sample_data/hg003_altair_ont_hiomr_matrix_20260523T141028Z`
- Review log target after approval: `/fsx/analysis_results/johnm/review_logs/hg003_hiomr_sequential_20260525T053424Z/review.log`

### Read-Only Evidence

- `squeue -u ubuntu` is empty.
- `/fsx`: `8.8T` total, `8.7T` used, `16G` available, `100%` used.
- `/fsx` inodes: `444K` total, `316K` used, `128K` free, `72%` used.
- `/fsx/analysis_results/ubuntu` immediate children at Gate 0:
  - `_orchestrators`
  - `hg003a_altair3_hiomr_full_1021`
  - `hg003a_altair3_hiomr_full_1021_dryrun`
  - `hg003a_altair3_hiomr_ilmn10x_ont10x_1021`
  - `hg003a_altair3_hiomr_ilmn15x_ont10x_1021`
  - `hg003a_altair3_hiomr_ilmn15x_ont5x_1021`
  - `hg003a_altair3_hiomr_ilmn15x_ont7x_1021`
  - `hg003a_altair3_hiomr_ilmn20x_ont10x_1021`
  - `hg003a_altair3_hiomr_ilmn20x_ont5x_1021`
  - `hg003a_altair3_hiomr_ilmn20x_ont7x_1021`
  - `hg003a_altair3_hiomr_ilmn5x_ont5x_1021`
  - `hg003a_altair3_hiomr_ilmn7x_ont5x_1021`
  - `hg003a_altair3_hiomr_ilmn7x_ont7x_1021`
  - `hg003a_altair3_ilmn_full_1021`
  - `hg003a_altair3_ilmn_full_1021_dryrun`
  - `hg003a_altair3_ilmn_full_1021_dryrun_retry1`
  - `hg003a_altair3_ont_full_1021`
  - `hg003a_altair3_ont_full_1021_dryrun`
- Existing success/failure markers:
  - `hg003a_altair3_hiomr_full_1021`: success yes, failed no.
  - Downsample runs: no successful markers; failed markers exist for `20x+10x`, `20x+7x`, `15x+10x`, `10x+10x`, and `7x+7x`.
- Staged manifest count for `hiomr_*_*.tsv`: `20`.
- Staged sample-data root exists.
- Headnode IAM can run workflow commands but cannot call FSx DRA APIs directly: `fsx:DescribeDataRepositoryAssociations` returned `AccessDeniedException`. DRA export orchestration must therefore be performed from the local `lsmc` AWS profile, not purely from a headnode tmux script.

## Destructive Approval Gate

The requested deletion is destructive. Before live deletion, the required second approval must explicitly approve:

`DELETE /fsx/analysis_results/ubuntu/* on hyb-hg003`

Exact effect when approved:

- Cancel any replacement `ubuntu` Slurm jobs if present.
- Kill any DayOA/Snakemake controller processes under `ubuntu` if present.
- Delete every immediate child of `/fsx/analysis_results/ubuntu` with `find /fsx/analysis_results/ubuntu -maxdepth 1 -mindepth 1 -exec rm -rf -- {} +`.
- Preserve the parent directory `/fsx/analysis_results/ubuntu`.
- Preserve staged manifests and staged sample data under `/fsx/analysis_results/johnm/...`.
- Delete local FSx copies of already exported full-coverage workdirs, dry-run dirs, failed downsample dirs, incomplete downsample dirs, and `_orchestrators`.
- Do not delete any S3 objects.
- Do not delete the cluster.
- Immediately record `df -h /fsx` after deletion and block rerun launch if usable space is not recovered.

## Sequential Run Matrix

Each experiment will use the matching staged manifest pair:

- `hiomr_ilmn20x_ont10x`
- `hiomr_ilmn20x_ont7x`
- `hiomr_ilmn20x_ont5x`
- `hiomr_ilmn15x_ont10x`
- `hiomr_ilmn15x_ont7x`
- `hiomr_ilmn15x_ont5x`
- `hiomr_ilmn10x_ont10x`
- `hiomr_ilmn7x_ont7x`
- `hiomr_ilmn7x_ont5x`
- `hiomr_ilmn5x_ont5x`

Workdir names:

- `hg003a_altair3_hiomr_ilmn20x_ont10x_1021`
- `hg003a_altair3_hiomr_ilmn20x_ont7x_1021`
- `hg003a_altair3_hiomr_ilmn20x_ont5x_1021`
- `hg003a_altair3_hiomr_ilmn15x_ont10x_1021`
- `hg003a_altair3_hiomr_ilmn15x_ont7x_1021`
- `hg003a_altair3_hiomr_ilmn15x_ont5x_1021`
- `hg003a_altair3_hiomr_ilmn10x_ont10x_1021`
- `hg003a_altair3_hiomr_ilmn7x_ont7x_1021`
- `hg003a_altair3_hiomr_ilmn7x_ont5x_1021`
- `hg003a_altair3_hiomr_ilmn5x_ont5x_1021`

Command template:

```bash
cd /fsx/analysis_results/ubuntu
day-clone -t 1.0.21 -d <workdir>
cd /fsx/analysis_results/ubuntu/<workdir>/daylily-omics-analysis
mkdir -p config
cp /fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z/<manifest>_samples.tsv config/samples.tsv
cp /fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z/<manifest>_units.tsv config/units.tsv
source dyoainit
dy-a slurm hg38_broad
dy-r produce_alignstats produce_sentdhiomr_snv_vcf produce_snv_concordances --config 'dedupers=["dmd"]' -p -j 234 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8
```

## Per-Run Success, Export, And Cleanup Protocol

For each workdir:

1. Write a review-log event before clone, before launch, on observed Slurm status, on success/failure, before export, after export task completion, after export verification, before delete, and after `df -h /fsx`.
2. Run exactly one workflow at a time using `-j 234`.
3. Success requires `daylily.successful_run` and no `daylily.failed_run`.
4. On success, export only that workdir path through FSx DRA to `s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/analysis_results/<workdir>/`.
5. Verify export by FSx-vs-S3 relative path and byte-size manifest for that workdir.
6. Delete only the completed local workdir after successful export verification.
7. Record `df -h /fsx` after each deletion.
8. If a run fails, preserve the failed workdir and logs, inspect Snakemake master log first, then Slurm logs, write the diagnosis into the review log, and attempt one focused rerun when the failure is actionable without source-code changes.
9. If source-code changes are required, stop and report the required DayOA fix/tag before continuing.

## Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| GATE-000 | Inventory | Capture live queue, FSx usage, current workdirs, staged manifests, and export permission shape. | SUCCESS | legitimate_safety_handling | Gate 0 | orchestrator | SSM read-only inventory at `2026-05-25T05:34:18Z`; headnode FSx API preflight returned `AccessDeniedException`. | | Baseline captured. |
| DELETE-001 | Cleanup | Delete all immediate children of `/fsx/analysis_results/ubuntu` and verify reclaimed `/fsx` space. | BLOCKED | legitimate_safety_handling | Destructive approval gate | orchestrator | User requested deletion; repo guardrail requires second explicit approval after exact destructive effect is stated. | Destructive FSx deletion approval required. | Waiting for `DELETE /fsx/analysis_results/ubuntu/* on hyb-hg003` approval. |
| LOG-001 | Review log | Create clear review log for check-ins. | OPEN | feature_implementation | Gate 1 | orchestrator | Planned remote log: `/fsx/analysis_results/johnm/review_logs/hg003_hiomr_sequential_20260525T053424Z/review.log`. | | |
| DRA-001 | Export setup | Create/reuse local-profile DRA export association for `/analysis_results/ubuntu/` to prior S3 destination. | OPEN | feature_implementation | Gate 2 | Agent C | Headnode IAM cannot do FSx API; local `lsmc` profile required. | | |
| RUN-001 | 20x+10x | Run, export, verify, and delete `hg003a_altair3_hiomr_ilmn20x_ont10x_1021`. | OPEN | feature_implementation | Gate 3 | Agent A | | | |
| RUN-002 | 20x+7x | Run, export, verify, and delete `hg003a_altair3_hiomr_ilmn20x_ont7x_1021`. | OPEN | feature_implementation | Gate 3 | Agent A | | | |
| RUN-003 | 20x+5x | Run, export, verify, and delete `hg003a_altair3_hiomr_ilmn20x_ont5x_1021`. | OPEN | feature_implementation | Gate 3 | Agent A | | | |
| RUN-004 | 15x+10x | Run, export, verify, and delete `hg003a_altair3_hiomr_ilmn15x_ont10x_1021`. | OPEN | feature_implementation | Gate 3 | Agent A | | | |
| RUN-005 | 15x+7x | Run, export, verify, and delete `hg003a_altair3_hiomr_ilmn15x_ont7x_1021`. | OPEN | feature_implementation | Gate 3 | Agent A | | | |
| RUN-006 | 15x+5x | Run, export, verify, and delete `hg003a_altair3_hiomr_ilmn15x_ont5x_1021`. | OPEN | feature_implementation | Gate 3 | Agent A | | | |
| RUN-007 | 10x+10x | Run, export, verify, and delete `hg003a_altair3_hiomr_ilmn10x_ont10x_1021`. | OPEN | feature_implementation | Gate 3 | Agent A | | | |
| RUN-008 | 7x+7x | Run, export, verify, and delete `hg003a_altair3_hiomr_ilmn7x_ont7x_1021`. | OPEN | feature_implementation | Gate 3 | Agent A | | | |
| RUN-009 | 7x+5x | Run, export, verify, and delete `hg003a_altair3_hiomr_ilmn7x_ont5x_1021`. | OPEN | feature_implementation | Gate 3 | Agent A | | | |
| RUN-010 | 5x+5x | Run, export, verify, and delete `hg003a_altair3_hiomr_ilmn5x_ont5x_1021`. | OPEN | feature_implementation | Gate 3 | Agent A | | | |
| FINAL-001 | Final report | Summarize terminal run states, exported S3 paths, retained failed dirs if any, and final `/fsx` space. | OPEN | feature_implementation | Gate 4 | orchestrator | | | |

## Acceptance

- Deletion occurs only after second explicit approval.
- Post-delete `df -h /fsx` is recorded before the first rerun.
- At most one HIOMR workflow is active at any time.
- Every workflow invocation uses `-j 234`.
- Each successful workdir is DRA-exported to the prior S3 destination and verified by relative path and byte size before local deletion.
- Review log is clear enough to inspect progress without attaching to the tmux/session.
- Failed workdirs are preserved until diagnosed; no failed data is deleted as part of the success cleanup path.
