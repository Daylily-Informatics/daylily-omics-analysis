# DayOA LongTR Catalog And Target Ledger

Created: 2026-05-28T08:15:16Z

## Objective

Create globally staged LongTR catalogs for the TRExplorer genome-wide catalog and a DayOA disease-repeat catalog, place them under the DayOA reference runtime-assets S3 prefix, and update DayOA so operators can run `longtr_all` and `longtr_diseaser` targets with explicit configured catalogs.

## Gate 0 Inventory Freeze

Controlling request: user asked to create globally available LongTR catalogs for `trexplorer_catalog` and `disease_repeat_catalog` under `runtime_assets/tool_specific_resources/longtr/<catalog-name>/` using AWS profile `lsmc` in `us-west-2`, then update the pipeline to allow `longtr_all` and `longtr_diseaser`.

Ledger path: `docs/plans/20260528T081516Z_longtr_catalog_targets_ledger.md`

Repository: `/Users/jmajor/projects/daylily/daylily-omics-analysis`

Branch:

```text
## codex/dayoa-local-evidence-dewey-refactor-20260528...origin/codex/dayoa-local-evidence-dewey-refactor-20260528
```

Dirty state before LongTR edits:

```text
 M config/day_profiles/local/templates/rule_config.yaml
 M config/day_profiles/slurm/templates/rule_config.yaml
 M docs/catalog_of_tools.md
 M docs/ops/multiqc_qc_targets.md
 M tests/test_giab_qc_contracts.py
 M tests/test_multiqc_qc_targets.py
 M workflow/Snakefile
 M workflow/rules/bcl2fq.smk
 M workflow/rules/bclconvert.smk
 M workflow/rules/common.smk
 M workflow/rules/evidence_manifest.smk
 M workflow/rules/expansionhunter.smk
 D workflow/rules/fastv.smk
 M workflow/rules/multiqc_cov_aln.smk
 M workflow/rules/multiqc_final_wgs.smk
 M workflow/rules/multiqc_for_bcl2fq.smk
 M workflow/rules/multiqc_for_raw_fastqs.smk
 M workflow/rules/multiqc_singleton.smk
 M workflow/rules/run_qc_reports.smk
 M workflow/rules/unmapped_metagenomics.smk
 D workflow/rules/verifybamid2_contam.smk
?? docs/plans/20260528T075728Z_qc_database_defaults_and_retired_rules_ledger.md
?? docs/plans/20260528T080714Z_sourmash_reference_collection_ledger.md
?? workflow/rules/archived_qc/
```

Existing dirty files are treated as prior work. This LongTR implementation may touch shared config/docs/tests/Snakefile files as needed, but must not revert unrelated dirty changes.

Instruction files read:

```text
AGENTS.md
/Users/jmajor/.agents/AGENTS.md
/Users/jmajor/.codex/AGENTS.md
/Users/jmajor/.codex/docs/plan-ledger-workflow.md
```

AWS identity and bucket discovery:

```text
aws sts get-caller-identity --profile lsmc --region us-west-2
Account: 108782052779

aws s3 ls --profile lsmc --region us-west-2
Relevant buckets observed:
- lsmc-dayoa-references-usw2
- lsmc-dayoa-runtime-assets-usw2
- lsmc-dayoa-omics-analysis-us-west-2

aws s3 ls s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/ --profile lsmc --region us-west-2
Existing runtime-assets prefix contains H_sapiens/, ganon2/, metagenomics/, sentieon_models_2_2/, sourmash/, ultima/, vep/, verifybam2/, verifybamid/.
```

Chosen S3 prefix: `s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/longtr/`

Rationale: user requested the bucket with `runtime_assets/tool_specific_resources/`; that prefix exists in `lsmc-dayoa-references-usw2`.

Initial source/catalog facts:

```text
resources/strchive/STRchive-disease-loci.hg38.stranger.json exists and contains 74 disease-locus entries.
workflow/rules/expansionhunter.smk consumes the STRchive/ExpansionHunter JSON catalog.
No active LongTR rule or config exists before this work.
```

Baseline tests: deferred until after focused wiring because current working tree is already dirty from prior QC target edits.

Known live-system limits:

- This work is allowed to create new S3 objects under the explicit runtime-assets prefix. No destructive S3 actions are planned.
- Cluster execution is not performed from this Mac; Snakemake dry-runs may be attempted locally only if the current dirty tree and local environment permit it.

## Tracking Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| LTR-001 | Gate 0 | Record dirty state, instruction files, AWS identity, bucket/prefix discovery, and initial LongTR source facts before edits. | SUCCESS | config_or_startup_contract | Gate 0 | orchestrator | This ledger Gate 0 section. |  | Inventory complete; implementation may proceed. |
| LTR-002 | S3 catalog asset | Stage TRExplorer LongTR catalog under `runtime_assets/tool_specific_resources/longtr/trexplorer_catalog/` with source metadata and checksums. | SUCCESS | feature_implementation | Gate 1 | orchestrator | Uploaded `TRExplorer.repeat_catalog_v2.hg38.1_to_1000bp_motifs.LongTR.bed.gz` and manifest to `s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/longtr/trexplorer_catalog/`; SHA256 `3f03351d525d2c6463106ee6b0ef5e4977de2ae0506c7a812d197d604ba090bb`; `head-object` size `84892721`. |  | TRExplorer v2.0 LongTR catalog is staged with source manifest. |
| LTR-003 | S3 catalog asset | Build and stage DayOA disease-repeat LongTR catalog derived from STRchive/ExpansionHunter JSON under `runtime_assets/tool_specific_resources/longtr/disease_repeat_catalog/` with source metadata and checksums. | SUCCESS | feature_implementation | Gate 1 | orchestrator | `workflow/scripts/convert_expansionhunter_catalog_to_longtr_bed.py`; generated 94 BED rows, skipped one zero-length component `DBQD2_XYLT1`; uploaded `.bed`, `.bed.gz`, manifest, skipped TSV to `s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/longtr/disease_repeat_catalog/`; gz SHA256 `50036a5b4b32e3a69dcbccd0080b2ffd5f776bb906f2d7bfeeea6807548bab27`; `head-object` size `1824`. |  | Disease repeat catalog is staged with conversion provenance and skipped-row evidence. |
| LTR-004 | Workflow config | Add explicit LongTR config for `longtr_all` and `longtr_diseaser`; no inferred defaults or service discovery. | SUCCESS | config_or_startup_contract | Gate 2 | orchestrator | `config/day_profiles/local/templates/rule_config.yaml`; `config/day_profiles/slurm/templates/rule_config.yaml`; `workflow/schemas/config.schema.yaml`. |  | Profiles explicitly configure command, env, aligners, deduper, and both catalog paths. |
| LTR-005 | Snakemake rules | Add LongTR rules and targets for all/catalog and disease-repeat catalog runs against ONT alignments. | SUCCESS | feature_implementation | Gate 2 | orchestrator | `workflow/rules/longtr.smk`; `workflow/Snakefile`; `workflow/envs/longtr_v0.1.yaml`. |  | `longtr_all` and `longtr_diseaser` targets are available and restricted to ONT CRAM aligners. |
| LTR-006 | Tests | Add focused static/contract tests for config, target names, required catalog inputs, and target wiring. | SUCCESS | contract_test | Gate 5 | orchestrator | `tests/test_longtr_contracts.py`; `tests/test_multiqc_qc_targets.py`. |  | Tests cover rule/env activation, explicit profile catalogs, and disease-catalog converter behavior. |
| LTR-007 | Docs | Document LongTR catalogs, S3 locations, and run targets. | SUCCESS | feature_implementation | Gate 5 | orchestrator | `docs/catalog_of_tools.md`; `docs/ops/multiqc_qc_targets.md`. |  | Documentation lists LongTR tool, catalog locations, and `dy-r` targets. |
| LTR-008 | Validation | Run focused tests and record S3 object existence/checksum evidence; mark cluster execution blocked if not run. | SUCCESS | contract_test | Gate 5 | orchestrator | `python -m pytest -q tests/test_longtr_contracts.py tests/test_multiqc_qc_targets.py` -> `23 passed`; S3 `aws s3 ls` and `head-object` checks for both catalog prefixes succeeded. |  | Local static validation and S3 existence checks passed; live cluster execution was not requested or performed. |

## Final Status

Rows: 8 `SUCCESS`, 0 `OPEN`, 0 `IN_PROGRESS`, 0 `ATTEMPTING_BUGFIX`, 0 `BLOCKED`, 0 `FAIL`.

Focused validation:

```text
eval "$(conda shell.zsh hook)" && conda activate DAY-EC && python -m pytest -q tests/test_longtr_contracts.py tests/test_multiqc_qc_targets.py
23 passed in 0.31s
```

S3 validation:

```text
s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/longtr/trexplorer_catalog/
- TRExplorer.repeat_catalog_v2.hg38.1_to_1000bp_motifs.LongTR.bed.gz, size 84892721
- TRExplorer.repeat_catalog_v2.hg38.1_to_1000bp_motifs.LongTR.manifest.json

s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/longtr/disease_repeat_catalog/
- dayoa_STRchive-disease-loci.hg38.longtr.bed
- dayoa_STRchive-disease-loci.hg38.longtr.bed.gz, size 1824
- dayoa_STRchive-disease-loci.hg38.longtr.manifest.json
- dayoa_STRchive-disease-loci.hg38.longtr.skipped.tsv
```

Cluster execution was not run from this Mac. To validate runtime behavior, use a Daylily headnode with `/fsx/references` mounted and an ONT manifest, then run:

```bash
dy-r longtr_diseaser -p -j 100 -k -n
dy-r longtr_all -p -j 100 -k -n
```
