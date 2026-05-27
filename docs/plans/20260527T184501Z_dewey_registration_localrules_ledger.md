# Dewey Registration Localrules Ledger

Created: 2026-05-27T18:45:01Z

## Objective

Confirm DayOA Dewey/QEO registration rules always execute locally on the Snakemake driver/headnode under the Slurm profile, then add a regression guard so they cannot quietly lose that contract.

## Gate 0 Inventory

| Field | Evidence |
|---|---|
| Repo | `/Users/jmajor/projects/daylily/daylily-omics-analysis` |
| Branch | `main` |
| Initial code state | `workflow/rules/qeo_registration.smk` already declared `localrules:` before the registration rules. |
| Correct Snakemake spelling | `localrules:` |

## Tracking Rows

| ID | Area | Requirement | Status | Evidence | Terminal Note |
|---|---|---|---|---|---|
| LOCAL-001 | Workflow rules | Dewey-touching registration rules run on the headnode/driver, not on Slurm compute jobs | SUCCESS | `workflow/rules/qeo_registration.smk` lines 73-79 list `register_multiqc_final`, `register_analysis_artifact_set`, `publish_qeo_ingest_event`, and QEO wrapper targets under `localrules:`. | No workflow rule edit was needed because the rule contract was already present. |
| TEST-001 | Regression test | Lock down that localrules contract in tests | SUCCESS | Added `_localrules_entries` and an assertion in `tests/test_multiqc_qc_targets.py` that the QEO/Dewey registration rules remain in the `localrules:` block. | `python -m pytest -q tests/test_multiqc_qc_targets.py tests/test_qeo_registration.py` passed: `26 passed in 1.61s`. |

## Final Evidence

- `workflow/rules/qeo_registration.smk` already has the correct `localrules:` directive.
- `tests/test_multiqc_qc_targets.py` now fails if the Dewey/QEO registration rules are removed from the `localrules:` block.
