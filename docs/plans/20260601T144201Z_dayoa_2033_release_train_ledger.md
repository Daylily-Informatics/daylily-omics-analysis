# DayOA 2.0.33 Release Train Ledger

Created: 2026-06-01T14:42:01Z

## Objective

Publish a new DayOA package release `2.0.33` for the DayEC follow-up release
train. This release is provenance-only unless validation exposes a required
source fix.

## Gate 0 Inventory

| Item | Evidence |
|---|---|
| Repo | `/Users/jmajor/projects/daylily/daylily-omics-analysis` |
| Branch | `codex/dayoa-local-evidence-dewey-refactor-20260528` |
| Baseline HEAD | `2c42e30`, annotated tag `2.0.32`, `origin/codex/dayoa-local-evidence-dewey-refactor-20260528` |
| Latest local semver tag | `2.0.32` |
| Package index before release | `python -m pip index versions daylily-omics-analysis` reported latest `2.0.32` |
| Next release | `2.0.33`; no local or remote `2.0.33` tag existed at Gate 0 |
| Pre-existing dirty file | `AGENTS.md` has Slurm service-boundary instruction edits and is intentionally not part of this release commit |

## Execution Ledger

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| DOA2033-001 | Provenance | Add a durable release ledger so `2.0.33` is not tagged on the exact `2.0.32` commit. | SUCCESS | release | Gate 1 | Codex | This ledger. |  | Release provenance recorded. |
| DOA2033-002 | Validation | Run focused DayOA validation before tagging. | SUCCESS | contract_test | Gate 5 | Codex | `python -m pytest -q tests/test_rule_log_benchmark_contracts.py tests/test_multiqc_qc_targets.py tests/test_evidence_manifest.py` -> `34 passed in 0.73s`. |  | Focused release validation passed. |
| DOA2033-003 | Git release | Commit, push branch, create annotated tag `2.0.33`, verify tag type, and push tag. | OPEN | release | Gate 6 | Codex |  |  |  |
| DOA2033-004 | Package publish | Build in the `TWINE` environment, upload with `twup`, and verify package-index visibility. | OPEN | release | Gate 6 | Codex |  |  |  |

## Final Status

Working ledger. Terminal status will be recorded after publication.
