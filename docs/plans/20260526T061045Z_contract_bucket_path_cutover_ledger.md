# Contract Bucket Path Cutover Execution Ledger

Controlling DayEC ledger: `/Users/jmajor/.codex/worktrees/dyec-fsx-dra-mounts/daylily-ephemeral-cluster/docs/plans/20260526T061045Z_contract_bucket_split_ledger.md`
Ledger path: `/Users/jmajor/projects/daylily/daylily-omics-analysis/docs/plans/20260526T061045Z_contract_bucket_path_cutover_ledger.md`

## Gate 0 Baseline

- Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- Branch: `codex/tstclu411c-hybrid-env-python`
- HEAD: `bc27487d62d190efe47ba5933a574812426a2b39`
- Status: dirty before this work; pre-existing modified docs/plans and untracked HG003 ledger/report files existed.
- Sweep: `rg -n "/fsx/data|/data/staged_sample_data|reference-bucket|reference_bucket|genomic_data|cached_envs|staged_sample_data" README.md dyoainit config workflow tests docs bin | wc -l` -> `657`
- Live AWS scope at Gate 0: no live S3 copy, bucket creation, lifecycle policy change, destructive action, or real cluster create was approved at initial implementation time.
- Assumption: active workflow paths cut over to `/fsx/references`, `/fsx/control_data`, `/fsx/runtime_assets`, and `/fsx/staging`; no `/fsx/data` compatibility path is added.

## Live AWS Amendment 20260526T071153Z

- User approved live non-destructive S3 bucket creation in `us-west-2` with `AWS_PROFILE=lsmc` for `lsmc-dayoa-references-usw2`, `lsmc-dayoa-control-data-usw2`, `lsmc-dayoa-runtime-assets-usw2`, `lsmc-dayoa-staging-usw2`, and `lsmc-dayoa-analysis-results-usw2`.
- User approved the same new Daylily-owned public reference versions with `AWS_PROFILE=daylily`; implemented as `daylily-dayoa-references-usw2`, `daylily-dayoa-control-data-usw2`, `daylily-dayoa-runtime-assets-usw2`, `daylily-dayoa-staging-usw2`, and `daylily-dayoa-analysis-results-usw2`.
- Source permission contract inspected from `daylily-omics-analysis-references-public` with `AWS_PROFILE=daylily`: region `us-west-2`, public policy status `true`, public access block flags all `false`, and ownership `BucketOwnerEnforced`.
- LSMC target policies were rewritten to target each LSMC bucket ARN, use LSMC account `108782052779` as the owner write exception, and use Daylily account `670484050738` as the cross-account writer.
- Daylily target policies were public read/list policies with Daylily account `670484050738` as the owner write exception; the copied cross-account LSMC statement was omitted to scrub LSMC/RCRF references.
- Anonymous public-list spot checks succeeded with `aws s3 ls s3://lsmc-dayoa-references-usw2 --no-sign-request --region us-west-2` and `aws s3 ls s3://daylily-dayoa-references-usw2 --no-sign-request --region us-west-2` returning exit 0 on empty buckets.
- Explicitly not performed: object copy, lifecycle policy changes, bucket deletion, real cluster creation, or S3 prefix population.

## Live AWS Amendment 20260526T072350Z

- User requested completion of the remaining live migration work and encryption enablement for the DayOA split buckets, Dewey buckets, and LSMC sequencing bucket.
- Encryption inventory verified default server-side encryption is already active on `lsmc-dayoa-references-usw2`, `lsmc-dayoa-control-data-usw2`, `lsmc-dayoa-runtime-assets-usw2`, `lsmc-dayoa-staging-usw2`, `lsmc-dayoa-analysis-results-usw2`, `daylily-dayoa-references-usw2`, `daylily-dayoa-control-data-usw2`, `daylily-dayoa-runtime-assets-usw2`, `daylily-dayoa-staging-usw2`, `daylily-dayoa-analysis-results-usw2`, `lsmc-ssf-sequencing-data`, `lsmc-dewey-0`, and `daylily-dewey-0`.
- All inspected buckets report default `SSEAlgorithm=AES256` with `BlockedEncryptionTypes=["SSE-C"]`; `lsmc-ssf-sequencing-data`, `lsmc-dewey-0`, and `daylily-dewey-0` also report `BucketKeyEnabled=true`.
- KMS alias inventory found no DayOA/clinical customer-managed KMS key in the LSMC account; Daylily has `alias/trail-daylily-ref-s3`, which is trail-specific, not a general DayOA data key.
- Source inventory confirmed `daylily-omics-analysis-references-public` has `cluster_boot_config/` and `data/`; `lsmc-dayoa-omics-analysis-us-west-2` mixes top-level FASTQs/manifests, `cluster_boot_config/`, `data/genomic_data/`, `data/cached_envs/`, `data/cram_data/`, `data/ilmn_kitefastqs/`, `data/pacbio/`, `data/staged/`, `data/staged_sample_data/`, `data/tool_specific_resources/`, `data/ug/`, `analysis_results/`, and other operational/result prefixes.
- Bulk copy remains blocked pending exact source and destination URI approval because a blind copy would preserve the overloaded legacy layout. Lifecycle policy changes, bucket deletion, and cluster creation remain blocked pending a separate confirmation after exact effects are stated.

## Live AWS Amendment 20260526T094754Z

- User approved the exact seven-prefix LSMC S3 copy set from `s3://lsmc-dayoa-omics-analysis-us-west-2/data/...` into the split `lsmc-dayoa-*` buckets with `AWS_PROFILE=lsmc` in `us-west-2`.
- User explicitly approved no lifecycle policy application to references, control-data, runtime-assets, results, Dewey, raw sequencing, or any other buckets mentioned here. No lifecycle policy mutation was performed.
- Copy was completed with AWS CLI multipart object copies and verified by source/destination object size comparison. Verification showed zero missing or size-mismatched objects for all approved mappings:
  - `organism_references/` -> `lsmc-dayoa-references-usw2/genomic_data/organism_references/`: 161 objects, 151,805,655,811 bytes.
  - `organism_annotations/` -> `lsmc-dayoa-references-usw2/genomic_data/organism_annotations/`: 1,358 objects, 188,961,257,035 bytes.
  - `organism_reads/` -> `lsmc-dayoa-control-data-usw2/genomic_data/organism_reads/`: 5,339 objects, 8,287,454,601,003 bytes.
  - `cram_data/` -> `lsmc-dayoa-control-data-usw2/cram_data/`: 154 objects, 2,631,677,875,018 bytes.
  - `cached_envs/` -> `lsmc-dayoa-runtime-assets-usw2/cached_envs/`: 68,362 objects, 11,195,108,255 bytes.
  - `staged/` -> `lsmc-dayoa-staging-usw2/staged/`: 34,816 objects, 886,070,160,684 bytes.
  - `staged_sample_data/` -> `lsmc-dayoa-staging-usw2/staged_sample_data/`: 3,829 objects, 11,105,111,230,649 bytes.
- Real cluster creation remains blocked because the approval still contained placeholders for `cluster name=<name>`, `config=<path>`, and `export_destination_s3_uri=s3://lsmc-dayoa-analysis-results-usw2/<prefix>/`.
- Bucket deletion and unapproved prefix population remain not performed.

## Control Ledger

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| DAYOA-001 | Orchestration | Record Gate 0 inventory before path cutover edits. | SUCCESS | plan_amendment | Gate 0 | orchestrator | This ledger. |  | Gate 0 recorded before path cutover edits. |
| DAYOA-002 | Init/runtime | Update `dyoainit` and activation paths for budget tags, Sentieon, and runtime assets outside references. | SUCCESS | feature_implementation | Gate 2 | Agent D | `dyoainit`, `config/daylily_cli_global.yaml`, rule/profile runtime paths; full pytest -> 178 passed. |  | Budget tags and Sentieon/runtime assets now resolve under `/fsx/runtime_assets`. |
| DAYOA-003 | Supporting files | Reclassify biological references and annotations to `/fsx/references`, runtime/tool assets to `/fsx/runtime_assets`, and validation reads to `/fsx/control_data`. | SUCCESS | feature_implementation | Gate 2 | Agent D | `config/supporting_files/*.yaml`, `.test_data`, `tests/fixtures`, scripts; active sweep has no `/fsx/data` outside this ledger. |  | References/annotations, runtime assets, and validation reads follow the split role roots. |
| DAYOA-004 | Profiles/rules | Update rule/profile hard-coded runtime and reference paths away from `/fsx/data`. | SUCCESS | feature_implementation | Gate 2 | Agent D | `config/day_profiles/*/templates/rule_config.yaml`, `workflow/rules/*.smk`; full pytest -> 178 passed. |  | Workflow/profile paths use `/fsx/references`, `/fsx/control_data`, and `/fsx/runtime_assets`. |
| DAYOA-005 | Fixtures/manifests | Move staged and validation-read fixture paths to `/fsx/staging` or `/fsx/control_data` as appropriate. | SUCCESS | contract_test | Gate 5 | Agent D | `.test_data`, `tests/fixtures/giab7_ilmn_5x`, `scripts/generate_giab7_ilmn5x_manifests.py`; `tests/test_giab_qc_contracts.py` passed. |  | Test fixtures and manifest generators no longer depend on `/fsx/data`. |
| DAYOA-006 | Docs | Update active docs away from `/fsx/data` and overloaded reference-bucket semantics. | SUCCESS | feature_implementation | Gate 5 | Agent E | `README.md`, `docs/*.md`, runbooks and active plan docs; active sweep clean outside ledger. |  | Active docs now describe the contract role paths. |
| DAYOA-007 | Negative sweep | Verify active source no longer requires `/fsx/data`; document any historical-only leftovers. | SUCCESS | contract_test | Gate 5 | Agent E | `rg -n "/fsx/data|/data/staged_sample_data|s3_bucket_name|reference-bucket objects|reference bucket" README.md dyoainit config workflow tests docs bin scripts .test_data *.md -g '!docs/plans/**'` -> no matches. |  | Negative sweep passed for active DayOA source and fixtures. |
| DAYOA-008 | Live AWS migration | Lifecycle/deletion/real cluster validation after bucket creation and data copy. | BLOCKED | feature_implementation | Gate 5 | orchestrator | Bucket creation is complete under `DAYOA-009`; encryption verification is complete under `DAYOA-010`; approved object copy is complete under `DAYOA-011`; lifecycle policy application was explicitly approved as a no-op; bucket deletion was not approved; real cluster creation approval still contains placeholders. | Exact `cluster name`, cluster `config` path, and export destination prefix are required before real cluster creation. | Terminal blocked for real cluster creation; no lifecycle policy mutation or deletion performed. |
| DAYOA-009 | Live AWS buckets | Create and configure contract role buckets in `us-west-2` for LSMC and scrubbed Daylily public counterparts. | SUCCESS | feature_implementation | Gate 5 | orchestrator | `AWS_PROFILE=lsmc` created `lsmc-dayoa-references-usw2`, `lsmc-dayoa-control-data-usw2`, `lsmc-dayoa-runtime-assets-usw2`, `lsmc-dayoa-staging-usw2`, `lsmc-dayoa-analysis-results-usw2`; `AWS_PROFILE=daylily` created `daylily-dayoa-references-usw2`, `daylily-dayoa-control-data-usw2`, `daylily-dayoa-runtime-assets-usw2`, `daylily-dayoa-staging-usw2`, `daylily-dayoa-analysis-results-usw2`; verification showed all ten buckets in `us-west-2`, public policy status `true`, public access block flags all `false`, and ownership `BucketOwnerEnforced`; Daylily policies contained no `lsmc`, `rcrf`, or `108782052779` references. |  | Live bucket creation and non-destructive policy configuration completed. |
| DAYOA-010 | Live AWS encryption | Ensure default bucket encryption is active on DayOA split buckets plus Dewey and LSMC sequencing buckets. | SUCCESS | feature_implementation | Gate 5 | orchestrator | `get-bucket-encryption` verified `SSEAlgorithm=AES256` and `BlockedEncryptionTypes=["SSE-C"]` for all ten DayOA split buckets, `lsmc-ssf-sequencing-data`, `lsmc-dewey-0`, and `daylily-dewey-0`; no missing encryption configuration was found. |  | Encryption was already enabled; no bucket encryption mutation was required. |
| DAYOA-011 | Live AWS copy | Copy approved LSMC source prefixes into the contract split buckets. | SUCCESS | feature_implementation | Gate 5 | orchestrator | Full verification compare showed zero missing or size-mismatched objects across seven mappings: `organism_references` 161 objects/151,805,655,811 bytes; `organism_annotations` 1,358/188,961,257,035; `organism_reads` 5,339/8,287,454,601,003; `cram_data` 154/2,631,677,875,018; `cached_envs` 68,362/11,195,108,255; `staged` 34,816/886,070,160,684; `staged_sample_data` 3,829/11,105,111,230,649. |  | Approved S3 copy completed and verified byte-exact. |

## Terminal Report

- Status counts: `SUCCESS=10`, `BLOCKED=1`, `OPEN=0`, `IN_PROGRESS=0`, `ATTEMPTING_BUGFIX=0`, `FAIL=0`.
- Local validation: `eval "$(conda shell.zsh hook)" && conda activate DAY-EC && python -m pytest -q` -> `178 passed`; focused tests `tests/test_tool_catalog_docs.py tests/test_giab_qc_contracts.py tests/test_complete_genomics_sentieon.py tests/test_multiqc_sample_identifiers.py -q` -> `56 passed`; py_compile of edited Python generators/helpers passed.
- Sweeps: active DayOA source, scripts, fixtures, and `.test_data` have no `/fsx/data`, `/data/staged_sample_data`, `s3_bucket_name`, old reference-bucket object wording, or generic "reference bucket" hits outside `docs/plans`.
- Diff hygiene: `git diff --check -- . ':(exclude)*.tsv' ':(exclude)*.csv'` passed. Raw `git diff --check` is not meaningful for edited TSV/CSV fixtures because trailing tab fields encode empty columns.
- Live AWS bucket creation, encryption verification, and approved S3 object copy are complete. Lifecycle policy changes were explicitly approved as a no-op and were not performed; deletion was not approved; real cluster validation remains blocked by placeholder values in the approval.
- All ledger rows are terminal. The local path-cutover objective plus approved live bucket-creation/encryption-verification/copy objectives are complete; the broader real-cluster validation objective is not complete because `DAYOA-008` remains blocked by missing exact cluster name, config path, and export prefix.
