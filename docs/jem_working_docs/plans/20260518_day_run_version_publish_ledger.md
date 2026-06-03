# day-run --version Publish Ledger

Date: 2026-05-18

## Gate 0: Inventory Freeze

- Controlling request: commit, push, open PR to `main`, merge when green, update local `main`, create and push a new bare semver tag.
- Ledger path: `docs/plans/20260518_day_run_version_publish_ledger.md`
- Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- Initial branch: `codex/multiqc-qc-no-dedup-default`
- Remote: `origin git@github.com:Daylily-Informatics/daylily-omics-analysis.git`
- Baseline status: modified `bin/day_run`, `bin/tabcomp.bash`, `docs/ops/dycli.md`, `tests/test_cli_commands.sh`; unrelated untracked report artifacts under `docs/`.
- Branch check: current branch was two commits ahead of `origin/main`; tag `1.0.11` points at that branch head, so the CLI change must be isolated from `origin/main` before PR creation.
- Latest fetched release tag before this flow: `1.0.11`; intended next bare semver if merge succeeds: `1.0.12`.
- Baseline checks already run in `DAY-EC`: `bin/day_run --version` printed `daylily-omics-analysis 1.0.9`; `bash tests/test_cli_commands.sh` passed `25/25`.

## Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| PUB-001 | Git scope | Isolate only the four CLI `--version` files from `origin/main`. | SUCCESS | feature_implementation | Gate 0 | orchestrator | Created `codex/day-run-version` from `origin/main`; `git diff --name-only origin/main --` lists only `bin/day_run`, `bin/tabcomp.bash`, `docs/ops/dycli.md`, `tests/test_cli_commands.sh`. |  | PR scope isolated from prior branch commits and unrelated untracked report artifacts. |
| PUB-002 | Validation | Re-run focused checks on the isolated branch. | SUCCESS | contract_test | Gate 5 | orchestrator | `bash -n bin/day_run && bash -n bin/tabcomp.bash && bash -n tests/test_cli_commands.sh && bin/day_run --version` passed; `bash tests/test_cli_commands.sh` passed `25/25`. |  | Focused local validation complete. |
| PUB-003 | Publish | Commit, push, and open PR against `main`. | SUCCESS | feature_implementation | Gate 5 | orchestrator | Commit `b409f0a` pushed to `origin/codex/day-run-version`; PR #147 opened against `main`. |  | Branch published and PR created. |
| PUB-004 | Merge | Merge PR only after required checks are green. | SUCCESS | feature_implementation | Gate 5 | orchestrator | User explicitly requested `--admin`; `gh pr merge 147 --squash --admin --delete-branch` succeeded. PR #147 merged at `dc02728669f903093368095090318027cfb0b5d2`. |  | Admin merge completed per user instruction. |
| PUB-005 | Release tag | Update local `main`, tag next bare semver, and push tag. | SUCCESS | feature_implementation | Gate 5 | orchestrator | Local `main` and `origin/main` are `dc02728669f903093368095090318027cfb0b5d2`; annotated tag `1.0.12` pushed to origin. |  | Release tag `1.0.12` published from merged `main`. |

## Current Terminal Report

- Terminal rows: `SUCCESS` 5, `BLOCKED` 0.
- Objective status: complete.
- Follow-up automation: `merge-day-run-version-pr-when-ready` deleted after successful merge and tag push.
