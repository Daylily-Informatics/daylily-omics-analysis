# HG003 Altair ILMN + ONT HIOMR Full-Coverage Matrix Ledger

## Objective

Run an all-chromosome HG003 validation campaign on `hyb-hg003` using Altair-produced Illumina HG003 lane FASTQs from the staged sequencer data and the staged single-sample HG003 ONT dataset. Establish solo ILMN and solo ONT baselines with alignstats and SNV concordance, run full-coverage ILMN+ONT HIOMR, then run the requested downsampled HIOMR matrix.

## Gate 0: Inventory Freeze

- Ledger path: `docs/plans/20260523T135557Z_hg003_altair_ont_hiomr_fullcov_matrix_ledger.md`
- Repo path: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- Local branch/status at planning: `main...origin/main`; dirty file already present from prior validation ledger: `docs/plans/20260523T124908Z_hg003_hiomr_ont_1021_cluster_validation_ledger.md`
- Current release basis: `1.0.21` exists on `origin/main` and includes the HIOMR rule-env Python fix.
- Cluster: `hyb-hg003`, region `us-west-2`, profile `lsmc`, headnode `i-03f1a49bbc4e39d4b`.
- Access model: SSM only through `daylily-ec headnode connect` / `daylily_ec.aws.ssm.run_shell`; remote commands use `bash -l -c`.
- Current `/fsx` after cleanup and dry-run setup: `8.8T` total, `1.3T` used, `7.5T` available, `15%` used.
- `/fsx/analysis_results/ubuntu` was cleared after explicit approval in `CLEAN-001`; current immediate children are dry-run workdirs only:
  - `hg003a_altair3_hiomr_full_1021_dryrun`
  - `hg003a_altair3_ilmn_full_1021_dryrun`
  - `hg003a_altair3_ilmn_full_1021_dryrun_retry1`
  - `hg003a_altair3_ont_full_1021_dryrun`
- Campaign manifest directory: `/fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z`.
- Existing staged ONT/Altair manifest:
  - samples: `/fsx/analysis_results/johnm/staged_manifests/remote_stage_20260522T203135Z_hg003_concordance_fsx_1019/20260523T113105Z_samples.tsv`
  - units: `/fsx/analysis_results/johnm/staged_manifests/remote_stage_20260522T203135Z_hg003_concordance_fsx_1019/20260523T113105Z_units.tsv`
  - sample/unit observed: `HG003-a`, run `20260514-LH01106-0009-B23TVLGLT4`, experiment `20260514-ILMN-Altair-Run-3`.
  - ILMN fields contain eight comma-separated lane FASTQs for R1 and eight matching lane FASTQs for R2.
  - ONT CRAM: `/fsx/staging/staged_sample_data/remote_stage_20260522T203135Z/20260514-LH01106-0009-B23TVLGLT4_HG003-a-NOVASEQ-PF-gdna-20260514-ILMN-Altair-Run-3_HG003-a_0/HG003_30x.cleaned.cram`
- Older staged Altair Run 1 lane FASTQs also exist under `/fsx/staging/staged_sample_data/remote_stage_20260517T132907Z/...20260512-LH01106-0006-A23K3H2LT4...Altair-Run-1...`, including HG003-a, HG003-b, and HG003-c lanes. The campaign will start from the authoritative 20260523 manifest unless inventory proves a different HG003 Altair-tagged dataset is required.
- Existing comma-separated FASTQ support evidence:
  - `workflow/scripts/fastq_path_lists.py` parses CSV-style R1/R2 fields and validates equal cardinality.
  - `tests/test_comma_fastq_lists.py` covers parsing and the direct-alignment path contract.
  - `workflow/rules/prep_input_sample_files.smk` intentionally does not stage comma-separated lists; these inputs are consumed directly by alignment and sequence QC rules.
- Slurm submission throttle:
  - `config/day_profiles/slurm/templates/config.yaml` default is `max-jobs-per-second: 10`.
  - Requested 20% slower submission rate is `--max-jobs-per-second 8`, to be passed explicitly on every planned `dy-r` command.

## Execution Rules

- Use fresh `day-clone -t 1.0.21` workdirs unless a tagged bugfix release is required.
- Do not patch live clones as final acceptance. Diagnostic live-clone edits must become tagged source changes before a success row can close.
- Dry-run before each real run.
- Every `dy-r` command must include `--max-jobs-per-second 8`.
- Use all chromosomes. Do not apply the prior chr4/5 limiter.
- Preserve the staged source data and staged manifests; generate new campaign manifests under `/fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_<timestamp>/`.
- Prefer comma-separated lane FASTQs in `ILMN_R1_PATH` and `ILMN_R2_PATH`. If a target rule rejects comma-separated paths, mark `FQ-003` `ATTEMPTING_BUGFIX`, inspect the exact failing rule/tool, then either fix source and release a new tag or create explicitly concatenated representative R1/R2 FASTQs as a documented blocked/approved workaround. Do not silently substitute merged FASTQs.
- Queue downsampled HIOMR workflows no more than four at a time after the full-coverage baseline passes dry-run.

## Owners

- Orchestrator: Gate 0, cleanup approval, release/tag discipline, shared manifests, queue control, final acceptance.
- Agent A: Illumina lane FASTQ inventory, comma-separated input validation, ILMN solo baseline.
- Agent B: ONT solo baseline and ONT downsample manifests.
- Agent C: Full-coverage HIOMR and HIOMR source bugfix loop.
- Agent D: Downsample matrix queueing, status rollup, output verification.

## Ledger

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| CLEAN-001 | FSx cleanup | If needed, delete `/fsx/analysis_results/ubuntu/*` before the campaign. | SUCCESS | legitimate_safety_handling | Gate 1 | orchestrator | User gave explicit approval with `APPROVE DELETE /fsx/analysis_results/ubuntu/*` and then `PLEASE IMPLEMENT THIS PLAN`; remote execution at `2026-05-23T14:01:52Z` cancelled Slurm jobs `496` and `493`, waited for an empty queue, deleted immediate children under `/fsx/analysis_results/ubuntu`, and verified no immediate child entries remained. | | Cleanup completed; parent directory preserved. |
| CLUSTER-001 | Cluster preflight | Verify headnode, login shell, `day-clone`, `tmux`, `squeue`, Slurm health, `/fsx` space, and current queue before launches. | SUCCESS | feature_implementation | Gate 1 | orchestrator | SSM refresh on `i-03f1a49bbc4e39d4b` returned `WHO=ubuntu`; `day-clone=/home/ubuntu/.local/bin/day-clone`, `tmux=/usr/bin/tmux`, `squeue=/opt/slurm/bin/squeue`; queue header only; `/fsx` `8.8T` total, `1.3T` used, `7.5T` available, `15%` used. | | Cluster ready for real launches. |
| DATA-001 | Source inventory | Identify the exact Altair HG003 ILMN dataset to use, confirm all lane FASTQs exist, and confirm the staged ONT CRAM exists. | SUCCESS | feature_implementation | Gate 2 | Agent A | Campaign manifests use `HG003-a` Altair Run 3 from `/fsx/analysis_results/johnm/staged_manifests/remote_stage_20260522T203135Z_hg003_concordance_fsx_1019/20260523T113105Z_units.tsv`; ONT CRAM `/fsx/staging/staged_sample_data/remote_stage_20260522T203135Z/20260514-LH01106-0009-B23TVLGLT4_HG003-a-NOVASEQ-PF-gdna-20260514-ILMN-Altair-Run-3_HG003-a_0/HG003_30x.cleaned.cram` exists and is `21471428852` bytes. | | Full-coverage source data selected. |
| DATA-002 | Pair validation | Validate R1/R2 lane counts, lane order, file existence, and first/last read-name pairing for every lane in the selected Altair HG003 dataset. | SUCCESS | contract_test | Gate 2 | Agent A | `/fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z/altair_run3_hg003a_lane_pair_validation.tsv` records 8 lane pairs, lanes `001` through `008`; all rows have `lane_match=true`, `read_count_match=true`, `first_read_match=true`, and `last_read_match=true`. Read counts by lane: `95566556`, `95402360`, `95178619`, `94474150`, `94614218`, `94424516`, `94754354`, `95024188`. | | Lane FASTQ pairing validated on FSx. |
| DATA-003 | Manifest generation | Create campaign samples/units manifests for full-coverage ILMN solo, ONT solo, full-coverage HIOMR, and all downsample combinations. | SUCCESS | feature_implementation | Gate 2 | orchestrator | Created `/fsx/analysis_results/johnm/staged_manifests/hg003_altair_ont_hiomr_matrix_20260523T141028Z/{full_ilmn,full_ont,full_hiomr}_{samples,units}.tsv`; `manifest_index.tsv` records the three full-coverage manifest pairs; `downsample_matrix.tsv` records the 10 requested combinations with `pending_downsample` status. | | Full-coverage manifests ready; physical downsample manifests still tracked under `DS-001`. |
| FQ-001 | CSV FASTQ dry-run | Dry-run ILMN alignment/SNV target with comma-separated `ILMN_R1_PATH` and `ILMN_R2_PATH`. | SUCCESS | contract_test | Gate 3 | Agent A | Initial ILMN dry-run `hg003a_altair3_ilmn_full_1021_dryrun` returned rc `1` because the command left `aligners=[]`, causing alias `produce_sentd_snv_vcf` to delegate to an empty `produce_sentD_vcf` input set. Retry `hg003a_altair3_ilmn_full_1021_dryrun_retry1` with `--config 'aligners=[\"sent\"]' 'dedupers=[\"na\"]'` returned rc `0` and constructed a 28-job DAG from the comma-separated lane FASTQs. | Missing explicit ILMN aligner config for the alias target, not CSV FASTQ rejection. | Use explicit `aligners=[\"sent\"]` and `dedupers=[\"na\"]` for ILMN solo. |
| FQ-002 | Raw FASTQ consumer check | Dry-run sequence QC / alignstats paths that consume raw FASTQ and confirm comma-separated paths do not force `pre_prep_raw_fq` staging. | SUCCESS | contract_test | Gate 3 | Agent A | Full HIOMR dry-run `hg003a_altair3_hiomr_full_1021_dryrun` returned rc `0` and constructed a 784-job DAG with comma-separated R1/R2 lane FASTQs. ILMN retry dry-run also returned rc `0`; no `pre_prep_raw_fq` comma-list failure occurred. | | Direct raw-FASTQ consumers accepted the comma-separated manifest path in DAG construction. |
| FQ-003 | Merge fallback decision | If comma-separated FASTQs fail in a required consumer, decide whether to fix source/tag or explicitly create merged representative R1/R2 FASTQs. | NO_LONGER_NEEDED | plan_amendment | Gate 3 | orchestrator | Both full-coverage ILMN retry and full-coverage HIOMR dry-runs accepted comma-separated R1/R2 paths. | | Merged FASTQs are not needed for full-coverage baseline execution; physical downsample generation may still create merged/downsampled FASTQs under `DS-001` for the coverage matrix. |
| ILMN-001 | ILMN solo baseline dry-run | Fresh clone dry-run for Altair HG003 ILMN solo with `produce_alignstats produce_sentd_snv_vcf produce_snv_concordances --max-jobs-per-second 8`. | SUCCESS | feature_implementation | Gate 4 | Agent A | `hg003a_altair3_ilmn_full_1021_dryrun_retry1` from fresh `day-clone -t 1.0.21` returned `/tmp/hg003a_altair3_ilmn_full_1021_dryrun_retry1.rc` = `__DRYRUN_RC__:0`; command included `--config 'aligners=[\"sent\"]' 'dedupers=[\"na\"]'` and `--max-jobs-per-second 8`. | | ILMN real run may launch with explicit aligner/deduper config. |
| ILMN-002 | ILMN solo baseline real run | Run Altair HG003 ILMN solo through alignstats and SNV concordance. | SUCCESS | feature_implementation | Gate 4 | Agent A | Fresh `day-clone -t 1.0.21` workdir `/fsx/analysis_results/ubuntu/hg003a_altair3_ilmn_full_1021`; tmux session `hg003a_altair3_ilmn_full_1021`; command included `--config 'aligners=[\"sent\"]' 'dedupers=[\"na\"]' --max-jobs-per-second 8`; controller rc file `/tmp/hg003a_altair3_ilmn_full_1021.rc` reports `__RUN_RC__:0`; `daylily.successful_run` exists. | | Completed successfully. |
| ONT-001 | ONT solo baseline dry-run | Fresh clone dry-run for staged HG003 ONT solo with `produce_alignstats produce_sentdont_snv_vcf produce_snv_concordances --max-jobs-per-second 8`. | SUCCESS | feature_implementation | Gate 4 | Agent B | `hg003a_altair3_ont_full_1021_dryrun` from fresh `day-clone -t 1.0.21` returned `/tmp/hg003a_altair3_ont_full_1021_dryrun.rc` = `__DRYRUN_RC__:0`; DAG had 21 jobs and command included `--max-jobs-per-second 8`. | | ONT real run may launch. |
| ONT-002 | ONT solo baseline real run | Run staged HG003 ONT solo through alignstats and SNV concordance. | SUCCESS | feature_implementation | Gate 4 | Agent B | Fresh `day-clone -t 1.0.21` workdir `/fsx/analysis_results/ubuntu/hg003a_altair3_ont_full_1021`; tmux session `hg003a_altair3_ont_full_1021_real`; command included `--max-jobs-per-second 8`; controller rc file `/tmp/hg003a_altair3_ont_full_1021_real.rc` reports `__RUN_RC__:0`; `daylily.successful_run` exists. | | Completed successfully. |
| HIOMR-001 | Full HIOMR dry-run | Fresh clone dry-run for full-coverage Altair ILMN plus staged ONT HIOMR across all chromosomes with `produce_alignstats produce_sentdhiomr_snv_vcf produce_snv_concordances --config dedupers=["dmd"] --max-jobs-per-second 8`. | SUCCESS | feature_implementation | Gate 5 | Agent C | `hg003a_altair3_hiomr_full_1021_dryrun` from fresh `day-clone -t 1.0.21` returned `/tmp/hg003a_altair3_hiomr_full_1021_dryrun.rc` = `__DRYRUN_RC__:0`; DAG had 784 jobs, used all-chromosome default `sentdhiomr` config, and command included `--config 'dedupers=[\"dmd\"]' --max-jobs-per-second 8`. | | Full HIOMR real run may launch. |
| HIOMR-002 | Full HIOMR real run | Run full-coverage Altair ILMN + staged ONT HIOMR through alignstats and SNV concordance. | SUCCESS | feature_implementation | Gate 5 | Agent C | Fresh `day-clone -t 1.0.21` workdir `/fsx/analysis_results/ubuntu/hg003a_altair3_hiomr_full_1021`; tmux session `hg003a_altair3_hiomr_full_1021_real`; command included `--config 'dedupers=[\"dmd\"]' --max-jobs-per-second 8`; controller rc file `/tmp/hg003a_altair3_hiomr_full_1021_real.rc` reports `__RUN_RC__:0`; `daylily.successful_run` exists. | | Completed successfully. |
| DS-001 | Downsample prep | Create or select CRAM/FASTQ inputs and manifests for ILMN/ONT coverage matrix: 20x+10x, 20x+7x, 20x+5x, 15x+10x, 15x+7x, 15x+5x, 10x+10x, 7x+7x, 7x+5x, 5x+5x. | SUCCESS | feature_implementation | Gate 6 | Agent D | Data output root `/fsx/analysis_results/johnm/staged_sample_data/hg003_altair_ont_hiomr_matrix_20260523T141028Z`; job/script root `/fsx/analysis_results/johnm/downsample_jobs/hg003_altair_ont_hiomr_matrix_20260523T141028Z`; metadata records ILMN seed `7`, ONT seed `33`, and 30x coverage basis. Corrected Slurm submission used `--comment daylily-global`: merge ILMN lanes `533`, downsample ONT CRAM `534`, downsample ILMN FASTQs after merge `535`, generate manifests after both branches `536`. Logs show merge ran `15:03:32`-`16:21:55` UTC, ONT downsample ran `15:03:32`-`15:05:51` UTC, ILMN downsample ran `16:21:55`-`19:47:54` UTC, manifest generation wrote 18 downsample manifest pairs at `19:47:54` UTC; all `.err` files are empty. `downsample_matrix.tsv` marks all 10 requested HIOMR combinations `ready`; output count is 27 files including merged FASTQs, 5 ILMN R1/R2 pairs plus validation TSVs, and 3 ONT CRAM/CRAI pairs plus validation TSVs. Earlier prep submissions `525`-`528` and `529`-`532` were cancelled because the cluster wrapper assigned `unknown-project` when the project was only present in `#SBATCH --comment`. | | Downsample inputs and manifests ready. |
| DS-002 | Downsample solo checks | Where possible, run solo alignstats and SNV concordance for the individual downsampled ILMN and ONT inputs needed by the matrix. | OPEN | feature_implementation | Gate 6 | Agent D | Queue no more than four workflows at a time; all `dy-r` commands include `--max-jobs-per-second 8`. | | |
| DS-003 | Downsample HIOMR matrix | Run all requested downsampled ILMN+ONT HIOMR combinations across all chromosomes. | OPEN | feature_implementation | Gate 6 | Agent D | Queue no more than four workflows at a time; all `dy-r` commands include `--max-jobs-per-second 8`. | | |
| BUGFIX-001 | Failure loop | For any failed dry-run or real run, preserve workdir/logs, mark owner row `ATTEMPTING_BUGFIX`, inspect Snakemake master log, rule log, Slurm logs, missing outputs, and release next tag before retrying as success. | OPEN | feature_implementation | Gate 7 | orchestrator | Applies to all live runs. | | |
| VERIFY-001 | Final verification | Verify terminal sentinels, no failed sentinels, alignstats TSVs, SNV VCF/indexes, concordance outputs, and HIOMR chunk/final outputs for every requested run. | OPEN | contract_test | Gate 8 | orchestrator | Final acceptance requires no `OPEN`, `IN_PROGRESS`, or `ATTEMPTING_BUGFIX` rows. | | |

## Planned Run Shapes

Baseline full-coverage solo ILMN:

```bash
dy-r produce_alignstats produce_sentd_snv_vcf produce_snv_concordances --config 'aligners=["sent"]' 'dedupers=["na"]' -p -j 100 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8 -n
dy-r produce_alignstats produce_sentd_snv_vcf produce_snv_concordances --config 'aligners=["sent"]' 'dedupers=["na"]' -p -j 100 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8
```

Baseline full-coverage solo ONT:

```bash
dy-r produce_alignstats produce_sentdont_snv_vcf produce_snv_concordances -p -j 5 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8 -n
dy-r produce_alignstats produce_sentdont_snv_vcf produce_snv_concordances -p -j 5 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8
```

Full-coverage HIOMR:

```bash
dy-r produce_alignstats produce_sentdhiomr_snv_vcf produce_snv_concordances --config 'dedupers=["dmd"]' -p -j 100 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8 -n
dy-r produce_alignstats produce_sentdhiomr_snv_vcf produce_snv_concordances --config 'dedupers=["dmd"]' -p -j 100 -k -T 0 --rerun-triggers mtime --max-jobs-per-second 8
```

Downsampled HIOMR matrix:

| ILMN | ONT | Status |
|---|---:|---|
| 20x | 10x | OPEN |
| 20x | 7x | OPEN |
| 20x | 5x | OPEN |
| 15x | 10x | OPEN |
| 15x | 7x | OPEN |
| 15x | 5x | OPEN |
| 10x | 10x | OPEN |
| 7x | 7x | OPEN |
| 7x | 5x | OPEN |
| 5x | 5x | OPEN |

## Acceptance

- All selected source files and generated manifests are recorded with exact paths.
- The comma-separated lane FASTQ behavior is proven by dry-run and, if accepted by the workflow, by the full ILMN/HIOMR real runs.
- Solo ILMN, solo ONT, full HIOMR, and all requested downsampled HIOMR combinations finish with `daylily.successful_run` and no `daylily.failed_run`.
- Required outputs exist for every run: alignstats MultiQC TSVs, SNV VCF/indexes, and SNV concordance outputs. HIOMR runs also require all requested chromosome chunk/final outputs.
- Slurm submission throttle is 20% slower than the profile default on every run: `--max-jobs-per-second 8`.
- Ledger rows are terminal before final acceptance.
