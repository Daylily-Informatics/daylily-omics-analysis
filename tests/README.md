# Daylily Test Suite

This directory contains shell and Python checks for the current CLI, workflow catalog, BCL Convert bootstrap, MultiQC reporting, Illumina run reports, Altair validation, alignment preservation, and Complete Genomics Sentieon wiring.

## Running The Core Checks

From the repository root:

```bash
bash tests/test_cli_commands.sh
bash tests/test_bclconvert_bootstrap.sh
python -m pytest tests/test_complete_genomics_sentieon.py tests/test_workflow_catalog.py
```

On macOS, activate `DAY-EC` first:

```bash
eval "$(conda shell.zsh hook)"
conda activate DAY-EC
```

## Files

| File | Coverage |
| --- | --- |
| `test_cli_commands.sh` | `day-monitor`, `day-activate`, `day-run`, `day-set-genome-build`, `day-deactivate`, aliases, completion, shell syntax, and selected docs coverage. |
| `test_bclconvert_bootstrap.sh` | BCL Convert bootstrap scripts, fixtures, generated units table behavior, and report expectations. |
| `test_altair_validation_contracts.py` | Altair RR/BAR denominator guards, seven-sample accuracy aggregation, coverage, and boundary status gates. |
| `test_altair_validation_workflow.py` | Altair Snakemake target, full-RR mosdepth wiring, boundary verification, and profile defaults. |
| `test_alignment_preservation_audit.py` | Static BAM/CRAM preservation audit wiring, minimap2/strobe extraction guards, and report-script contracts. |
| `test_illumina_run_reports.py` | Explicit Illumina run-metrics config, report-script parsing contracts, read-disposition output, and final MultiQC opt-in wiring. |
| `test_multiqc_qc_targets.py` | Staged MultiQC targets, runtime-gated QC tools, and final report wiring. |
| `test_multiqc_report_intro.py` | Generated final MultiQC intro/header content and float-format overlay behavior. |
| `test_complete_genomics_sentieon.py` | MGI bundle paths, `DNBSEQ` platform, and canonical/deprecated `cgt7p` routing to `sentcg/cgt7p`. |
| `test_workflow_catalog.py` | `load_workflow_catalog()` and `render_workflow_command()` behavior. |

## Notes

These tests are intentionally lightweight. They validate repository wiring and documented contracts; they do not replace full Snakemake dry-runs or headnode execution tests for workflow changes.
