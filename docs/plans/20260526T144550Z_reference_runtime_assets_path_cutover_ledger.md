# DayOA Reference Runtime Assets Path Cutover Ledger

Created: 2026-05-26T14:45:50Z

## Objective

Cut DayOA from `/fsx/runtime_assets` to `/fsx/references/runtime_assets`,
preserve the current external sequencing staging contract, and release the
change under the next available DayOA tag after the current MultiQC dry-run
release without rewriting `1.0.36` or later tags.

## Gate 0 Inventory

- Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`.
- Git state: `## codex/tstclu411c-hybrid-env-python...origin/codex/tstclu411c-hybrid-env-python`.
- Existing immutable tag: `1.0.36` resolves to `6aa9a9f789bdbb14a1088c3e35e9e6af30313979`.
- Initial tag sweep: `git grep -n -E '/fsx/runtime_assets|staged_sample_data' 1.0.36 -- bin config workflow tests .test_data` found 237 hits.
- Required new runtime root: `/fsx/references/runtime_assets`.
- Required active staging root: `/fsx/staging/staged_external_sequencing_data`.

## Ledger

| ID | Area | Requirement | Status | Category | Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| DOA-RRA-001 | Inventory | Record path-cutover baseline and tag provenance. | SUCCESS | contract_test | Gate 0 | orchestrator | Gate 0 section. |  | Baseline recorded. |
| DOA-RRA-002 | Runtime paths | Replace active `/fsx/runtime_assets` references with `/fsx/references/runtime_assets`. | SUCCESS | feature_implementation | Gate 1 | Agent D | Bulk path update across `bin`, `config`, `workflow`, `tests`, and `scripts`; post-sweep `rg -n "/fsx/runtime_assets|staged_sample_data|/fsx/data" bin config workflow tests scripts .test_data` returned no active hits. |  | Active runtime assets path points under the references DRA. |
| DOA-RRA-003 | Staging paths | Ensure active staging expectations use `/fsx/staging/staged_external_sequencing_data`; retired names only in negative tests or historical docs. | SUCCESS | contract_test | Gate 1 | Agent D | Same active sweep returned no `staged_sample_data` hits. |  | Staging remains on `staged_external_sequencing_data`. |
| DOA-RRA-004 | Tests | Run focused parser/config/rule tests for the path cutover. | SUCCESS | contract_test | Gate 2 | Agent D | `python -m pytest -q tests/test_complete_genomics_sentieon.py tests/test_workflow_catalog.py` returned `8 passed`; `bash tests/test_cli_commands.sh` returned `28 passed, 0 failed`; `git diff --check` passed. |  | Focused DayOA validation is green. |
| DOA-RRA-005 | Release | Create an annotated DayOA tag after path-cutover tests pass; exact future tag must be selected at execution time. | SUCCESS | feature_implementation | Gate 3 | Agent D | Committed full DayOA worktree as `b2c8057` (`Cut runtime assets over to reference mount`), including pre-existing MultiQC env/doc/plan changes per user instruction; created annotated tag `1.0.37`; pushed branch `codex/tstclu411c-hybrid-env-python` and tag `1.0.37` to origin. |  | `1.0.37` is published for DayEC catalog use. |
| DOA-RRA-006 | Plan amendment | Remove the stale assumption that path cutover owns DayOA tag `1.0.37`. | SUCCESS | plan_amendment | Gate 0 | orchestrator | Current user direction requested an immediate MultiQC/AlignStats dry-run release before path cutover execution. |  | Path-cutover work remains open; future execution must choose a then-current release tag. |

Execution amendment: the controlling user request for this run re-selected `1.0.37` for the runtime-assets path cutover because the current HEAD still has only `1.0.35` and `1.0.36` tags. The release row above now tracks `1.0.37`.

## Acceptance Notes

- Do not move or rewrite `1.0.36` or later published tags.
- Do not add `/fsx/runtime_assets` compatibility logic.
