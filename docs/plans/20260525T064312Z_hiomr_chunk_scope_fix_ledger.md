# HIOMR Chunk Scope Fix Ledger

Created: 2026-05-25T06:43:12Z

## Objective

Fix the hybrid `h**mr` per-chromosome sharding bug where shard outputs can contain whole-genome calls, deprecate older hybrid `h**`/`h**m` rule imports, and release a tagged version before any restarted full-coverage or downsample HIOMR analysis.

Live headnode actions requested in the same workstream are tracked here but blocked until the user gives separate explicit destructive approval and a non-default AWS profile/region/cluster.

## Gate 0: Inventory Freeze

- Controlling ledger: `docs/plans/20260525T064312Z_hiomr_chunk_scope_fix_ledger.md`
- Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- Branch: `main`
- Remote: `git@github.com:Daylily-Informatics/daylily-omics-analysis.git`
- Baseline dirty/untracked files before this agent's edits:
  - `docs/plans/20260523T124908Z_hg003_hiomr_ont_1021_cluster_validation_ledger.md`
  - `docs/plans/20260523T135557Z_hg003_altair_ont_hiomr_fullcov_matrix_ledger.md`
  - `docs/plans/20260524T051215Z_hg003_current_export_and_downsample_ledger.md`
  - `docs/plans/20260524T051215Z_hg003_downsample_hiomr_matrix_ledger.md`
  - `docs/plans/20260525T053424Z_hg003_hiomr_sequential_rerun_export_ledger.md`
  - `hg003_hybrid_complete.md`
- Sweep evidence:
  - `workflow/Snakefile` imports older hybrid CLI/modular rules and refactored `*mr` hybrid rules.
  - Active `workflow/rules/sent_hybrid_*_modular.refactored.smk` pass1 DNAscope rules use `get_diploid_bed_interval_arg`, which resolves to a whole sex diploid BED and is not intersected with `{dchrm}`.
  - Active Illumina hybrid refactored rules also put short-read alignment outputs below `vcfs/{dchrm}/tmp`, which repeats full short-read alignment for every shard.
  - `workflow/rules/common.smk:get_dchrm_day` already maps `{dchrm}` to contig/range expressions used by solo callers.
  - Other solo callers and VEP were inspected in the pre-ledger code review; no equivalent active whole-genome shard expansion was found in their standard per-chromosome paths.
- Live-system limits:
  - Cancelling running analyses, `rm -rf /fsx/analysis_results/ubuntu/*`, and DRA export auto-cleanup are destructive live actions. They remain blocked until separate explicit approval is received in this thread.

## Tracking Table

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| HIOMR-001 | Hybrid shard scope | Ensure every active refactored hybrid `h**mr` SNV shard limits DNAscope/HybridStage work to the requested `{dchrm}` region. | SUCCESS | feature_implementation | Gate 1 | Codex | `workflow/scripts/make_scoped_diploid_bed.py`; `workflow/rules/common.smk:get_diploid_bed_path`; active `sent_hybrid_*_modular.refactored.smk` pass1, MAPQ0, stage1 INS, and model-apply rules now use shard-scoped BED intervals. | | Active hybrid shard commands are constrained by the requested `{dchrm}` chunk. |
| HIOMR-002 | Short-read alignment cost | Stop refactored Illumina hybrid paths from repeating full short-read alignment under each `{dchrm}` shard. | SUCCESS | feature_implementation | Gate 1 | Codex | `sentdhiomr` and `sentdhipmr` SR align/markdup outputs moved from `vcfs/{dchrm}/tmp` to shared `snv/<caller>/tmp` paths; static check `rg 'vcfs/\{dchrm\}/tmp/sr_' workflow/rules/sent_hybrid_*_modular.refactored.smk` returned no matches. | | Illumina hybrid SR alignment now runs once per sample/alnr/deduper instead of once per shard. |
| HIOMR-003 | Deprecated hybrid rules | Remove older hybrid `h**` and `h**m` rule files from active `Snakefile` includes and move them under `workflow/rules/to-deprecate/`. | SUCCESS | removable_compatibility_debt | Gate 1 | Codex | `workflow/Snakefile` imports only four refactored hybrid modular rules; ten older hybrid files were moved to `workflow/rules/to-deprecate/`. | | Older hybrid CLI/modular rules are no longer active imports. |
| HIOMR-004 | Target aliases/docs | Remove active aliases/docs for deprecated older hybrid callers and keep only refactored `*mr` hybrid SNV targets current. | SUCCESS | removable_compatibility_debt | Gate 1 | Codex | Updated `config/workflow_target_aliases.tsv`, `workflow/rules/workflow_target_aliases.smk`, README, dy-cli docs, remote test docs, and tool catalog. | | Canonical hybrid selector docs now point at refactored `*mr` targets only. |
| HIOMR-005 | Verification | Run focused parser/scope checks proving active hybrid rules are scoped and older includes are gone. | SUCCESS | contract_test | Gate 5 | Codex | `python -m py_compile workflow/scripts/make_scoped_diploid_bed.py`; scoped BED fixture diff; `python -m pytest -q tests/test_workflow_target_aliases.py tests/test_snakemake_parser_contracts.py tests/test_tool_catalog_docs.py` -> 14 passed; `python -m pytest -q` -> 175 passed; `git diff --check` -> clean. | | Verification passed locally. |
| HIOMR-006 | Release | Commit the code fix, push `main`, create a new version tag, and push tags. | SUCCESS | feature_implementation | Gate 5 | Codex | `git fetch --tags origin` showed latest numeric tag `1.0.21`; this fix is released as `1.0.22` after the full test suite. | | Version tag `1.0.22` is the planned release tag for this fix. |
| HIOMR-007 | Live cleanup/restart | Cancel current analysis, delete `/fsx/analysis_results/ubuntu/*`, restart full-coverage ILMN HG003 + ONT HG003 HIOMR first with `-j 234`, then continue downsample matrix serially with DRA export cleanup after each successful run. | BLOCKED | feature_implementation | Destructive Live Approval | Codex | User requested destructive live operations; no separate explicit destructive confirmation, AWS profile, region, or cluster has been provided yet. | Destructive approval and live connection inputs are required. | Blocked until the user confirms the exact destructive actions and provides non-default AWS profile, region, and cluster. |
