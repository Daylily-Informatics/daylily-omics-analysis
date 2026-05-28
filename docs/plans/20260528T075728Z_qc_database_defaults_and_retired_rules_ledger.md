# QC Database Defaults And Retired Rules Ledger

Started: `2026-05-28T07:57:28Z`
Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
Branch: `codex/dayoa-local-evidence-dewey-refactor-20260528`

## Objective

Add confirmed profile defaults for QC database/truthset assets where available, keep unavailable sourmash databases explicit rather than invented, and retire FASTV plus VerifyBamID2 rule files out of the active top-level `workflow/rules/` namespace. Verify that `workflow/Snakefile` does not active-include retired rules and that no non-retired `.smk` file expects their outputs.

## Gate 0 Baseline

Instruction file read: `AGENTS.md`.

Initial dirty worktree:

```text
## codex/dayoa-local-evidence-dewey-refactor-20260528...origin/codex/dayoa-local-evidence-dewey-refactor-20260528
 M tests/test_multiqc_qc_targets.py
 M workflow/Snakefile
 M workflow/rules/bcl2fq.smk
 M workflow/rules/bclconvert.smk
 M workflow/rules/evidence_manifest.smk
 M workflow/rules/expansionhunter.smk
 M workflow/rules/multiqc_cov_aln.smk
 M workflow/rules/multiqc_final_wgs.smk
 M workflow/rules/multiqc_for_bcl2fq.smk
 M workflow/rules/multiqc_for_raw_fastqs.smk
 M workflow/rules/multiqc_singleton.smk
 M workflow/rules/run_qc_reports.smk
 M workflow/rules/unmapped_metagenomics.smk
```

Reference bucket checks used `AWS_PROFILE=lsmc`, `AWS_DEFAULT_REGION=us-west-2`.

## Control Rows

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| G0-001 | Ledger | Record baseline and dirty state before edits. | SUCCESS | plan_amendment | Gate 0 | orchestrator | This ledger. |  | Baseline recorded. |
| REF-001 | Metagenomics defaults | Add profile defaults for confirmed Kraken2 and Ganon2 assets; do not invent sourmash DB paths. | SUCCESS | config_or_startup_contract | Gate 1 | orchestrator | Added `unmapped_metagenomics` defaults to `config/day_profiles/local/templates/rule_config.yaml` and `config/day_profiles/slurm/templates/rule_config.yaml`: Kraken2 `/fsx/references/runtime_assets/tool_specific_resources/metagenomics/kraken2/k2_pluspfp_16_GB_20260226`, Ganon2 `/fsx/references/runtime_assets/tool_specific_resources/ganon2/dayoa_qc_refseq_abfv_complete_top1_20260528`, `threads: 16`, `mem_mb: 64000`, and `read_limit: all`. `aws s3 ls s3://lsmc-dayoa-references-usw2/runtime_assets/tool_specific_resources/sourmash/ --profile lsmc --region us-west-2` returned no objects, so `sourmash_databases: []` remains explicit. | No published sourmash DB found. | Kraken2 and Ganon2 are now profile defaults; sourmash remains fail-hard until a DB is actually published. |
| REF-002 | Truvari defaults | Add profile defaults for confirmed HG002 GIAB SV v5.0q truthset. | SUCCESS | config_or_startup_contract | Gate 1 | orchestrator | Added `truvari_sv_benchmark.truthsets.HG002.regions.giab_sv_v5_0q_hc` to local/slurm profile templates with confirmed VCF, TBI, and benchmark BED under `/fsx/references/genomic_data/organism_annotations/H_sapiens/hg38/controls/giab/sv/v5.0q/HG002/giabHCv5q/`. |  | HG002 Truvari SV truthset is now declared by default. |
| RET-001 | FASTV retirement | Disable FASTV by removing active Snakefile include, removing external expected outputs, and archiving the rule file. | SUCCESS | feature_implementation | Gate 1 | orchestrator | Moved `workflow/rules/fastv.smk` to `workflow/rules/archived_qc/fastv.smk`; removed active `include: "rules/fastv.smk"` from `workflow/Snakefile`; removed FASTV from `MULTIQC_QC_LONG_RUNNING_TOOLS`; removed final MultiQC expectations for `seqqc/fastv` JSON/HTML. | FASTV was still active-included at baseline. | FASTV is archived and no longer active. |
| RET-002 | VerifyBamID2 retirement | Confirm VerifyBamID2 is not active-included, no non-retired `.smk` expects its outputs, and archive the rule file. | SUCCESS | feature_implementation | Gate 1 | orchestrator | Moved `workflow/rules/verifybamid2_contam.smk` to `workflow/rules/archived_qc/verifybamid2_contam.smk`; replaced stale disabled include comment with archive note; removed stale commented VerifyBamID2 output references from `workflow/rules/multiqc_cov_aln.smk`. | Rule was disabled but still top-level at baseline. | VerifyBamID2 is archived and remains inactive. |
| TEST-001 | Verification | Run focused static tests and grep checks. | SUCCESS | contract_test | Gate 2 | orchestrator | `python -m pytest -q tests/test_multiqc_qc_targets.py tests/test_giab_qc_contracts.py tests/test_contam_identity_bundle.py tests/test_unmapped_metagenomics.py tests/test_truvari_sv_benchmark.py` -> `63 passed in 0.47s`; active Snakefile include check printed `NO_ACTIVE_FASTV_OR_VERIFYBAMID2_INCLUDES`; `rg -n "seqqc/fastv|alignqc/contam/vb2|verifybamid2_panel_comparison_mqc|fastv\\.done|fastv\\.json|fastv\\.html|vb2\\.tsv|vb2_mqc" workflow/rules --glob '*.smk' --glob '!**/archived_qc/**'` returned no matches. |  | Verification passed. |

## Terminal Status

All ledger rows are terminal. Objective completed with one explicit limitation: no sourmash database path was added because no sourmash collection was found in the reference bucket.
