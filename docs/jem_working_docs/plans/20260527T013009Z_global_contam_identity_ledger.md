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
  - `/Users/jmajor/.agents/AGENTS.md`
  - `/Users/jmajor/.codex/AGENTS.md`
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
| GCI-002 | Snakemake | Add global contamination/identity rule bundle and targets | SUCCESS | feature_implementation | Gate 1 | orchestrator | `workflow/rules/contam_identity.smk` adds `produce_ngstroublefinder_contam_identity`, `produce_haplocheck_contam_identity`, `produce_read_haps_contam_identity`, `produce_charr_contam_identity`, and `produce_global_contam_check`; full tests -> `211 passed`. |  | Bundle target exists and pulls GATK/site-mix, NGSTroubleFinder, Haplocheck, read_haps, CHARR, Peddy, and Somalier evidence surfaces. |
| GCI-003 | Snakemake | Retire VerifyBamID2 from active Snakemake include | SUCCESS | removable_compatibility_debt | Gate 1 | orchestrator | `workflow/Snakefile` comments out `include: "rules/verifybamid2_contam.smk"`; `tests/test_multiqc_qc_targets.py` and `tests/test_contam_identity_bundle.py` assert no active include. |  | Historical rule file remains for provenance; active DAG and final MultiQC no longer pull VerifyBamID2 panel comparison. |
| GCI-004 | Config | Add explicit config blocks for contam identity tools | SUCCESS | config_or_startup_contract | Gate 2 | orchestrator | `config/day_profiles/local/templates/rule_config.yaml`, `config/day_profiles/slurm/templates/rule_config.yaml`, `config/day_profiles/local/rule_config.yaml`; YAML load check -> `yaml ok`. |  | Config blocks require explicit commands, env YAMLs, runtime resources, primary SNV caller, reliable SNP file, Hail AF resource, and Haplocheck modes. |
| GCI-005 | Parsing | Add evidence-only parser and `_mqc.tsv` outputs | SUCCESS | feature_implementation | Gate 1 | orchestrator | `workflow/scripts/compile_contam_identity_mqc.py`; `tests/test_contam_identity_bundle.py` proves native evidence preservation, including read_haps `PASS_FAIL` and `REASON`. |  | Parser emits `contam_identity_mqc.tsv`, `ngstroublefinder_mqc.tsv`, `haplocheck_mtdna_mqc.tsv`, `read_haps_mqc.tsv`, and `charr_mqc.tsv` as evidence only. |
| GCI-006 | MultiQC | Gate final MultiQC on `contam_identity` and stage native evidence | SUCCESS | feature_implementation | Gate 1 | orchestrator | `workflow/rules/common.smk`, `workflow/rules/multiqc_final_wgs.smk`, `workflow/scripts/stage_multiqc_inputs.py`, `config/external_tools/multiqc_config.yaml`; focused suite -> `53 passed`. |  | Final MultiQC includes the bundle only via explicit target/requested-tool gate and stages native NGSTroubleFinder, Haplocheck, read_haps, and CHARR evidence. |
| GCI-007 | Tests | Add parser and Snakemake contract tests | SUCCESS | contract_test | Gate 5 | orchestrator | `tests/test_contam_identity_bundle.py`, `tests/test_multiqc_qc_targets.py`, `tests/test_multiqc_sample_identifiers.py`; focused suite -> `53 passed`; full suite -> `211 passed`. |  | Tests cover parser preservation, active include retirement, config contracts, MultiQC custom content, and staging behavior. |
| GCI-008 | Docs | Document tool inventory, evidence semantics, and VerifyBamID2 retirement | SUCCESS | historical_docs_only | Gate 5 | orchestrator | `docs/ops/multiqc_qc_targets.md`, `docs/catalog_of_tools.md`; full tests -> `211 passed`. |  | Docs mark VerifyBamID2 retired, document evidence-only semantics, target/config examples, tool links, and catalog rows for NGSTroubleFinder, Haplocheck, read_haps, and CHARR. |
| GCI-009 | Validation | Run focused tests, broader tests/coverage if feasible, and dry-run where possible | BLOCKED | contract_test | Gate 5 | orchestrator | `python -m py_compile workflow/scripts/compile_contamination_mqc.py workflow/scripts/compile_contam_identity_mqc.py workflow/scripts/run_charr_contam.py workflow/scripts/stage_multiqc_inputs.py` -> pass; YAML load -> `yaml ok`; focused tests -> `53 passed`; full tests -> `211 passed`; coverage -> `84%`; Snakemake dry-run with `DAYOA` env and explicit `snv_callers=["sentd"]` parsed config and reached DAG build, then stopped on missing `/fsx/references/.../GRCh38_no_alt_analysis_set.fasta`. | Local Mac lacks configured `/fsx` reference/input assets; `DAY-EC` also does not expose `snakemake`, so dry-run required `DAYOA`. | Local code/tests are validated; full Snakemake DAG validation is blocked until run through `daylily-ec`/SSM on a configured headnode with a non-default AWS profile. |

## Final State

- Terminal rows: 9 of 9.
- Success rows: 8.
- Blocked rows: 1 (`GCI-009`, headnode/reference-dependent Snakemake dry-run completion).
- Objective status: implementation and local validation complete; cluster-dependent DAG validation remains blocked by missing local `/fsx` assets.
- Additional check: `git diff --check` is still blocked by pre-existing trailing whitespace in `bin/util/profile_freshness_warn.bash` and `dyoainit`, which were dirty at Gate 0 and are outside this ledger's owned code changes.
