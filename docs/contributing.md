# Contributing To DayOA

DayOA contributions should preserve the repository boundary: explicit manifests in, reproducible workflow evidence out. Cluster lifecycle, FSx mounts, staging, export, registry writes, QC disposition, and release decisions belong outside this repo.

## New Runnable Pipelines

Add a new DayOA pipeline when it naturally shares DayOA reference assets, manifests, result layout, MultiQC/evidence contracts, and Snakemake execution. Prefer a separate runnable repository when the pipeline is already maintained as nf-core/Nextflow, WDL, CWL, or another external workflow. DYEC can run those repositories beside DayOA when they honor the FSx analysis-root and export contract.

Avoid growing a monolithic `day_run` or single kitchen-sink target. The historical large DayOA command surface is a convenience artifact from early operator workflows, not a design goal. New work should be modular:

- one or more focused rules under `workflow/rules/`
- explicit config keys with no inferred defaults
- declared outputs under `results/day/<build>/` or `results/runs/<RUNID>/`
- log and benchmark files for every long-running rule
- `_mqc.tsv` or other parser-ready data where MultiQC/report consumers need it
- a target alias callable with `dy-r <target>`
- focused tests and catalog documentation

## Hard-Failure Contract

Do not add fallback behavior. Missing config, missing credentials, missing references, missing licenses, missing runtime assets, malformed manifests, duplicate sample identities, and absent expected outputs should fail loudly with a clear message. This keeps expensive cluster work from silently using the wrong input or environment.

## Documentation And Catalog Updates

For every enabled tool or pipeline family, update [`catalog_of_tools.md`](catalog_of_tools.md) with:

- tool or integration name
- target and rule evidence
- input producers and output file types
- environment or version evidence
- upstream documentation or publication links
- packaged fixtures when present
- pytest or shell coverage
- notes explaining whether the surface is active, dormant, disabled, or historical

Operator examples should use `source dyoainit`, `dy-a ...`, and `dy-r ...` as separate commands. Agent/headnode workflow instructions must not invoke `snakemake` directly.

## Verification

For documentation-only changes, run the focused docs/catalog tests touched by the change. For workflow changes, add the narrowest useful tests first, then run the relevant catalog, target, MultiQC, evidence-manifest, and shell-wrapper tests. Live cluster validation belongs in a tracked `docs/plans/` ledger with exact commands, outputs, blockers, and terminal state.
