# DayOA Evidence Manifest Dewey/QEO Readiness Ledger

Controlling plan: chat-approved "Ledgered Dewey Registration and QEO MultiQC Ingest Trial"
Ledger path: `docs/plans/20260531T074927Z_dayoa_evidence_manifest_dewey_qeo_ledger.md`

## Gate 0 Baseline

- Repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- Branch: `codex/dayoa-local-evidence-dewey-refactor-20260528`
- Initial dirty state: existing modified files in README/docs/config/workflow/tests plus untracked `docs/ops/results_directory_structure.md` and `workflow/scripts/prepare_bclconvert_demux_fastqc_inputs.py`; preserve as parallel work.
- Instructions read: `/Users/jmajor/.agents/AGENTS.md`, `/Users/jmajor/.codex/AGENTS.md`, repo `AGENTS.md`, `/Users/jmajor/.codex/docs/plan-ledger-workflow.md`.
- Scope boundary: DayOA only. Do not edit DYEC, Dewey, or QEO repos.
- Non-fallback rule: missing files or non-derivable metadata must fail or remain absent; do not infer defaults.
- Inspection evidence:
  - `daylily_omics_analysis/evidence_manifest.py` has current final-MultiQC-only helper and generic inventory CLI.
  - `workflow/rules/evidence_manifest.smk` writes `results/day/<genome>/reports/dayoa_evidence_manifest.json`.
  - `tests/test_evidence_manifest.py` is the focused existing coverage surface.

## Control Ledger

| ID | Area | Requirement | Status | Category | Approval Gate | Owner | Evidence | Root Cause | Terminal Note |
|---|---|---|---|---|---|---|---|---|---|
| DAYOA-001 | Evidence classification | Classify VCF/VCF indexes, CRAM/CRAI, BAM/BAI/CSI, MultiQC HTML/data files, logs, sources, general stats, and parser-relevant TSV/JSON as first-class evidence artifacts. | SUCCESS | feature_implementation | Gate 1 | DayOA agent | `daylily_omics_analysis/evidence_manifest.py`; `tests/test_evidence_manifest.py::test_file_classification_covers_analysis_outputs_and_indexes`; focused pytest pass. |  | Added explicit artifact roles for alignment, variant, MultiQC, run QC, BCL Convert, log, benchmark, manifest, and parser-relevant table/JSON files. |
| DAYOA-002 | Evidence inventory | Inventory final MultiQC, run QC MultiQC, BCL Convert MultiQC, and selected analysis result files without registering with Dewey/QEO. | SUCCESS | feature_implementation | Gate 1 | DayOA agent | `discover_first_class_evidence_files`, `build_analysis_evidence_manifest`, `analysis-inventory` CLI; `tests/test_evidence_manifest.py::test_analysis_inventory_discovers_results_multiqc_and_derivable_metadata`. |  | Added DayOA-local discovery under explicit `config/` and `results/` roots; no registration side effects added. |
| DAYOA-003 | Metadata | Add only explicit artifact metadata derivable from path/workflow context. | SUCCESS | feature_implementation | Gate 1 | DayOA agent | `artifact_metadata`; metadata assertions in `tests/test_evidence_manifest.py`. |  | Added result scope, genome build, run ID, sample ID, artifact format, report kind/name, and run QC platform only when path conventions make them explicit. |
| DAYOA-004 | Tests | Add focused tests for new classifications, report roots, metadata, and fail-hard behavior. | SUCCESS | contract_test | Gate 5 | DayOA agent | `tests/test_evidence_manifest.py` new classification, inventory, metadata, and empty-inventory failure coverage. |  | Focused contract coverage added and passing. |
| DAYOA-005 | Final acceptance | Run focused DayOA tests and terminalize ledger rows. | SUCCESS | contract_test | Gate 5 | DayOA agent | `python -m pytest tests/test_evidence_manifest.py -q -> 9 passed`; combined focused pytest command -> `19 passed`; `python -m py_compile daylily_omics_analysis/evidence_manifest.py workflow/scripts/write_dayoa_evidence_manifest.py -> 0`. |  | All DayOA-owned rows are terminal; no DayOA-side blocker remains. |
| DAYOA-006 | Manifest tags | Tag `config/samples.tsv` and `config/units.tsv` explicitly and derive sample/experiment/run/unit metadata from the manifest tables. | SUCCESS | feature_implementation | Gate 1 | orchestrator | `daylily_omics_analysis/evidence_manifest.py`; `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 python -m pytest tests/test_evidence_manifest.py -q -> 9 passed`. |  | `samples_manifest` and `units_manifest` records now carry explicit tags plus sample names, experiment IDs, run IDs, lane/barcode/library/platform metadata where present. |
| DAYOA-007 | MultiQC tags | Add sample/experiment/run/unit metadata and tags to MultiQC report HTML and data-dir artifacts. | SUCCESS | feature_implementation | Gate 1 | orchestrator | `tests/test_evidence_manifest.py::test_analysis_inventory_discovers_results_multiqc_and_derivable_metadata`; focused pytest pass. |  | MultiQC HTML/data records now include `sample:*`, `experiment:*`, `run:*`, and report-kind tags derived from `config/samples.tsv` and `config/units.tsv`. |

## Final Terminal Report

- Terminal rows: 7 `SUCCESS`, 0 `BLOCKED`, 0 `FAIL`, 0 working.
- Objective completion: complete for the requested DayOA-only implementation scope.
- Tests:
  - `eval "$(conda shell.zsh hook)" && conda activate DAY-EC && python -m pytest tests/test_evidence_manifest.py -q`
  - `eval "$(conda shell.zsh hook)" && conda activate DAY-EC && python -m pytest tests/test_evidence_manifest.py tests/test_multiqc_qc_targets.py::test_staged_multiqc_targets_and_dependencies_exist tests/test_workflow_target_aliases.py tests/test_bclconvert_multiqc.py::test_bclconvert_rule_exports_metrics_to_genome_build_multiqc_dir tests/test_run_qc_reports.py::test_run_qc_rules_are_shell_only_and_separate_from_final_multiqc -q`
  - `eval "$(conda shell.zsh hook)" && conda activate DAY-EC && python -m py_compile daylily_omics_analysis/evidence_manifest.py workflow/scripts/write_dayoa_evidence_manifest.py`
