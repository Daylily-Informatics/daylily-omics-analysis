# DayOA 2.0.31 Release Ledger

Created: 2026-05-31T20:30:00Z

Objective: publish DayOA `2.0.31` so DYEC can pin an available package and
catalog release after the `2.0.30` package was not available from the package
index.

## Gate 0: Inventory Freeze

Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`

Branch: `codex/dayoa-local-evidence-dewey-refactor-20260528`

Baseline head:

```text
fe71e6d HEAD -> codex/dayoa-local-evidence-dewey-refactor-20260528, tag: 2.0.30, origin/codex/dayoa-local-evidence-dewey-refactor-20260528
```

Dirty source changes at Gate 0:

- `dyoainit`: replace `dy-h="echo hello"` with `dy-h="bin/day_run help"` and add `day-help="bin/day_run help"`.
- `tests/test_shell_wrapper_contracts.py`: assert the help aliases are present and the placeholder alias is absent.

Package-index fact:

```text
pip index versions daylily-omics-analysis -> latest stable 2.0.29; 2.0.30 was not available
```

## Execution Ledger

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| DOA-001 | Shell help alias | Replace the placeholder `dy-h` alias with DayOA help behavior. | SUCCESS | feature_implementation | Gate 5 | Codex | `dyoainit` now exposes `day-help` and `dy-h` as `bin/day_run help`. | `dy-h="echo hello"` was a placeholder. | Included in the `2.0.31` release commit. |
| DOA-002 | Validation | Validate the shell wrapper contract. | SUCCESS | contract_test | Gate 5 | Codex | `pytest -q tests/test_shell_wrapper_contracts.py` -> `15 passed`; `git diff --check` -> clean. |  | Focused validation passed before release. |
| DOA-003 | Publication | Commit, annotate tag `2.0.31`, push branch, push tag, and publish the package. | PENDING | release | Gate 6 | Codex |  |  | Complete after branch/tag/package publication evidence is captured. |

## Final Status

In progress.
