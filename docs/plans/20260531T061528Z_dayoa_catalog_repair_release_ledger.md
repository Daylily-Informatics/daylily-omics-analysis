# DayOA Catalog Repair And Release Ledger

Created: 2026-05-31T06:15:28Z

## Objective

Prepare DayOA for the next DYEC command-catalog validation round by fixing the remaining
Hybrid Ultima+ONT catalog failure when it is DayOA-owned, promoting mounted-run BCL
Convert behavior into DayOA, updating active technical documentation, validating locally
and on `dyec-test`, then committing, tagging, building, and publishing the next DayOA
release.

## Gate 0 Inventory

| Item | Evidence |
|---|---|
| Repo | `/Users/jmajor/projects/daylily/daylily-omics-analysis` |
| Branch | `codex/dayoa-local-evidence-dewey-refactor-20260528` tracking origin |
| Baseline HEAD | `3d5e86c` |
| Baseline tag | `2.0.23` |
| Dirty state | `git status --short --branch --untracked-files=all` returned only the clean branch line |
| Controlling DYEC repo | `/Users/jmajor/.codex/worktrees/dyec-fsx-dra-mounts/daylily-ephemeral-cluster` |
| Live cluster target | `dyec-test`, `us-west-2`, `AWS_PROFILE=lsmc`, executing entity `ubuntu` |
| Prior hard-gate failure | DYEC validation ledger reports `hybrid_ultima_ont_snv` failed as `ccv20260530r49_hybrid_ultima_ont_snv` after Stage1 repair; Stage2 emitted `failed to find target hap` and Sentieon `HapCutAltMap` assertions |
| Current BCL state | DayOA source now owns no-copy mounted run-dir execution, per-lane BCL Convert jobs, 192-vCPU aggressive flags, local postprocessing, and sample-sheet setting injection with `BarcodeMismatchesIndex1,0` and `BarcodeMismatchesIndex2,0` configured by default |
| Release target | Next DayOA tag `2.0.24`, annotated non-`v` tag if validation passes |

## Tracking Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| DAYOA-001 | Hybrid Ultima+ONT | Diagnose `sentdhuomr` Stage1/Stage2 behavior and implement a DayOA-owned fix if root cause is rules/config/input shaping. | IN_PROGRESS | feature_implementation | Gate 1 | dayoa-agent | `workflow/rules/sent_hybrid_ug_ont_modular.refactored.smk` now writes Stage1 HAP/INS driver output to temp SAM files before sort/quickcheck, fails hard on missing Stage1 BAMs, and handles empty refined regions in Stage2/Stage3/Pass2. Focused parser tests pass. | Stage2 previously failed after an empty/invalid target-hap path; source now treats empty target-hap/refined-region results as explicit empty outputs, not silent fallback. | Awaiting live hard-gate validation. |
| DAYOA-002 | BCL Convert | Promote no-copy mounted run-dir execution, per-lane BCL Convert jobs, aggressive 192-vCPU flags, local postprocessing, and dormant sample-sheet settings injection into DayOA source. | IN_PROGRESS | feature_implementation | Gate 1 | dayoa-agent | `workflow/rules/bclconvert.smk`, `workflow/scripts/run_bclconvert_lane.sh`, `workflow/scripts/prepare_bclconvert_lane_samplesheet.py`, and `workflow/scripts/merge_bclconvert_lanes.py` implement direct mounted input, lane splitting, merge/postprocess, and zero barcode mismatch injection. Live validation should use `day-clone -d bclconvert_0_mm`. |  | Awaiting focused/live validation. |
| DAYOA-003 | BCL Convert | Add/adjust tests for BCL direct mounted input, lane-split rules, sample-sheet setting injection, local postprocessing, and generated units compatibility. | SUCCESS | contract_test | Gate 5 | dayoa-agent | `python -m pytest -q tests/test_bclconvert_multiqc.py tests/test_multiqc_qc_targets.py` passed; `bash tests/test_bclconvert_bootstrap.sh` passed; helper py_compile passed. |  | Focused BCL tests cover lane split, zero mismatch injection, invalid mismatch rejection, and no full run-dir copy. |
| DAYOA-004 | Hybrid Tests | Add/adjust tests that prove Hybrid Ultima+ONT handles the diagnosed failure mode without silent fallback. | SUCCESS | contract_test | Gate 5 | dayoa-agent | `python -m pytest -q tests/test_snakemake_parser_contracts.py` passed with assertions for sequential Stage1 driver outputs and empty refined-region handling. |  | Static/parser contracts cover the implemented hybrid failure mode. |
| DAYOA-005 | Docs | Update active user/operator/technical docs for current DayOA behavior, BCL mounted-run execution, sample-sheet settings, and hybrid known state. | IN_PROGRESS | feature_implementation | Gate 5 | docs-agent | Updated `README.md`, `docs/README.md`, `docs/ops/dycli.md`, `docs/catalog_of_tools.md`, and added `docs/workflows/bclconvert.md`. |  | Release-state and final validation notes still pending. |
| DAYOA-006 | Local Validation | Run `bash -n dyoainit`, focused tests, broad pytest, and `git diff --check`. | SUCCESS | contract_test | Gate 5 | orchestrator | `bash -n dyoainit`, `bash -n workflow/scripts/run_bclconvert_lane.sh`, helper `py_compile`, focused pytest (`43 passed`), `bash tests/test_bclconvert_bootstrap.sh` (`11 passed`), full `python -m pytest -q` (`239 passed`), and `git diff --check` all passed. |  | Local validation is clean before live `dyec-test` hard gate. |
| DAYOA-007 | Live Validation | Run targeted `hybrid_ultima_ont_snv` on `dyec-test`; rerun BCL catalog rows if DayOA BCL source changes. | OPEN | contract_test | Gate 5 | orchestrator | BCL rerun must use the `bclconvert_0_mm` analysis/workset name so the remote clone command is `day-clone -d bclconvert_0_mm`. |  |  |
| DAYOA-008 | Release | Commit DayOA changes, create annotated tag `2.0.24`, push branch/tag, build with `python -m build` from `TWINE`, and publish with `twup`. | OPEN | config_or_startup_contract | Gate 5 | release-agent |  |  |  |

## Assumptions

- Active docs are in scope; historical ledgers, archived docs, quarantine docs, and old reports are not rewritten except for necessary current-state pointers.
- If `hybrid_ultima_ont_snv` cannot reach live `rc=0` after at least one DayOA-owned bugfix attempt, this ledger must stop at `FAIL` or `BLOCKED` and the release must not claim all commands work.
- No destructive AWS resource deletion is included. Cleanup is limited to validation analysis directories generated by this work after export/receipt verification.
