# NA00232 SMN12 HiOMR Four-Chip Validation Ledger

Created: 2026-06-15T06:07:02Z

## Objective

Run `NA00232` with ILMN 20x plus ONT chips 1, 2, 3, and 4 through the current DayOA HiOMR SMN12 caller set, using:

- current DayOA `jem-dev`;
- Sentieon `202503.03`;
- `sentieon-cli==1.6.3`;
- `segdup-caller@v0.6.0`;
- Sentieon HiOMR segdup restricted to `SMN1`;
- enabled orthogonal SMN12 callers: SMNCopyNumberCaller, SMAca, Broad sma-finder, and HapSMA.

Report whether the higher ONT coverage and current Sentieon stack improve caller behavior compared with the prior `NA00232` two-chip and chip4-only evidence.

## Gate 0 Inventory

Controlling ledger: `docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/ledger.md`

Repos:

- DayOA: `/Users/jmajor/projects/lsmc/daylily-omics-analysis`, branch `jem-dev`, baseline `git status --short --branch` included unrelated untracked HG003/Ultima plan artifacts and `jem/`.
- DYEC: `/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster`, branch `jem-dev`, baseline `git status --short --branch` was clean.

Instruction files read:

- `/Users/jmajor/.codex/AGENTS-HOW-TO-RUN-DAYOA.md`
- `/Users/jmajor/.agents/AGENTS-HOW-TO-RUN-DAYOA.md`
- `/Users/jmajor/.agents/AGENTS.md`
- `/Users/jmajor/.codex/AGENTS.md`
- `/Users/jmajor/projects/lsmc/AGENTS.md`
- `/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster/AGENTS.md`
- `/Users/jmajor/projects/lsmc/daylily-omics-analysis/AGENTS.md`
- `/Users/jmajor/.codex/docs/plan-ledger-workflow.md`
- `/Users/jmajor/.augment/AGENTS.md`
- `/Users/jmajor/.augment/rules/*.md`

Prior evidence:

- Previous 4NA ledger recorded `chip3 barcode18 0`, `chip1 barcode18 73`, `chip2 barcode18 73`, and `chip4 barcode18 73`.
- Previous 4NA report recorded `NA00232` as expected SMA-positive (`SMN1=0`, `SMN2=1`) with two successful units:
  - `chip1-chip2`: SMNCopy `0/1`, Sentieon `0/1`, sma-finder `has SMA`, HapSMA mean SMN-region coverage `7.71`, no-call phase-set status.
  - `chip4-only-sub-for-missing-chip3`: SMNCopy `0/1`, Sentieon `0/1`, sma-finder `has SMA`, HapSMA mean SMN-region coverage `3.32`, no-call low-coverage status.

Active DayOA config evidence from local `jem-dev`:

- Sentieon envs pin `sentieon=202503.03`.
- Sentieon CLI pins include `sentieon-cli==1.6.3`.
- Segdup env pins `git+https://github.com/Sentieon/segdup-caller.git@v0.6.0`.
- Slurm profile references `/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/`.
- Slurm profile `sentdhiomr.segdup_sr_model` is `SentieonIlluminaWGS2.2.bundle`.
- Slurm profile `sentdhiomr.segdup_lr_model` is `DNAscopeONT2.3.bundle`.

## Tracking Rows

| ID | Area | Requirement | Status | Category | Gate | Owner | Evidence | Root Cause | Terminal Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| N4C-001 | Input availability | Verify exact `NA00232` ONT chip1, chip2, chip3, and chip4 data plus ILMN 20x paired FASTQs on the target headnode. | BLOCKED | config_or_startup_contract | Gate 0 | orchestrator | SSM `bae50010-f7b0-41dd-af19-79fe915eed0f`, JSON `ssm_inspect_inputs_runtime.json`: ILMN R1/R2 exist; staged chip counts are chip1=73, chip2=73, chip3=0, chip4=73. Raw mount `/fsx/run_dir_mounts/20260513_ONT_HG003` has only one 1556-byte barcode18 file and zero PBM13545/PBM14931/PBM13048 barcode18 files. | Exact requested chip3 barcode18 data for `NA00232` is absent from both the staged 4NA input root and the bounded raw-mount check. | Four-chip run was not launched. |
| N4C-002 | Runtime | Verify headnode uses current Sentieon runtime/software and SMN segdup model paths before launch. | SUCCESS | config_or_startup_contract | Gate 0 | orchestrator | SSM `bae50010-f7b0-41dd-af19-79fe915eed0f`: `/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/sentieon` exists; `SentieonIlluminaWGS2.2.bundle` size `127015170`; `DNAscopeONT2.3.bundle` size `925744416`; HapSMA support BEDs, Clair3 model files, and hg38_broad map-ont `.mmi` are present. Local DayOA env YAMLs pin `sentieon=202503.03`, `sentieon-cli==1.6.3`, and `segdup-caller@v0.6.0`. |  | Runtime assets needed for the new stack are visible, but no workflow used them because Gate 0 input availability failed. |
| N4C-003 | Analysis setup | Create a current DayOA analysis workdir/config for exactly one `NA00232` four-chip unit, with no chip substitution. | SKIPPED | feature_implementation | Gate 2 | orchestrator | Gate N4C-001 blocked. |  | No config or workdir was created because exact four-chip inputs are incomplete. |
| N4C-004 | Dry-run | Run supported `dy-r` dry-run in persistent `ubuntu` tmux and verify planned targets for SMN12 callers plus SMN-only Sentieon segdup. | SKIPPED | contract_test | Gate 5 | orchestrator | Gate N4C-001 blocked. |  | No `dy-r` dry-run was launched. |
| N4C-005 | Live run | Run supported `dy-r` live workflow to terminal status if exact inputs exist and dry-run passes. | SKIPPED | feature_implementation | Gate 5 | orchestrator | Gate N4C-001 blocked. |  | No live workflow was launched. |
| N4C-006 | Results | Collect caller outputs and compare to prior `NA00232` two-chip/chip4-only evidence. | SKIPPED | contract_test | Gate 5 | orchestrator | No new run outputs exist. Prior evidence remains the 202503.02 two-unit NA00232 result: SMNCopy `0/1`, Sentieon `0/1`, sma-finder `has SMA`, HapSMA no-call with mean coverage `7.71` for chip1+chip2 and `3.32` for chip4-only substitute. |  | Cannot evaluate higher four-chip coverage because chip3 data is absent and no four-chip workflow was run. |
| N4C-007 | Export/report | Export or otherwise preserve final report/evidence if live results complete. | SUCCESS | feature_implementation | Gate 5 | orchestrator | Final blocked report: `report.md`; inspection JSON: `ssm_inspect_inputs_runtime.json`; inspection helper: `ssm_inspect_inputs_runtime.py`. |  | Report preserved locally; no result export was needed because no analysis was launched. |
| N4C-008 | Approved substitute inputs | After user approval, build exactly one `NA00232` substitute unit using ILMN 20x plus ONT chip1, chip2, and chip4 only. | SUCCESS | config_or_startup_contract | Gate 0 | orchestrator | Config metadata `chip124_manifest_metadata.json`: chip1=73, chip2=73, chip4=73, total ONT FASTQs=219; `samples_chip124.tsv`; `units_chip124.tsv`; runtime patch `patch_smn12_runtime_chip124.py`. | Exact chip3 remains absent. | Substitute scope is explicitly `chip1+chip2+chip4, no chip3`. |
| N4C-009 | Approved substitute setup | Create a current DayOA workdir/config for the approved chip1+2+4 unit. | SUCCESS | feature_implementation | Gate 2 | orchestrator | SSM `da1e2163-010c-4b19-8f0e-b7d780e99747`, JSON `ssm_prepare_chip124.json`: analysis id `na00232_smn12_chip124_20260615T062929Z`; remote repo `/fsx/analysis_results/dyecX4/na00232_smn12_chip124_20260615T062929Z/daylily-omics-analysis`; DayOA checkout `13b324a52ba8a5b2edb12dd685403c8e8cddd6c2`; `RUNID=HYB-NA00232-smn12-current-20260615`; `LANEID=chip1-chip2-chip4`; `ONT_FASTQS=219`. |  | Config copied to remote workdir from `s3://lsmc-ssf-sequencing-data/derived/analysis_results/hyb-only/ubuntu/na00232_smn12_chip124_20260615T062929Z/config/`. |
| N4C-010 | Approved substitute dry-run | Run supported `dy-r` dry-run in persistent `ubuntu` tmux and verify planned targets for SMN12 callers plus SMN-only Sentieon segdup. | SUCCESS | contract_test | Gate 5 | orchestrator | Launch SSM `00dedec5-24ae-44ef-9736-0e3f9b5420b3`; poll SSM `0f8968f9-633b-47a3-b6de-4e2b40650e4a`; JSON `ssm_poll_dryrun_chip124_1.json`; dry-run marker `__DRYRUN_RC__=0`; `Job stats` total `20`; planned `produce_htd_calls`, `produce_smn12_orthogonal_calls`, and `sentdhiomr_call_segdup` for `SMN1`. |  | Dry-run passed. |
| N4C-011 | Approved substitute live run | Run supported `dy-r` live workflow to terminal status. | SUCCESS | feature_implementation | Gate 5 | orchestrator | Launch SSM `18e145e1-fdec-449b-884e-408fe951c43a`; live session `dayoa_na00232_smn12_chip124_20260615T062929Z_live`; live log `logs/live_smn12_chip124_20260615T062929Z.log`; polls `ssm_poll_live_chip124_1.json` through `ssm_poll_live_chip124_9.json`. At `2026-06-15T07:44:14Z`, workflow reached `20 of 20 steps (100%) done`, `WORKFLOW SUCCESS`, `RETURN CODE: 0`; final poll SSM `96bcb7cf-9873-4522-81a1-e568d7647e8f`. |  | Live workflow completed successfully. |
| N4C-012 | Approved substitute results | Collect caller outputs and compare to prior `NA00232` two-chip/chip4-only evidence. | SUCCESS | contract_test | Gate 5 | orchestrator | Result collector `ssm_collect_chip124_results.py`; successful collection SSM `ed1d97c4-d9bd-4d0a-93b8-3244ea3152b0`; `ssm_collect_chip124_results.json`. SMNCopy `SMN1=0`, `SMN2=1`, `isSMA=true`, `PASS:Majority`; Sentieon segdup `SMN1=0`, `SMN2=1`, `sentieon=202503.03`, `segdup-caller=0.6.0`; sma-finder `has SMA`; HapSMA mean SMN-region coverage `11.031685` but still `NO_PHASE_SET`. |  | Current run confirms expected SMA-positive result; HapSMA coverage improved but no phase-set call. |
| N4C-013 | Approved substitute report | Update final report/evidence for the approved chip1+2+4 substitute run. | SUCCESS | feature_implementation | Gate 5 | orchestrator | Final report: `report.md`; ledger updated with terminal live/result state. |  | Report preserved locally. |

## Commands And Evidence Log

## 20260615T061516Z Input And Runtime Gate

Read-only SSM inspection:

```bash
cd /Users/jmajor/projects/lsmc/daylily-ephemeral-cluster
source ./activate
PYTHONPATH="$PWD" python /Users/jmajor/projects/lsmc/daylily-omics-analysis/docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/ssm_inspect_inputs_runtime.py --cluster dyecX4 --profile lsmc --region us-west-2 --output /Users/jmajor/projects/lsmc/daylily-omics-analysis/docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/ssm_inspect_inputs_runtime.json
```

Result:

- SSM command id: `bae50010-f7b0-41dd-af19-79fe915eed0f`
- Headnode: `i-05815cdeec4a6dad8`, host `ip-10-0-0-45`, user `ubuntu`
- ILMN 20x inputs exist:
  - R1 `/fsx/analysis_inputs/ubuntu/4na_hiomr_smn12_20260611T220404Z/ilmn/4_nas_ds_to_20x/NA00232-SMN_S46_ds20x_R1_001.fastq.gz`, `17262515732` bytes
  - R2 `/fsx/analysis_inputs/ubuntu/4na_hiomr_smn12_20260611T220404Z/ilmn/4_nas_ds_to_20x/NA00232-SMN_S46_ds20x_R2_001.fastq.gz`, `17800937474` bytes
- Staged ONT barcode18 counts:
  - `chip1`: `73` FASTQs, `19642355519` bytes
  - `chip2`: `73` FASTQs, `16310740013` bytes
  - `chip3`: `0` FASTQs, `0` bytes
  - `chip4`: `73` FASTQs, `15490905346` bytes
- Bounded raw mount check at `/fsx/run_dir_mounts/20260513_ONT_HG003`:
  - all barcode18 FASTQs: `1` file, `1556` bytes
  - PBM13545 barcode18: `0`
  - PBM14931 barcode18: `0`
  - PBM13048 barcode18: `0`
  - the one raw barcode18 sample path is `PBM13745`, not a staged 4NA chip flowcell.
- Runtime assets visible on FSx:
  - `/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bin/sentieon`
  - `/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bundles/SentieonIlluminaWGS2.2.bundle`
  - `/fsx/references/runtime_assets/cached_envs/sentieon-genomics-202503.03/bundles/DNAscopeONT2.3.bundle`
  - HapSMA SMN BED, HapSMA homopolymer BED, Clair3 R10 model files, and hg38_broad map-ont `.mmi`.

Decision:

The exact requested `NA00232` ILMN 20x + ONT chip1+chip2+chip3+chip4 run is blocked because chip3 barcode18 data is absent. No substitute run was launched.

## 20260615T062929Z Approved Chip1+Chip2+Chip4 Substitute Run

After the blocked four-chip gate, the user explicitly approved running `NA00232` with ILMN 20x plus ONT chip1, chip2, and chip4. The substitute run intentionally excludes chip3 because chip3 barcode18 data is absent.

Config build:

- Helper: `build_chip124_config.py`
- Metadata: `chip124_manifest_metadata.json`
- Samples: `samples_chip124.tsv`
- Units: `units_chip124.tsv`
- Runtime patch: `patch_smn12_runtime_chip124.py`

Config scope:

- `RUNID`: `HYB-NA00232-smn12-current-20260615`
- `LANEID`: `chip1-chip2-chip4`
- `SAMPLEID`: `NA00232`
- `BARCODEID`: `barcode18`
- ILMN 20x R1/R2: same `NA00232-SMN_S46_ds20x` pair verified in Gate 0
- ONT FASTQs: chip1 `73`, chip2 `73`, chip4 `73`, total `219`
- HTD callers: `smn12`, `smaca`, `sma_finder`, `hapsma`
- Sentieon HiOMR segdup genes: `SMN1`

Remote setup:

```bash
cd /Users/jmajor/projects/lsmc/daylily-ephemeral-cluster
source ./activate
PYTHONPATH="$PWD" python /Users/jmajor/projects/lsmc/daylily-omics-analysis/docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/ssm_prepare_chip124.py --cluster dyecX4 --profile lsmc --region us-west-2 --output /Users/jmajor/projects/lsmc/daylily-omics-analysis/docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/ssm_prepare_chip124.json
```

Result:

- SSM command id: `da1e2163-010c-4b19-8f0e-b7d780e99747`
- Remote repo: `/fsx/analysis_results/dyecX4/na00232_smn12_chip124_20260615T062929Z/daylily-omics-analysis`
- DayOA checkout: `13b324a52ba8a5b2edb12dd685403c8e8cddd6c2`
- Unit validation: `RUNID=HYB-NA00232-smn12-current-20260615`, `LANEID=chip1-chip2-chip4`, `ONT_FASTQS=219`

Dry-run:

```bash
cd /Users/jmajor/projects/lsmc/daylily-ephemeral-cluster
source ./activate
PYTHONPATH="$PWD" python /Users/jmajor/projects/lsmc/daylily-omics-analysis/docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/ssm_launch_dryrun_chip124.py --cluster dyecX4 --profile lsmc --region us-west-2 --output /Users/jmajor/projects/lsmc/daylily-omics-analysis/docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/ssm_launch_dryrun_chip124.json
```

Result:

- Launch SSM command id: `00dedec5-24ae-44ef-9736-0e3f9b5420b3`
- Poll SSM command id: `0f8968f9-633b-47a3-b6de-4e2b40650e4a`
- Dry-run log: `/fsx/analysis_results/dyecX4/na00232_smn12_chip124_20260615T062929Z/daylily-omics-analysis/logs/dryrun_smn12_chip124_20260615T062929Z.log`
- Marker: `__DRYRUN_RC__=0`
- Planned jobs: `20`
- Planned targets include `produce_htd_calls`, `produce_smn12_orthogonal_calls`, and `sentdhiomr_call_segdup` for `SMN1`

Live run:

```bash
cd /Users/jmajor/projects/lsmc/daylily-ephemeral-cluster
source ./activate
PYTHONPATH="$PWD" python /Users/jmajor/projects/lsmc/daylily-omics-analysis/docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/ssm_launch_live_chip124.py --cluster dyecX4 --profile lsmc --region us-west-2 --output /Users/jmajor/projects/lsmc/daylily-omics-analysis/docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/ssm_launch_live_chip124.json
```

Result:

- Launch SSM command id: `18e145e1-fdec-449b-884e-408fe951c43a`
- Live tmux session: `dayoa_na00232_smn12_chip124_20260615T062929Z_live`
- Live log: `/fsx/analysis_results/dyecX4/na00232_smn12_chip124_20260615T062929Z/daylily-omics-analysis/logs/live_smn12_chip124_20260615T062929Z.log`
- Status at `2026-06-15T06:51:03Z`: live run active; Snakemake main progress `4 of 20 steps (20%) done`; Slurm job `5623` (`sentmm2ont_align_sort`) running on `i384nvme-dy-mem384nvme-1`; no `__LIVE_RC__` marker yet.
- Status at `2026-06-15T07:07:01Z`: ONT align/sort completed; main log advanced to `178200` bytes; HapSMA job `5626` and Sentieon HiOMR SR alignment job `5627` were submitted and in `CF`; no `__LIVE_RC__` marker yet.
- Status at `2026-06-15T07:17:33Z`: workflow progress `6 of 20 steps (30%) done`; HapSMA finished; Sentieon HiOMR SR alignment job `5627` running on `i192nvme-dy-price192nvme-1`; no `__LIVE_RC__` marker yet.
- Status at `2026-06-15T07:33:10Z`: Sentieon HiOMR SR alignment completed; SMN1 segdup-caller job `5646` running on `i192hugenvme-dy-price192hugenvme-1`; SR CRAM export job `5645` in `CF`; no `__LIVE_RC__` marker yet.
- Status at `2026-06-15T07:38:50Z`: SMN1 segdup-caller job `5646` completed; `sentdhiomr_call_segdup` and `produce_sentdhiomr_segdup` completed; workflow progress `12 of 20 steps (60%) done`; SR CRAM export job `5645` running; no `__LIVE_RC__` marker yet.
- Status at `2026-06-15T07:44:26Z`: workflow completed `20 of 20 steps (100%) done`; `WORKFLOW SUCCESS`; `RETURN CODE: 0`; no remaining Slurm jobs for this run.

Result collection:

```bash
cd /Users/jmajor/projects/lsmc/daylily-ephemeral-cluster
source ./activate
PYTHONPATH="$PWD" python /Users/jmajor/projects/lsmc/daylily-omics-analysis/docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/ssm_collect_chip124_results.py --cluster dyecX4 --profile lsmc --region us-west-2 --output /Users/jmajor/projects/lsmc/daylily-omics-analysis/docs/plans/20260615T060702Z_na00232_smn12_hiomr_4chip/ssm_collect_chip124_results.json
```

Successful compact collection:

- SSM command id: `ed1d97c4-d9bd-4d0a-93b8-3244ea3152b0`
- Output: `ssm_collect_chip124_results.json`
- Collected report files:
  - `results/day/hg38_broad/other_reports/htd_calls_mqc.tsv`, size `5967`
  - `results/day/hg38_broad/other_reports/smn12_orthogonal_calls_mqc.tsv`, size `6240`
- Collected Sentieon segdup files:
  - `SMN1.yaml`, size `2007`
  - `SMN1.result.vcf.gz`, size `22628`
  - `SMN1.result.vcf.gz.tbi`, size `72`

Caller summaries:

| caller | result |
| --- | --- |
| SMNCopyNumberCaller / `smn12` | `SMN1=0`, `SMN2=1`, `SMN2delta78=0`, `isSMA=true`, `isCarrier=false`, `PASS:Majority`, median depth `27.33`, total CN raw `0.919`, full-length CN raw `1.027` |
| Sentieon HiOMR segdup SMN1 | `SMN1=0`, `SMN2=1`, `sentieon=202503.03`, `segdup-caller=0.6.0` |
| Broad `sma_finder` | `has SMA`, confidence `13`, `0/14` C840 reads with SMN1 base C |
| SMAca | completed; summary coverage avg `SMN1=4.717640162747397`, avg `SMN2=7.005000172419739`; MQC row does not expose direct CN fields |
| HapSMA | mean SMN-region coverage `11.031685`; `NO_PHASE_SET`, `no_call_no_phase_set` |

Comparison to prior `NA00232` evidence:

- Prior chip1+chip2, Sentieon stack `202503.02`: SMNCopy `0/1`, Sentieon segdup `0/1`, sma-finder `has SMA`, HapSMA mean coverage `7.71` with no-call/no-phase-set.
- Prior chip4-only substitute, Sentieon stack `202503.02`: SMNCopy `0/1`, Sentieon segdup `0/1`, sma-finder `has SMA`, HapSMA mean coverage `3.32` with no-call/low-coverage.
- Current chip1+chip2+chip4, Sentieon stack `202503.03`: SMNCopy `0/1`, Sentieon segdup `0/1`, sma-finder `has SMA`, HapSMA mean coverage `11.031685` but still no-call/no-phase-set.

Conclusion:

The new stack and higher ONT coverage did not change the main interpretation because the decisive callers already called the expected SMA-positive result. It did improve HapSMA coverage over both prior units, but did not make HapSMA produce a phase-set call.
