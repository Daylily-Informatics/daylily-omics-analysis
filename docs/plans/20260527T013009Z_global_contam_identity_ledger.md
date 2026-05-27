# Global Contamination/Identity Bundle Ledger

Controlling plan: chat request, 2026-05-27
Ledger path: `docs/plans/20260527T013009Z_global_contam_identity_ledger.md`

## Gate 0 Inventory Freeze

- Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- Branch/state: `## main...origin/main`
- HEAD: `2398d4a9fe9cf05b23bf76d5214f1b029dcfa2c2`
- Recent tags: `2.0.5`, `2.0.4`, `2.0.3`, `2.0.2`, `2.0.1`
- Pre-existing dirty files not owned by this ledger at start:
  - `bin/day_activate`
  - `bin/util/profile_freshness_warn.bash`
  - `config/day_profiles/local/templates/profile.info`
  - `config/day_profiles/local/templates/profile_env.bash`
  - `dyoainit`
  - `tests/test_shell_wrapper_contracts.py`
- Required instruction files read:
  - `AGENTS.md`
  - `/Users/jmajor/.codex/docs/plan-ledger-workflow.md`
- Local instruction discovery: `find . -maxdepth 2 -type f \( -path './.codex/*' -o -path './.agents/*' -o -name AGENTS.md -o -name CLAUDE.md \) -print | sort` -> `./AGENTS.md`
- Recon commands:
  - `rg -n "include: \"rules/verifybamid2_contam.smk\"|include: \"rules/site_mix_contam.smk\"|include: \"rules/relatedness_batch.smk\"|MULTIQC_QC_LONG_RUNNING_TOOLS|def qc_tool_enabled|rule contamination_mqc_gather|rule produce_site_mix_contam_estimate|rule produce_peddy|rule produce_relatedness|def stage_known_input" workflow/Snakefile workflow/rules/common.smk workflow/rules/site_mix_contam.smk workflow/rules/peddy.smk workflow/rules/relatedness_batch.smk workflow/scripts/stage_multiqc_inputs.py`
  - `rg -n "custom_data|sp:|contamination:|relatedness:|peddy_sample_qc|unmapped_metagenomics" config/external_tools/multiqc_config.yaml`
  - Memory recon confirmed previous DayOA contamination/MultiQC proof surfaces and prior VerifyBamID2/GATK disagreement context.
- Current implementation anchors:
  - Active includes: `site_mix_contam.smk`, `relatedness_batch.smk`, `verifybamid2_contam.smk`
  - Current aggregation: `workflow/rules/site_mix_contam.smk::contamination_mqc_gather`
  - Current parser: `workflow/scripts/compile_contamination_mqc.py`
  - Current final MultiQC gate: `workflow/rules/multiqc_final_wgs.smk::_alignment_component_inputs`
  - Current staging: `workflow/scripts/stage_multiqc_inputs.py`
  - Current MultiQC custom content: `config/external_tools/multiqc_config.yaml`
- Baseline tests: deferred until after source changes because the user requested implementation and the repo already has unrelated dirty shell/profile edits.
- Live cluster validation: blocked for this ledger until run through `daylily-ec` on a configured headnode with an explicit non-default AWS profile.

## Control Ledger

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| GCI-001 | Ledger | Record Gate 0 before runtime edits | SUCCESS | feature_implementation | Gate 0 | orchestrator | This ledger Gate 0 section |  | Gate 0 recorded with dirty state and recon anchors. |
| GCI-002 | Snakemake | Add global contamination/identity rule bundle and targets | OPEN | feature_implementation | Gate 1 | orchestrator |  |  |  |
| GCI-003 | Snakemake | Retire VerifyBamID2 from active Snakemake include | OPEN | removable_compatibility_debt | Gate 1 | orchestrator |  |  |  |
| GCI-004 | Config | Add explicit config blocks for contam identity tools | OPEN | config_or_startup_contract | Gate 2 | orchestrator |  |  |  |
| GCI-005 | Parsing | Add evidence-only parser and `_mqc.tsv` outputs | OPEN | feature_implementation | Gate 1 | orchestrator |  |  |  |
| GCI-006 | MultiQC | Gate final MultiQC on `contam_identity` and stage native evidence | OPEN | feature_implementation | Gate 1 | orchestrator |  |  |  |
| GCI-007 | Tests | Add parser and Snakemake contract tests | OPEN | contract_test | Gate 5 | orchestrator |  |  |  |
| GCI-008 | Docs | Document tool inventory, evidence semantics, and VerifyBamID2 retirement | OPEN | historical_docs_only | Gate 5 | orchestrator |  |  |  |
| GCI-009 | Validation | Run focused tests, broader tests/coverage if feasible, and dry-run where possible | OPEN | contract_test | Gate 5 | orchestrator |  |  |  |
