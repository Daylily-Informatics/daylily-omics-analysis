# SMN12 Orthogonal Caller Integration Ledger

Objective: plug SMAca, Broad sma-finder, and HapSMA into DayOA as explicit SMN12 complementary caller targets alongside SMNCopyNumberCaller and Sentieon HiOMR segdup-caller.

Controlling plan: user-provided 10-agent ledger plan in the 2026-06-10 Codex thread.

## Gate 0: Inventory Freeze

- Repo: `/Users/jmajor/projects/lsmc/daylily-omics-analysis`
- Branch baseline: `## jem-dev...origin/jem-dev`
- Version baseline: `git describe --tags --always --dirty` -> `10.0.3-dirty`
- Ledger path: `docs/plans/20260610T223735Z_smn12_orthogonal_callers_ledger.md`
- Workflow execution contract: local source/test work is allowed; any DayOA workflow dry-run/live validation on a headnode must use an initialized persistent `ubuntu` tmux pane with `source dyoainit`, `dy-a ...`, then `dy-r ...`. No direct `snakemake` invocation.
- External source checks: official SMAca, broadinstitute/sma-finder, and UMCUGenetics/HapSMA GitHub README surfaces inspected for command shape and caller capability.

Pre-existing dirty/untracked files before this SMN integration:

```text
 M config/day_profiles/local/templates/rule_config.yaml
 M config/day_profiles/slurm/templates/rule_config.yaml
 M tests/test_multiqc_qc_targets.py
 M tests/test_ont_fastq_contracts.py
 M tests/test_sentieon_model_bundle_config.py
 M tests/test_slurm_profile.py
 M workflow/rules/alignstats_compile.smk
 M workflow/rules/bcftools_vcfstat.smk
 M workflow/rules/calc_coverage_eveness.smk
 M workflow/rules/calc_coverage_evenness_two.smk
 M workflow/rules/common.smk
 M workflow/rules/generate_deduplicated_bams.smk
 M workflow/rules/multiqc_cov_aln.smk
 M workflow/rules/multiqc_final_wgs.smk
 M workflow/rules/picard.smk
 M workflow/rules/rtg_vcfeval.smk
 M workflow/rules/rtg_vcfstats.smk
 M workflow/rules/sent_snv_ont.smk
 M workflow/rules/unmapped_metagenomics.smk
 M workflow/rules/vep.smk
 M workflow/rules/workflow_target_aliases.smk
?? docs/plans/20260610T092523Z_dyecX4_doppelmark_ont_ultima_kitchensink_ledger.md
?? docs/plans/20260610T223735Z_smn12_orthogonal_callers_ledger.md
?? tests/test_pangenome_kitchensink_contracts.py
```

## Agent Rows

| ID | Agent | Area | Requirement | Status | Category | Approval Gate | Evidence | Root Cause | Terminal Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SMN-001 | agent-orchestrator | Ledger | Own ledger, Gate 0 inventory, dirty-worktree boundaries, final acceptance. | SUCCESS | feature_implementation | Gate 0 | Gate 0 recorded above; final validation evidence recorded below. | N/A | Pre-existing dirty files were preserved and scoped SMN/HTD edits were recorded. |
| SMN-002 | agent-input-contracts | Inputs | Define shared helpers for SMN short-read and long-read CRAM selection. | SUCCESS | contract_test | Gate 1 | `workflow/rules/common.smk`; `tests/test_htd_callers_contract.py::test_smn12_uses_hybrid_sr_cram_and_hard_validates_summary` | N/A | Added `smn_short_cram/crai`, `smn_long_cram/crai`, short/long aligner selectors, ONT/graph rejection, HiOMR SR/LR routing. |
| SMN-003 | agent-smncopy | SMNCopyNumberCaller | Preserve existing `produce_smn12` behavior and move it onto shared SR helper. | SUCCESS | feature_implementation | Gate 1 | `workflow/rules/smn_copynumbercaller.smk`; focused pytest pass. | N/A | `produce_smn12` now expands `smn_short_read_aligners()` and HiOMR uses `sentdhiomr.sr_dedup.cram`. |
| SMN-004 | agent-smaca | SMAca | Re-enable/repair SMAca as a real selectable short-read caller with hard output checks. | SUCCESS | feature_implementation | Gate 1 | `workflow/rules/smaca.smk`; `workflow/envs/smaca_v0.1.yaml`; focused pytest pass. | N/A | SMAca is actively included, uses shared short-read CRAM routing, checks command presence, non-empty TSV, and header. |
| SMN-005 | agent-smafinder | sma-finder | Add Broad sma-finder short-read affected-status caller with no fabricated copy number. | SUCCESS | feature_implementation | Gate 1 | `workflow/rules/sma_finder.smk`; `workflow/envs/sma_finder_v0.1.yaml`; `workflow/scripts/htd_calls_mqc.py`; focused pytest pass. | N/A | Added affected-status-only TSV/JSON outputs; SMN1/SMN2 CN fields remain `NA`. |
| SMN-006 | agent-hapsma | HapSMA | Add HapSMA ONT-only dev/exploratory caller with explicit config and coverage gate. | SUCCESS | feature_implementation | Gate 1 | `workflow/rules/hapsma.smk`; `workflow/envs/hapsma_v0.1.yaml`; focused pytest pass. | N/A | HapSMA is handled as a normal selected caller/orthogonal evidence source; it is dev-labeled and hard-fails without explicit Nextflow/HapSMA config, ploidy, email, SMN region, and mean-coverage gate. |
| SMN-007 | agent-hiomr | HiOMR | Integrate HiOMR-specific routing and Sentieon SMN1 segdup evidence. | SUCCESS | feature_implementation | Gate 1 | `workflow/rules/common.smk`; `workflow/rules/smn12_orthogonal_calls.smk`; focused pytest pass. | N/A | Short-read SMN callers consume HiOMR SR dedup CRAM; HapSMA consumes HiOMR LR CRAM; orthogonal target includes Sentieon SMN1 segdup evidence when HiOMR aligners are configured. |
| SMN-008 | agent-summary | Summary/MultiQC | Build `other_reports/smn12_orthogonal_calls_mqc.tsv` with caller capability fields and discordance flag. | SUCCESS | feature_implementation | Gate 1 | `workflow/scripts/smn12_orthogonal_calls_mqc.py`; `config/external_tools/multiqc_config.yaml`; compileall pass. | N/A | Added one-row-per-sample/caller summary with capability, evidence source, CN/status fields, and discordance flag. |
| SMN-009 | agent-catalog-tests | Tests/catalog | Wire workflow aliases/catalog visibility and focused tests. | SUCCESS | contract_test | Gate 1 | `daylily_omics_analysis/data/workflow_catalog.v1.json`; `docs/catalog_of_tools.md`; focused pytest pass. | N/A | `htd_callers` supports `smn12`, `smaca`, `sma_finder`, `hapsma`; default remains Cyrius-only. |
| SMN-010 | agent-validation | Validation | Run focused pytest and record exact headnode `dy-r` validation command. | SUCCESS | contract_test | Gate 5 | `python -m pytest -q tests/test_htd_callers_contract.py tests/test_workflow_catalog.py tests/test_multiqc_qc_targets.py tests/test_workflow_target_aliases.py tests/test_tool_catalog_docs.py && python -m compileall -q workflow/scripts/htd_calls_mqc.py workflow/scripts/smn12_orthogonal_calls_mqc.py` -> `60 passed`, compileall `exit_code=0`. | N/A | Headnode dry-run command is recorded below and must be run only from a persistent initialized `ubuntu` tmux DayOA pane. |

## Validation Evidence

Local focused validation:

```text
python -m pytest -q tests/test_htd_callers_contract.py tests/test_workflow_catalog.py tests/test_multiqc_qc_targets.py tests/test_workflow_target_aliases.py tests/test_tool_catalog_docs.py && python -m compileall -q workflow/scripts/htd_calls_mqc.py workflow/scripts/smn12_orthogonal_calls_mqc.py
60 passed in 0.33s
compileall exit_code=0
```

Headnode runtime validation command, to run only in a persistent `ubuntu` tmux login pane after initializing DayOA:

```bash
source dyoainit
dy-a slurm hg38_broad
dy-r produce_smn12_orthogonal_calls -p -k -j <N> -n
```

Runtime note: no headnode `dy-r` dry-run was launched from this source-edit turn. The command is recorded for the runtime gate because DayOA workflow execution must happen from an initialized persistent headnode pane, not from a local or non-interactive Snakemake invocation.

## Acceptance Checklist

- No rows remain `OPEN`, `IN_PROGRESS`, or `ATTEMPTING_BUGFIX`.
- `produce_smn12_orthogonal_calls` exists as an explicit target.
- `htd_callers` supports `smaca`, `sma_finder`, and `hapsma` while remaining opt-in.
- Short-read SMN callers never consume ONT-only CRAM paths.
- HapSMA is dev/exploratory, ONT-only, included through normal caller/orthogonal target routing, and hard-fails without explicit runtime config and coverage evidence.
- Sentieon HiOMR segdup SMN1 evidence is included when HiOMR is configured.
- Focused pytest suite passes locally.
