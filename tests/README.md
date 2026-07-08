# Daylily Test Suite

This directory contains shell and Python checks for the current CLI, workflow catalog, BCL Convert bootstrap, and Complete Genomics Sentieon wiring.

## Running The Core Checks

From the repository root:

```bash
bash tests/test_cli_commands.sh
bash tests/test_bclconvert_bootstrap.sh
python -m pytest tests/test_complete_genomics_sentieon.py tests/test_workflow_catalog.py
python -m pytest tests/test_rule_log_benchmark_contracts.py tests/test_snakemake_parser_contracts.py tests/test_shell_wrapper_contracts.py
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
| `test_complete_genomics_sentieon.py` | MGI bundle paths, `DNBSEQ` platform, and canonical/deprecated `cgt7p` routing to `sentcg/cgt7p`. |
| `test_workflow_catalog.py` | `load_workflow_catalog()` and `render_workflow_command()` behavior. |
| `test_rule_log_benchmark_contracts.py` | Active Snakemake rules expose log and benchmark evidence contracts. |
| `test_snakemake_parser_contracts.py` | Active rule files avoid parser and runtime command-shape regressions. |
| `test_shell_wrapper_contracts.py` | `dyoainit`, `day_run`, and shell wrapper contracts remain explicit. |

## Notes

These tests are intentionally lightweight. They validate repository wiring and documented contracts; they do not replace full Snakemake dry-runs or headnode execution tests for workflow changes.
