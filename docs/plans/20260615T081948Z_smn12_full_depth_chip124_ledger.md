# Full-Depth 4NA SMN12 HiOMR Rerun And Sentieon Export Ledger

Created: 2026-06-15T08:19:48Z

## Objective

Run full-depth ILMN plus combined ONT chip1+chip2+chip4 HiOMR SMN12 caller workflows for the two 4NA samples with curated SMN12 truth:

- `NA00232`: expected `SMN1=0`, `SMN2=2`.
- `NA09677`: expected `SMN1=0`, `SMN2=3`.

Before launching new runs, inventory past completed Sentieon test work, export only completed and inactive work, and do not delete anything from `/fsx/analysis_results` unless the exact deletion list receives a second explicit destructive-action approval.

## Gate 0 Inventory

Controlling ledger: `docs/plans/20260615T081948Z_smn12_full_depth_chip124_ledger.md`

Repos:

- DayOA: `/Users/jmajor/projects/lsmc/daylily-omics-analysis`, branch `jem-dev`; baseline had untracked HG003/Ultima plan artifacts and `jem/` unrelated to this task.
- DYEC: `/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster`, branch `jem-dev`; baseline clean.

Instruction files read:

- `/Users/jmajor/.codex/AGENTS-HOW-TO-RUN-DAYOA.md`
- `/Users/jmajor/.agents/AGENTS-HOW-TO-RUN-DAYOA.md`
- `/Users/jmajor/.agents/AGENTS.md`
- `/Users/jmajor/.codex/AGENTS.md`
- `/Users/jmajor/projects/lsmc/AGENTS.md`
- `/Users/jmajor/projects/lsmc/daylily-omics-analysis/AGENTS.md`
- `/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster/AGENTS.md`
- `/Users/jmajor/.codex/docs/plan-ledger-workflow.md`
- `/Users/jmajor/.augment/AGENTS.md`
- `/Users/jmajor/.augment/rules/*.md`

Hard execution contracts:

- DayOA workflow runs must use `dy-r`, never raw `snakemake`.
- DayOA workflow commands must run as `ubuntu` inside persistent, meaningfully named tmux sessions with separate `source dyoainit`, `dy-a slurm hg38_broad`, and `dy-r ...` commands.
- SSM one-shot commands may inspect, prepare files, or send keys into tmux; they must not act as workflow controllers.
- Cleanup must exclude any directory that is actively running or plausibly owned by another active agent.
- Destructive deletion from `/fsx/analysis_results` is not approved by the initial request alone. It requires a second explicit approval after exact candidates are listed.

Known local truth sources:

- `bin/util/other/smn1_smn2_copy_numbers_expanded.tsv` records `NA00232` as `SMN1_exon7=0`, `SMN2_exon7=2`, `SMN1_exon8=0`, `SMN2_exon8=2`.
- `bin/util/other/smn1_smn2_copy_numbers_expanded.tsv` records `NA09677` as `SMN1_exon7=0`, `SMN2_exon7=3`, `SMN1_exon8=0`, `SMN2_exon8=3`.

Prior 4NA staged sample set:

- `docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/previous_4na_samples.tsv` contains `NA00232`, `NA09677`, `NA03986`, and `NA05164`.
- Only `NA00232` and `NA09677` have curated SMN12 status in the local expanded truth table.

## Tracking Rows

| ID | Area | Requirement | Status | Category | Gate | Owner | Evidence | Root Cause | Terminal Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FDS-001 | Ledger | Create durable execution ledger and record repo/instruction baseline. | SUCCESS | feature_implementation | Gate 0 | orchestrator | This ledger. Local `git status --short --branch` recorded in Gate 0. |  | Ledger created before remote mutation or workflow launch. |
| FDS-002 | Active-state inventory | Inventory active tmux sessions, Slurm jobs, DayOA controller processes, and candidate `/fsx/analysis_results` directories before export or cleanup. | SUCCESS | config_or_startup_contract | Gate 0 | orchestrator | `docs/plans/20260615T081948Z_smn12_full_depth_chip124/exact_preflight.json`, SSM `3c0e3952-b90f-43ff-b2f2-ff183a23cb95`. |  | Active other-agent HG003 pangenome directories identified and excluded from cleanup. |
| FDS-003 | Export candidates | Identify completed Sentieon test work that is inactive and eligible for DRA export. | SUCCESS | config_or_startup_contract | Gate 0 | orchestrator | `exact_preflight.json` `__CANDIDATE__` rows for four inactive completed directories. |  | Four inactive completed directories selected; active HG003 current/prior hg38 runs skipped. |
| FDS-004 | DRA export | Export eligible inactive completed Sentieon test work before launching new full-depth runs. | SUCCESS | feature_implementation | Gate 2 | orchestrator | `docs/plans/20260615T081948Z_smn12_full_depth_chip124/exports/*/fsx_export.yaml`. |  | All four exports reported `status: success`, task lifecycle `SUCCEEDED`, DRA detached, and no FSx data deletion. |
| FDS-005 | Cleanup deletion | Delete successfully exported completed Sentieon test work from `/fsx/analysis_results`. | BLOCKED | legitimate_safety_handling | Gate 2 | orchestrator | Exact deletion candidates listed in Evidence Log. Instruction policy requires explicit destructive-action approval after exact paths are listed. | Destructive deletion approval not yet obtained for exact paths. | No deletion performed. |
| FDS-006 | Full-depth input discovery | Verify full-depth ILMN R1/R2 and combined ONT chip1+2+4 FASTQs for `NA00232` and `NA09677`; fail hard if any required input is absent. | SUCCESS | config_or_startup_contract | Gate 0 | orchestrator | `full_depth_input_check_after_mount_refresh.json`, SSM `1da36f1d-1e44-4e01-90b2-db7375dc918a`. |  | Full-depth ILMN R1/R2 visible for both samples; ONT chip1+chip2+chip4 has 219 FASTQs per sample. |
| FDS-007 | Config build | Build exact two-sample config using full-depth ILMN and combined ONT chip1+2+4, with no chip3 and no 20x downsample ILMN. | SUCCESS | feature_implementation | Gate 2 | orchestrator | `samples_full_depth_chip124.tsv`, `units_full_depth_chip124.tsv`, `full_depth_chip124_manifest_metadata.json`, config S3 prefix `s3://lsmc-ssf-sequencing-data/derived/analysis_results/hyb-only/dyecX4/smn12_full_ilmn_chip124_20260615T092300Z/config/`. |  | Exactly two units, no `ds20x` tokens, full-depth ILMN paths, lane `chip1-chip2-chip4`. |
| FDS-008 | Runtime patch | Ensure config uses current Sentieon stack, `DNAscopeONT2.3.bundle`, `SentieonIlluminaWGS2.2.bundle`, `sentieon-cli==1.6.3`, `segdup-caller==0.6.0`, and `seqdup_genes=SMN1`. | SUCCESS | config_or_startup_contract | Gate 2 | orchestrator | `patch_smn12_runtime_full_depth_chip124.py`; `full_depth_input_check_after_mount_refresh.json`; local `workflow/envs/sentieon_v0.3.yaml` and `workflow/envs/segdup_v0.2.yaml`; `config/day_profiles/slurm/templates/rule_config.yaml`. |  | Runtime assets are `sentieon-genomics-202503.03`; `sentieon-cli==1.6.3`; `segdup-caller` pinned to `v0.6.0`; segdup restricted to `SMN1` for this run. |
| FDS-009 | Dry-run | Run supported `dy-r` dry-run in an interactive tmux pane for `produce_smn12_orthogonal_calls produce_htd_calls produce_sentdhiomr_segdup`. | SUCCESS | contract_test | Gate 5 | orchestrator | `ssm_launch_dryrun_full_depth_chip124.json`, `ssm_poll_dryrun_full_depth_chip124_1.json`. |  | Dry-run returned `__DRYRUN_RC__=0` and planned 32 jobs. |
| FDS-010 | Live run | Launch supported `dy-r` live workflow in persistent tmux after dry-run passes. | SUCCESS | feature_implementation | Gate 5 | orchestrator | `ssm_launch_live_full_depth_chip124.json`; terminal poll `ssm_poll_live_full_depth_chip124_compact_27.json`. |  | Live tmux session `dayoa_smn12_full_chip124_20260615T092300Z_live` reached `32 of 32 steps (100%) done` and returned code 0. |
| FDS-011 | Results | Collect SMN12 caller outputs and compare `NA00232` and `NA09677` to curated truth. | SUCCESS | contract_test | Gate 5 | orchestrator | `ssm_collect_full_depth_results.json`; `ssm_collect_full_depth_results_compact.json`; prior comparison SSM `6706e9f1-1f89-4777-ba9e-7fa878ef00dd` and `5a9481a8-65df-4804-a4ad-74e03cf56f27`. |  | Full-depth run completed all callers. SMN1/affected status improved or remained correct; SMN2 copy number remains undercalled. |
| FDS-012 | Final report | Update ledger with terminal states and report exported, skipped, active, deletion-blocked, launched, completed, and failed items separately. | SUCCESS | feature_implementation | Gate 5 | orchestrator | This ledger and final chat response. |  | All tracked rows are terminal. Cleanup deletion remains blocked pending explicit destructive approval. |

## Evidence Log

### 20260615T081948Z Gate 0 Start

- Created ledger.
- User clarified cleanup must only apply to work not actively running by other agents.
- Destructive deletion remains blocked pending exact-path approval.

### 20260615T083346Z Active-State And Export Preflight

- Remote inspection SSM command: `3c0e3952-b90f-43ff-b2f2-ff183a23cb95`.
- Active work excluded from cleanup:
  - `/fsx/analysis_results/dyecX4/hg003_ilmn30x_pg_current_hg38_1004_20260615T080558Z/daylily-omics-analysis`
  - `/fsx/analysis_results/dyecX4/hg003_ilmn30x_pg_prior_hg38_1004_20260615T082114Z/daylily-omics-analysis`
- Inactive completed export candidates:
  - `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_current_1004_20260614T220039Z`
  - `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_prior_1004_20260614T220039Z`
  - `/fsx/analysis_results/ubuntu/hg003_ilmn30x_linear_sentd_1004_20260615T034314Z`
  - `/fsx/analysis_results/dyecX4/na00232_smn12_chip124_20260615T062929Z`

### 20260615T084048Z-20260615T085603Z Export Receipts

All four exports succeeded with `delete_data_in_file_system: false`, `task_lifecycle: SUCCEEDED`, and `detach_lifecycle: DELETED`.

| FSx source | Destination | Association | Task |
| --- | --- | --- | --- |
| `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_current_1004_20260614T220039Z/` | `s3://lsmc-ssf-sequencing-data/derived/analysis_results/hyb-only/ubuntu/hg003_ilmn30x_pg_current_1004_20260614T220039Z/` | `dra-0b9180e318c79fac9` | `task-0cd306f5cbd23b396` |
| `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_prior_1004_20260614T220039Z/` | `s3://lsmc-ssf-sequencing-data/derived/analysis_results/hyb-only/ubuntu/hg003_ilmn30x_pg_prior_1004_20260614T220039Z/` | `dra-0d18163976fdef708` | `task-0e9dd78acd790ba15` |
| `/fsx/analysis_results/ubuntu/hg003_ilmn30x_linear_sentd_1004_20260615T034314Z/` | `s3://lsmc-ssf-sequencing-data/derived/analysis_results/hyb-only/ubuntu/hg003_ilmn30x_linear_sentd_1004_20260615T034314Z/` | `dra-0bd20852db6dbe62f` | `task-03eaf2074073959fd` |
| `/fsx/analysis_results/dyecX4/na00232_smn12_chip124_20260615T062929Z/` | `s3://lsmc-ssf-sequencing-data/derived/analysis_results/hyb-only/dyecX4/na00232_smn12_chip124_20260615T062929Z/` | `dra-09acb9861906187bb` | `task-046045719223d5682` |

Exact deletion candidates, pending separate destructive approval:

- `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_current_1004_20260614T220039Z`
- `/fsx/analysis_results/ubuntu/hg003_ilmn30x_pg_prior_1004_20260614T220039Z`
- `/fsx/analysis_results/ubuntu/hg003_ilmn30x_linear_sentd_1004_20260615T034314Z`
- `/fsx/analysis_results/dyecX4/na00232_smn12_chip124_20260615T062929Z`

### 20260615T092300Z Full-Depth HiOMR Setup

- Mounted full-depth ILMN S3 prefix read-only via DYEC run mount:
  - Source: `s3://lsmc-ssf-sequencing-data/basecalls/lsmc/ssf-hq/lh01121/2026/20260526_LH01121_0004_B23WW2NLT4/Analysis/1/Data/BCLConvert/fastq/`
  - Mount id: `ilmn-lh01121-b23ww2nlt4-fastq`
  - FSx path: `/fsx/run_dir_mounts/ilmn-lh01121-b23ww2nlt4-fastq/`
  - DRA: `dra-03f0f32e9f6ceea13`
  - Lifecycle: `AVAILABLE`
- Refreshed input verification SSM command: `1da36f1d-1e44-4e01-90b2-db7375dc918a`.
- Full-depth ILMN files:
  - `NA00232-SMN_S46_R1_001.fastq.gz`: `40957861653`
  - `NA00232-SMN_S46_R2_001.fastq.gz`: `42168686123`
  - `NA09677-SMN_S47_R1_001.fastq.gz`: `38992932096`
  - `NA09677-SMN_S47_R2_001.fastq.gz`: `40539959624`
- ONT chip1+chip2+chip4 inputs:
  - `NA00232` / `barcode18`: 73 + 73 + 73 FASTQs, 219 total.
  - `NA09677` / `barcode19`: 73 + 73 + 73 FASTQs, 219 total.
- Generated config and uploaded it to `s3://lsmc-ssf-sequencing-data/derived/analysis_results/hyb-only/dyecX4/smn12_full_ilmn_chip124_20260615T092300Z/config/`.
- Remote analysis root: `/fsx/analysis_results/dyecX4/smn12_full_ilmn_chip124_20260615T092300Z/daylily-omics-analysis`.
- Remote DayOA commit: `9c14e6b0a2a674015e06cd25e0590b546644f6a0`.

### 20260615T093237Z Dry-Run And Live Launch

- Dry-run tmux: `dayoa_smn12_full_chip124_20260615T092300Z_dryrun`.
- Dry-run log: `/fsx/analysis_results/dyecX4/smn12_full_ilmn_chip124_20260615T092300Z/daylily-omics-analysis/logs/dryrun_smn12_full_chip124_20260615T092300Z.log`.
- Dry-run returned `__DRYRUN_RC__=0` and planned 32 jobs.
- Live tmux: `dayoa_smn12_full_chip124_20260615T092300Z_live`.
- Live command used `dy-r produce_smn12_orthogonal_calls produce_htd_calls produce_sentdhiomr_segdup -p -T 0 -k -j 500 --rerun-triggers mtime`.
- Latest live evidence at 2026-06-15T09:40:34Z: two `sentmm2ont_align_sort` jobs running in Slurm, one per sample.

### 20260615T111007Z Live Completion

- Terminal compact poll: `docs/plans/20260615T081948Z_smn12_full_depth_chip124/ssm_poll_live_full_depth_chip124_compact_27.json`.
- Remote live log reached `32 of 32 steps (100%) done`.
- `RETURN CODE: 0`.
- `squeue` for the poll was empty.

Key stage notes:

- ONT `sentmm2ont_align_sort` completed for both samples with pipeline statuses `0 0 0 0`.
- HapSMA completed but no-called both samples because no HapSMA phase set was detected in `chr5:69949523-71054173`; region coverage was about 11.03x for `NA00232` and 10.66x for `NA09677`.
- Sentieon HiOMR segdup SMN1 calling completed for both samples under Sentieon `202503.03` and `segdup-caller` `0.6.0`.

### 20260615T111223Z Caller Result Comparison

Compact result source: `docs/plans/20260615T081948Z_smn12_full_depth_chip124/ssm_collect_full_depth_results_compact.json`.

| Sample | Expected | Sentieon segdup SMN1 | SMNCopyNumberCaller (`smn12`) | sma-finder | SMAca | HapSMA |
| --- | --- | --- | --- | --- | --- | --- |
| `NA00232` | `SMN1=0`, `SMN2=2` | `SMN1=0` matches; YAML also reports `SMN2=1` but this run was restricted to SMN1 segdup | `SMN1=0`, `SMN2=1`, `isSMA=true` | `has SMA`, confidence `25`, `0/26` C840 reads with SMN1 base C | no explicit CN; `cov_SMN1_a/b/c=0`, SMN2 coverage evidence present | no-call, no phase set |
| `NA09677` | `SMN1=0`, `SMN2=3` | `SMN1=0` matches; YAML also reports `SMN2=1` but this run was restricted to SMN1 segdup | `SMN1=0`, `SMN2=1`, `isSMA=true` | `has SMA`, confidence `37`, `0/39` C840 reads with SMN1 base C | no explicit CN; `cov_SMN1_a/b/c=0`, SMN2 coverage evidence present | no-call, no phase set |

Comparison to prior completed `NA00232` chip1+chip2+chip4 run:

- Prior report inspection SSM command: `6706e9f1-1f89-4777-ba9e-7fa878ef00dd`.
- Prior segdup YAML inspection SSM command: `5a9481a8-65df-4804-a4ad-74e03cf56f27`.
- Prior `NA00232` `smn12` called `SMN1=0`, `SMN2=1`; full-depth run still calls `SMN1=0`, `SMN2=1`.
- Prior `NA00232` sma-finder called `has SMA` with confidence `13`; full-depth run calls `has SMA` with confidence `25`.
- Prior `NA00232` Sentieon segdup YAML reported `SMN1=0`, `SMN2=1`; full-depth run reports the same while the workflow-level target is SMN1-only.

Conclusion:

- The full-depth run and current Sentieon stack correctly recover the affected/SMN1-null status for both samples.
- The higher coverage/full-depth run does not recover the curated SMN2 copy numbers. Both `smn12` and the SMN1-restricted segdup YAML show `SMN2=1` for both samples, while expected values are 2 and 3.
- SMAca and HapSMA do not currently provide usable SMN1/SMN2 copy-number calls in this run. HapSMA no-called because no phase set was detected.
- The main improvement over the prior `NA00232` run is sma-finder confidence (`13` to `25`), not copy-number correctness.
