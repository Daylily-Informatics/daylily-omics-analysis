# HG003 1x Hybrid MultiQC / AlignStats Dry-Run Ledger

Created: 2026-05-26T14:58:05Z

## Objective

Commit the current DayOA dirty work, update DayOA to consume the tagged
`lsmc-bio/MultiQC` fork release with native AlignStats autodetection, tag a new
DayOA release, and use that DayOA tag for a non-destructive HG003 1x hybrid
dry-run on the `hyb-hg003` cluster.

Requested dry-run command:

```bash
dy-r produce_snv_concordances produce_multiqc_final produce_alignstats -j 50 -p -k -n
```

## Gate 0 Inventory

- Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`.
- Initial branch: `codex/tstclu411c-hybrid-env-python`.
- Initial DayOA version: `1.0.36` at `6aa9a9f789bdbb14a1088c3e35e9e6af30313979`.
- Initial dirty state: untracked `docs/plans/20260526T144550Z_reference_runtime_assets_path_cutover_ledger.md`.
- Target DayOA release tag for this dry-run: `1.0.40`.
- MultiQC fork release to consume: `1.36.dev0-lsmc.6`.
- MultiQC release evidence: remote tag `1.36.dev0-lsmc.6` resolves to annotated tag object `3aa74d4b28f7272fcf95776cd89b77ca6d07629b` and commit `1955aa4971b0868f377bec0d21bfb7a7eac7c699`.
- DayOA target evidence: `produce_snv_concordances`, `produce_multiqc_final`, and `produce_alignstats` exist in `workflow/rules`.
- Cluster: `hyb-hg003`; AWS profile `lsmc`; region `us-west-2`.
- Access model: SSM/daylily-ec only; no direct SSH.
- Run mode: dry-run only (`-n`), no destructive AWS or FSx mutation requested.
- Genome build: `hg38_broad`.

## Ledger

| ID | Area | Requirement | Status | Category | Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| HG1X-001 | Inventory | Record baseline repo state, target names, release inputs, and cluster assumptions. | SUCCESS | contract_test | Gate 0 | orchestrator | Gate 0 section; `rg` confirmed target rule names. |  | Baseline recorded. |
| HG1X-002 | DayOA pin | Update `workflow/envs/multiqc_v0.1.yaml` to consume MultiQC `1.36.dev0-lsmc.6`. | SUCCESS | feature_implementation | Gate 1 | orchestrator | `workflow/envs/multiqc_v0.1.yaml`; `pip download --no-deps https://github.com/lsmc-bio/MultiQC/archive/refs/tags/1.36.dev0-lsmc.6.zip` succeeded. |  | MultiQC env pin updated and install URL validated. |
| HG1X-003 | DayOA release | Commit all new/changed/dirty DayOA files, push branch, create annotated DayOA tag `1.0.40`, and push tag. | OPEN | feature_implementation | Gate 2 | orchestrator |  |  |  |
| HG1X-004 | Manifest | Stage or identify an HG003 1x hybrid manifest for the dry-run without silently substituting another sample or non-hybrid dataset. | OPEN | contract_test | Gate 3 | orchestrator |  |  |  |
| HG1X-005 | Cluster preflight | Verify SSM/headnode access, `ubuntu` user, `day-clone`, `tmux`, and `squeue` on `hyb-hg003`. | OPEN | contract_test | Gate 3 | orchestrator |  |  |  |
| HG1X-006 | Dry-run | Run the requested `dy-r` command from the new DayOA tag using the HG003 1x hybrid manifest and capture exit status. | OPEN | contract_test | Gate 4 | orchestrator |  |  |  |
| HG1X-007 | Final status | Update this ledger with terminal row states and report exact DayOA/MultiQC tags and dry-run result. | OPEN | contract_test | Gate 5 | orchestrator |  |  |  |

## Acceptance Criteria

- DayOA branch is pushed and tagged before cluster testing.
- `workflow/envs/multiqc_v0.1.yaml` installs `lsmc-bio/MultiQC` tag
  `1.36.dev0-lsmc.6`.
- The cluster workdir is cloned from the new DayOA tag, not a floating branch.
- The dry-run uses HG003 hybrid inputs and the exact requested target list and
  flags.
- Any missing manifest, missing cluster command, or missing target fails loudly
  and is recorded here; no alternate target or non-HG003 dataset is substituted.

## Local Validation Before Release Tag

- `python -m pytest -q tests/test_ultima_run_qc_contracts.py tests/test_multiqc_qc_targets.py tests/test_multiqc_sample_identifiers.py tests/test_workflow_target_aliases.py` -> `54 passed`.
- `git diff --check` -> passed.
- Secret scan for OpenAI keys, AWS secrets, private keys, signed URLs, and bearer tokens -> no matches.
- `pip download --no-deps https://github.com/lsmc-bio/MultiQC/archive/refs/tags/1.36.dev0-lsmc.6.zip` -> succeeded.
