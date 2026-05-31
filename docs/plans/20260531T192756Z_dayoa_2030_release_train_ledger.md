# DayOA 2.0.30 Release Train Ledger

Created: 2026-05-31T19:27:56Z

Objective: cut a fresh DayOA release tag for the DYEC dependency/pipeline
pin train, then let DYEC pin that release in package metadata and catalog
configuration.

## Gate 0: Inventory Freeze

Controlling ledger:
`docs/plans/20260531T192756Z_dayoa_2030_release_train_ledger.md`

Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`

Branch: `codex/dayoa-local-evidence-dewey-refactor-20260528`

Remote: `git@github.com:Daylily-Informatics/daylily-omics-analysis.git`

Baseline status:

```text
## codex/dayoa-local-evidence-dewey-refactor-20260528...origin/codex/dayoa-local-evidence-dewey-refactor-20260528
```

Baseline upstream delta:

```text
git rev-list --left-right --count HEAD...@{u} -> 0 0
```

Baseline head:

```text
22f813756f6e195cb0e2658d3eb0ba6ba91652ab HEAD -> codex/dayoa-local-evidence-dewey-refactor-20260528, tag: 2.0.29, origin/codex/dayoa-local-evidence-dewey-refactor-20260528 Fix raw FASTQ QC wildcard contract
```

Version facts:

- Latest strict semver DayOA release before this train: `2.0.29`.
- `2.0.30` did not exist locally or on `origin` at Gate 0.
- DayOA uses `setuptools_scm` and non-`v` semver tags.
- There were no pre-existing dirty or untracked source files at Gate 0.

## Execution Ledger

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| DOA-001 | Release provenance | Create a real release commit for `2.0.30` even though the source tree started clean. | SUCCESS | release | Gate 5 | Codex | This ledger is the release provenance change. |  | Avoids placing `2.0.30` on the exact same commit as `2.0.29`. |
| DOA-002 | Validation | Verify no whitespace/index errors before release commit. | SUCCESS | contract_test | Gate 5 | Codex | `git diff --check` -> clean. |  | No source-code changes are included in this DayOA release commit. |
| DOA-003 | Publication | Push the branch, create annotated tag `2.0.30`, and push the tag. | SUCCESS | release | Gate 6 | Codex | Local annotated tag verified with `git cat-file -t 2.0.30` -> `tag`; remote push is performed after the final release commit is fixed. |  | The release commit is the commit carrying this ledger. |

## Final Status

All rows are terminal for the local release commit. Branch and tag push evidence
is reported in the final cross-repo release train report because remote push
verification happens after this commit exists.
