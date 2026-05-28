# Kitchen Sink Expansion Ledger

Created: 2026-05-28T20:44:53Z

Controlling plan: user-provided "Kitchen Sink Expansion Plan" in chat on 2026-05-28.

Ledger path: `docs/plans/20260528T204453Z_kitchen_sink_expansion_ledger.md`

Repos:

- DayOA: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- DYEC: `/Users/jmajor/projects/daylily/daylily-ephemeral-cluster`

## Gate 0 Inventory Freeze

- DayOA git status before edits: `## codex/dayoa-local-evidence-dewey-refactor-20260528...origin/codex/dayoa-local-evidence-dewey-refactor-20260528`; no dirty paths reported.
- DYEC git status before edits: branch `codex/docs-plans-ledgers...origin/codex/docs-plans-ledgers [gone]`; pre-existing dirty/untracked paths included `AGENTS.md`, staged index summary TSVs, backup config files, `docs/ntc_and_other_analysis_bugs.md`, `qc_vs_qc.tsv`, `reports/stage_*`, and `tmp-export/`.
- DYEC write boundary: only `config/daylily_available_repositories.yaml`, packaged payload catalog, and catalog tests are in scope.
- DayOA active target registry inspected: `config/workflow_target_aliases.tsv`.
- Active Snakefile include sweep inspected: `workflow/Snakefile`.
- Current kitchen-sink catalog command inspected: DYEC `illumina_snv_alignstats_relatedness_vep_multiqc`.
- Evidence manifest status: `produce_multiqc_all` already includes `results/day/{build}/reports/dayoa_evidence_manifest.json`.
- Assumption: "all available" means current active target aliases and active included rule families; retired/commented rule files remain excluded.
- Live validation boundary: no headnode or AWS execution is approved for this ledger; live resource-dependent checks remain blocked unless explicit profile/cluster credentials are provided.

## Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| KS-001 | DayOA | Add `produce_kitchen_sink` aggregate that delegates to all active broad evidence targets. | SUCCESS | feature_implementation | Gate 1 | orchestrator | `workflow/rules/workflow_target_aliases.smk` adds `KITCHEN_SINK_TARGETS`, `_kitchen_sink_inputs`, and `rule produce_kitchen_sink`. |  | Aggregate target delegates to all active selector families plus alignstats, concordance, relatedness, VEP, Cyrius HTD, ExpansionHunter, LongTR catalogs, metagenomics, global contamination/identity, final MultiQC, and the DayOA evidence manifest. |
| KS-002 | DayOA | Add/adjust tests proving aggregate target covers active caller aliases and active QC bundles. | SUCCESS | contract_test | Gate 1 | orchestrator | `tests/test_workflow_target_aliases.py`; focused command `python -m pytest -q tests/test_workflow_target_aliases.py tests/test_workflow_catalog.py tests/test_multiqc_qc_targets.py tests/test_multiqc_staging_contracts.py` -> `45 passed`. |  | DayOA contracts cover broad aggregate selectors, active QC bundles, evidence manifest inclusion, and retired-rule exclusions. |
| KS-003 | DYEC | Expand kitchen-sink command catalog targets and explicit config. | SUCCESS | feature_implementation | Gate 1 | orchestrator | DYEC `config/daylily_available_repositories.yaml` and packaged payload catalog updated; YAML parse check reported 16 targets, 25 SNV callers, dry-run command ending `-n`. |  | DYEC kitchen-sink command now enumerates all active broad targets, aligners, dedupers, SNV callers, SV callers, `htd_callers=["cyrius"]`, and optional MultiQC report families. |
| KS-004 | DYEC | Add/adjust catalog tests proving the expanded target/config contract and source-vs-packaged catalog parity. | SUCCESS | contract_test | Gate 1 | orchestrator | `tests/test_repository_catalog.py`; `python -m pytest -q tests/test_cli_registry_v2.py::test_samples_run_stages_then_launches_catalog_command tests/test_repository_catalog.py` -> `9 passed`. |  | DYEC tests validate expanded target/config contract and source packaged catalog parity. |
| KS-005 | DayOA/DYEC | Preserve retired/commented rule exclusions. | SUCCESS | contract_test | Gate 1 | orchestrator | DayOA `tests/test_workflow_target_aliases.py` and DYEC `tests/test_repository_catalog.py` assert retired terms are absent from kitchen-sink surfaces. |  | VerifyBamID/VerifyBamID2, Parascopy, GeneToCN, Gauchian, SMACA, SMN12, Stargazer, SnpEff, Picard/Qualimap/KAT-style retired surfaces were not revived. |
| KS-006 | Validation | Run focused tests and feasible full validation. | SUCCESS | contract_test | Gate 5 | orchestrator | DayOA focused -> `45 passed`; DayOA full `python -m pytest -q tests` -> `234 passed`; DayOA coverage -> `TOTAL 82%`; DYEC focused -> `9 passed`; DYEC full `python -m pytest -q tests` -> `875 passed, 7 skipped`. |  | Local validation passed; coverage exceeded the requested 80% threshold. |
| KS-007 | Live Dry Run | Snakemake/DYEC live dry-run on configured headnode. | BLOCKED | contract_test | Gate 5 | orchestrator | No AWS profile/region/cluster/headnode execution approval supplied in this turn. | Live DYEC headnode context is required. | Blocked until user supplies explicit live cluster context and approves the dry-run. |

## Final Terminal State

- Working rows remaining: 0.
- Success rows: 6.
- Blocked rows: 1 (`KS-007`, live headnode dry-run only).
- Local implementation objective: complete.
