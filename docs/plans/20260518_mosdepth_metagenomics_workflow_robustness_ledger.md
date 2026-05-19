# 20260518 Mosdepth, Metagenomics, And Workflow Robustness Ledger

## Gate 0 Baseline

- Ledger path: `docs/plans/20260518_mosdepth_metagenomics_workflow_robustness_ledger.md`
- Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- Baseline time: `2026-05-18T18:31:44Z`
- Baseline branch: `main...origin/main`
- Pre-existing untracked files:
  - `docs/202260518_sequening_analysis_state.md`
  - `docs/20260518.html`
  - `docs/plans/20260518_day_run_version_publish_ledger.md`
  - `docs/plans/20260518_html_report_publish_ledger.md`
  - `docs/plans/run_qc_ont_all_cloudfront_publish_ledger.md`
- Instruction files read:
  - `AGENTS.md`
  - `/Users/jmajor/.codex/docs/plan-ledger-workflow.md`
- Sweep evidence:
  - `rg -n "mosdepth=|find .*\\|.*head|find .*\\|.*grep.*head|max_reads|unmapped_metagenomics|produce_snpeff|stage_multiqc_inputs|_mqc\\.log|daylily.failed_run|PERCENT_USED|sample_sex_for_required_tool\\(wildcards, \\\"ExpansionHunter\\\"\\)|cohort.samples.tsv|somalier" workflow bin dyoainit config tests docs -S`
  - Current mosdepth env pin is `workflow/envs/mosdepth_v0.1.yaml: mosdepth=0.3.2`.
  - Current unmapped metagenomics target is `produce_unmapped_metagenomics_quick` with `max_reads` capping.
  - Current `bin/day_run` non-dry-run branch can mask failed Snakemake by returning the `echo daylily.failed_run` status.
  - Current `dyoainit` budget display calculates `PERCENT_USED` even when budget fields are missing.
  - Current SIGPIPE-prone gather patterns exist in `workflow/rules/seqfu.smk`, `workflow/rules/calc_coverage_eveness.smk`, and `workflow/rules/calc_coverage_evenness_two.smk`.
  - Current Somalier batch rule already declares `cohort.samples.tsv`, `cohort.pairs.tsv`, `cohort.groups.tsv`, and `cohort.html`, and moves extract outputs to deterministic paths.
  - Current MultiQC final rules already pass `--ignore "*_mqc.log"`.
  - Current `workflow/rules/snpeff.smk` still defines `produce_snpeff`, although docs call SnpEff dormant/disabled.
- Assumptions:
  - "Most recent mosdepth" means upstream/Bioconda `0.3.14`.
  - "Fastest" unmapped metagenomics means Kraken2 `--quick` over all primary pass-QC human-unmapped reads.
  - Kraken2 DB path remains explicit config; no inferred DB path or fallback.
  - Control detection is metadata-only from `sample_info`, not sample-name inference.

## Status Protocol

Statuses: `OPEN`, `IN_PROGRESS`, `ATTEMPTING_BUGFIX`, `SUCCESS`, `DUPLICATE`, `NO_LONGER_NEEDED`, `FAIL`, `BLOCKED`.

## Ledger Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| G0-001 | Ledger | Record baseline repo status, sweeps, current mosdepth/metagenomics wiring, and dirty files. | SUCCESS | plan_amendment | Gate 0 | Agent 0 | Gate 0 section above. |  | Baseline captured before implementation edits. |
| MOS-001 | Mosdepth | Pin mosdepth to `0.3.14`. | SUCCESS | feature_implementation | Gate 1 | Agent 1 | `workflow/envs/mosdepth_v0.1.yaml`; `python -m pytest -q tests/test_mosdepth_contracts.py` -> 3 passed. | Older env pin was stale. | Mosdepth env now pins `mosdepth=0.3.14`. |
| MOS-002 | Mosdepth | Harden mosdepth strict shell and declared output checks. | SUCCESS | feature_implementation | Gate 1 | Agent 1 | `workflow/rules/mosdepth.smk`; `tests/test_mosdepth_contracts.py`; focused suite -> 114 passed. | Mosdepth outputs were not contract-checked tightly enough for staged reporting. | Rule shell now uses strict checks and validates declared native outputs. |
| MOS-003 | Mosdepth/MultiQC | Enable mosdepth by default in final/kitchen-sink alignment QC. | SUCCESS | feature_implementation | Gate 1 | Agent 0/1 | `_alignment_qc_native_inputs()` includes mosdepth summaries for `QC_CRAM_ALIGNERS` and `qc_alignment_dedupers()`; focused suite -> 114 passed. | Mosdepth was optional/stale relative to final alignment QC expectations. | Final/kitchen-sink staged MultiQC now expects native mosdepth summaries by default. |
| META-001 | Metagenomics | Keep Kraken2 as the fastest default metagenomic classifier. | SUCCESS | feature_implementation | Gate 1 | Agent 5 | `workflow/rules/unmapped_metagenomics.smk`; `docs/catalog_of_tools.md`; `tests/test_unmapped_metagenomics.py` -> included in 114 passed. | Existing Kraken2 surface matched fastest repo-native path. | Kraken2 remains the only implemented unmapped metagenomics classifier. |
| META-002 | Metagenomics | Change unmapped metagenomics from capped `max_reads` mode to `read_limit: all` default. | SUCCESS | feature_implementation | Gate 1 | Agent 5 | `workflow/rules/unmapped_metagenomics.smk`; `workflow/scripts/summarize_unmapped_metagenomics.py`; `tests/test_unmapped_metagenomics.py::test_summarize_unmapped_metagenomics_rejects_capped_read_limit`. | Prior rule implemented a capped quick screen. | Capped reads are rejected; summary rows report `read_limit=all`. |
| META-003 | Metagenomics | Add Kraken2 `--quick` default and reject `--memory-mapping` unless explicitly configured. | SUCCESS | feature_implementation | Gate 1 | Agent 5 | `kraken2 --quick` in `workflow/rules/unmapped_metagenomics.smk`; `memory_mapping` defaults false; focused suite -> 114 passed. | Fast-all mode needed an explicit fastest classifier behavior. | Kraken2 always gets `--quick`; `--memory-mapping` appears only when `memory_mapping: true`. |
| META-004 | Metagenomics | Require explicit `unmapped_metagenomics.kraken2_db`; do not invent DB paths. | SUCCESS | config_or_startup_contract | Gate 2 | Agent 5 | `test -d {params.kraken2_db:q}` and config validation in `workflow/rules/unmapped_metagenomics.smk`; focused suite -> 114 passed. | A metagenomic DB is operator-specific and must not be inferred. | Missing or non-directory DB fails hard. |
| META-005 | Metagenomics/MultiQC | Add unmapped metagenomics to kitchen-sink/final MultiQC only when explicitly enabled/configured. | SUCCESS | feature_implementation | Gate 1 | Agent 0/5 | `workflow/rules/multiqc_final_wgs.smk`; `workflow/scripts/stage_multiqc_inputs.py`; `config/external_tools/multiqc_config.yaml`; focused suite -> 114 passed. | Focused Kraken2 report was not connected to final staged MultiQC. | Final MultiQC includes custom and native Kraken inputs only with `enable_tools=['unmapped_metagenomics']` and explicit config. |
| PIPE-001 | Shell | Remove SIGPIPE-prone `find | head` patterns. | SUCCESS | feature_implementation | Gate 1 | Agent 2 | `workflow/rules/seqfu.smk`; `workflow/rules/calc_coverage_eveness.smk`; `workflow/rules/calc_coverage_evenness_two.smk`; `tests/test_shell_wrapper_contracts.py`; focused suite -> 114 passed. | `find | head` under pipefail can return 141/SIGPIPE even when the selected path exists. | Scoped SeqFu and coverage gathers now use declared inputs or arrays instead of pipefail-prone global scans. |
| RUN-001 | Wrapper | Make `bin/day_run` return real Snakemake failures. | SUCCESS | feature_implementation | Gate 1 | Agent 2 | `bin/day_run`; `tests/test_shell_wrapper_contracts.py::test_day_run_failed_snakemake_writes_marker_and_exits_nonzero`; focused suite -> 114 passed. | Failure marker `echo` could mask the Snakemake nonzero exit. | `day_run` now captures the workflow status before writing the failure marker and exits with that status. |
| ACT-001 | Activation | Harden `dyoainit --skip-project-check`. | SUCCESS | legitimate_safety_handling | Gate 4 | Agent 2 | `dyoainit`; `tests/test_shell_wrapper_contracts.py`; `bash tests/test_cli_commands.sh` -> 25 passed. | Budget display and unset-shell variables could fail before workflow execution. | `--skip-project-check` avoids budget math and exports `NA` budget fields; invalid project/budget state fails hard. |
| PATH-001 | QC Pathing | Prevent `sent/na` downstream QC leaks. | SUCCESS | feature_implementation | Gate 1 | Agent 0/3 | `qc_variant_dedupers()` in `workflow/rules/common.smk`; Peddy, relatedness, site-mix, and unmapped-metagenomics use non-`na` deduper families where downstream QC should not consume no-dedup outputs; focused suite -> 114 passed. | Alignment-QC no-dedup scope leaked into downstream QC aggregation. | Relatedness/Somalier and Peddy now avoid `na`; contamination uses real dedupers; metagenomics uses real dedupers for fast-all mode. |
| CTRL-001 | Controls | Metadata-only control/NTC gating. | SUCCESS | feature_implementation | Gate 1 | Agent 3 | `workflow/rules/common.smk`; `workflow/rules/peddy.smk`; `workflow/rules/site_mix_contam.smk`; `workflow/rules/relatedness_batch.smk`; `tests/test_qc_eligibility_contracts.py`; focused suite -> 114 passed. | NTC/control samples were inferred or allowed into tools that cannot produce meaningful outputs. | Negative controls/NTCs are excluded by explicit metadata; positive controls remain eligible. |
| EH-001 | ExpansionHunter | Gate ExpansionHunter before DAG construction for sex `na`. | SUCCESS | feature_implementation | Gate 1 | Agent 3 | `workflow/rules/expansionhunter.smk`; `tests/test_qc_eligibility_contracts.py`; `tests/test_expansionhunter_contracts.py`; focused suite -> 114 passed. | ExpansionHunter could enter the DAG with invalid sex metadata. | Non-control samples must have male/female sex metadata before ExpansionHunter targets expand. |
| SOM-001 | Somalier | Deterministic Somalier output paths and declared cohort outputs. | SUCCESS | feature_implementation | Gate 1 | Agent 3 | `workflow/rules/relatedness_batch.smk`; `workflow/scripts/stage_multiqc_inputs.py`; `tests/test_qc_eligibility_contracts.py`; focused suite -> 114 passed. | Somalier native names did not reliably match declared Snakemake output paths. | Extract outputs are moved to deterministic paths; cohort `samples`, `pairs`, `groups`, and `html` outputs are declared and checked. |
| SNPEFF-001 | Annotation | Remove deprecated SnpEff from kitchen-sink paths. | SUCCESS | removable_compatibility_debt | Gate 1 | Agent 3 | `workflow/Snakefile` keeps `# include: "rules/snpeff.smk"`; `workflow/rules/snpeff.smk` removes help-visible `# TARGET`; `tests/test_multiqc_qc_targets.py`; focused suite -> 114 passed. | Deprecated SnpEff was visible in old target surfaces. | SnpEff remains dormant/unimported and is not pulled into final MultiQC paths. |
| MQC-001 | MultiQC | Add/test concrete `produce_multiqc_stage_final`. | SUCCESS | feature_implementation | Gate 1 | Agent 4 | `workflow/rules/multiqc_final_wgs.smk`; `tests/test_multiqc_staging_contracts.py::test_final_stage_alias_is_concrete_and_targets_final_stage_done`; focused suite -> 114 passed. | Rule-name target invocation cannot be wildcarded. | Concrete alias targets `reports/multiqc_inputs/final/.stage.done`. |
| MQC-002 | MultiQC | Prove `*_mqc.log` files are ignored by MultiQC custom content. | SUCCESS | contract_test | Gate 1 | Agent 4 | `workflow/rules/multiqc_final_wgs.smk`; `workflow/scripts/multiqc_log_guard.py`; `tests/test_multiqc_staging_contracts.py`; focused suite -> 114 passed. | Custom-content discovery could parse log files as tables. | Report rules ignore `*_mqc.log`; guard renames empty legacy logs and rejects non-empty matches. |
| TEST-001 | Tests | Run focused pytest suite and record results. | SUCCESS | contract_test | Gate 5 | Agent 0 | `python -m pytest -q tests/test_unmapped_metagenomics.py tests/test_mosdepth_contracts.py tests/test_multiqc_staging_contracts.py tests/test_shell_wrapper_contracts.py tests/test_qc_eligibility_contracts.py tests/test_multiqc_qc_targets.py tests/test_multiqc_sample_identifiers.py tests/test_giab_qc_contracts.py tests/test_expansionhunter_contracts.py tests/test_workflow_target_aliases.py` -> 114 passed; `bash tests/test_cli_commands.sh` -> 25 passed; `python -m py_compile workflow/scripts/stage_multiqc_inputs.py workflow/scripts/summarize_unmapped_metagenomics.py workflow/scripts/relatedness_report.py` -> pass; `git diff --check` -> pass. |  | Focused static/contract gates passed; no live Snakemake execution was launched from this repo checkout. |
| FINAL-001 | Final | Terminalize rows and report objective completion. | SUCCESS | plan_amendment | Gate 5 | Agent 0 | All ledger rows terminal after integration and verification. |  | Objective complete at repo implementation/test level. |

## Final Evidence

- Implementation paths changed: `bin/day_run`, `dyoainit`, `config/external_tools/multiqc_config.yaml`, `workflow/envs/mosdepth_v0.1.yaml`, `workflow/rules/{common,mosdepth,seqfu,calc_coverage_eveness,calc_coverage_evenness_two,peddy,site_mix_contam,relatedness_batch,expansionhunter,snpeff,multiqc_final_wgs,unmapped_metagenomics}.smk`, `workflow/scripts/{stage_multiqc_inputs,summarize_unmapped_metagenomics}.py`, docs, and focused tests.
- Focused pytest gate: `python -m pytest -q tests/test_unmapped_metagenomics.py tests/test_mosdepth_contracts.py tests/test_multiqc_staging_contracts.py tests/test_shell_wrapper_contracts.py tests/test_qc_eligibility_contracts.py tests/test_multiqc_qc_targets.py tests/test_multiqc_sample_identifiers.py tests/test_giab_qc_contracts.py tests/test_expansionhunter_contracts.py tests/test_workflow_target_aliases.py` -> 114 passed.
- CLI guard gate: `bash tests/test_cli_commands.sh` -> 25 passed.
- Syntax/static gates: `python -m py_compile workflow/scripts/stage_multiqc_inputs.py workflow/scripts/summarize_unmapped_metagenomics.py workflow/scripts/relatedness_report.py` -> pass; `git diff --check` -> pass.
- No live Snakemake run or headnode workflow was launched for this repo implementation pass.
