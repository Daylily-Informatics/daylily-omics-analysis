# Workflow Catalog

The package exposes a small workflow catalog API for tools that need to render `dy-r` commands without scraping Markdown.

## Python API

```python
from daylily_omics_analysis import load_workflow_catalog, render_workflow_command
```

`load_workflow_catalog()` returns a deep copy of the packaged JSON catalog at:

```text
daylily_omics_analysis/data/workflow_catalog.v1.json
```

`render_workflow_command(...)` validates a requested workflow, genome build, execution profile, options, and input context. On success it returns:

- `valid`
- `repository`
- `catalog_version`
- `workflow_id`
- `display_name`
- `argv`
- `shell_preview`
- `summary`
- `normalized_spec`
- `validation_errors`
- `warnings`

The shell preview currently renders a single convenience line with `source dyoainit`, `dy-a`, and `dy-r`. When launching long-running headnode workflows manually, still initialize one command at a time in tmux because `dy-a` and `dy-r` are shell functions.

## Current Catalog Contents

Catalog version: `1.0.0`

Current workflow IDs:

- `test_help`
- `germline_wgs_snv`
- `germline_wgs_snv_sv`
- `germline_wgs_kitchensink`

The catalog currently covers general WGS workflow rendering. The newer Complete Genomics/MGI `sentcg/smd/cgt7p` route is implemented in Snakemake rules and tested in `tests/test_complete_genomics_sentieon.py`, but it is not yet a catalog workflow entry.

## Validation

```bash
python -m pytest tests/test_workflow_catalog.py
```
