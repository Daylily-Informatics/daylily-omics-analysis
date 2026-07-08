# DayOA 10.0.66 Release Ledger

Date: 2026-07-08T04:21:00Z

## Scope

Commit current dirty DayOA changes on `jem-dev`, push `jem-dev`, create annotated tag `10.0.66`, and push the tag for the downstream DYEC pin update.

## Baseline

- Repo: `/Users/jmajor/projects/lsmc/daylily-omics-analysis`
- Branch: `jem-dev`
- Remote: `origin git@github.com:lsmc-bio/daylily-omics-analysis.git`
- Previous highest tag after fetch: `10.0.65`
- Selected new tag: `10.0.66`
- Ahead/behind before commit: `0 0` relative to `origin/jem-dev`
- Validation already run before release:
  - `/Users/jmajor/miniconda3/envs/DAY-EC/bin/python -m pytest -q --cov=daylily_omics_analysis --cov-report=term-missing --cov-report=json:/tmp/dayoa_after_cov.json` -> `395 passed`, coverage `83.75%`
  - `/Users/jmajor/miniconda3/envs/DAY-EC/bin/python -m py_compile tests/test_coverage_contracts.py tests/test_tool_catalog_docs.py`
  - `git diff --check`

## Rows

| ID | Requirement | Status | Evidence | Terminal Note |
|---|---|---|---|---|
| GATE0 | Record release baseline and target version. | SUCCESS | Baseline above. | Ready to commit. |
| COMMIT | Commit current dirty DayOA changes. | SUCCESS | This ledger is part of the release commit. | Dirty DayOA changes are committed for `10.0.66`. |
| PUSH_BRANCH | Push `jem-dev`. | DUPLICATE | Controlling release train ledger: `/Users/jmajor/projects/lsmc/daylily-ephemeral-cluster/docs/plans/20260708T042100Z_dayoa_dyec_release_train_ledger.md`. | Branch push evidence is tracked in the cross-repo release train ledger and final report. |
| TAG | Create and push annotated tag `10.0.66`. | DUPLICATE | Controlling release train ledger records the tag verification. | Tag evidence is tracked in the cross-repo release train ledger and final report. |
| VERIFY | Verify tag object and remote refs. | DUPLICATE | Controlling release train ledger records remote verification. | Verification is tracked in the cross-repo release train ledger and final report. |
