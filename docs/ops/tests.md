# Tests And Validation

Run tests from the repository root. On macOS, activate the local execution environment first:

```bash
eval "$(conda shell.zsh hook)"
conda activate DAY-EC
```

## Documentation-Only Checks

```bash
git diff --check
python -m pytest -q tests/test_tool_catalog_docs.py tests/test_workflow_catalog.py
```

Run shell contract tests when CLI entrypoints or BCL Convert bootstrap docs change:

```bash
bash tests/test_cli_commands.sh
bash tests/test_bclconvert_bootstrap.sh
```

## Test Inventory

| Test | Purpose |
| --- | --- |
| `tests/test_cli_commands.sh` | CLI shell entrypoints, aliases, completion, monitor behavior, and docs coverage. |
| `tests/test_bclconvert_bootstrap.sh` | BCL Convert bootstrap scripts, rules, fixtures, and report expectations. |
| `tests/test_illumina_run_reports.py` | Illumina run-folder metrics, required-file failures, read-equivalent math, read disposition residual math, and report wiring. |
| `tests/test_complete_genomics_sentieon.py` | Complete Genomics/MGI model paths and `sentcg/cgt7p` routing. |
| `tests/test_tool_catalog_docs.py` | README/catalog link, tool-catalog schema, and required code-sourced rows. |
| `tests/test_altair_validation_contracts.py` | Altair RR/BAR denominator guards, seven-sample accuracy aggregation, coverage and boundary status gates. |
| `tests/test_altair_validation_workflow.py` | Altair Snakemake target, full-RR mosdepth wiring, boundary verification, and profile defaults. |
| `tests/test_multiqc_qc_targets.py` | Staged MultiQC targets, runtime-gated QC tools, VEP chunking, and final report contracts. |
| `tests/test_expansionhunter_contracts.py` | ExpansionHunter resources, parser, outputs, and MultiQC integration. |
| `tests/test_giab_qc_contracts.py` | GIAB/QC contracts for contamination, relatedness, manifests, and supporting resources. |
| `tests/test_workflow_catalog.py` | Packaged workflow catalog validation and command rendering. |

## Workflow Dry-Runs

For rule or profile changes, run a target dry-run after CLI initialization:

```bash
source dyoainit
dy-a local hg38
dy-r produce_alignstats -p -j 1 -n
```

For Slurm-only behavior, use a headnode workset and run the same command under `dy-a slurm <build>`.
