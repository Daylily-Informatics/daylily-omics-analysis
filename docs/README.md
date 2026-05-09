# Daylily Omics Documentation

This directory holds the canonical documentation for the current `daylily-omics-analysis` codebase. Prefer these docs for new runs and developer work.

The production contract is that this repository runs inside a `daylily-ephemeral-cluster` workset clone, with Daylily omics/reference data mounted under `/fsx/data`. Use the [`daylily-ephemeral-cluster`](https://github.com/Daylily-Informatics/daylily-ephemeral-cluster) `daylily-ec` CLI for cluster access, read staging, and `samples.tsv` / `units.tsv` creation or delivery. Local execution is for fixture smoke tests, docs validation, and workflow development.

## Current Operator Docs

| Document | Use |
| --- | --- |
| [`quickest_start.md`](quickest_start.md) | Minimal local smoke-test checklist. |
| [`first_ephemeral_cluster_analysis.md`](first_ephemeral_cluster_analysis.md) | First Slurm-backed analysis on a prepared headnode. |
| [`ops/dycli.md`](ops/dycli.md) | Daylily CLI command behavior. |
| [`ops/config.md`](ops/config.md) | Profiles, sample/unit tables, config precedence, and scratch behavior. |
| [`ops/dir_and_file_scheme.md`](ops/dir_and_file_scheme.md) | Current output and log layout. |
| [`remote_test_execution.md`](remote_test_execution.md) | Persistent tmux execution and monitoring pattern. |

## Current Workflow Docs

| Document | Use |
| --- | --- |
| [`workflows/complete_genomics_sentieon.md`](workflows/complete_genomics_sentieon.md) | Complete Genomics/MGI `sentcg -> smd -> cgt7p`. |
| [`workflows/bclconvert_bootstrap.md`](workflows/bclconvert_bootstrap.md) | Illumina BCL Convert bootstrap. |
| [`workflows/ensemble_vcf.md`](workflows/ensemble_vcf.md) | Ensemble VCF notes. |
| [`README_sentieon_pangenome_shortreads.md`](README_sentieon_pangenome_shortreads.md) | Sentieon pangenome short-read notes. |

## Developer Docs

| Document | Use |
| --- | --- |
| [`ops/tests.md`](ops/tests.md) | Validation commands and test inventory. |
| [`ops/workflow_catalog.md`](ops/workflow_catalog.md) | Packaged workflow catalog API. |
| [`ops/analysis_manifest.md`](ops/analysis_manifest.md) | Legacy manifest conversion notes. |
| [`catalog_of_tools.md`](catalog_of_tools.md) | Code-sourced catalog of available tool integrations, evidence, outputs, tests, and dormant status. |

## Historical Notes

Several top-level Markdown files are preserved as records of specific debugging or launch efforts. They are not canonical operator docs:

- `addQCplan.md`
- `addqc_plan.md`
- `dhiomr_report.md`
- `ENSEMBLE_INTEGRATION_SUMMARY.md`
- `expansion_hunter_plan.md`
- `expansion_hunter_plan_v2.md`
- `run_cg.md`
- `gotimeplan.md`
- `hyb_runbook.md`
- `hybrun.md`
- `ugdata.md`
- `RTG_CONCORDANCE_REFACTOR.md`
- `FAIL_REPORT.md`
- `TELEMETRY_FILE_PROMPT.md`
- `sentieon_hybrid_ILMN_ONT_MODULAR_PATCHES.md`
- `sentieon_hybrid_ILMN_ONT_MODULAR_PATCHES_READGROUP_FIXES.md`
- `tmpdir_audit_report.md` is a dated audit report; re-check the current rules before treating its statuses as current.

Some historical notes contain literal command transcripts from older runs. Do not reuse those blocks verbatim when they conflict with current access rules, especially the `daylily-ec`/SSM-only headnode path and the rule that `source dyoainit`, `dy-a`, and `dy-r` should run as separate shell commands.

When a historical note conflicts with the canonical docs, use the canonical docs and then verify against the current code.
