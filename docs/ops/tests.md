# Tests And Validation

Run tests from the repository root. On macOS, activate the local execution environment first:

```bash
eval "$(conda shell.zsh hook)"
conda activate DAY-EC
```

## Documentation-Only Checks

```bash
git diff --check
bash tests/test_cli_commands.sh
bash tests/test_bclconvert_bootstrap.sh
python -m pytest tests/test_complete_genomics_sentieon.py tests/test_workflow_catalog.py
```

## Test Inventory

| Test | Purpose |
| --- | --- |
| `tests/test_cli_commands.sh` | CLI shell entrypoints, aliases, completion, monitor behavior, and docs coverage. |
| `tests/test_bclconvert_bootstrap.sh` | BCL Convert bootstrap scripts, rules, fixtures, and report expectations. |
| `tests/test_complete_genomics_sentieon.py` | Complete Genomics/MGI model paths and `sentcg/cgt7p` routing. |
| `tests/test_workflow_catalog.py` | Packaged workflow catalog validation and command rendering. |

## Workflow Dry-Runs

For rule or profile changes, run a target dry-run after CLI initialization:

```bash
source dyoainit
dy-a local hg38
dy-r produce_alignstats -p -j 1 -n
```

For Slurm-only behavior, use a headnode workset and run the same command under `dy-a slurm <build>`.
