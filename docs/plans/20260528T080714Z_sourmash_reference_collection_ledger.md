# Sourmash Reference Collection Runtime Asset Ledger

Created: 2026-05-28T08:07:14Z

## Objective

Publish a sourmash collection under the DayOA reference bucket runtime-asset namespace at
`s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/sourmash/`, then wire the
automounted FSx path into the DayOA local and Slurm profile templates so future clusters can run
`produce_unmapped_metagenomics_sourmash_gather` without rebuilding the collection.

## Gate 0: Inventory Freeze

- Ledger path: `docs/plans/20260528T080714Z_sourmash_reference_collection_ledger.md`
- Repo path: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- Branch: `codex/dayoa-local-evidence-dewey-refactor-20260528`
- Commit: `49dbbce995d23219ad4bea35814b308a5cee1cd8`
- AWS profile/region: `lsmc` / `us-west-2`
- Target bucket prefix: `s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/sourmash/`
- Target mounted prefix: `/fsx/references/runtime_assets/tool_specific_resources/sourmash/`
- Source collection: official sourmash GTDB RS226 page, `gtdb-reps-rs226-k31.dna.zip`, DNA k=31 scaled=1000 species representatives.
- Source URL: `https://farm.cse.ucdavis.edu/~ctbrown/sourmash-db.new/gtdb-rs226/gtdb-reps-rs226-k31.dna.zip`
- Source HTTP HEAD evidence: `200 OK`, `Content-Length: 3896377378`, `Last-Modified: Wed, 30 Apr 2025 06:51:23 GMT`, `ETag: "e83e0022-633f95866dd59"`.
- Local scratch evidence: `df -h /tmp` showed 292 GiB available.
- Existing S3 evidence: `aws s3 ls s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/sourmash/ --recursive --profile lsmc --region us-west-2` returned no objects.
- Bare-shell CLI evidence: `command -v sourmash` returned no path; validation will use zip integrity and manifest/metadata inspection unless the repo runtime environment provides the CLI.
- Initial dirty state:

```text
## codex/dayoa-local-evidence-dewey-refactor-20260528...origin/codex/dayoa-local-evidence-dewey-refactor-20260528
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
?? workflow/rules/archived_qc/
```

## Tracking Ledger

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| SMASH-001 | Source selection | Use a real sourmash collection that matches DayOA k=31/scaled=1000 DNA gather settings. | SUCCESS | config_or_startup_contract | Gate 0 | orchestrator | Official sourmash GTDB RS226 docs list `gtdb-reps-rs226-k31.dna.zip` as species representatives, DNA, k=31, scaled=1000; embedded `SOURMASH-MANIFEST.csv` rows show `ksize=31`, `moltype=DNA`, `scaled=1000`. |  | Collection matches the existing DayOA sourmash gather profile settings. |
| SMASH-002 | Runtime asset | Download and validate the collection before publishing. | SUCCESS | config_or_startup_contract | Gate 2 | orchestrator | Downloaded `/tmp/dayoa_sourmash_refs/20260528T080714Z/gtdb-reps-rs226-k31.dna.zip`; `stat -f %z` -> `3896377378`; `shasum -a 256` -> `6f3cc74f0bdcf6f84466ba91f87d6f2bf30081d5814bdf006cafd1e9cbbeada9`; `unzip -tq` -> no errors; `zipinfo -t` -> `143385 files`. |  | Local collection is structurally valid and provenance-hashed before S3 publication. |
| SMASH-003 | Runtime asset | Upload the collection and provenance manifest under the DayOA runtime-assets sourmash subdir. | SUCCESS | config_or_startup_contract | Gate 2 | orchestrator | Uploaded `s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/sourmash/gtdb-rs226/gtdb-reps-rs226-k31.dna.zip`; sidecars `.sha256` and `.provenance.txt`; `head-object` -> `ContentLength: 3896377378`, `ContentType: application/zip`, `ServerSideEncryption: AES256`, ETag `"196a02692bb20d952daec8f965f88613-465"`; `aws s3 ls` shows all three objects. |  | Runtime asset is published under the shared reference bucket sourmash subdir. |
| SMASH-004 | DayOA profiles | Set local and Slurm `unmapped_metagenomics.sourmash_databases` to the automounted `/fsx/references/...` collection path. | SUCCESS | config_or_startup_contract | Gate 2 | orchestrator | Updated `config/day_profiles/local/templates/rule_config.yaml` and `config/day_profiles/slurm/templates/rule_config.yaml` to `sourmash_databases: ["/fsx/references/runtime_assets/tool_specific_resources/sourmash/gtdb-rs226/gtdb-reps-rs226-k31.dna.zip"]`. |  | Future clusters using the reference-bucket automount can resolve the sourmash collection without rebuilding it. |
| SMASH-005 | Docs and tests | Update docs/tests so the profile default contract expects the published sourmash collection path. | SUCCESS | contract_test | Gate 5 | orchestrator | Updated `docs/ops/multiqc_qc_targets.md`, `docs/catalog_of_tools.md`, and `tests/test_multiqc_qc_targets.py`; removed the stale empty-sourmash default assertion and replaced it with the mounted runtime-asset path. |  | Docs and tests now describe the published GTDB RS226 sourmash default. |
| SMASH-006 | Acceptance | Run focused validation and terminalize all ledger rows. | SUCCESS | contract_test | Gate 5 | orchestrator | `python -m pytest -q tests/test_multiqc_qc_targets.py tests/test_unmapped_metagenomics.py` -> `35 passed in 0.23s`; final `python -m pytest -q tests/test_tool_catalog_docs.py tests/test_multiqc_qc_targets.py tests/test_unmapped_metagenomics.py` -> `40 passed in 0.17s`; profile YAML load check -> `YAML_OK`; `git diff --check` -> pass; S3 list shows zip, `.sha256`, and `.provenance.txt`. |  | All rows terminal; sourmash runtime asset and DayOA mounted-path defaults are complete. |

## Final Status

All ledger rows are terminal. Objective completed.

Published runtime asset:

- S3: `s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/sourmash/gtdb-rs226/gtdb-reps-rs226-k31.dna.zip`
- Mounted DayOA path: `/fsx/references/runtime_assets/tool_specific_resources/sourmash/gtdb-rs226/gtdb-reps-rs226-k31.dna.zip`
- SHA-256: `6f3cc74f0bdcf6f84466ba91f87d6f2bf30081d5814bdf006cafd1e9cbbeada9`
- Sidecars: `.sha256`, `.provenance.txt`
