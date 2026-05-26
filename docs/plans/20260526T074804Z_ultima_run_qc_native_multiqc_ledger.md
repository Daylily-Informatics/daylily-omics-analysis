# Ultima Run QC, Native MultiQC, And AlignStats Execution Ledger

Date: 2026-05-26

## Control Surface

- Ledger path: `docs/plans/20260526T074804Z_ultima_run_qc_native_multiqc_ledger.md`
- DayOA repo: `/Users/jmajor/projects/daylily/daylily-omics-analysis`
- MultiQC repo: `/Users/jmajor/projects/lsmc/MultiQC`
- AlignStats repo: `/Users/jmajor/projects/lsmc/alignstats`
- Planned standalone repo: `/Users/jmajor/projects/lsmc/ur-qc`

This ledger tracks the approved cross-repo implementation program for Ultima run-level QC, a standalone open-source `ur-qc` parser/export package, native MultiQC Ultima support, and native MultiQC AlignStats support.

## Gate 0 Inventory

| Item | Evidence |
| --- | --- |
| DayOA branch | `codex/tstclu411c-hybrid-env-python` |
| DayOA dirty state | Pre-existing broad tracked edits and untracked ledgers were present before this work. This implementation only owns the Ultima run-QC docs, fixtures, tests, and MultiQC config additions listed in the final evidence. |
| MultiQC fork | `/Users/jmajor/projects/lsmc/MultiQC`, remote `git@github.com:lsmc-bio/MultiQC.git`, branch initially `main` |
| AlignStats repo | `/Users/jmajor/projects/lsmc/alignstats`, remote `git@github.com:lsmc-bio/alignstats.git` |
| `ur-qc` repo | `/Users/jmajor/projects/lsmc/ur-qc` was missing at Gate 0 and must be created as part of execution. |
| Live S3 evidence | Read-only inspection with `AWS_PROFILE=lsmc`, region `us-west-2`, bucket `s3://lsmc-ssf-sequencing-data/`. |
| Reviewed Ultima examples | `basecalls/lsmc/ssf-hq/RUN602202/2026/602202-20260512_1805/`, `RUN602220/2026/602220-20260417_2047/`, `RUN602221/2026/602221-20260417_2346/`. |

## Live Ultima Evidence Summary

The three reviewed native-WGS run roots contain root-level `*_LibraryInfo.xml`, `*_SequencingInfo.json`, root merged trimmer CSVs, `run_SecondaryAnalysis.txt`, `run_VariantCalling.txt`, and `UploadCompleted.json`. Per sample/barcode folders contain CRAM/CRAI, Picard-style `.csv`, summary `.json`, `_FlowQ.metric`, `_SNVQ.metric`, trimmer CSVs, MapQ bedGraphs, VerifyBamID-style selfSM outputs, unmatched CRAM/metric outputs, and a barcode-loop histogram CSV.

Important observed details:

- `LibraryInfo.xml` sample entries carry `Id`, `Index_Label`, `Index_Sequence`, `application_type`, secondary-analysis fields, and other attributes. Unknown attributes must be preserved in normalized JSON metadata.
- Root `UploadCompleted.json` can be zero bytes, which must normalize to status `completed_empty_marker`, not to a hidden success with fabricated timestamps.
- `_FlowQ.metric` and `_SNVQ.metric` are Picard-style metrics with histogram sections. FlowQ/SNVQ must not be described as Illumina-equivalent Q-score without a documented caveat.
- Root and per-sample trimmer files use headers such as `read group`, `format`, `segment index`, `num input reads`, `num failed reads`, `num filtered reads`, and `num failures`.
- `.selfSM.selfSM` can contain `FREEMIX`; `.selfSM.contamination_stats.csv` can contain `PCT_contamination`.

## Work Ledger

| ID | Area | Requirement | Status | Category | Gate | Owner | Evidence | Root Cause | Terminal Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| G0 | Orchestration | Record baseline repos, instructions, S3 evidence, and scope boundaries. | SUCCESS | plan_amendment | Gate 0 | orchestrator | This ledger and read-only S3/repo inventory. |  | Baseline recorded before implementation edits. |
| A1 | Evidence | Document observed Ultima schemas from live run examples and public/vendor references. | SUCCESS | feature_implementation | Gate 1 | evidence-agent | `docs/specs/ultima_run_qc_requirements.md`, `docs/specs/ugrun_metrics_schema.md`, `.test_data/data/ultima_run_qc/` |  | Observed live Ultima schemas are captured in requirements/schema docs and represented by fake minimal fixtures. |
| A2 | DayOA | Add immediate custom-data contract, MultiQC config additions, operator workflow, and tests. | SUCCESS | contract_test | Gate 1 | dayoa-agent | `config/external_tools/multiqc_config.yaml`, `docs/specs/ugrun_multiqc_contract.md`, `tests/test_ultima_run_qc_contracts.py`; `$CONDA_PREFIX/bin/python -m pytest -q tests/test_ultima_run_qc_contracts.py` -> `5 passed` |  | Custom-data sections, search patterns, order, docs, fixture, and contract tests landed. |
| A3 | ur-qc | Create local open-source `ur-qc` repo with `ugrun` CLI, normalized parsers, fixtures, and tests. | SUCCESS | feature_implementation | Gate 1 | urqc-agent | `/Users/jmajor/projects/lsmc/ur-qc`, branch `codex/ultima-run-qc`, commit `07ad171`, remote `https://github.com/lsmc-bio/ur-qc`, `$CONDA_PREFIX/bin/python -m pytest -q` -> `5 passed` |  | Repo created and pushed with initial parser scaffold. Declared but incomplete commands fail explicitly instead of writing placeholders. |
| A4 | MultiQC Ultima | Add native `ultima` module to the lsmc-bio MultiQC fork. | SUCCESS | feature_implementation | Gate 1 | multiqc-ultima-agent | `/Users/jmajor/projects/lsmc/MultiQC/multiqc/modules/ultima`, branch `codex/ultima-alignstats-native`, `$CONDA_PREFIX/bin/python -m pytest -q tests/test_ultima_alignstats_parsers.py multiqc/modules/ultima/tests/test_ultima.py multiqc/modules/alignstats/tests/test_alignstats.py` -> `7 passed` |  | Native module reads normalized `ur-qc` TSVs, requires `Sample` first, and does not scan large alignment files. |
| A5 | MultiQC AlignStats | Add native `alignstats` module to the lsmc-bio MultiQC fork. | SUCCESS | feature_implementation | Gate 1 | multiqc-alignstats-agent | `/Users/jmajor/projects/lsmc/MultiQC/multiqc/modules/alignstats`, parser tests above -> `7 passed`; AlignStats source docs at `/Users/jmajor/projects/lsmc/alignstats/doc/kv_pairs.tsv` |  | Native module supports combo TSV and JSON-like reports, including mean/median/mode/standard-deviation families. |
| A6 | Release | Preserve upstreamable boundaries and document release/PR split. | SUCCESS | plan_amendment | Gate 5 | release-agent | `docs/workflows/ultima_run_qc.md`, `/Users/jmajor/projects/lsmc/MultiQC/docs/plans/20260526T074804Z_ultima_alignstats_native_modules.md`, `/Users/jmajor/projects/lsmc/ur-qc/docs/plans/20260526T074804Z_ur_qc_scaffold.md` |  | Upstreamable module boundaries are documented. LSMC-specific grouping remains in DayOA config. |

## Gates

| Gate | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| Gate 0: Inventory Freeze | Baseline and reviewed evidence recorded before edits. | SUCCESS | Sections above. |
| Gate 1: Local Implementation | Docs, specs, parser package, native modules, and tests land locally. | SUCCESS | Rows A1 through A5 are terminal. |
| Gate 2: Validation | Focused tests pass in each touched repo. | SUCCESS | DayOA `5 passed`; `ur-qc` `5 passed`; MultiQC focused parser/module tests `7 passed`; py_compile passed for touched Python files. |
| Gate 3: Remote Publication | Create or push GitHub repos only after local tests and branch checks. | SUCCESS | `lsmc-bio/ur-qc` created and branch `codex/ultima-run-qc` pushed. MultiQC and DayOA changes remain local branches/worktree changes. |
| Gate 5: Final Acceptance | No working ledger rows remain unless explicitly blocked with root cause. | SUCCESS | All rows are terminal. |

## Open Questions

- Whether `ur-qc` should publish to PyPI under `ur-qc` before upstream MultiQC review.
- Whether native MultiQC Ultima should accept raw `LibraryInfo.xml` directly in upstream scope or only normalized `ur-qc` outputs.
- Whether AlignStats upstream should prefer native JSON-like reports only, or include DayOA `alignstats_combo_mqc.tsv` as a first-class input format.

## Validation Notes

- Installing the MultiQC fork editable into `DAY-EC` was required before the native module tests could import MultiQC. Pip reported existing AWS CDK packages in that environment still require `typeguard~=2.13.3`, while MultiQC installed `typeguard 4.5.2`.
- No destructive AWS action was performed.
- Live S3 access was read-only.
