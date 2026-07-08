# DRAGEN SNV Concordance Ledger

Controlling request: formalize DRAGEN so `produce_snv_concordances` runs after `produce_sentpg_snv_vcf`, without changing the existing Ubuntu `slurm` path.

Ledger path: `docs/plans/20260708T052008Z_dragen_snv_concordance_ledger.md`

## Gate 0 Baseline

- DayOA repo: `/Users/jmajor/projects/lsmc/dragen-fix-20260708/daylily-omics-analysis`
- DayOA branch: `codex/dragen-headnode-launch-fix`
- DayOA status: `## codex/dragen-headnode-launch-fix...origin/codex/dragen-headnode-launch-fix`, clean
- DYEC repo: `/Users/jmajor/projects/lsmc/dragen-fix-20260708/daylily-ephemeral-cluster`
- DYEC branch: `codex/dragen-headnode-launch-fix`
- DYEC status: unrelated dirty files remain in `daylily_ec/cli.py`, `tests/test_cli_registry_v2.py`, and generated TSVs under `docs/plans/20260707T144453Z_dyec_tests_command_catalog_sample_logs/illumina_pangenome_snv/`
- Baseline sweep: `rg -n "DAYLILY_DRAGEN|produce_snv_concordances|sentpg_dragen|slurm_rhel|rtg_vcfeval|sent_aln_sort_snv" workflow config tests bin | wc -l` -> `103`
- Key source surfaces inspected: `workflow/rules/rtg_vcfeval.smk`, `workflow/rules/common.smk`, `workflow/rules/sent_aln_sort_snv.smk`, `config/day_profiles/slurm/templates/rule_config.yaml`, `bin/day_activate`, `bin/day_run`
- Live validation target: existing DYEC DRAGEN cluster `dragen-fix5-20260708`, profile `lsmc`, region `us-west-2`, only through `dy-r` in a persistent `ubuntu` tmux/login-shell pane.
- Assumptions: keep the existing `slurm`/Ubuntu profile behavior unchanged; put RHEL/DRAGEN partition differences in a new explicit `slurm_rhel` profile; no destructive AWS or Slurm admin actions.

## Control Ledger

| ID | Area/Repo | Requirement/Surface | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| DRG-CONC-001 | DayOA profile | Add explicit `slurm_rhel` day profile for DRAGEN/RHEL clusters with f2 `dragen` partition routing for pangenome and concordance work, while leaving `slurm` unchanged. | SUCCESS | feature_implementation | Gate 1 | Codex | Added `config/day_profiles/slurm_rhel/templates/*`; `pytest tests/test_slurm_profile.py tests/test_pangenome_kitchensink_contracts.py tests/test_workflow_target_aliases.py tests/test_sentieon_model_bundle_config.py -q` -> `33 passed`. |  | `slurm_rhel` profile exists, uses `DAY_PROFILE=slurm_rhel`, default `partition=dragen`, and DRAGEN/pangenome/RTG sections route to `dragen`; `slurm` remains unchanged except explicit false flag. |
| DRG-CONC-002 | DayOA workflow | Make `produce_snv_concordances` include the monolithic `sent_aln_sort_snv` DRAGEN/Sentieon pangenome VCF when the active profile explicitly enables it. | SUCCESS | feature_implementation | Gate 1 | Codex | `workflow/rules/rtg_vcfeval.smk` adds `concordance_snv_alnr_ddup_tuples()` and special `sent/spmd/sentpg` VCF/TBI input path gated by `rtg_vcfeval.enable_sentpg_dragen_concordance`; focused tests -> `33 passed`. |  | `produce_snv_concordances` can depend on the monolithic `align/sent/snv/sentpg` VCF only when the profile flag is true. |
| DRG-CONC-003 | DayOA workflow | Avoid broad rule changes that would alter the Ubuntu `slurm` concordance path for `sentd`, `deep19`, and existing pangenome routes. | SUCCESS | contract_test | Gate 1 | Codex | `config/day_profiles/slurm/templates/rule_config.yaml` sets `enable_sentpg_dragen_concordance: false`; tuple broadening is local to `rtg_vcfeval.smk` concordance helper; focused tests -> `33 passed`. |  | Default Ubuntu `slurm` profile keeps existing RTG partitions and generic input paths. |
| DRG-CONC-004 | DayOA tests | Add focused tests proving `slurm_rhel` resources and DRAGEN concordance routing without relying on compatibility fallback behavior. | SUCCESS | contract_test | Gate 1 | Codex | Added assertions in `tests/test_slurm_profile.py` and `tests/test_pangenome_kitchensink_contracts.py`; `pytest ... -q` -> `33 passed`. |  | Tests cover explicit `slurm_rhel` enablement, `slurm` disablement, and removal of `DAYLILY_DRAGEN` symlink behavior. |
| DRG-CONC-005 | Live validation | Validate with `dy-r` from a persistent headnode shell that `produce_sentpg_snv_vcf produce_snv_concordances` can run and produce RTG concordance outputs on the DRAGEN f2 spot path. | OPEN | feature_implementation | Gate 5 | Codex | Pending |  |  |
