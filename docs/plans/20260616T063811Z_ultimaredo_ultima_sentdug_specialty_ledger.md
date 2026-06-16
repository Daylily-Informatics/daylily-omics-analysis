# Ultimaredo Ultima Sentdug Specialty Caller Ledger

Controlling plan: `/Users/jmajor/projects/lsmc/docs/ultima_reproc_plan.md` and `/Users/jmajor/projects/lsmc/docs/ultima_reproc_plan_pre.md`
Ledger path: `/Users/jmajor/projects/lsmc/daylily-omics-analysis/docs/plans/20260616T063811Z_ultimaredo_ultima_sentdug_specialty_ledger.md`

## Gate 0 Baseline

- Repo: `/Users/jmajor/projects/lsmc/daylily-omics-analysis`
- Branch/status: `jem-dev...origin/jem-dev`, clean at baseline.
- Source plan hash: both source plans have SHA256 `0956d7f4c2e60ba0c45ed283fd311223400eaf18df18bd5e1bbb6efe522a8218`.
- Sweep: `rg -n "produce_sentdug_(mito|segdup|cnv|sv)|sent_ug_specialty|sentdug_.*specialty|segdup_sr_model|cnv_model_bundle" ...`
- Sweep result: no `produce_sentdug_*` specialty targets or `sent_ug_specialty` module existed; existing segdup model keys were limited to hybrid contexts and local template placeholders.
- DayOA execution contract: no raw `snakemake`; cluster validation must use `dy-r` in persistent `ubuntu` tmux on the headnode.

## Control Ledger

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| G0-001 | Baseline | Record source plans, branch state, current target absence, and DayOA run contract. | SUCCESS | contract_test | Gate 0 | orchestrator | Gate 0 section above. |  | Baseline captured before runtime edits. |
| CFG-001 | Config | Add `sentdug` specialty config keys for CNV, segdup, mito, SV, resources, and partitions in local and Slurm templates. | SUCCESS | feature_implementation | Gate 1 | Agent 2 | `config/day_profiles/local/templates/rule_config.yaml`, `config/day_profiles/slurm/templates/rule_config.yaml`; YAML parse check passed. |  | Added explicit specialty keys and kept SV disabled by default. |
| RULE-001 | Rules | Add Ultima-only `sent_ug_specialty.smk` rules consuming `align/ug/{sample}.cram`. | SUCCESS | feature_implementation | Gate 1 | Agent 3 | `workflow/rules/sent_ug_specialty.smk`, `workflow/Snakefile`. |  | Added shared UG CRAM materialization plus mito, segdup, CNV, and blocked SV target rules. |
| TARGET-001 | Targets | Register experimental direct targets without adding them to current selectors. | SUCCESS | feature_implementation | Gate 1 | Agent 4 | `config/workflow_target_aliases.tsv`; `tests/test_workflow_target_aliases.py` stayed passing. |  | Registered `produce_sentdug_mito`, `produce_sentdug_segdup`, `produce_sentdug_cnv`, and `produce_sentdug_sv` as experimental `specialty_caller` rows only. |
| TEST-001 | Tests | Add focused static tests for rule inclusion, direct targets, config keys, and explicit SV block behavior. | SUCCESS | contract_test | Gate 5 | Agent 5 | `tests/test_sentdug_specialty_callers.py`. |  | Added tests covering include, UG-only inputs, profile keys, registry status, and SV block semantics. |
| VALID-001 | Validation | Run focused local tests and Python/Snakemake-adjacent syntax checks available on this Mac. | SUCCESS | contract_test | Gate 5 | Agent 5 | `python -m pytest tests/test_sentdug_specialty_callers.py tests/test_workflow_target_aliases.py -q -> 13 passed`; `python -m pytest tests/test_sentdug_specialty_callers.py tests/test_workflow_target_aliases.py tests/test_slurm_profile.py tests/test_slurm_caller_partitions.py tests/test_sentieon_model_bundle_config.py -q -> 26 passed`; `python -m pytest tests/test_expansionhunter_contracts.py -q -> 13 passed`; YAML parse check -> `yaml ok`. |  | Local wrapper dry-run was attempted through `dy-r` but stopped before DAG construction because this Mac lacks the required `DAYOA` conda env. |
| HG003-CLUSTER-001 | Cluster validation | Run HG003 dry-run/live test on `ultimaredo` when available. | BLOCKED | contract_test | Gate 5 | Agent 8 | Local `dy-r` attempt: `dy-a local hg38_broad` stopped with `Error: macOS local mode requires the DAYOA conda environment.` | `ultimaredo` is not available in this local implementation step, and this Mac lacks the local `DAYOA` env. | Unblock by running `dy-r produce_sentdug_mito produce_sentdug_segdup produce_sentdug_cnv produce_sentdug_sv -n` from an initialized `ubuntu` tmux pane on the cluster. |
| FINAL-001 | Final | Terminalize all rows and summarize cluster-side HG003 validation still required. | SUCCESS | plan_amendment | Gate 5 | orchestrator | All ledger rows are terminal; one row is `BLOCKED` for future cluster validation. |  | Local development is complete; objective is not fully cluster-validated until HG003 runs on `ultimaredo`. |

## Final Status

- Terminal rows: 8.
- Success rows: 7.
- Blocked rows: 1 (`HG003-CLUSTER-001`).
- Open/in-progress/bugfix rows: 0.
