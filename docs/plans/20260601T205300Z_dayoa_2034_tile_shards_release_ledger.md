# DayOA 2.0.34 Tile-Shard Release Ledger

Created: 2026-06-01T20:53:00Z

## Objective

Review and merge `codex/dayoa-bclconvert-tile-shards-20260601` into the
current DayOA release branch pinned by DayEC, then publish DayOA `2.0.34` for
the follow-on DYEC double release train.

## Gate 0 Inventory

| Item | Evidence |
|---|---|
| Repo | `/Users/jmajor/.codex/worktrees/dayoa-2034-release` |
| Source repo | `/Users/jmajor/projects/daylily/daylily-omics-analysis` |
| Target branch | `codex/dayoa-local-evidence-dewey-refactor-20260528` tracking `origin/codex/dayoa-local-evidence-dewey-refactor-20260528` |
| Target baseline HEAD | `1005bc897397c81853c9457340f2c7b6e9affd06` (`Record DayOA 2.0.33 publication`) |
| Source branch | `origin/codex/dayoa-bclconvert-tile-shards-20260601` |
| Source commit | `f8a24c13b338ab62dc8e4bcc004b7bcc10d54e8e` (`Add BCL Convert tile sharding`) |
| Current DayEC pin | `daylily-ephemeral-cluster` branch `codex/dyec515-full-catalog-20260531` pins `daylily-omics-analysis==2.0.33` |
| Latest DayOA semver tag | `2.0.33`; no local or remote `2.0.34` tag at Gate 0 |
| Pre-existing dirty state | Release worktree was clean at Gate 0. Existing source checkout had a dirty `AGENTS.md`, so this separate worktree is used to avoid unrelated changes. |

## Execution Ledger

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| DOA2034-001 | Review | Review source branch changes for release-blocking defects before publishing. | SUCCESS | contract_test | Gate 1 | Codex | Reviewed `f8a24c13b338ab62dc8e4bcc004b7bcc10d54e8e`; changes are scoped to BCL Convert tile-shard config, Snakemake rules, the tile-shard merge helper, docs, and BCL Convert tests. No release-blocking defects found. One harmless duplicate assignment of `BCL_TILE_SHARD_LANES_RAW` remains in `workflow/rules/bclconvert.smk`; it does not alter behavior because both assignments read the same config key. |  | Branch is acceptable for release after validation. |
| DOA2034-002 | Merge | Merge `origin/codex/dayoa-bclconvert-tile-shards-20260601` into the target DayOA release branch. | SUCCESS | feature_implementation | Gate 1 | Codex | Merge commit `4d25a978fa09819b5a3de1590f8a9916e673b256` using `git merge --no-ff origin/codex/dayoa-bclconvert-tile-shards-20260601 -m "Merge BCL Convert tile sharding"`; merge affected 11 files with 845 insertions and 14 deletions. |  | Tile-shard branch is merged into `codex/dayoa-local-evidence-dewey-refactor-20260528`. |
| DOA2034-003 | Validation | Run focused DayOA validation for BCL Convert tile sharding and release hygiene. | SUCCESS | contract_test | Gate 5 | Codex | `python -m pytest -q tests/test_bclconvert_multiqc.py tests/test_tool_catalog_docs.py` -> `17 passed`; `bash tests/test_bclconvert_bootstrap.sh` -> `11 passed`; `python -m py_compile workflow/scripts/merge_bclconvert_tile_shards.py`, `bash -n workflow/scripts/run_bclconvert_lane.sh`, and `git diff --check HEAD~1..HEAD` passed; corrected lint command `python -m ruff check workflow/scripts/merge_bclconvert_tile_shards.py tests/test_bclconvert_multiqc.py && bash -n workflow/scripts/run_bclconvert_lane.sh` passed; full `python -m pytest -q` -> `252 passed`. |  | Local validation is clean. |
| DOA2034-004 | Git release | Commit release ledger, push branch, create annotated tag `2.0.34`, verify tag type and target, and push tag. | OPEN | release | Gate 6 | Codex |  |  |  |
| DOA2034-005 | Package publish | Build in the `TWINE` environment, upload with `twup`, and verify package-index visibility for `2.0.34`. | OPEN | release | Gate 6 | Codex |  |  |  |

## Final Status

Working ledger. Terminal status will be recorded after the DayOA release is
tagged, pushed, uploaded, and visible on the package index.
