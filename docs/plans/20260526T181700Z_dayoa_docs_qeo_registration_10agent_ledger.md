# DayOA Documentation Rebuild + QEO/KEO Registration Ledger

Created: 2026-05-26T18:17:00Z

## Gate 0 Inventory

Objective: rebuild DayOA documentation after quarantining legacy narrative/reference docs, then add deterministic Dewey/QEO artifact registration to the Snakemake DAG without changing Daylily's execution-plane role.

Guardrails:

- Preserve `AGENTS.md`, `CLAUDE.md` if present, and `docs/plans/` as active control records.
- Preserve existing user changes. Initial dirty state includes `.test_data/**/units.tsv`, `docs/catalog_of_tools.md`, `docs/plans/20260526T144550Z_reference_runtime_assets_path_cutover_ledger.md`, `pyproject.toml`, and `tests/test_workflow_catalog.py`.
- No Dewey registration inside MultiQC generation rules.
- No fallback behavior, compatibility shims, inferred defaults, polling daemon, ClickHouse, React SPA, MegaQC, QC pass/fail logic, release authority, registry authority, or sample-name identity collapse.
- Daylily produces evidence. Dewey registers evidence. QEO observes evidence. R2 interprets and releases.

Recon evidence:

- Documentation inventory before quarantine: 106 documentation-like files at depth <= 3 excluding `.git`, `.snakemake`, and `quarantine`.
- Focused baseline command: `python -m pytest -q tests/test_multiqc_qc_targets.py tests/test_multiqc_staging_contracts.py tests/test_multiqc_sample_identifiers.py`
- Focused baseline result: 49 passed in 0.23s.
- MultiQC rule surface: `workflow/rules/multiqc_final_wgs.smk`.
- MultiQC staging surface: `workflow/scripts/stage_multiqc_inputs.py`.
- Sample identity surface: `workflow/rules/common.smk` `day_stage_sample_id`.
- Existing MultiQC config surface: `config/external_tools/multiqc_config.yaml`.

## Ledger

| ID | Area/Repo | Requirement/Surface | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| DAYOA-QEO-001 | daylily-omics-analysis | Gate 0 inventory and baseline | SUCCESS | ledger | none | Agent 1 | Focused baseline 49 passed; dirty state recorded | n/a | Gate 0 complete before implementation edits |
| DAYOA-QEO-002 | daylily-omics-analysis | Quarantine legacy narrative/reference docs while preserving control docs | SUCCESS | docs | none | Agent 2 | `quarantine/legacy-docs/README.md`, `quarantine/legacy-docs/root/`, `quarantine/legacy-docs/docs/` | Legacy docs were broad and stale | Active `docs/plans/` preserved |
| DAYOA-QEO-003 | daylily-omics-analysis | Regenerate canonical README/docs entrypoints with Daylily ecosystem guidance | SUCCESS | docs | none | Agent 9 | `README.md`, `docs/README.md` | Entry docs needed current execution-plane framing | Top guidance names daylily-ephemeral-cluster, Ursa, and Bloom |
| DAYOA-QEO-004 | daylily-omics-analysis | QEO reconnaissance document | SUCCESS | docs | none | Agent 3 | `docs/qeo/QEO_DAYOA_RECON.md` | QEO integration needed repo-grounded source map | Recon covers paths, rules, risks, and modifications |
| DAYOA-QEO-005 | daylily-omics-analysis | Deterministic artifact inventory and manifest checksums | SUCCESS | code | none | Agent 4 | `daylily_omics_analysis/qeo_registration.py`, `tests/test_qeo_registration.py` | Dewey/QEO require replay-safe artifact identity | SHA256, canonical JSON, required-file checks implemented |
| DAYOA-QEO-006 | daylily-omics-analysis | Strict Dewey/local-only registration client and receipts | SUCCESS | code | Dewey credentials only for live calls | Agent 5 | `RegistrationConfig`, local-only tests, Dewey config validation tests | DayOA must register evidence without becoming authority | Dewey mode requires explicit URL/token/storage root |
| DAYOA-QEO-007 | daylily-omics-analysis | Snakemake 7 DAG registration rules | SUCCESS | workflow | none | Agent 6 | `workflow/rules/qeo_registration.smk`, `workflow/Snakefile` include | Registration must be a DAG edge after MultiQC | Rules added after MultiQC generation boundary |
| DAYOA-QEO-008 | daylily-omics-analysis | QEO ingest manifest and outbox event contracts | SUCCESS | code | none | Agent 7 | `qeo_ingest_manifest`, `build_artifact_produced_event`, event tests | QEO must ingest refs/manifests, not crawl filesystems | Event is deterministic and excludes sample names |
| DAYOA-QEO-009 | daylily-omics-analysis | Golden corpus and unit tests | SUCCESS | tests | none | Agent 8 | `docs/qeo/QEO_GOLDEN_CORPUS_TEST_PLAN.md`, `tests/test_qeo_registration.py` | Registration semantics need deterministic coverage | Synthetic golden fixture tests added; GIAB expansion documented |
| DAYOA-QEO-010 | daylily-omics-analysis | Tool/pipeline inventory, worked examples, diagrams, MultiQC examples | SUCCESS | docs | none | Agent 9 | `docs/catalog_of_tools.md`, `docs/examples/multiqc/README.md`, QEO docs | Operators need complete task-oriented documentation | Tool inventory has public links, examples, and diagrams |
| DAYOA-QEO-011 | daylily-omics-analysis | Final validation, coverage, dry-run evidence | BLOCKED | validation | live cluster not assumed | Agent 10 | pytest 199 passed; coverage 84%; shell CLI 28 passed; py_compile passed; Snakemake command missing | Must distinguish local checks from cluster-dependent checks | Local checks complete; Snakemake dry-run blocked by `zsh:1: command not found: snakemake` |

## Validation Summary

- Focused baseline before implementation: `49 passed in 0.23s`.
- Focused final suite: `50 passed in 0.23s`.
- Full pytest with coverage: `199 passed in 4.52s`.
- Coverage: `TOTAL 560 statements, 87 missed, 84%`.
- Shell CLI suite: `28 passed, 0 failed`.
- Python compile: `python -m py_compile daylily_omics_analysis/qeo_registration.py workflow/scripts/register_qeo_artifacts.py` passed.
- Snakemake parse/dry-run: blocked in the local shell because `snakemake` is not on PATH.
- Live cluster examples: not run. No AWS profile, region, cluster, or second-stage live approval was provided.

All ledger rows are terminal. The local repo objective is complete except for the explicitly blocked Snakemake/cluster validation surfaces.
