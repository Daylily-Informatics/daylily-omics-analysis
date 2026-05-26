# Staging External Sequencing Data Cutover Ledger

Controlling DayEC ledger: `/Users/jmajor/.codex/worktrees/dyec-fsx-dra-mounts/daylily-ephemeral-cluster/docs/plans/20260526T102840Z_staging_external_sequencing_data_cutover_ledger.md`
Ledger path: `/Users/jmajor/projects/daylily/daylily-omics-analysis/docs/plans/20260526T102840Z_staging_external_sequencing_data_cutover_ledger.md`

## Gate 0 Baseline

- Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- Branch: `codex/tstclu411c-hybrid-env-python`
- HEAD at baseline: `398ca8b0d457ff1b0c9fa350b52961db9185404d`
- Status: dirty before this change with many pre-existing modified fixtures, docs, scripts, workflow files, and untracked plan/spec artifacts.
- Active DayOA source does not own DayEC S3 staging writes; it consumes generated `samples.tsv` and `units.tsv` from DayEC and documents the explicit role roots.
- Active DayOA grep for `staged_sample_data` outside `docs/plans`, `docs/archive`, and rendered images returned no current code hits; remaining `staged` text is generic MultiQC/workflow staging language, not the DayEC external sequencing-data subpath.
- Live AWS scope: no S3 copy, delete, lifecycle mutation, or real cluster creation is approved in this request.
- Assumption: DayOA docs should describe the active external sequencing staging path only where DayEC/production staging paths are named; generic workflow staging terms stay unchanged.

## Control Ledger

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| DAYOA-SED-001 | Orchestration | Record Gate 0 inventory and relationship to DayEC staging ownership. | SUCCESS | plan_amendment | Gate 0 | orchestrator | This ledger. |  | Gate 0 recorded before implementation. |
| DAYOA-SED-002 | Active code/docs | Update any active DayOA references to the renamed external sequencing staging subpath. | SUCCESS | feature_implementation | Gate 5 | orchestrator | Active DayOA sweep for `staged_sample_data`, `/fsx/staged_external`, `/fsx/staged`, and retired `/fsx/staging/staged` paths returned no code/doc/test hits outside excluded historical/generated areas. |  | No DayOA code edits required; DayEC owns generation of this path. |
| DAYOA-SED-003 | Live S3 prefixes | Rename or delete existing S3 prefixes. | BLOCKED | feature_implementation | Gate 5 | orchestrator | Existing copied prefixes remain `s3://lsmc-dayoa-staging-usw2/staged/` and `s3://lsmc-dayoa-staging-usw2/staged_sample_data/`. | S3 rename requires copy plus destructive delete; no exact source/destination copy approval or destructive delete approval was given in this request. | Blocked pending explicit live S3 copy/delete decision. |

## Terminal Report

- Status counts: `SUCCESS=2`, `BLOCKED=1`, `OPEN=0`, `IN_PROGRESS=0`, `ATTEMPTING_BUGFIX=0`, `FAIL=0`.
- Validation: active DayOA grep returned no current references requiring edit.
- Terminal acceptance met for DayOA active code/docs. Live S3 prefix rename/delete remains blocked pending explicit approval.
