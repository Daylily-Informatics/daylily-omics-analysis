# DayOA 2.0.26 Release Train Ledger

Date: 2026-05-31

## Objective

Release current DayOA fixes so DYEC can pin a deployed DayOA tag for a new cluster validation round.

## Gate 0

| Check | Evidence | Status |
|---|---|---|
| Repo | `/Users/jmajor/projects/daylily/daylily-omics-analysis` on `codex/dayoa-local-evidence-dewey-refactor-20260528` | SUCCESS |
| Dirty state | `README.md`, `docs/workflows/bclconvert.md`, `tests/test_bclconvert_multiqc.py`, `workflow/scripts/prepare_bclconvert_lane_samplesheet.py`, `workflow/scripts/run_bclconvert_lane.sh`, release ledger | SUCCESS |
| Latest semver tag | `2.0.25`; `git cat-file -t 2.0.25` -> `tag` | SUCCESS |
| Release target | `2.0.26`, annotated non-`v` tag | OPEN |

## Rows

| ID | Requirement | Status | Evidence |
|---|---|---|---|
| DAYOA-001 | Keep lane-specific BCL Convert sample sheets from emitting unsupported `GenerateFastqcMetrics`. | SUCCESS | `workflow/scripts/prepare_bclconvert_lane_samplesheet.py`; `tests/test_bclconvert_multiqc.py::test_bclconvert_lane_samplesheet_strips_fastqc_metrics_setting`. |
| DAYOA-002 | Validate focused BCL behavior and repository health sufficient for release. | SUCCESS | `bash -n dyoainit`; `python -m pytest -q` -> `249 passed`; Ruff check for modified Python files passed; `git diff --check` passed. |
| DAYOA-003 | Commit, tag `2.0.26`, push branch/tag, build, and publish. | OPEN |  |
