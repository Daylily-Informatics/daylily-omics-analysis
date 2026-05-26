# HG003 Current Export And Downsample Planning Ledger

## Objective

Produce a shareable status report for the completed HG003 Altair ILMN + ONT full-coverage analyses, export the current `/fsx/analysis_results/ubuntu/` snapshot from `hyb-hg003` to S3 by FSx DRA, and create a separate execution ledger for the requested downsample HIOMR matrix.

## Gate 0: Inventory Freeze

- Ledger path: `docs/plans/20260524T051215Z_hg003_current_export_and_downsample_ledger.md`
- Report path: `hg003_hybrid_complete.md`
- Downsample ledger path: `docs/plans/20260524T051215Z_hg003_downsample_hiomr_matrix_ledger.md`
- Local repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- Local branch/status at start: `main...origin/main`; pre-existing dirty plan docs:
  - `docs/plans/20260523T124908Z_hg003_hiomr_ont_1021_cluster_validation_ledger.md`
  - `docs/plans/20260523T135557Z_hg003_altair_ont_hiomr_fullcov_matrix_ledger.md`
- Cluster: `hyb-hg003`
- AWS profile/region: `lsmc`, `us-west-2`
- Headnode: `i-03f1a49bbc4e39d4b`
- FSx filesystem: `fs-04fb08a9a0d8a6752`
- Current `/fsx`: `8.8T` total, `1.6T` used, `7.2T` available, `18%` used.
- Slurm queue: empty for `ubuntu`.
- Existing DRA associations on `fs-04fb08a9a0d8a6752`: only `/data/` to `s3://lsmc-dayoa-omics-analysis-us-west-2/data/`.
- Destination prefix before export: `s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/analysis_results/` had `0` objects and `0` bytes.

## Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| GATE-000 | Inventory | Refresh cluster, queue, FSx, completed workdirs, DRA overlap, and destination prefix before export. | SUCCESS | legitimate_safety_handling | Gate 0 | orchestrator | SSM read-only refresh showed empty queue and completed markers; `aws fsx describe-data-repository-associations` showed only `/data/`; `aws s3 ls .../analysis_results/ --summarize` showed zero objects. | | Baseline captured. |
| REPORT-001 | Report | Write `hg003_hybrid_complete.md` separating completed full-coverage results from downsample runs that are to be produced. | SUCCESS | feature_implementation | Gate 1 | Agent B | `hg003_hybrid_complete.md` created and updated with DRA task `task-07845dd08e72eec58`, DRA `dra-0b82228ada587f7ab`, manifest counts, and downsample launch state. | | Shareable report exists. |
| AMEND-001 | Export scope | Scope export to the three completed full-coverage workdirs after downsample workdirs began mutating under `/fsx/analysis_results/ubuntu/`. | SUCCESS | plan_amendment | Gate 2 | orchestrator | User asked to continue export and downsample runs concurrently; exporting the entire root would race against active downsample writes. Export task paths were limited to the three completed full-coverage workdirs. | | Current export is stable and complete for completed full-coverage results. |
| EXPORT-001 | DRA export | Create temporary output DRA for `/analysis_results/ubuntu/`, run `EXPORT_TO_REPOSITORY`, and export completed full-coverage workdirs to `s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/analysis_results/`. | SUCCESS | feature_implementation | Gate 2 | Agent C | Temporary DRA `dra-0b82228ada587f7ab`; export task `task-07845dd08e72eec58`; task status `SUCCEEDED`, `10463` total, `10463` succeeded, `0` failed. Paths exported: `hg003a_altair3_ilmn_full_1021`, `hg003a_altair3_ont_full_1021`, `hg003a_altair3_hiomr_full_1021`. DRA detached with `DeleteDataInFileSystem=False`; only `/data/` DRA remains. | | Export complete and temporary DRA removed. |
| VERIFY-001 | Export verification | Compare FSx and S3 manifests by relative path and byte size; require exact match. | SUCCESS | contract_test | Gate 3 | Agent C | Symlink-inclusive FSx manifest and S3 manifest matched: `9029` entries each, `42814922525` bytes each, `0` missing, `0` extra, `0` size mismatches. FSx manifest: `s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/export_manifests/20260524T051215Z/fsx_manifest.tsv`; S3 manifest: `s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/export_manifests/20260524T051215Z/s3_manifest.tsv`; verification summary: `s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/export_manifests/20260524T051215Z/verification_summary.json`. | | Verification complete. |
| DOWNSAMPLE-PLAN-001 | Downsample matrix | Create decision-complete downsample HIOMR matrix ledger and launch the requested matrix. | SUCCESS | feature_implementation | Gate 1 | Agent D | `docs/plans/20260524T051215Z_hg003_downsample_hiomr_matrix_ledger.md` created. Tmux session `hg003_hiomr_ds_matrix_20260524` launched; all 10 dry-runs returned rc `0`; first real batch of four workflows started. | | Matrix execution is in progress in remote tmux. |
| DELETE-001 | Cluster deletion | Do not delete the cluster after current export; cluster is needed for downsample HIOMR runs. | BLOCKED | legitimate_safety_handling | Destructive approval gate | orchestrator | User-approved plan explicitly says no cluster deletion until after downsample completion and separate explicit destructive-action approval. | Cluster still needed for downsample matrix. | Blocked pending downsample completion and separate approval. |

## Export Target

- FSx file system path: `/analysis_results/ubuntu/`
- Headnode path: `/fsx/analysis_results/ubuntu/`
- S3 destination: `s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/analysis_results/`
- Exported paths:
  - `/analysis_results/ubuntu/hg003a_altair3_ilmn_full_1021/`
  - `/analysis_results/ubuntu/hg003a_altair3_ont_full_1021/`
  - `/analysis_results/ubuntu/hg003a_altair3_hiomr_full_1021/`
- Manifest prefix: `s3://lsmc-ssf-sequencing-data/derived/hyb-hg003/export_manifests/20260524T051215Z/`

## Final Acceptance

- `REPORT-001`, `EXPORT-001`, and `VERIFY-001` are terminal `SUCCESS`.
- `DELETE-001` remains `BLOCKED` by design.
- The cluster must remain running after this task.
