# DayOA Bucket Contract Release Ledger

Controlling plan: DayOA side of the 15-agent bucket contract release and `bucketsamok` validation.
Ledger path: `docs/plans/20260526T185422Z_bucket_contract_dayoa_release_ledger.md`
Created: 2026-05-26T18:54:22Z

## Gate 0 Baseline

- Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- Branch/head: `codex/tstclu411c-hybrid-env-python`, `1c147d70d8b1082d7dafa51fa074e736a321800b`
- Dirty state at Gate 0: `docs/plans/20260526T181700Z_dayoa_docs_qeo_registration_10agent_ledger.md` modified.
- Latest local non-v semver tag: `1.0.38`.
- Breaking release target: `2.0.0`.
- Sweep command: `rg -n "reference_bucket|control_data_bucket|stage_bucket|--reference-bucket|--control-data-bucket|--stage-bucket|bucket-or-prefix|/fsx/runtime_assets|/fsx/data|/data/staged_sample_data|lsmc-dayoa-omics-analysis-us-west-2" daylily_omics_analysis workflow config .test_data docs tests scripts README.md AGENTS.md -S -g '!quarantine/**' -g '!docs/plans/**'`
- Gate 0 hits: `AGENTS.md` historical runbook references to the old monolith bucket; `docs/qeo/QEO_DAYOA_INTEGRATION.md` example old monolith URI. No active workflow/source hit was found by the Gate 0 sweep.

## Control Ledger

| ID | Agent | Area | Requirement | Status | Category | Approval Gate | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| DAYOA-BKT-001 | Agent 9 | Path scan | Audit active source/config/tests for old bucket and FSx path assumptions. | SUCCESS | contract_test | Gate 1 | Active scan for old public bucket/path contract returned no hits after doc cleanup. |  | Active source/config/tests have no old bucket/path assumptions. |
| DAYOA-BKT-002 | Agent 9 | Docs/examples | Remove or update active non-historical old monolith bucket examples. | SUCCESS | feature_implementation | Gate 1 | `AGENTS.md` now uses explicit verified manifest URI placeholders; `docs/qeo/QEO_DAYOA_INTEGRATION.md` example uses `s3://lsmc-dayoa-analysis-results-usw2/...`. |  | Old monolith bucket examples removed from active docs. |
| DAYOA-BKT-003 | Agent 9 | Runtime contract | Ensure active execution paths use `/fsx/references`, `/fsx/references/runtime_assets`, slim reads, and on-demand staging. | SUCCESS | feature_implementation | Gate 1 | Focused tests `python -m pytest -q tests/test_workflow_catalog.py tests/test_qeo_registration.py tests/test_multiqc_qc_targets.py -> 34 passed`; `git diff --check` clean. |  | Runtime contract is represented in active tests/fixtures. |
| DAYOA-BKT-004 | Agent 10 | Dirty work | Include all dirty DayOA work in the release commit, including work not originally made by Codex. | OPEN | feature_implementation | Release gate | User explicitly requested inclusion. |  |  |
| DAYOA-BKT-005 | Agent 10 | Release | Tag breaking DayOA cutover as `2.0.0` after PR merge from `1.0.38` baseline. | BLOCKED | config_or_startup_contract | Release gate | Local tag baseline `1.0.38`. | Requires implementation, tests, PR merge. |  |

## Acceptance Checks

- Focused DayOA catalog/workflow/path tests pass.
- Active scan is clean for old bucket/path assumptions except explicitly historical archived material.
- Release is tagged `2.0.0` only after tests and merge gates pass.
