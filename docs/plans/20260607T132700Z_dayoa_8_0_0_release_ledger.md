# DayOA 8.0.0 Release Ledger

Created: 2026-06-07T13:27:00Z

## Objective

Create the Daylily Omics Analysis major release `8.0.0` as the upstream release in the DayOA -> DYEC train. DayOA uses `setuptools-scm`; the package version is derived from the annotated non-`v` semver tag.

## Scope

- Repo: `/Users/jmajor/projects/lsmc/daylily-omics-analysis`
- Branch: `jem-dev`
- Previous release tag at Gate 0: `5.0.18`
- Target release tag: `8.0.0`
- Runtime changes in this commit: none; this is a major release marker for the current DayOA execution-plane state.

## Ledger

| ID | Requirement | Status | Evidence | Terminal Note |
|---|---|---|---|---|
| `G0-001` | Confirm clean DayOA source state and no existing `8.0.0` tag before release. | `SUCCESS` | `git status --short --branch` -> clean `jem-dev...origin/jem-dev` before this ledger was added. `git tag --list '8.0.0'` -> no local tag. `git ls-remote --tags origin refs/tags/8.0.0 refs/tags/8.0.0^{}` -> no remote tag. | Gate 0 complete. |
| `TEST-001` | Run local DayOA validation before tagging. | `FAIL` | `eval "$(conda shell.zsh hook)" && conda activate DAY-EC && python --version && python -m pytest -q` -> Python 3.12.12; 274 passed, 5 failed. Failures: retired `/fsx/data` and `/fsx/runtime_assets` references in `docs/jem_working_docs`; missing benchmark/log contract expectations in `tests/test_multiqc_qc_targets.py` and `tests/test_rule_log_benchmark_contracts.py`; missing `docs/plans/20260526T074804Z_ultima_run_qc_native_multiqc_ledger.md`. | Full local DayOA suite is not green at release Gate 0; failure predates release ledger content and needs a release decision. |
| `REL-001` | Commit this release ledger and create annotated tag `8.0.0` on the release commit. | `OPEN` | Pending. |  |
| `REL-002` | Hand the `8.0.0` tag to DYEC for catalog/dependency pinning. | `OPEN` | Pending. |  |

## Notes

- Use non-`v` annotated semver tags.
- Do not run DayOA workflows from this local Mac release step.
