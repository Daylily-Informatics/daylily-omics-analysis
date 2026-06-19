# Dynamic DPPL Memory And Partition Ordering Execution Ledger

Date: 2026-06-19T00:35:33Z

## Gate 0: Inventory Freeze

- Controlling ledger: `docs/plans/20260619T003533Z_dynamic_resources_partition_ledger.md`
- Repo: `/Users/jmajor/projects/lsmc/daylily-omics-analysis`
- Branch/status: `jem-dev...origin/jem-dev`, clean before implementation.
- Required instructions read: `/Users/jmajor/projects/lsmc/AGENTS.md`, `/Users/jmajor/projects/lsmc/daylily-omics-analysis/AGENTS.md`, `/Users/jmajor/.codex/AGENTS-HOW-TO-RUN-DAYOA.md`, `/Users/jmajor/.codex/docs/plan-ledger-workflow.md`.
- Active config surfaces: `config/day_profiles/slurm/templates/rule_config.yaml`, `config/day_profiles/local/templates/rule_config.yaml`, `config/day_profiles/slurm/templates/config.yaml`.
- Active helper/code surfaces: `workflow/rules/common.smk`, `daylily_omics_analysis/slurm/spot_partition_order.py`, primary compute rule files under `workflow/rules/`.
- Existing tests to update/run: `tests/test_spot_partition_order.py`, `tests/test_slurm_caller_partitions.py`, `tests/test_multiqc_qc_targets.py`; add focused dynamic resource helper tests.
- Benchmark evidence: local benchmark summaries show DPPL/dmd markdup RSS p95 about 451 GiB and max about 470 GiB. The initial Slurm formula is floor 512000 MB, 6144 MB/GiB input BAM, cap 800000 MB, rounded up to 1000 MB.
- Live-system limit: no headnode/AWS profile was provided in this implementation turn. Live `dy-r` dry-run and live Slurm/AWS permission validation cannot be marked `SUCCESS` locally; row `PART-003`/`DRYRUN-001` must remain `BLOCKED` unless a valid interactive `ubuntu` headnode session is supplied.
- DayOA execution contract: do not invoke raw `snakemake`; dry-run validation must use `source dyoainit`, `dy-a slurm <genome_build>`, then `dy-r ... -n` in a persistent interactive `ubuntu` tmux/login shell.

## Progress Accounting

- Current readiness: live slim validation in progress.
- Basis: all implementation, config, static tests, unit tests, local compile checks, and headnode command packet are complete; user supplied live target `AWS_PROFILE=lsmc`, `region=us-west-2`, cluster `tstpartition` on 2026-06-19.
- Remaining work: deploy the exact source state to `tstpartition`, prove live Slurm/AWS partition-cost refresh, run slim DRA-backed Doppelmark validation through `dy-r`, and prove `PARTITION_MAGIC=0` plus `local` profile pass-through.
- Local blocker evidence captured 2026-06-19T01:03:41Z: `daylily-ec` missing, `dyec` missing, and local AWS credentials unavailable.
- Headnode validation packet: `docs/plans/20260619T010341Z_dynamic_resources_headnode_validation_packet.md`.

## 2026-06-19 Slim Validation Gate Update

- Target: `AWS_PROFILE=lsmc`, `region=us-west-2`, cluster `tstpartition`.
- Read-only cluster preflight: `daylily-ec cluster-info --profile lsmc --region us-west-2` showed `tstpartition CREATE_COMPLETE`; `daylily-ec headnode jobs --profile lsmc --region us-west-2 --cluster tstpartition` showed only the queue header.
- Deployment branch: `codex/dynamic-partition-slim-validation`.
- Analysis/workdir: `/fsx/analysis_results/ubuntu/dynamic_partition_slim_20260619/daylily-omics-analysis`.
- Source data: `.test_data/data/stress_tests/ilmn/hg003/3x/{samples.tsv,units.tsv}` copied to `config/`, with FASTQ paths under `/fsx/references/genomic_data/organism_reads_slim/`.
- Command scope: slim catalog rows that exercise `produce_dmd_dedup_cram` and dynamic partition resources. Exclude `complete_genomics_mgi_snv_concordance` because catalog metadata records it as blocked on unverified CG mate pairs.
- Execution contract: no raw `snakemake`; headnode workflow commands must run through `dy-r` in persistent `ubuntu` tmux after separate `source dyoainit` and `dy-a ...` commands.

## Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| G0-001 | Ledger | Record inventory, repo state, surfaces, assumptions, and live-system limits before code edits. | SUCCESS | plan_amendment | Gate 0 | Orchestrator | This Gate 0 section. `git status --short --branch` was clean. |  | Inventory frozen before implementation. |
| MEM-001 | DPPL Memory | Add Snakemake-visible DPPL memory helper and slurm/local config keys. | SUCCESS | feature_implementation | Gate 1 | Agent A | `daylily_omics_analysis/workflow_resources.py`; `workflow/rules/common.smk`; slurm/local `doppelmark.dynamic_mem_*` keys. |  | Slurm dynamic defaults: floor 512000, per GiB 6144, cap 800000, round 1000. Local profile disables dynamic sizing. |
| MEM-002 | DPPL Memory | Update `doppelmark_dups.resources.mem_mb` to use the helper. | SUCCESS | feature_implementation | Gate 1 | Agent A | `workflow/rules/doppel_mrkdups.smk` uses `mem_mb=derive_doppelmark_mem_mb`. |  | Helper fails hard for missing/unreadable/empty BAM and malformed dynamic memory config. |
| PART-001 | Partition Costing | Generalize cached live Slurm/AWS partition ordering with 30 minute cache, locking, and atomic write. | SUCCESS | feature_implementation | Gate 1 | Agent B | `daylily_omics_analysis/slurm/spot_partition_order.py`; `python -m py_compile ...` passed. |  | Cache path `~/.config/dayoa/partition_costs.log`; lock path `.lock`; TSV header matches plan; no static config fallback remains. |
| PART-002 | Rule Integration | Wire `derive_partition_order` into primary alignment, dedup, and SNV compute rules only. | SUCCESS | feature_implementation | Gate 1 | Agent C | Alignment/dedup/SNV primary rule files updated; helper exclusions pinned by `tests/test_dynamic_resource_helpers.py`. |  | Sort/index/concat/chunkdir/target helpers remain on configured partitions. |
| PART-003 | Live Metadata | Validate live headnode can read Slurm metadata and AWS pricing permissions. | BLOCKED | legitimate_safety_handling | Gate 5 | Agent B | No interactive `ubuntu` headnode tmux/login shell or AWS profile was provided in this local implementation turn. `daylily-ec` and `dyec` are not installed locally; `aws sts get-caller-identity` reports missing credentials. Headnode packet: `docs/plans/20260619T010341Z_dynamic_resources_headnode_validation_packet.md`. | Missing live DayOA headnode session. | Blocked pending live read-only `sinfo`/`scontrol` plus EC2 read-only pricing evidence on a headnode. |
| TEST-001 | Tests | Unit-test DPPL sizing floors, caps, rounding, pass-through, and hard failures. | SUCCESS | contract_test | Gate 5 | Agent D | `python -m pytest tests/test_dynamic_resource_helpers.py -q` -> 10 passed. |  | Covered pass-through, floor, rounding, cap, missing input, bad config. |
| TEST-002 | Tests | Unit-test cache freshness, stale refresh, locking path, malformed log failure, missing partition failure, and `PARTITION_MAGIC=0`. | SUCCESS | contract_test | Gate 5 | Agent D | `python -m pytest tests/test_dynamic_resource_helpers.py -q` -> 11 passed. |  | Covered local/`PARTITION_MAGIC=0` pass-through, stale refresh, fresh-cache reuse, lock calls, EC2 private-IP/private-DNS node address resolution, malformed cache with missing live metadata. |
| TEST-003 | Tests | Static tests assert primary rule integration and helper-rule non-integration. | SUCCESS | contract_test | Gate 5 | Agent D | `python -m pytest tests/test_dynamic_resource_helpers.py tests/test_slurm_caller_partitions.py tests/test_multiqc_qc_targets.py -q` -> 39 passed. |  | Static assertions cover representative alignment, dedup, and SNV primary rules plus helper exclusions. |
| DRYRUN-001 | DayOA Dry Run | Validate through `dy-r ... -n` in interactive headnode tmux, never raw `snakemake`. | BLOCKED | legitimate_safety_handling | Gate 5 | Agent D | Contract doc read; no raw `snakemake` invoked. Headnode packet gives exact tmux commands for `PARTITION_MAGIC=0 dy-r ... -n` and live `dy-r ... -n`. | Missing interactive headnode session. | Blocked pending `source dyoainit`, `dy-a slurm <genome_build>`, `PARTITION_MAGIC=0 dy-r ... -n`, and live `dy-r ... -n`. |
| SLIM-001 | Deployment | Commit/push the exact dynamic-resource source state to `codex/dynamic-partition-slim-validation` for headnode cloning. | IN_PROGRESS | plan_amendment | Gate 5 | Codex | Local branch preparation in progress from `jem-dev`; dirty scope is the dynamic resource/helper/rule/test/ledger files listed by `git status --short`. |  |  |
| SLIM-002 | Headnode Setup | Clone branch on `tstpartition`, initialize a persistent single-pane tmux session, and stage HG003 slim samples/units from repo fixtures. | OPEN | legitimate_safety_handling | Gate 5 | Codex | Planned session `dynamic_partition_slim_20260619`; workdir `/fsx/analysis_results/ubuntu/dynamic_partition_slim_20260619/daylily-omics-analysis`. |  |  |
| SLIM-003 | Live Metadata | Refresh `~/.config/dayoa/partition_costs.log` from live Slurm/AWS metadata for `i384nvme,i192nvme`. | OPEN | legitimate_safety_handling | Gate 5 | Codex | Planned command: `DAY_PROFILE=slurm AWS_REGION=us-west-2 python -m daylily_omics_analysis.slurm.spot_partition_order i384nvme,i192nvme`. |  |  |
| SLIM-004 | Disablement | Prove `PARTITION_MAGIC=0` preserves configured partition order and does not refresh the cache during a minimal `dy-r ... -n`. | OPEN | contract_test | Gate 5 | Codex | Planned command: `PARTITION_MAGIC=0 AWS_REGION=us-west-2 dy-r produce_sent_align produce_dmd_dedup_cram produce_sentd_snv_vcf produce_snv_concordances produce_alignstats -p -k -j 20 --rerun-triggers mtime -n`. |  |  |
| SLIM-005 | Local Profile | Prove `dy-a local hg38_broad` preserves configured partition order and does not hit Slurm/AWS metadata. | OPEN | contract_test | Gate 5 | Codex | Planned `dy-r ... -n` under local profile plus direct `derive_partition_order("i384nvme,i192nvme")` probe. |  |  |
| SLIM-006 | Live Slim Run | Run minimal slim `illumina_snv_alignstats` equivalent through `dy-r` without `-n` to exercise Doppelmark dynamic memory against produced BAM input. | OPEN | contract_test | Gate 5 | Codex | Planned command: `AWS_REGION=us-west-2 dy-r produce_sent_align produce_dmd_dedup_cram produce_sentd_snv_vcf produce_snv_concordances produce_alignstats -p -k -j 20 --rerun-triggers mtime`. |  |  |
| SLIM-007 | Broader Dry Runs | Run broader successful Doppelmark catalog dry-runs for `illumina_snv_alignstats_relatedness_vep_multiqc` and `illumina_hg002_kitchensink_multiqc`. | OPEN | contract_test | Gate 5 | Codex | Planned `dy-r` equivalents of the catalog rows; CG/MGI row excluded due catalog-blocked mate-pair validation. |  |  |
| SLIM-008 | Debug Attempts | If live validation fails from code behavior, record at least one concrete bugfix attempt with local tests before retry. | OPEN | plan_amendment | Gate 5 | Codex | No bugfix attempt required yet. |  |  |

## Verification

- `python -m pytest tests/test_dynamic_resource_helpers.py -q` -> 11 passed.
- `python -m pytest tests/test_dynamic_resource_helpers.py tests/test_slurm_caller_partitions.py tests/test_multiqc_qc_targets.py -q` -> 40 passed.
- `python -m py_compile daylily_omics_analysis/slurm/spot_partition_order.py daylily_omics_analysis/workflow_resources.py` -> passed.
- `rg -n "update_rule_config|partition_strategy|partition_instance_catalog|spot_price_runtime|--rule-config|dynamic BWA-MEM2A" .` -> only historical release-note mentions remain.
