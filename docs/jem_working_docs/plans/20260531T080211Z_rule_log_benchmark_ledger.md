# Rule Log And Benchmark Directive Ledger

Created: 2026-05-31T08:02:11Z

## Objective

Add explicit `log:` and `benchmark:` directives to every Snakemake rule imported by `workflow/Snakefile` that is missing either directive, using names consistent with nearby existing patterns.

## Gate 0: Inventory Freeze

| Item | Evidence |
|---|---|
| Repo | `/Users/jmajor/projects/daylily/daylily-omics-analysis` |
| Branch | `codex/dayoa-local-evidence-dewey-refactor-20260528` |
| Dirty state before edits | Existing modified/untracked files present before this change; do not revert or overwrite unrelated work. |
| Existing dirty files | `README.md`, `config/day_profiles/local/templates/rule_config.yaml`, `config/day_profiles/slurm/templates/rule_config.yaml`, `config/external_tools/multiqc_config.yaml`, `daylily_omics_analysis/evidence_manifest.py`, `docs/README.md`, `docs/catalog_of_tools.md`, `docs/ops/multiqc_qc_targets.md`, `docs/plans/20260531T061528Z_dayoa_catalog_repair_release_ledger.md`, `docs/specs/ugrun_cli_contract.md`, `docs/workflows/bclconvert.md`, `docs/workflows/ultima_run_qc.md`, `tests/test_bclconvert_bootstrap.sh`, `tests/test_bclconvert_multiqc.py`, `tests/test_evidence_manifest.py`, `tests/test_run_qc_reports.py`, `workflow/rules/bclconvert.smk`, `workflow/rules/run_qc_reports.smk`, untracked `docs/ops/results_directory_structure.md`, `docs/plans/20260531T074927Z_dayoa_evidence_manifest_dewey_qeo_ledger.md`, `workflow/scripts/prepare_bclconvert_demux_fastqc_inputs.py`. |
| Include inventory command | `rg -n '^\\s*include:' workflow/Snakefile workflow/rules` |
| Baseline audit command | Python parser over `workflow/Snakefile` direct/transitive includes, detecting `rule`/`checkpoint` blocks and `log:`/`benchmark:` directives. |
| Imported rule files | 86 |
| Imported rules | 500 |
| Executable imported rules | 444 |
| Executable rules with both before edits | 208 |
| Executable rules missing either before edits | 236 |
| Aggregate/input-only rules missing either before edits | 56 |
| Rules in `workflow/Snakefile` itself | `day` and `all`, both executable and missing both before edits. |

## Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| RLB-001 | Inventory | Record imported rule baseline and dirty state before edits. | SUCCESS | feature_implementation | Gate 0 | orchestrator | Gate 0 table above. |  | Inventory recorded before runtime rule edits. |
| RLB-002 | Workflow rules | Add missing `log:` directives to executable imported rules and `workflow/Snakefile` executable rules. | SUCCESS | feature_implementation | Gate 1 | codex | Added directives across `workflow/Snakefile` and imported `workflow/rules/*.smk` files. |  | Executable rules now have `log:` directives. |
| RLB-003 | Workflow rules | Add missing `benchmark:` directives to executable imported rules and `workflow/Snakefile` executable rules. | SUCCESS | feature_implementation | Gate 1 | codex | Added directives across `workflow/Snakefile` and imported `workflow/rules/*.smk` files. |  | Executable rules now have `benchmark:` directives. |
| RLB-004 | Aggregate rules | Add missing `log:` and `benchmark:` directives to aggregate/input-only imported rules when syntactically accepted by Snakemake. | SUCCESS | feature_implementation | Gate 1 | codex | Added directives to aggregate/input-only targets; normalized older five-space `input:` indentation in deprecated target rules. |  | Aggregate/input-only imported rules now have both directives under the static parser contract. |
| RLB-005 | Validation | Re-run the audit and prove no imported rules are missing either directive. | SUCCESS | contract_test | Gate 5 | codex | Final audit: 87 files, 501 rules, `missing_any=0`, `missing_exec=0`; wildcard consistency audit: `log_benchmark_wildcard_mismatches=0`. |  | Missing-directive and wildcard-consistency audits are clean. |
| RLB-006 | Validation | Run focused Snakemake parse/list validation and available tests. | SUCCESS | contract_test | Gate 5 | codex | `git diff --check` passed; `python -m pytest -q tests/test_rule_log_benchmark_contracts.py` -> 2 passed; `python -m pytest -q tests/test_workflow_target_aliases.py tests/test_multiqc_qc_targets.py tests/test_multiqc_staging_contracts.py` -> 36 passed; `python -m pytest -q tests` -> 248 passed. `snakemake` executable/module was unavailable in local `DAY-EC`, so Snakemake parse/list validation could not be run locally. |  | Local static and pytest validation passed; live Snakemake parse remains environment-dependent. |

## Final Evidence

- Files changed by this rule-directive pass: 78 existing workflow files plus this ledger and `tests/test_rule_log_benchmark_contracts.py`.
- Final static directive audit: 87 Snakefile/imported files, 501 rules, 0 missing `log:`, 0 missing `benchmark:`.
- Final log/benchmark wildcard-set audit: 0 mismatches.
- Test evidence:
  - `git diff --check` passed.
  - `python -m pytest -q tests/test_rule_log_benchmark_contracts.py` -> 2 passed.
  - `python -m pytest -q tests/test_workflow_target_aliases.py tests/test_multiqc_qc_targets.py tests/test_multiqc_staging_contracts.py` -> 36 passed.
  - `python -m pytest -q tests` -> 248 passed.
- Local limitation:
  - `snakemake` and `python -m snakemake` are not available in the local `DAY-EC` environment, so direct Snakemake parse/list validation was not executed on this Mac.
