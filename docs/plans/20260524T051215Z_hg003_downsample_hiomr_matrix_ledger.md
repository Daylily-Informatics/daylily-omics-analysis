# HG003 Downsample HIOMR Matrix Ledger

## Objective

Run the requested all-chromosome HG003 downsample HIOMR matrix using DayOA `1.0.21`, the prepared Altair Run 3 HG003-a ILMN downsample FASTQs, and the prepared HG003 ONT downsample CRAMs.

## Gate 0: Current State

- Cluster: `hyb-hg003`, `us-west-2`, profile `lsmc`
- Headnode: `i-03f1a49bbc4e39d4b`
- DayOA version to use: `1.0.21`
- Source manifest root: `/fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z`
- Source data root: `/fsx/analysis_results/johnm/staged_sample_data/hg003_altair_ont_hiomr_matrix_20260523T141028Z`
- Current status: downsample input files and manifests are ready; no downsample HIOMR workdirs exist under `/fsx/analysis_results/ubuntu/`.
- Queue rule: dry-runs first; real runs queued no more than four workflows at a time.
- Every `dy-r` command must include `--max-jobs-per-second 8`.
- Do not patch live clones as final acceptance. If a code fix is needed, cut a new DayOA tag and relaunch from fresh clones.

## Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| GATE-000 | Inventory | Refresh cluster, FSx, queue, manifest roots, and repo state before launch. | SUCCESS | legitimate_safety_handling | Gate 0 | orchestrator | SSM launch verified `day-clone`, `tmux`, and `squeue`; tmux session `hg003_hiomr_ds_matrix_20260524` created with one window and one pane. | | Launch baseline captured. |
| DS-DATA-001 | Data | Verify all downsample ILMN FASTQs, ONT CRAMs, CRAIs, samples TSVs, and units TSVs exist. | SUCCESS | contract_test | Gate 1 | Agent A | All 10 dry-runs constructed DAGs with the expected downsample manifests and input files. | | Inputs accepted by DayOA `1.0.21`. |
| DS-DRYRUN-001 | 20x+10x | Dry-run `hg003a_altair3_hiomr_ilmn20x_ont10x_1021`. | SUCCESS | feature_implementation | Gate 2 | Agent B | `hg003a_altair3_hiomr_ilmn20x_ont10x_1021.dryrun.rc` = `0`. | | Dry-run passed. |
| DS-DRYRUN-002 | 20x+7x | Dry-run `hg003a_altair3_hiomr_ilmn20x_ont7x_1021`. | SUCCESS | feature_implementation | Gate 2 | Agent B | `hg003a_altair3_hiomr_ilmn20x_ont7x_1021.dryrun.rc` = `0`. | | Dry-run passed. |
| DS-DRYRUN-003 | 20x+5x | Dry-run `hg003a_altair3_hiomr_ilmn20x_ont5x_1021`. | SUCCESS | feature_implementation | Gate 2 | Agent B | `hg003a_altair3_hiomr_ilmn20x_ont5x_1021.dryrun.rc` = `0`. | | Dry-run passed. |
| DS-DRYRUN-004 | 15x+10x | Dry-run `hg003a_altair3_hiomr_ilmn15x_ont10x_1021`. | SUCCESS | feature_implementation | Gate 2 | Agent B | `hg003a_altair3_hiomr_ilmn15x_ont10x_1021.dryrun.rc` = `0`. | | Dry-run passed. |
| DS-DRYRUN-005 | 15x+7x | Dry-run `hg003a_altair3_hiomr_ilmn15x_ont7x_1021`. | SUCCESS | feature_implementation | Gate 2 | Agent B | `hg003a_altair3_hiomr_ilmn15x_ont7x_1021.dryrun.rc` = `0`. | | Dry-run passed. |
| DS-DRYRUN-006 | 15x+5x | Dry-run `hg003a_altair3_hiomr_ilmn15x_ont5x_1021`. | SUCCESS | feature_implementation | Gate 2 | Agent B | `hg003a_altair3_hiomr_ilmn15x_ont5x_1021.dryrun.rc` = `0`. | | Dry-run passed. |
| DS-DRYRUN-007 | 10x+10x | Dry-run `hg003a_altair3_hiomr_ilmn10x_ont10x_1021`. | SUCCESS | feature_implementation | Gate 2 | Agent B | `hg003a_altair3_hiomr_ilmn10x_ont10x_1021.dryrun.rc` = `0`. | | Dry-run passed. |
| DS-DRYRUN-008 | 7x+7x | Dry-run `hg003a_altair3_hiomr_ilmn7x_ont7x_1021`. | SUCCESS | feature_implementation | Gate 2 | Agent B | `hg003a_altair3_hiomr_ilmn7x_ont7x_1021.dryrun.rc` = `0`. | | Dry-run passed. |
| DS-DRYRUN-009 | 7x+5x | Dry-run `hg003a_altair3_hiomr_ilmn7x_ont5x_1021`. | SUCCESS | feature_implementation | Gate 2 | Agent B | `hg003a_altair3_hiomr_ilmn7x_ont5x_1021.dryrun.rc` = `0`. | | Dry-run passed. |
| DS-DRYRUN-010 | 5x+5x | Dry-run `hg003a_altair3_hiomr_ilmn5x_ont5x_1021`. | SUCCESS | feature_implementation | Gate 2 | Agent B | `hg003a_altair3_hiomr_ilmn5x_ont5x_1021.dryrun.rc` = `0`. | | Dry-run passed. |
| DS-RUN-001 | 20x+10x | Run `hg003a_altair3_hiomr_ilmn20x_ont10x_1021`. | IN_PROGRESS | feature_implementation | Gate 3 | Agent C | `real_start` at `2026-05-24T05:26:40Z`; Slurm jobs submitted. | | |
| DS-RUN-002 | 20x+7x | Run `hg003a_altair3_hiomr_ilmn20x_ont7x_1021`. | IN_PROGRESS | feature_implementation | Gate 3 | Agent C | `real_start` at `2026-05-24T05:26:40Z`; Slurm jobs submitted. | | |
| DS-RUN-003 | 20x+5x | Run `hg003a_altair3_hiomr_ilmn20x_ont5x_1021`. | IN_PROGRESS | feature_implementation | Gate 3 | Agent C | `real_start` at `2026-05-24T05:26:40Z`; Slurm jobs submitted. | | |
| DS-RUN-004 | 15x+10x | Run `hg003a_altair3_hiomr_ilmn15x_ont10x_1021`. | IN_PROGRESS | feature_implementation | Gate 3 | Agent C | `real_start` at `2026-05-24T05:26:40Z`; Slurm jobs submitted. | | |
| DS-RUN-005 | 15x+7x | Run `hg003a_altair3_hiomr_ilmn15x_ont7x_1021`. | OPEN | feature_implementation | Gate 3 | Agent C | Launch only after dry-run success. | | |
| DS-RUN-006 | 15x+5x | Run `hg003a_altair3_hiomr_ilmn15x_ont5x_1021`. | OPEN | feature_implementation | Gate 3 | Agent C | Launch only after dry-run success. | | |
| DS-RUN-007 | 10x+10x | Run `hg003a_altair3_hiomr_ilmn10x_ont10x_1021`. | OPEN | feature_implementation | Gate 3 | Agent C | Launch only after dry-run success. | | |
| DS-RUN-008 | 7x+7x | Run `hg003a_altair3_hiomr_ilmn7x_ont7x_1021`. | OPEN | feature_implementation | Gate 3 | Agent C | Launch only after dry-run success. | | |
| DS-RUN-009 | 7x+5x | Run `hg003a_altair3_hiomr_ilmn7x_ont5x_1021`. | OPEN | feature_implementation | Gate 3 | Agent C | Launch only after dry-run success. | | |
| DS-RUN-010 | 5x+5x | Run `hg003a_altair3_hiomr_ilmn5x_ont5x_1021`. | OPEN | feature_implementation | Gate 3 | Agent C | Launch only after dry-run success. | | |
| DS-VERIFY-001 | Verification | Verify success markers, alignstats TSVs, SNV VCF/indexes, HIOMR outputs, and concordance TSVs for all 10 runs. | OPEN | contract_test | Gate 4 | orchestrator | Must inspect each workdir. | | |
| DS-EXPORT-001 | Export | DRA-export completed downsample workdirs after matrix completion. | OPEN | feature_implementation | Gate 5 | Agent D | Use the same verified S3 tree under `derived/hyb-hg003/analysis_results/`. | | |
| DS-REPORT-001 | Report | Update `hg003_hybrid_complete.md` from planned/in-progress to completed downsample stats. | OPEN | feature_implementation | Gate 6 | Agent D | Report should include exported S3 locations and stats for each matrix cell. | | |

## Launch Template

For every workdir:

```bash
cd /fsx/analysis_results/ubuntu
day-clone -t 1.0.21 -d <workdir>
cd /fsx/analysis_results/ubuntu/<workdir>/daylily-omics-analysis
mkdir -p config
cp /fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z/<manifest>_samples.tsv config/samples.tsv
cp /fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z/<manifest>_units.tsv config/units.tsv
source dyoainit
dy-a slurm hg38_broad
dy-r produce_alignstats produce_sentdhiomr_snv_vcf produce_snv_concordances --config 'dedupers=["dmd"]' -p -j 100 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8 -n
dy-r produce_alignstats produce_sentdhiomr_snv_vcf produce_snv_concordances --config 'dedupers=["dmd"]' -p -j 100 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8
```

## Acceptance

- All dry-runs return `0`.
- All real runs have `daylily.successful_run` and no `daylily.failed_run`.
- No more than four real downsample workflows run concurrently.
- Every completed workdir has alignstats and GIAB concordance TSVs.
- The report is updated with final downsample stats and exported S3 locations.
