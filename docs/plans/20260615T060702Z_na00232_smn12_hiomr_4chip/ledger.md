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
