# Ultima Pangenome Sharding Ledger

Controlling plan: user-provided `Ultima Pangenome Sharding Ledger Plan`
Ledger path: `docs/plans/20260615T090019Z_ultima_pangenome_sharding_ledger.md`
Repo: `/Users/jmajor/projects/lsmc/daylily-omics-analysis`

## Objective

Build an experimental sharded Ultima pangenome path for HG003 validation without changing current monolithic `produce_pangenome_ug_vcf` behavior. The new path uses caller code `sentpgs`, writes separate shard/final paths under `snv/sentpgs`, and remains an explicit direct target outside current all-target selectors until HG003 evidence supports promotion.

## Gate 0 Baseline

- Baseline time: `2026-06-15T09:00:19Z`.
- Branch: `jem-dev...origin/jem-dev`.
- Dirty repo state before this ledger: modified implementation files plus unrelated pre-existing untracked `docs/plans/20260615T052434Z_*`, `docs/plans/20260615T053844Z_*`, `docs/plans/20260615T060845Z_*`, `docs/plans/20260615T081948Z_*`, and `jem/`.
- Current monolithic HG003 job preserved: Slurm job `49`, session `altair_hg003_ultima_pg_20260615T052434Z`, workset `/fsx/analysis_results/ubuntu/altair_hg003_ultima_pg_20260615T052434Z/daylily-omics-analysis`.
- Current monolithic job state from read-only status at `2026-06-15T09:00:24Z`: `RUNNING`, `Restarts=1`, `ReqTRES=cpu=128,mem=200000M`, `AllocTRES=cpu=384,mem=200000M`, on `i384nvme-dy-price384nvme-1`.
- Current monolithic job log tail: `dnascope-pangenome` DNAscope progress reached `85% @chr19:31000001`, peak memory `19632MB`; final `sentpg` VCF still missing at status poll time.
- HG003 CRAM/CRAI links in the monolithic workset point to read-only mounted inputs: `/fsx/staging/hg003_ultima_40x/cram/HG003_40X.cram` and `/fsx/staging/hg003_ultima_40x/cram/HG003_40X.cram.crai`.
- No destructive actions taken; current monolithic job left untouched.
- Sidecar reviewers: Agent 2/Hubble alias and routing, Agent 3/Linnaeus BED helper/tests, Agent 4/Peirce rule shape, Agent 5/Pascal cluster-validation sequence.

## Evidence Commands

- `python -m py_compile workflow/scripts/make_scoped_pangenome_bed.py` -> exit `0`.
- `pytest tests/test_pangenome_ug_sharding.py tests/test_workflow_target_aliases.py tests/test_pangenome_kitchensink_contracts.py -q` -> `25 passed in 0.33s`.
- `python docs/plans/20260615T052434Z_altairval_hg003_ultima_ssm_status.py` -> read-only cluster status captured at `2026-06-15T09:00:24Z`.
- `python docs/plans/20260615T090019Z_ultima_pangenome_sharding_ssm_launch_dryrun.py --analysis-id altair_hg003_ultima_pgs_20260615T090354Z --session altair_hg003_ultima_pgs_20260615T090354Z --ref cebd0d25ebd9d2c885aba918f766fbde4368b709` -> DayOA dry-run launched in separate tmux/workset.
- First sharded dry-run reached auto-config `aligners=pangenome_ug`, `snv_callers=sentpgs`, planned 18 shard BED jobs, 18 per-shard `sentieon_pangenome_ug_sharded` jobs, concat, target marker, and `rtg_vcfeval_roi`; failed with `RuleException` in existing concordance rule because `RTG_MEM="${rtg_mem_gb}G"` was not escaped for Snakemake shell formatting.
- `workflow/rules/rtg_vcfeval.smk` bugfix: escaped internal shell variable as `RTG_MEM="${{rtg_mem_gb}}G"`.

## Control Ledger

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| G0-001 | Baseline | Record repo state, dirty files, current HG003 run state, and target design. | SUCCESS | feature_implementation | Gate 0 | Agent 1 | Gate 0 baseline above; read-only status for job `49`; no unrelated files staged. |  | Baseline recorded before cluster validation; current monolithic job preserved. |
| CFG-001 | Config | Add `sentpgs` shard config to local and Slurm profiles. | SUCCESS | feature_implementation | Gate 2 | Agent 2 | `config/day_profiles/slurm/templates/rule_config.yaml`; `config/day_profiles/local/templates/rule_config.yaml`; pytest `test_sentpgs_profile_config_matches_requested_shard_defaults`. |  | Slurm shard list matches HIOMR default; local default is `19-20`; shard/concat resources present. |
| COMMON-001 | Routing | Add `SENTPGS_CHRMS` and `sentpgs` concordance routing. | SUCCESS | feature_implementation | Gate 2 | Agent 2 | `workflow/rules/common.smk`; pytest `test_sentpgs_common_routing_contract`; pytest `test_sentpg_variant_paths_use_fixed_spmd_deduper`. |  | `sentpgs` maps only to `pangenome_ug` and uses `spmd` for graph pangenome paths. |
| BED-001 | BED helper | Implement deterministic shard BED helper. | SUCCESS | contract_test | Gate 1 | Agent 3 | `workflow/scripts/make_scoped_pangenome_bed.py`; py_compile exit `0`; pytest helper tests for contigs, expanded ranges, subregions, empty overlap, unknown contigs, and malformed BED. |  | Helper fails hard on malformed/empty inputs and writes only canonical intersections for the requested resolved shard. |
| RULE-001 | Workflow rules | Add scatter/gather pangenome rules. | SUCCESS | feature_implementation | Gate 2 | Agent 4 | `workflow/rules/sentieon_pangenome_ug.smk`; pytest `test_sentpgs_rules_are_isolated_from_monolithic_sentpg`. |  | Added shard BED, per-shard caller, FOFN, concat/index, and explicit target marker under `sentpgs` paths without changing monolithic `sentpg`. |
| ALIAS-001 | Target alias | Register experimental direct target. | SUCCESS | feature_implementation | Gate 2 | Agent 2 | `config/workflow_target_aliases.tsv`; pytest `test_experimental_sharded_pangenome_target_autoconfigs_without_current_selector`; pytest current all-target check. |  | Direct target auto-configs `aligners=pangenome_ug`, `snv_callers=sentpgs`; `sentpgs` is not current and all-target set remains unchanged. |
| TEST-001 | Local tests | Add focused tests. | SUCCESS | contract_test | Gate 5 | Agent 3 | `tests/test_pangenome_ug_sharding.py`; `tests/test_workflow_target_aliases.py`; `tests/test_pangenome_kitchensink_contracts.py`; `25 passed`. |  | Focused local regression and helper tests pass. |
| DRYRUN-001 | Cluster dry-run | Run DayOA dry-run on `altairval` in a new workset. | ATTEMPTING_BUGFIX | contract_test | Gate 5 | Agent 5 | Workset `altair_hg003_ultima_pgs_20260615T090354Z` cloned `cebd0d25ebd9d2c885aba918f766fbde4368b709`; `dy-r produce_pangenome_ug_sharded_vcf produce_snv_concordances -p -j 150 -k -T 0 --rerun-triggers mtime -n` reached expected sharded DAG and failed in `rtg_vcfeval_roi` shell formatting. | Existing `rtg_vcfeval_roi` shell block used `${rtg_mem_gb}` without Snakemake escaping. | Bugfix in progress: escape as `${{rtg_mem_gb}}`; rerun dry-run from updated commit. |
| LIVE-001 | Cluster live | Run full sharded HG003 pilot from mounted read-only CRAM/CRAI. | OPEN | feature_implementation | Gate 5 | Agent 5 |  |  | Pending successful dry-run. |
| CONC-001 | Concordance | Run concordance for HG003 sharded output. | OPEN | contract_test | Gate 5 | Agent 5 |  |  | Pending successful sharded VCF/TBI. |
| BENCH-001 | Runtime evidence | Capture runtime/cost evidence. | OPEN | contract_test | Gate 5 | Agent 5 |  |  | Pending live sharded run benchmarks and Slurm accounting evidence. |
| FINAL-001 | Finalization | Terminalize all ledger rows. | OPEN | plan_amendment | Gate 5 | Agent 1 |  |  | Pending cluster rows. |

## Implementation Notes

- `sentpgs` is intentionally experimental and direct-only in `workflow_target_aliases.tsv`.
- `sentpgs` uses `SENTPGS_CHRMS` from `config["sentieon_pangenome_ug"][f"{genome_build}_sentpgs_chrms"]`.
- The FOFN for `sentpgs` follows configured shard-list order directly and does not use `sort_concat_chrm_list.py`; that existing helper assumes decimal sub-shards and is not safe for plain chromosome tokens.
- The monolithic rule still writes `snv/sentpg/...sentpg.snv.sort.vcf.gz` and still passes `-b "{params.canonical_bed}"`.
